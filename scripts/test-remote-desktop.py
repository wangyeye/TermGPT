#!/usr/bin/env python3
"""Exercise the real embedded VNC client on a synthetic loopback RFB server. No saved credentials are read."""
import json, os, queue, shutil, socket, struct, subprocess, sys, threading, time
from pathlib import Path
if sys.platform != 'darwin' or not shutil.which('clang'):
    raise SystemExit('Requires macOS with Command Line Tools')
helper = Path(sys.argv[1] if len(sys.argv)>1 else '.build/remote-arm64/TermGPTRemoteDesktop').resolve()
if not helper.is_file(): raise SystemExit('Build scripts/build-remote-desktop.sh first')
audio_mode = '--audio' in sys.argv
password_mode = '--password' in sys.argv
black_mode = '--initial-black' in sys.argv
resize_mode = '--resize' in sys.argv
resize_black = '--resize-black' in sys.argv
password = 'fixture8' if password_mode else ''
listener = socket.socket(); listener.bind(('127.0.0.1',0)); listener.listen(1); listener.settimeout(20)
events = queue.Queue(); errors = queue.Queue(); packets = queue.Queue()
def read_exact(stream, length):
    data = b''
    while len(data)<length:
        chunk = stream.recv(length-len(data)) if hasattr(stream,'recv') else stream.read(length-len(data))
        if not chunk: raise EOFError()
        data += chunk
    return data
