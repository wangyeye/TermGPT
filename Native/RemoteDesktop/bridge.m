// SPDX-License-Identifier: GPL-3.0-or-later
// Separate process: framed stdout carries RGBA frames, status, clipboard and certificate challenges.
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <arpa/inet.h>
#include <signal.h>
#include <stdarg.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/addin.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/channels/channels.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>
#include <winpr/ssl.h>
#include <rfb/rfbclient.h>
#include <openssl/ssl.h>

static atomic_bool stopped = false;
static pthread_mutex_t outputLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray<NSDictionary*> *commands;
static NSDictionary *configuration;
static NSData *localClipboard;
static CliprdrClientContext *clip;
static BOOL clipboardReady = NO;
static NSCondition *certificateCondition;
static NSInteger certificateDecision = -1;
static BOOL writeAll(const void *data, size_t length) {
 const uint8_t *p = data;
 while (length) { ssize_t n = write(STDOUT_FILENO, p, length); if (n <= 0) { atomic_store(&stopped, true); return NO; } p += n; length -= n; }
 return YES;
}
static void packet(uint8_t kind, NSData *data) {
 if (data.length > 40 * 1024 * 1024) return;
 pthread_mutex_lock(&outputLock);
 uint32_t size = htonl((uint32_t)data.length + 1);
 if (writeAll(&size, 4) && writeAll(&kind, 1)) writeAll(data.bytes, data.length);
 pthread_mutex_unlock(&outputLock);
}
static void status(NSString *text) { packet(2, [text dataUsingEncoding:NSUTF8StringEncoding]); }
static void vncError(const char *format, ...) {
 char buffer[4096]; va_list args; va_start(args, format); vsnprintf(buffer, sizeof(buffer), format, args); va_end(args);
 packet(6, [[NSString stringWithUTF8String:buffer] ?: @"VNC protocol error" dataUsingEncoding:NSUTF8StringEncoding]);
}
static void vncLog(const char *format, ...) {
 // Keep negotiation/failure details, omit server desktop names and framebuffer contents.
 if (!strstr(format, "security") && !strstr(format, "auth") && !strstr(format, "protocol") && !strstr(format, "failed") && !strstr(format, "Unable") && !strstr(format, "Unknown") && !strstr(format, "timeout")) return;
 char buffer[4096]; va_list args; va_start(args, format); vsnprintf(buffer, sizeof(buffer), format, args); va_end(args);
 packet(6, [[NSString stringWithUTF8String:buffer] ?: @"VNC negotiation" dataUsingEncoding:NSUTF8StringEncoding]);
}
static void frame(const uint8_t *pixels, int width, int height, int stride) {
 if (!pixels || width < 1 || height < 1 || width > 4096 || height > 2160) return;
 uint32_t dimensions[2] = { htonl(width), htonl(height) };
 NSMutableData *data = [NSMutableData dataWithBytes:dimensions length:8];
 for (int y = 0; y < height; y++) [data appendBytes:pixels + y * stride length:width * 4];
 packet(1, data);
}
static NSDictionary *readCommand(void) {
 NSMutableData *data = [NSMutableData data];
 uint8_t c;
 while (read(STDIN_FILENO, &c, 1) == 1) {
  if (c == '\n') { id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; return [object isKindOfClass:NSDictionary.class] ? object : nil; }
  if (data.length >= 2 * 1024 * 1024) return nil;
  [data appendBytes:&c length:1];
 }
 return nil;
}
static void *readInputs(void *unused) {
 @autoreleasepool {
  while (!atomic_load(&stopped)) {
   NSDictionary *item = readCommand(); if (!item) break;
   NSString *type = item[@"type"];
   if ([type isEqual:@"stop"]) break;
   if ([type isEqual:@"certificate"]) {
    [certificateCondition lock]; certificateDecision = [item[@"accept"] boolValue] ? 2 : 0;
    [certificateCondition broadcast]; [certificateCondition unlock];
   } else { @synchronized(commands) { if (commands.count < 1024) [commands addObject:item]; } }
  }
  atomic_store(&stopped, true);
  [certificateCondition lock]; [certificateCondition broadcast]; [certificateCondition unlock];
 }
 return NULL;
}
static NSArray *takeInputs(void) { @synchronized(commands) { NSArray *items = [commands copy]; [commands removeAllObjects]; return items; } }
static DWORD verifyCertificate(freerdp *rdp, const char *host, UINT16 port, const char *commonName, const char *subject, const char *issuer, const char *fingerprint, DWORD flags) {
 [certificateCondition lock]; certificateDecision = -1;
 NSDictionary *info = @{@"host": [NSString stringWithUTF8String:host ?: ""], @"subject": [NSString stringWithUTF8String:subject ?: ""], @"issuer": [NSString stringWithUTF8String:issuer ?: ""], @"fingerprint": [NSString stringWithUTF8String:fingerprint ?: ""]};
 packet(4, [NSJSONSerialization dataWithJSONObject:info options:0 error:nil]);
 NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300];
 while (certificateDecision < 0 && !atomic_load(&stopped)) if (![certificateCondition waitUntilDate:deadline]) break;
 DWORD result = certificateDecision == 2 ? 2 : 0;
 [certificateCondition unlock]; return result;
}
static DWORD verifyChanged(freerdp *rdp, const char *host, UINT16 port, const char *cn, const char *sub, const char *issuer, const char *fp, const char *oldSub, const char *oldIssuer, const char *oldFP, DWORD flags) { return verifyCertificate(rdp, host, port, cn, sub, issuer, fp, flags); }
static UINT announceClipboard(CliprdrClientContext *context) {
 BOOL hasText; @synchronized(commands) { hasText = localClipboard != nil; }
 CLIPRDR_FORMAT format = { .formatId = CF_UNICODETEXT };
 CLIPRDR_FORMAT_LIST list = {0}; list.numFormats = hasText ? 1 : 0; list.formats = &format;
 return context->ClientFormatList(context, &list);
}
static UINT monitorReady(CliprdrClientContext *context, const CLIPRDR_MONITOR_READY *event) {
 CLIPRDR_GENERAL_CAPABILITY_SET general = {0}; general.capabilitySetType = CB_CAPSTYPE_GENERAL; general.capabilitySetLength = 12; general.version = CB_CAPS_VERSION_2; general.generalFlags = CB_USE_LONG_FORMAT_NAMES;
 CLIPRDR_CAPABILITIES caps = {0}; caps.cCapabilitiesSets = 1; caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
 context->ClientCapabilities(context, &caps); @synchronized(commands) { clipboardReady = YES; } return announceClipboard(context);
}
static UINT remoteFormats(CliprdrClientContext *context, const CLIPRDR_FORMAT_LIST *list) {
 CLIPRDR_FORMAT_LIST_RESPONSE response = {0}; response.common.msgFlags = CB_RESPONSE_OK;
 context->ClientFormatListResponse(context, &response);
 for (UINT32 i = 0; i < list->numFormats; i++) if (list->formats[i].formatId == CF_UNICODETEXT) {
  CLIPRDR_FORMAT_DATA_REQUEST request = {0}; request.requestedFormatId = CF_UNICODETEXT;
  return context->ClientFormatDataRequest(context, &request);
 }
 return 0;
}
static UINT clipboardRequest(CliprdrClientContext *context, const CLIPRDR_FORMAT_DATA_REQUEST *request) {
 CLIPRDR_FORMAT_DATA_RESPONSE response = {0}; NSData *data; @synchronized(commands) { data = localClipboard; }
 response.common.msgFlags = request->requestedFormatId == CF_UNICODETEXT && data ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
 response.common.dataLen = (UINT32)data.length; response.requestedFormatData = data.bytes;
 return context->ClientFormatDataResponse(context, &response);
}
static UINT clipboardResponse(CliprdrClientContext *context, const CLIPRDR_FORMAT_DATA_RESPONSE *response) {
 if ((response->common.msgFlags & CB_RESPONSE_FAIL) || response->common.dataLen > 1024 * 1024 || response->common.dataLen % 2) return 0;
 NSString *text = [[NSString alloc] initWithBytes:response->requestedFormatData length:response->common.dataLen encoding:NSUTF16LittleEndianStringEncoding];
 text = [text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0"]];
 if (text) packet(3, [text dataUsingEncoding:NSUTF8StringEncoding]); return 0;
}
static void channelConnected(void *context, const ChannelConnectedEventArgs *event) {
 if (strcmp(event->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
  @synchronized(commands) { clip = event->pInterface; }
  clip->custom = context;
  clip->MonitorReady = monitorReady; clip->ServerFormatList = remoteFormats;
  clip->ServerFormatDataRequest = clipboardRequest; clip->ServerFormatDataResponse = clipboardResponse;
 }
}
static BOOL preConnect(freerdp *rdp) {
 PubSub_SubscribeChannelConnected(rdp->context->pubSub, channelConnected);
 return YES;
}
static BOOL loadChannels(freerdp *rdp) {
 return freerdp_client_load_addins(rdp->context->channels, rdp->context->settings);
}
static BOOL beginPaint(rdpContext *context) { context->gdi->primary->hdc->hwnd->invalid->null = TRUE; return TRUE; }
static BOOL endPaint(rdpContext *context) {
 rdpGdi *gdi = context->gdi;
 if (!gdi->primary->hdc->hwnd->invalid->null) frame(gdi->primary_buffer, gdi->width, gdi->height, gdi->stride);
 return TRUE;
}
static BOOL resizeDesktop(rdpContext *context) {
 UINT32 width = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth), height = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
 if (width > 4096 || height > 2160) return FALSE;
 return gdi_resize(context->gdi, width, height);
}
static BOOL postConnect(freerdp *rdp) {
 if (!gdi_init(rdp, PIXEL_FORMAT_RGBA32)) return FALSE;
 rdp->context->update->BeginPaint = beginPaint; rdp->context->update->EndPaint = endPaint; rdp->context->update->DesktopResize = resizeDesktop;
 status(@"connected"); return TRUE;
}
static void runRDP(void) {
 if (!winpr_InitializeSSL(WINPR_SSL_INIT_DEFAULT)) { status(@"RDP crypto initialization failed"); return; }
 freerdp_register_addin_provider(freerdp_channels_load_static_addin_entry, 0);
 freerdp *rdp = freerdp_new(); if (!rdp) { status(@"RDP initialization failed"); return; }
 rdp->PreConnect = preConnect; rdp->PostConnect = postConnect; rdp->LoadChannels = loadChannels;
 rdp->VerifyCertificateEx = verifyCertificate; rdp->VerifyChangedCertificateEx = verifyChanged;
 if (!freerdp_context_new(rdp)) { freerdp_free(rdp); return; }
 rdpSettings *s = rdp->context->settings;
 freerdp_settings_set_string(s, FreeRDP_ServerHostname, [configuration[@"host"] UTF8String]);
 freerdp_settings_set_uint32(s, FreeRDP_ServerPort, [configuration[@"port"] unsignedIntValue]);
 freerdp_settings_set_string(s, FreeRDP_Username, [configuration[@"user"] UTF8String]);
 freerdp_settings_set_string(s, FreeRDP_Password, [configuration[@"password"] UTF8String]);
 freerdp_settings_set_string(s, FreeRDP_Domain, [configuration[@"domain"] UTF8String]);
 freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, 1440); freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, 900);
 freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32);
 freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, [configuration[@"clipboard"] boolValue]);
 freerdp_settings_set_bool(s, FreeRDP_SoftwareGdi, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_NetworkAutoDetect, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_SupportHeartbeatPdu, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_SupportMultitransport, FALSE);
 freerdp_settings_set_uint32(s, FreeRDP_MultitransportFlags, 0);
 freerdp_settings_set_bool(s, FreeRDP_DeviceRedirection, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_AudioCapture, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_NlaSecurity, TRUE); freerdp_settings_set_bool(s, FreeRDP_TlsSecurity, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_RdpSecurity, FALSE); freerdp_settings_set_bool(s, FreeRDP_IgnoreCertificate, FALSE);
 freerdp_settings_set_uint32(s, FreeRDP_TcpConnectTimeout, 15000);
 if (!freerdp_connect(rdp)) {
  UINT32 error = freerdp_get_last_error(rdp->context);
  packet(6, [[NSString stringWithFormat:@"RDP error 0x%08x %s: %s", error, freerdp_get_last_error_name(error), freerdp_get_last_error_string(error)] dataUsingEncoding:NSUTF8StringEncoding]);
  status([NSString stringWithFormat:@"RDP connection failed (0x%08x). Check credentials, certificate and remote desktop service.", error]);
 }
 else {
  while (!atomic_load(&stopped) && !freerdp_shall_disconnect_context(rdp->context)) {
   @autoreleasepool {
    for (NSDictionary *item in takeInputs()) {
     NSString *type = item[@"type"];
     if ([type isEqual:@"mouse"]) freerdp_input_send_mouse_event(rdp->context->input, [item[@"flags"] unsignedIntValue], [item[@"x"] unsignedIntValue], [item[@"y"] unsignedIntValue]);
     else if ([type isEqual:@"key"]) freerdp_input_send_keyboard_event_ex(rdp->context->input, [item[@"down"] boolValue], FALSE, [item[@"scan"] unsignedIntValue]);
     else if ([type isEqual:@"text"]) {
      NSString *text = item[@"text"]; for (NSUInteger i = 0; i < text.length; i++) { unichar ch = [text characterAtIndex:i]; freerdp_input_send_unicode_keyboard_event(rdp->context->input, 0, ch); freerdp_input_send_unicode_keyboard_event(rdp->context->input, KBD_FLAGS_RELEASE, ch); }
     } else if ([type isEqual:@"clipboard"]) {
      NSString *text = [item[@"text"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
      NSMutableData *data = [[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy]; uint16_t zero = 0; [data appendBytes:&zero length:2];
      CliprdrClientContext *clipboardContext; BOOL ready;
      @synchronized(commands) { localClipboard = data; clipboardContext = clip; ready = clipboardReady; }
      if (clipboardContext && ready) announceClipboard(clipboardContext);
     }
    }
    HANDLE handles[64]; DWORD count = freerdp_get_event_handles(rdp->context, handles, 64);
    if (!count || WaitForMultipleObjects(count, handles, FALSE, 15) == WAIT_FAILED || !freerdp_check_event_handles(rdp->context)) break;
   }
  }
  status(@"disconnected");
 }
 clip = NULL; freerdp_disconnect(rdp); if (rdp->context->gdi) gdi_free(rdp); freerdp_context_free(rdp); freerdp_free(rdp);
}
static char *vncPassword(rfbClient *client) { return strdup([configuration[@"password"] UTF8String] ?: ""); }
static rfbCredential *vncCredential(rfbClient *client, int type) {
 if (type != rfbCredentialTypeUser) return NULL;
 rfbCredential *credential = calloc(1, sizeof(rfbCredential));
 credential->userCredential.username = strdup([configuration[@"user"] UTF8String] ?: ""); credential->userCredential.password = vncPassword(client); return credential;
}
static rfbBool vncAllocate(rfbClient *client) {
 if (client->width <= 0 || client->height <= 0 || client->width > 4096 || client->height > 2160) return FALSE;
 free(client->frameBuffer); client->frameBuffer = calloc((size_t)client->width * client->height, 4); return client->frameBuffer != NULL;
}
static void vncFrame(rfbClient *client) { frame(client->frameBuffer, client->width, client->height, client->width * 4); }
static void vncClipboard(rfbClient *client, const char *text, int length) {
 if (![configuration[@"clipboard"] boolValue] || length < 0 || length > 1024 * 1024) return;
 NSString *string = [[NSString alloc] initWithBytes:text length:length encoding:NSISOLatin1StringEncoding]; if (string) packet(3, [string dataUsingEncoding:NSUTF8StringEncoding]);
}
static void vncClipboardUTF8(rfbClient *client, const char *text, int length) { if ([configuration[@"clipboard"] boolValue] && length >= 0 && length <= 1024*1024) packet(3, [NSData dataWithBytes:text length:length]); }
static void runVNC(void) {
 rfbClientErr = vncError;
 rfbClientLog = vncLog;
 rfbClient *client = rfbGetClient(8, 3, 4); if (!client) return;
 client->serverHost = strdup([configuration[@"host"] UTF8String]); client->serverPort = [configuration[@"port"] intValue];
 client->format.redShift = 0; client->format.greenShift = 8; client->format.blueShift = 16; client->format.bigEndian = FALSE;
 client->GetPassword = vncPassword; client->GetCredential = vncCredential; client->MallocFrameBuffer = vncAllocate; client->FinishedFrameBufferUpdate = vncFrame;
 client->GotXCutText = vncClipboard; client->GotXCutTextUTF8 = vncClipboardUTF8;
 client->canHandleNewFBSize = TRUE; client->connectTimeout = 15; client->readTimeout = 20;
 client->appData.useRemoteCursor = FALSE; client->appData.enableJPEG = FALSE;
 if (!rfbInitClient(client, NULL, NULL)) { status(@"VNC connection failed. Check password, host and VNC service."); return; }
 status(@"connected"); int buttons = 0;
 // Request a complete initial framebuffer without requiring mouse/keyboard activity.
 SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
 while (!atomic_load(&stopped)) {
  @autoreleasepool {
   for (NSDictionary *item in takeInputs()) {
    NSString *type = item[@"type"];
    if ([type isEqual:@"mouse"]) { buttons = [item[@"buttons"] intValue]; SendPointerEvent(client, [item[@"x"] intValue], [item[@"y"] intValue], buttons); }
    else if ([type isEqual:@"key"]) SendKeyEvent(client, [item[@"keysym"] unsignedIntValue], [item[@"down"] boolValue]);
    else if ([type isEqual:@"text"]) { NSString *text = item[@"text"]; for (NSUInteger i = 0; i < text.length; i++) { uint32_t ch = [text characterAtIndex:i]; if (ch > 255) ch |= 0x01000000; SendKeyEvent(client, ch, TRUE); SendKeyEvent(client, ch, FALSE); } }
    else if ([type isEqual:@"clipboard"] && [configuration[@"clipboard"] boolValue]) {
     NSString *text = item[@"text"]; NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
     if (!SendClientCutTextUTF8(client, (char*)data.bytes, (int)data.length)) {
      NSData *legacy = [text dataUsingEncoding:NSISOLatin1StringEncoding];
      if (legacy) SendClientCutText(client, (char*)legacy.bytes, (int)legacy.length);
      else packet(5, [@"This VNC server does not support Unicode clipboard text." dataUsingEncoding:NSUTF8StringEncoding]);
     }
    }
   }
   // Read-ahead can hold the next clipboard/update message even when select reports no new socket bytes.
   BOOL buffered = client->buffered || (client->tlsSession && SSL_pending((SSL*)client->tlsSession) > 0);
   int ready = buffered ? 1 : WaitForMessage(client, 15000); if (ready < 0 || (ready && !HandleRFBServerMessage(client))) break;
  }
 }
 status(@"disconnected"); free(client->frameBuffer); client->frameBuffer = NULL; rfbClientCleanup(client);
}
int main(void) { @autoreleasepool {
 signal(SIGPIPE, SIG_IGN); setenv("WLOG_LEVEL", "OFF", 1); setenv("WLOG_APPENDER", "CONSOLE", 1);
 commands = [NSMutableArray array]; certificateCondition = [NSCondition new];
 configuration = readCommand();
 if (!configuration || ![configuration[@"host"] isKindOfClass:NSString.class]) return 2;
 if (!winpr_InitializeSSL(WINPR_SSL_INIT_DEFAULT)) { status(@"Desktop crypto initialization failed"); return 2; }
 if ([configuration[@"diagnostic"] boolValue]) {
  wLog *log = WLog_GetRoot(); WLog_SetLogAppenderType(log, WLOG_APPENDER_CONSOLE);
  WLog_ConfigureAppender(WLog_GetLogAppender(log), "outputstream", "stderr"); WLog_SetLogLevel(log, WLOG_DEBUG);
 }
 pthread_t reader; pthread_create(&reader, NULL, readInputs, NULL);
 status(@"connecting");
 if ([configuration[@"protocol"] isEqual:@"rdp"]) runRDP(); else runVNC();
 atomic_store(&stopped, true);
 return 0;
} }
