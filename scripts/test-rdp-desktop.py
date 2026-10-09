#!/usr/bin/env python3
"""Real loopback TLS RDP fixture: certificate approval, bitmap, input, Unicode clipboard. No production hosts or credentials."""
import json, os, queue, shutil, struct, subprocess, sys, tempfile, threading, time
from pathlib import Path
if sys.platform != 'darwin' or not shutil.which('openssl'): raise SystemExit('Requires macOS, Python 3 and OpenSSL command')
root=Path(__file__).resolve().parent.parent
folder=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'.build/remote-arm64'
helper=folder/'TermGPTRemoteDesktop';fixture=folder/'TermGPTRDPFixture'
if not helper.is_file() or not fixture.is_file():raise SystemExit('Build scripts/build-remote-desktop.sh arm64 .build/remote-arm64 ON first')
def exact(stream,length):
    data=b''
    while len(data)<length:
        chunk=stream.read(length-len(data))
        if not chunk:raise EOFError()
        data+=chunk
    return data
with tempfile.TemporaryDirectory(prefix='termgpt-rdp-test-') as tmp:
    cert=Path(tmp)/'certificate.pem';key=Path(tmp)/'private.pem'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    diagnostic=(folder/'rdp-fixture.log').open('wb')
    environment=dict(os.environ,HOME=tmp,XDG_CONFIG_HOME=tmp)
    server=subprocess.Popen([str(fixture),str(cert),str(key)],stdout=subprocess.PIPE,stderr=diagnostic,text=True,env=environment)
    client=None;packets=queue.Queue();events=queue.Queue();failures=queue.Queue()
    try:
        first=server.stdout.readline();assert first.startswith('port '),first
        port=int(first.split()[1])
        def server_events():
            for line in server.stdout:events.put(line.strip())
        threading.Thread(target=server_events,daemon=True).start()
        client_environment=dict(PATH='/usr/bin:/bin',WLOG_LEVEL='OFF',HOME=tmp,TMPDIR=tmp,LANG='en_US.UTF-8')
        client=subprocess.Popen([str(helper)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=diagnostic,env=client_environment)
        def read_packets():
            try:
                while True:
                    size=struct.unpack('>I',exact(client.stdout,4))[0]
                    if not 1<=size<=40*1024*1024:raise AssertionError('Invalid packet framing')
                    data=exact(client.stdout,size);packets.put((data[0],data[1:]))
            except EOFError:pass
            except Exception as error:failures.put(error)
        threading.Thread(target=read_packets,daemon=True).start()
        def send(item):client.stdin.write(json.dumps(item).encode()+b'\n');client.stdin.flush()
        send(dict(protocol='rdp',host='127.0.0.1',port=port,user='fixture',password='synthetic-not-real',domain='',clipboard=True,diagnostic=True,width=800,height=600))
        seen=set();deadline=time.monotonic()+30
        while seen!={'certificate','frame','clipboard'} and time.monotonic()<deadline:
            kind,payload=packets.get(timeout=30)
            if kind==4:
                info=json.loads(payload);assert info['fingerprint'];seen.add('certificate');send(dict(type='certificate',accept=True))
            elif kind==1:
                width,height=struct.unpack('>II',payload[:8]);assert width>0 and height>0
                assert (width,height)==(800,600),(width,height)
                assert payload[8:11]==bytes([255,0,0]),payload[8:12];seen.add('frame')
            elif kind==3:
                assert payload.decode()=='remote RDP 中文',payload;seen.add('clipboard')
            elif kind==2 and b'failed' in payload:raise AssertionError(payload.decode())
        assert seen=={'certificate','frame','clipboard'},seen
        send(dict(type='resize',width=1000,height=700))
        deadline=time.monotonic()+20
        while True:
            kind,payload=packets.get(timeout=20)
            if kind==1 and struct.unpack('>II',payload[:8])==(1000,700):
                assert len(payload)==8+1000*700*4;break
            if time.monotonic()>deadline:raise AssertionError('RDP did not resize its framebuffer')
        send(dict(type='key',scan=0x1e,keysym=0x61,down=True));send(dict(type='mouse',x=2,y=1,flags=0x9000,buttons=1));send(dict(type='clipboard',text='local RDP fixture 中文'))
        expected={'key','mouse','clipboard','resize 1000 700','audio-confirmed'};deadline=time.monotonic()+20
        while expected and time.monotonic()<deadline:expected.discard(events.get(timeout=20))
        assert not expected,expected
        send(dict(type='stop'));client.wait(timeout=5)
        print('Real TLS RDP certificate approval, bitmap, keyboard, pointer and bidirectional Unicode clipboard passed.')
        print('RDP initial 800x600 resolution, dynamic 1000x700 monitor layout and resized framebuffer passed.')
        print('RDP PCM audio negotiation and playback acknowledgment passed.')
        print('Fixture uses TLS security; production Windows NLA accounts require separate live verification.')
    finally:
        for process in [client,server]:
            if process is not None and process.poll() is None:process.kill();process.wait()
        diagnostic.close()