def server():
    try:
        connection,_=listener.accept()
        with connection:
            connection.settimeout(20)
            connection.sendall(b'RFB 003.008\n'); assert read_exact(connection,12)==b'RFB 003.008\n'
            security = b'\x02' if password_mode else b'\x01'
            connection.sendall(b'\x01'+security); assert read_exact(connection,1)==security
            if password_mode:
                challenge=bytes(range(16));connection.sendall(challenge)
                key=bytes(int(f'{byte:08b}'[::-1],2) for byte in password.encode()).hex()
                expected=subprocess.check_output(['/usr/bin/openssl','enc','-des-ecb','-nopad','-nosalt','-K',key],input=challenge,stderr=subprocess.DEVNULL)
                assert read_exact(connection,16)==expected
            connection.sendall(b'\0'*4); read_exact(connection,1)
            name=b'TermGPT synthetic desktop'
            connection.sendall(struct.pack('>HHBBBBHHHBBB3xI',4,3,32,24,0,1,255,255,255,0,8,16,len(name))+name)
            sent=False; woke=False; dimensions=(4,3)
            while True:
                kind=read_exact(connection,1)[0]
                if kind==0: read_exact(connection,19)
                elif kind==2:
                    header=read_exact(connection,3); encodings=read_exact(connection,struct.unpack('>H',header[1:])[0]*4)
                    if audio_mode: assert -259 in struct.unpack('>'+str(len(encodings)//4)+'i',encodings)
                elif kind==3:
                    read_exact(connection,9)
                    # Solid red RGBA plus a text clipboard notification.
                    if not sent:
                        framebuffer=struct.pack('>BBHHHHHi',0,0,1,0,0,4,3,0)+(bytes([0,0,0,0]) if black_mode else bytes([255,0,0,0]))*12
                        text=b'remote clipboard fixture'
                        # One TCP write forces read-ahead of the next message after the framebuffer.
                        if resize_mode:
                            # Screen ID zero is valid and must survive the client's resize request.
                            framebuffer += struct.pack('>BBHHHHHi',0,0,1,0,0,4,3,-308)+struct.pack('>B3xIHHHHI',1,0,0,0,4,3,0)
                        if audio_mode: framebuffer += struct.pack('>BBHHHHHi',0,0,1,0,0,0,0,-259)
                        connection.sendall(framebuffer+struct.pack('>BBBBI',3,0,0,0,len(text))+text); sent=True
                elif kind==255 and audio_mode:
                    subtype,operation=struct.unpack('>BH',read_exact(connection,3));assert subtype==1
                    if operation==2: assert read_exact(connection,6)==bytes([3,2,0,0,0xac,0x44])
                    elif operation==0:
                        samples=b''.join(struct.pack('<hh',500 if i%100<50 else -500,500 if i%100<50 else -500) for i in range(8820))
                        connection.sendall(bytes([255,1,0,1,255,1,0,2])+struct.pack('>I',len(samples))+samples)
                    else: raise AssertionError('Unexpected audio operation')
                elif kind==4:
                    data=read_exact(connection,7); events.put(('key',data[0],struct.unpack('>I',data[3:])[0]))
                elif kind==5:
                    data=read_exact(connection,5); events.put(('mouse',data[0],*struct.unpack('>HH',data[1:])))
                    if (black_mode or resize_black) and not woke:
                        assert data[0] == 0, 'Initial display wake must not press a mouse button'
                        woke=True
                        width,height=dimensions
                        connection.sendall(struct.pack('>BBHHHHHi',0,0,1,0,0,width,height,0)+bytes([255,0,0,0])*width*height)
                elif kind==6:
                    data=read_exact(connection,7); length=struct.unpack('>I',data[3:])[0]
                    # No extended clipboard was advertised, so this remains Latin-1.
                    events.put(('clipboard',read_exact(connection,length)))
                elif kind==251 and resize_mode:
                    header=read_exact(connection,7); width,height,count=struct.unpack('>xHHB',header[:6])
                    assert count==1
                    screen=read_exact(connection,16); identifier,x,y,w,h,flags=struct.unpack('>IHHHHI',screen)
                    assert identifier==0 and (w,h)==(width,height) and (x,y)==(0,0)
                    events.put(('resize',width,height))
                    dimensions=(width,height);woke=False
                    connection.sendall(struct.pack('>BBHHHHHi',0,0,1,1,0,width,height,-308)+struct.pack('>B3xIHHHHI',1,0,0,0,width,height,0)+struct.pack('>BBHHHHHi',0,0,1,0,0,width,height,0)+(bytes([0,0,0,0]) if resize_black else bytes([255,0,0,0]))*width*height)
                else: raise AssertionError('Unexpected RFB message')
    except EOFError: pass
    except Exception as error: errors.put(error)
thread=threading.Thread(target=server,daemon=True);thread.start()
diagnostic = helper.parent / 'vnc-fixture.log'
log = diagnostic.open('wb')
process=subprocess.Popen([str(helper)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log)
def collect():
    try:
        while True:
            length=struct.unpack('>I',read_exact(process.stdout,4))[0]
            if not 1<=length<=40*1024*1024: raise AssertionError('Invalid helper framing')
            payload=read_exact(process.stdout,length); packets.put((payload[0],payload[1:]))
    except EOFError: pass
    except Exception as error: errors.put(error)
threading.Thread(target=collect,daemon=True).start()
def send(item): process.stdin.write(json.dumps(item).encode()+b'\n');process.stdin.flush()
try:
    send(dict(protocol='vnc',host='127.0.0.1',port=listener.getsockname()[1],user='',password=password,domain='',clipboard=True))
    seen=set(); statuses=[]; deadline=time.monotonic()+20
    while time.monotonic()<deadline and seen!={1,3}:
        try: kind,payload=packets.get(timeout=20)
        except queue.Empty:
            if not errors.empty(): raise errors.get()
            raise AssertionError(('Missing frame/clipboard',seen,statuses,process.poll()))
        if kind==2: statuses.append(payload.decode(errors='replace'))
        if kind==1:
            assert struct.unpack('>II',payload[:8])==(4,3)
            if black_mode and payload[8:]==b'\0'*48:continue
            assert payload[8:]==bytes([255,0,0,0])*12;seen.add(1)
        if kind==3: assert payload==b'remote clipboard fixture';seen.add(3)
    assert seen=={1,3}
    if audio_mode:
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            kind,payload=packets.get(timeout=10)
            if kind==6 and payload==b'VNC audio buffer consumed':break
        else: raise AssertionError('VNC audio not consumed')
        print('VNC QEMU Audio negotiated, PCM playback queue consumed samples.')
    if resize_mode:
        for size in [(800,600),(1000,700)]:
            send(dict(type='resize',width=size[0],height=size[1]))
            deadline=time.monotonic()+15
            while True:
                kind,payload=packets.get(timeout=15)
                if kind==1 and struct.unpack('>II',payload[:8])==size:
                    assert len(payload)==8+size[0]*size[1]*4
                    if payload[8:12]==bytes([255,0,0,0]):break
                if time.monotonic()>deadline:raise AssertionError('Resize did not produce matching framebuffer')
    send(dict(type='audio',muted=True));send(dict(type='audio',muted=False))
    send(dict(type='key',scan=0x1e,keysym=0x61,down=True))
    send(dict(type='mouse',x=2,y=1,flags=0x9000,buttons=1))
    send(dict(type='clipboard',text='local clipboard fixture'))
    expected={('key',1,0x61),('mouse',1,2,1),('clipboard',b'local clipboard fixture')}
    deadline=time.monotonic()+20
    while expected and time.monotonic()<deadline: expected.discard(events.get(timeout=20))
    assert not expected
    send(dict(type='stop'));process.wait(timeout=5)
    if not errors.empty(): raise errors.get()
    print('Real VNC '+('password authentication, ' if password_mode else 'handshake, ')+'framebuffer, keyboard, pointer and bidirectional text clipboard passed.')
    if resize_mode:print('VNC dynamic resolution and valid screen ID zero passed at 800x600 and 1000x700.')
finally:
    if process.poll() is None:process.kill();process.wait()
    listener.close();thread.join(timeout=2)
    log.close()
