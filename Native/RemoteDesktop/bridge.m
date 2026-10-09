// SPDX-License-Identifier: GPL-3.0-or-later
// Separate process: framed stdout carries RGBA frames, status, clipboard and certificate challenges.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <arpa/inet.h>
#include <signal.h>
#include <stdarg.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/codecs.h>
#include <freerdp/input.h>
#include <freerdp/addin.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
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
static DispClientContext *display;
static BOOL displayReady = NO;
static UINT64 displayMaxArea;
static UINT32 desiredWidth = 720, desiredHeight = 600, sentWidth, sentHeight;
static void rememberResize(NSDictionary *item) {
 int width = [item[@"width"] intValue], height = [item[@"height"] intValue];
 if (width < 200 || height < 200 || width > 4096 || height > 2160) return;
 desiredWidth = width & ~1; desiredHeight = height;
}
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
extern void termgpt_rdpsnd_set_muted(int muted);
extern void termgpt_rdpsnd_set_state_callback(void (*callback)(const char*));
static atomic_bool audioMuted;
static atomic_int lastAudioState = -1;
static void audioState(const char *state) {
 int value = !strcmp(state,"waiting") ? 0 : !strcmp(state,"ready") ? 1 : !strcmp(state,"playing") ? 2 : !strcmp(state,"bell") ? 3 : !strcmp(state,"idle") ? 5 : 4;
 if (atomic_exchange(&lastAudioState, value) == value) return;
 @autoreleasepool { packet(7, [[NSString stringWithUTF8String:state] dataUsingEncoding:NSUTF8StringEncoding]); }
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
static UINT displayCaps(DispClientContext *context, UINT32 monitors, UINT32 factorA, UINT32 factorB) {
 @synchronized(commands) { displayReady = monitors > 0; displayMaxArea = (UINT64)factorA * factorB; }
 packet(6, [@"RDP dynamic resolution channel ready" dataUsingEncoding:NSUTF8StringEncoding]); return CHANNEL_RC_OK;
}
static void sendRDPResize(void) {
 @synchronized(commands) {
  if (!display || !displayReady || (sentWidth == desiredWidth && sentHeight == desiredHeight)) return;
  if (displayMaxArea && (UINT64)desiredWidth * desiredHeight > displayMaxArea) return;
  DISPLAY_CONTROL_MONITOR_LAYOUT layout = {0}; layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
  layout.Width = desiredWidth; layout.Height = desiredHeight;
  layout.PhysicalWidth = MAX(10, desiredWidth * 254 / 960); layout.PhysicalHeight = MAX(10, desiredHeight * 254 / 960);
  layout.DesktopScaleFactor = 100; layout.DeviceScaleFactor = 100;
  if (display->SendMonitorLayout(display, 1, &layout) == CHANNEL_RC_OK) {
   sentWidth = desiredWidth; sentHeight = desiredHeight;
   packet(6, [[NSString stringWithFormat:@"RDP resize requested %ux%u", sentWidth, sentHeight] dataUsingEncoding:NSUTF8StringEncoding]);
  }
 }
}
static void channelConnected(void *context, const ChannelConnectedEventArgs *event) {
 if (strcmp(event->name, "rdpsnd") == 0) audioState("ready");
 if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) {
  @synchronized(commands) { display = event->pInterface; display->DisplayControlCaps = displayCaps; }
 }
 if (strcmp(event->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
  @synchronized(commands) { clip = event->pInterface; }
  clip->custom = context;
  clip->MonitorReady = monitorReady; clip->ServerFormatList = remoteFormats;
  clip->ServerFormatDataRequest = clipboardRequest; clip->ServerFormatDataResponse = clipboardResponse;
 }
}
static void channelDisconnected(void *context, const ChannelDisconnectedEventArgs *event) {
 if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) { @synchronized(commands) { display = NULL; displayReady = NO; } }
}
static BOOL preConnect(freerdp *rdp) {
 PubSub_SubscribeChannelConnected(rdp->context->pubSub, channelConnected);
 PubSub_SubscribeChannelDisconnected(rdp->context->pubSub, channelDisconnected);
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
 // xrdp pads bitmap scanlines to four pixels. Resize decoder capacity as
 // well as the framebuffer; otherwise larger planar updates cannot decode.
 if (!freerdp_client_codecs_reset(context->codecs, FREERDP_CODEC_ALL, (width + 3) & ~3u, height)) return FALSE;
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
 if (!freerdp_context_new(rdp)) { status(@"RDP initialization failed: user home/configuration directory unavailable"); freerdp_free(rdp); return; }
 rdpSettings *s = rdp->context->settings;
 freerdp_settings_set_string(s, FreeRDP_ServerHostname, [configuration[@"host"] UTF8String]);
 freerdp_settings_set_uint32(s, FreeRDP_ServerPort, [configuration[@"port"] unsignedIntValue]);
 freerdp_settings_set_string(s, FreeRDP_Username, [configuration[@"user"] UTF8String]);
 freerdp_settings_set_string(s, FreeRDP_Password, [configuration[@"password"] UTF8String]);
 freerdp_settings_set_string(s, FreeRDP_Domain, [configuration[@"domain"] UTF8String]);
 rememberResize(configuration);
 freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, desiredWidth); freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, desiredHeight);
 freerdp_settings_set_bool(s, FreeRDP_SupportDisplayControl, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_DynamicResolutionUpdate, TRUE);
 freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32);
 freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, [configuration[@"clipboard"] boolValue]);
 freerdp_settings_set_bool(s, FreeRDP_SoftwareGdi, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_NetworkAutoDetect, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_SupportHeartbeatPdu, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_SupportMultitransport, FALSE);
 freerdp_settings_set_uint32(s, FreeRDP_MultitransportFlags, 0);
 freerdp_settings_set_bool(s, FreeRDP_DeviceRedirection, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_AudioCapture, FALSE);
 freerdp_settings_set_bool(s, FreeRDP_NlaSecurity, TRUE); freerdp_settings_set_bool(s, FreeRDP_TlsSecurity, TRUE);
 freerdp_settings_set_bool(s, FreeRDP_RdpSecurity, FALSE); freerdp_settings_set_bool(s, FreeRDP_IgnoreCertificate, FALSE);
 freerdp_settings_set_uint32(s, FreeRDP_TcpConnectTimeout, 15000);
 termgpt_rdpsnd_set_state_callback(audioState); audioState("waiting");
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
     if ([type isEqual:@"audio"]) { atomic_store(&audioMuted, [item[@"muted"] boolValue]); termgpt_rdpsnd_set_muted(atomic_load(&audioMuted)); }
    else if ([type isEqual:@"resize"]) rememberResize(item);
     else if ([type isEqual:@"mouse"]) freerdp_input_send_mouse_event(rdp->context->input, [item[@"flags"] unsignedIntValue], [item[@"x"] unsignedIntValue], [item[@"y"] unsignedIntValue]);
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
    sendRDPResize();
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
static BOOL checkedInitialVNCFrame = NO;
static rfbBool vncAllocate(rfbClient *client) {
 if (client->width <= 0 || client->height <= 0 || client->width > 4096 || client->height > 2160) return FALSE;
 checkedInitialVNCFrame = NO;
 packet(6, [[NSString stringWithFormat:@"VNC framebuffer size %dx%d", client->width, client->height] dataUsingEncoding:NSUTF8StringEncoding]);
 free(client->frameBuffer); client->frameBuffer = calloc((size_t)client->width * client->height, 4); return client->frameBuffer != NULL;
}
static void vncFrame(rfbClient *client) {
 frame(client->frameBuffer, client->width, client->height, client->width * 4);
 if (!checkedInitialVNCFrame && client->frameBuffer) {
  checkedInitialVNCFrame = YES; BOOL black = YES;
  for (size_t i = 0; i < (size_t)client->width * client->height * 4; i += 4) {
   if (client->frameBuffer[i] || client->frameBuffer[i+1] || client->frameBuffer[i+2]) { black = NO; break; }
  }
  if (black) {
   packet(6, [@"Initial framebuffer is black; sending pointer motion with no buttons to wake display" dataUsingEncoding:NSUTF8StringEncoding]);
   int x = client->width / 2, y = client->height / 2;
   SendPointerEvent(client, x, y, 0);
   SendPointerEvent(client, MIN(x+1, client->width-1), y, 0);
   SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
  }
 }
}
static void vncClipboard(rfbClient *client, const char *text, int length) {
 if (![configuration[@"clipboard"] boolValue] || length < 0 || length > 1024 * 1024) return;
 NSString *string = [[NSString alloc] initWithBytes:text length:length encoding:NSISOLatin1StringEncoding]; if (string) packet(3, [string dataUsingEncoding:NSUTF8StringEncoding]);
}
static void vncClipboardUTF8(rfbClient *client, const char *text, int length) { if ([configuration[@"clipboard"] boolValue] && length >= 0 && length <= 1024*1024) packet(3, [NSData dataWithBytes:text length:length]); }
static void sendVNCResize(rfbClient *client) {
 // A received screen layout confirms ExtendedDesktopSize support. Preserve its screen ID.
 if (!client->screen.width || !client->screen.height || client->requestedResize ||
     (sentWidth == desiredWidth && sentHeight == desiredHeight)) return;
 rfbSetDesktopSizeMsg message = {0}; rfbExtDesktopScreen screen = client->screen;
 message.type = rfbSetDesktopSize; message.width = htons(desiredWidth); message.height = htons(desiredHeight); message.numberOfScreens = 1;
 screen.x = screen.y = 0; screen.width = message.width; screen.height = message.height;
 if (WriteToRFBServer(client, (char*)&message, sz_rfbSetDesktopSizeMsg) &&
     WriteToRFBServer(client, (char*)&screen, sz_rfbExtDesktopScreen)) {
  client->requestedResize = TRUE; sentWidth = desiredWidth; sentHeight = desiredHeight;
  packet(6, [[NSString stringWithFormat:@"VNC resize requested %ux%u", sentWidth, sentHeight] dataUsingEncoding:NSUTF8StringEncoding]);
  SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
 }
}
// QEMU Audio uses signed 16-bit little-endian stereo PCM at the requested rate.
// Queue capacity is bounded; audio is dropped rather than blocking desktop input.
static AudioQueueRef vncAudio;
static atomic_uint vncQueuedBytes;
static BOOL vncAudioStarted;
static atomic_bool vncAudioReported;
static void audioConsumed(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
 atomic_fetch_sub(&vncQueuedBytes, buffer->mAudioDataByteSize);
 AudioQueueFreeBuffer(queue, buffer);
 if (!atomic_exchange(&vncAudioReported, true)) { @autoreleasepool { packet(6, [@"VNC audio buffer consumed" dataUsingEncoding:NSUTF8StringEncoding]); audioState("playing"); } }
}
static void stopVNCAudio(void) {
 if (vncAudio) { AudioQueueStop(vncAudio, true); AudioQueueDispose(vncAudio, true); vncAudio = NULL; }
 atomic_store(&vncQueuedBytes, 0); vncAudioStarted = NO;
}
static BOOL prepareVNCAudio(void) {
 if (vncAudio) return YES;
 atomic_store(&vncAudioReported, false);
 AudioStreamBasicDescription format = {0}; format.mSampleRate = 44100;
 format.mFormatID = kAudioFormatLinearPCM; format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
 format.mBytesPerPacket = 4; format.mFramesPerPacket = 1; format.mBytesPerFrame = 4; format.mChannelsPerFrame = 2; format.mBitsPerChannel = 16;
 BOOL ready = AudioQueueNewOutput(&format, audioConsumed, NULL, NULL, NULL, 0, &vncAudio) == noErr;
 if (ready) AudioQueueSetParameter(vncAudio, kAudioQueueParam_Volume, atomic_load(&audioMuted) ? 0 : 1);
 return ready;
}
static rfbBool vncAudioEncoding(rfbClient *client, rfbFramebufferUpdateRectHeader *rect) {
 if ((int32_t)rect->encoding != -259) return FALSE;
 uint8_t format[] = {255, 1, 0, 2, 3, 2, 0, 0, 0xac, 0x44};
 uint8_t enable[] = {255, 1, 0, 0};
 if (!prepareVNCAudio() || !WriteToRFBServer(client, (char*)format, sizeof(format)) || !WriteToRFBServer(client, (char*)enable, sizeof(enable))) {
  packet(6, [@"VNC audio output could not start" dataUsingEncoding:NSUTF8StringEncoding]); audioState("error");
 } else { packet(6, [@"VNC QEMU Audio negotiated: PCM 44100 Hz stereo" dataUsingEncoding:NSUTF8StringEncoding]); audioState("ready"); }
 return TRUE;
}
static rfbBool vncAudioMessage(rfbClient *client, rfbServerToClientMsg *message) {
 if (message->type != 255) return FALSE;
 uint8_t header[3];
 if (!ReadFromRFBServer(client, (char*)header, 3) || header[0] != 1) { atomic_store(&stopped, true); return TRUE; }
 unsigned operation = ((unsigned)header[1] << 8) | header[2];
 if (operation == 0) { stopVNCAudio(); audioState("idle"); return TRUE; }
 if (operation == 1) { prepareVNCAudio(); return TRUE; }
 if (operation != 2) { atomic_store(&stopped, true); return TRUE; }
 uint32_t networkLength;
 if (!ReadFromRFBServer(client, (char*)&networkLength, 4)) { atomic_store(&stopped, true); return TRUE; }
 uint32_t length = ntohl(networkLength);
 if (length > 1024 * 1024 || length % 4) { atomic_store(&stopped, true); return TRUE; }
 NSMutableData *samples = [NSMutableData dataWithLength:length];
 if (!ReadFromRFBServer(client, samples.mutableBytes, length)) { atomic_store(&stopped, true); return TRUE; }
 if (!length || !vncAudio || atomic_load(&vncQueuedBytes) + length > 176400) return TRUE;
 AudioQueueBufferRef buffer;
 if (AudioQueueAllocateBuffer(vncAudio, length, &buffer) != noErr) return TRUE;
 memcpy(buffer->mAudioData, samples.bytes, length); buffer->mAudioDataByteSize = length;
 atomic_fetch_add(&vncQueuedBytes, length);
 if (AudioQueueEnqueueBuffer(vncAudio, buffer, 0, NULL) != noErr) {
  atomic_fetch_sub(&vncQueuedBytes, length); AudioQueueFreeBuffer(vncAudio, buffer); return TRUE;
 }
 if (!vncAudioStarted) {
  vncAudioStarted = AudioQueueStart(vncAudio, NULL) == noErr;
  packet(6, [(vncAudioStarted ? @"VNC audio playback started" : @"VNC audio playback failed") dataUsingEncoding:NSUTF8StringEncoding]);
 }
 return TRUE;
}
static void vncBell(rfbClient *client) { if (!atomic_load(&audioMuted)) NSBeep(); }
static int vncAudioEncodings[] = {-259, 0};
static rfbClientProtocolExtension vncAudioExtension = {.encodings=vncAudioEncodings, .handleEncoding=vncAudioEncoding, .handleMessage=vncAudioMessage};

