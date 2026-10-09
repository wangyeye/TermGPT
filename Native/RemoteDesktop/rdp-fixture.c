// SPDX-License-Identifier: MIT
// Synthetic loopback TLS RDP server used only by the native integration test.
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <freerdp/peer.h>
#include <freerdp/freerdp.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/crypto/privatekey.h>
#include <freerdp/server/cliprdr.h>
#include <freerdp/channels/channels.h>
#include <winpr/synch.h>
#include <winpr/wtsapi.h>
#include <winpr/wlog.h>
#include <winpr/ssl.h>
static CliprdrServerContext *clip;
static HANDLE vcm;
static const BYTE remoteText[] = {'r',0,'e',0,'m',0,'o',0,'t',0,'e',0,' ',0,'R',0,'D',0,'P',0,' ',0,0x2d,0x4e,0x87,0x65,0,0};
static const BYTE localText[] = {'l',0,'o',0,'c',0,'a',0,'l',0,' ',0,'R',0,'D',0,'P',0,' ',0,'f',0,'i',0,'x',0,'t',0,'u',0,'r',0,'e',0,' ',0,0x2d,0x4e,0x87,0x65,0,0};
static UINT clientCapabilities(CliprdrServerContext *ctx, const CLIPRDR_CAPABILITIES *caps) {
 CLIPRDR_FORMAT format = { .formatId = CF_UNICODETEXT };
 CLIPRDR_FORMAT_LIST list = {0}; list.numFormats = 1; list.formats = &format;
 return ctx->ServerFormatList(ctx, &list);
}
static UINT clientFormats(CliprdrServerContext *ctx, const CLIPRDR_FORMAT_LIST *list) {
 CLIPRDR_FORMAT_LIST_RESPONSE response = {0}; response.common.msgFlags = CB_RESPONSE_OK;
 ctx->ServerFormatListResponse(ctx, &response);
 for (UINT32 i=0;i<list->numFormats;i++) if (list->formats[i].formatId == CF_UNICODETEXT) {
  CLIPRDR_FORMAT_DATA_REQUEST request={0}; request.requestedFormatId = CF_UNICODETEXT; return ctx->ServerFormatDataRequest(ctx, &request);
 }
 return 0;
}
static UINT dataRequest(CliprdrServerContext *ctx, const CLIPRDR_FORMAT_DATA_REQUEST *req) {
 CLIPRDR_FORMAT_DATA_RESPONSE response={0}; response.common.msgFlags=CB_RESPONSE_OK; response.common.dataLen=sizeof(remoteText); response.requestedFormatData=remoteText;
 return ctx->ServerFormatDataResponse(ctx,&response);
}
static UINT dataResponse(CliprdrServerContext *ctx, const CLIPRDR_FORMAT_DATA_RESPONSE *response) {
 if (!(response->common.msgFlags & CB_RESPONSE_FAIL) && response->common.dataLen == sizeof(localText) && memcmp(response->requestedFormatData,localText,sizeof(localText))==0) { puts("clipboard");fflush(stdout); } return 0;
}
static BOOL activate(freerdp_peer *peer) {
 BYTE pixels[16*16*4]; for(size_t i=0;i<sizeof(pixels);i+=4){pixels[i]=0;pixels[i+1]=0;pixels[i+2]=255;pixels[i+3]=0;}
 BITMAP_DATA data={0}; data.destRight=15;data.destBottom=15;data.width=16;data.height=16;data.bitsPerPixel=32;data.bitmapLength=sizeof(pixels);data.bitmapDataStream=pixels;
 BITMAP_UPDATE update={0};update.number=1;update.rectangles=&data;update.skipCompression=TRUE;
 if (!peer->context->update->BitmapUpdate(peer->context,&update)) return FALSE;
 clip=cliprdr_server_context_new(vcm);if(!clip)return FALSE;
 clip->rdpcontext=peer->context;clip->autoInitializationSequence=TRUE;clip->useLongFormatNames=TRUE;
 clip->ClientCapabilities=clientCapabilities;clip->ClientFormatList=clientFormats;clip->ClientFormatDataRequest=dataRequest;clip->ClientFormatDataResponse=dataResponse;
 puts("connected");fflush(stdout);return clip->Start(clip)==0;
}
static BOOL keyboard(rdpInput *input,UINT16 flags,UINT8 code){if(code==0x1e){puts("key");fflush(stdout);}return TRUE;}
static BOOL mouse(rdpInput *input,UINT16 flags,UINT16 x,UINT16 y){if(x==2&&y==1){puts("mouse");fflush(stdout);}return TRUE;}
static BOOL postConnect(freerdp_peer *peer){return TRUE;}
int main(int argc,char **argv){
 if(argc!=3)return 2;
 wLog *log=WLog_GetRoot();WLog_SetLogAppenderType(log,WLOG_APPENDER_CONSOLE);WLog_ConfigureAppender(WLog_GetLogAppender(log),"outputstream","stderr");WLog_SetLogLevel(log,WLOG_DEBUG);
 if(!WTSRegisterWtsApiFunctionTable(FreeRDP_InitWtsApi())||!winpr_InitializeSSL(WINPR_SSL_INIT_DEFAULT))return 2;
 int sock=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in address={0};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(bind(sock,(struct sockaddr*)&address,sizeof(address))||listen(sock,1))return 2;
 socklen_t len=sizeof(address);getsockname(sock,(struct sockaddr*)&address,&len);printf("port %u\n",ntohs(address.sin_port));fflush(stdout);
 int fd=accept(sock,NULL,NULL);close(sock);if(fd<0)return 2;
 freerdp_peer *peer=freerdp_peer_new(fd);if(!peer||!freerdp_peer_context_new(peer))return 2;
 rdpSettings *settings=peer->context->settings;
 rdpPrivateKey *key=freerdp_key_new_from_file_enc(argv[2],NULL);rdpCertificate *cert=freerdp_certificate_new_from_file(argv[1]);if(!key||!cert)return 2;
 freerdp_settings_set_pointer_len(settings,FreeRDP_RdpServerRsaKey,key,1);freerdp_settings_set_pointer_len(settings,FreeRDP_RdpServerCertificate,cert,1);
 freerdp_settings_set_bool(settings,FreeRDP_NlaSecurity,FALSE);freerdp_settings_set_bool(settings,FreeRDP_TlsSecurity,TRUE);freerdp_settings_set_bool(settings,FreeRDP_RdpSecurity,FALSE);freerdp_settings_set_bool(settings,FreeRDP_ExtSecurity,FALSE);
 freerdp_settings_set_uint32(settings,FreeRDP_ColorDepth,32);
 freerdp_settings_set_bool(settings,FreeRDP_NetworkAutoDetect,FALSE);freerdp_settings_set_bool(settings,FreeRDP_SupportHeartbeatPdu,FALSE);freerdp_settings_set_bool(settings,FreeRDP_SupportMultitransport,FALSE);
 freerdp_settings_set_uint32(settings,FreeRDP_MultitransportFlags,0);
 vcm=WTSOpenServerA((LPSTR)peer->context);
 peer->PostConnect=postConnect;peer->Activate=activate;peer->context->input->KeyboardEvent=keyboard;peer->context->input->MouseEvent=mouse;
 if(!peer->Initialize(peer))return 2;
 for(;;){HANDLE handles[64];DWORD count=peer->GetEventHandles(peer,handles,64);if(!count||WaitForMultipleObjects(count,handles,FALSE,20)==WAIT_FAILED||!peer->CheckFileDescriptor(peer)||!WTSVirtualChannelManagerCheckFileDescriptor(vcm))break;}
 if(clip){clip->Stop(clip);cliprdr_server_context_free(clip);}WTSCloseServer(vcm);peer->Disconnect(peer);freerdp_peer_context_free(peer);freerdp_peer_free(peer);return 0;
}