static void runVNC(void) {
 rfbClientRegisterExtension(&vncAudioExtension);
 rememberResize(configuration);
 rfbClientErr = vncError;
 rfbClientLog = vncLog;
 rfbClient *client = rfbGetClient(8, 3, 4); if (!client) return;
 client->serverHost = strdup([configuration[@"host"] UTF8String]); client->serverPort = [configuration[@"port"] intValue];
 client->format.redShift = 0; client->format.greenShift = 8; client->format.blueShift = 16; client->format.bigEndian = FALSE;
 client->GetPassword = vncPassword; client->GetCredential = vncCredential; client->MallocFrameBuffer = vncAllocate; client->FinishedFrameBufferUpdate = vncFrame;
 client->Bell = vncBell;
 client->GotXCutText = vncClipboard; client->GotXCutTextUTF8 = vncClipboardUTF8;
 client->canHandleNewFBSize = TRUE; client->connectTimeout = 15; client->readTimeout = 20;
 client->appData.useRemoteCursor = FALSE; client->appData.enableJPEG = FALSE;
 if (!rfbInitClient(client, NULL, NULL)) { status(@"VNC connection failed. Check password, host and VNC service."); return; }
 status(@"connected"); audioState("bell"); int buttons = 0;
 // Request a complete initial framebuffer without requiring mouse/keyboard activity.
 SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
 while (!atomic_load(&stopped)) {
  @autoreleasepool {
   for (NSDictionary *item in takeInputs()) {
    NSString *type = item[@"type"];
    if ([type isEqual:@"audio"]) { atomic_store(&audioMuted, [item[@"muted"] boolValue]); if (vncAudio) AudioQueueSetParameter(vncAudio, kAudioQueueParam_Volume, atomic_load(&audioMuted) ? 0 : 1); }
    else if ([type isEqual:@"resize"]) rememberResize(item);
    else if ([type isEqual:@"mouse"]) { buttons = [item[@"buttons"] intValue]; SendPointerEvent(client, [item[@"x"] intValue], [item[@"y"] intValue], buttons); }
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
   sendVNCResize(client);
   // Read-ahead can hold the next clipboard/update message even when select reports no new socket bytes.
   BOOL buffered = client->buffered || (client->tlsSession && SSL_pending((SSL*)client->tlsSession) > 0);
   int ready = buffered ? 1 : WaitForMessage(client, 15000); if (ready < 0 || (ready && !HandleRFBServerMessage(client))) break;
  }
 }
 stopVNCAudio();
 status(@"disconnected"); free(client->frameBuffer); client->frameBuffer = NULL; rfbClientCleanup(client);
}
int main(void) { @autoreleasepool {
 // Standalone callers and older app builds may omit HOME; FreeRDP requires it during context creation.
 if (!getenv("HOME") || !*getenv("HOME")) setenv("HOME", NSHomeDirectory().UTF8String, 1);
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
