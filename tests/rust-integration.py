"""Offline C/Rust comparison through real CUPS raster and fd 3/4 APIs.

The backend here is a deliberately simple synthetic LBP2900, not a hardware
simulation claim. It exercises the system ABI and records complete CAPT output.
No CUPS daemon, queue, USB device, network or root access is used.
"""
import os
import selectors
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUST = ROOT / 'rust/target/release/rastertocapt-lbp2900-rust'
C = ROOT / 'build/tests/c-reference'
LAUNCH = '''import os,sys
back=os.dup(int(sys.argv[1])); side=os.dup(int(sys.argv[2]))
os.dup2(back,3); os.dup2(side,4)
os.set_inheritable(3,True); os.set_inheritable(4,True)
os.execv(sys.argv[3],sys.argv[3:])
'''

def run(program, raster, mode='normal', expected_pages=1):
    back, child_back = socket.socketpair()
    side, child_side = socket.socketpair()
    proc = subprocess.Popen([sys.executable, '-c', LAUNCH,
        str(child_back.fileno()), str(child_side.fileno()), str(program),
        '1', 'fixture-user', 'fixture-title', '1', '', str(raster)],
        pass_fds=(child_back.fileno(), child_side.fileno()), stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    child_back.close(); child_side.close()
    sel = selectors.DefaultSelector()
    sel.register(side, selectors.EVENT_READ, 'side')
    sel.register(proc.stdout, selectors.EVENT_READ, 'output')
    sel.register(proc.stderr, selectors.EVENT_READ, 'error')
    buffers = {'side': bytearray(), 'output': bytearray(), 'error': bytearray()}
    transcript = []
    page = 0
    received = 0
    completed = 0
    started = time.monotonic()
    sent_cancel = False
    try:
        while sel.get_map():
            assert time.monotonic()-started < 25, (program, mode, buffers['error'][-2000:])
            if mode == 'cancel' and not sent_cancel and time.monotonic()-started > 0.3:
                proc.send_signal(signal.SIGTERM); sent_cancel = True
            for key, _ in sel.select(0.05):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    sel.unregister(key.fileobj)
                    continue
                name = key.data
                buffers[name].extend(chunk)
                if name == 'error':
                    continue
                data = buffers[name]
                while len(data) >= 4:
                    size = (int.from_bytes(data[2:4], 'big')+4 if name == 'side'
                            else int.from_bytes(data[2:4], 'little'))
                    assert 4 <= size <= 65539
                    if len(data) < size:
                        break
                    packet = bytes(data[:size]); del data[:size]
                    if name == 'side':
                        command = packet[0]
                        assert command in [2, 4], command
                        payload = (b'MFG:Canon;MDL:LBP3000;' if mode == 'wrong-model'
                                   else b'MFG:Canon;MDL:LBP2900;') if command == 4 else b''
                        side.sendall(bytes([command, 1])+len(payload).to_bytes(2, 'big')+payload)
                        continue
                    transcript.append(packet)
                    cmd = int.from_bytes(packet[:2], 'little')
                    if cmd == 0xd0a9:
                        page += 1
                    if cmd == 0xc0a4:
                        received = page
                    if cmd == 0xe0a7:
                        completed = page
                    if cmd in [0xd0a9, 0xc0a0, 0xc0a4]:
                        continue
                    payload = bytearray(40 if cmd == 0xa0a8 else 2)
                    if cmd == 0xa0a8:
                        for offset, value in [(14,page),(16,page),(18,completed),(20,completed),(34,received)]:
                            payload[offset:offset+2] = value.to_bytes(2,'little')
                    if cmd == 0xa2a0:
                        payload = bytearray([0,0,0x34,0x12])
                    if mode == 'short-job' and cmd == 0xa2a0:
                        payload = bytearray(2)
                    response = struct.pack('<HH',cmd,len(payload)+4)+payload
                    if mode != 'cancel':
                        back.sendall(response)
            if proc.poll() is not None:
                # Sockets no longer need a response; pipes may still contain logs.
                for sock in [side]:
                    try: sel.unregister(sock)
                    except KeyError: pass
        result = proc.wait(timeout=3)
        log = bytes(buffers['error'])
        assert not buffers['output'], 'partial CAPT output'
        if mode == 'normal':
            assert result == 0, (program, result, log)
            assert log.count(b'PAGE: ') == expected_pages, log
        else:
            assert result != 0, (program, mode, log)
            assert b'PAGE: ' not in log, log
        if mode in ['wrong-model', 'invalid-raster']:
            assert not transcript, transcript
        return transcript
    finally:
        if proc.poll() is None:
            proc.kill(); proc.wait()
        sel.close(); back.close(); side.close()
        proc.stdout.close(); proc.stderr.close()

def normalize(packets):
    normalized = []
    for original in packets:
        packet = bytearray(original)
        if packet[:2] == b'\xa1\xe1':
            packet[28:35] = b'\0'*7  # Local wall-clock timestamp only.
        normalized.append(bytes(packet))
    return normalized

with tempfile.TemporaryDirectory(prefix='lbp-rust-test-') as temp:
    raster = Path(temp)/'synthetic.raster'
    for width,height,pages in [(8,2,1),(4736,141,2),(8192,256,1)]:
        raster.write_bytes(subprocess.check_output([str(ROOT/'build/tests/rust-raster'),str(width),str(height),str(pages)]))
        if width == 8:
            subprocess.run([str(ROOT/'build/tests/rust-adapter'),str(raster)],check=True,timeout=5)
        c = normalize(run(C,raster,expected_pages=pages))
        rust = normalize(run(RUST,raster,expected_pages=pages))
        assert c == rust, ('C/Rust CAPT transcript differs',width,height,pages,
            next(((i,a[:100],b[:100]) for i,(a,b) in enumerate(zip(c,rust)) if a!=b), (len(c),len(rust))))
        print(f'PASS real CUPS C/Rust transcript: {width}x{height}, {pages} page(s)', flush=True)
    for mode in ['wrong-model','short-job','cancel']:
        run(RUST,raster,mode)
        print('PASS Rust integration failure:',mode,flush=True)
    raster.write_bytes(b'not a raster')
    run(RUST,raster,'invalid-raster')
    print('PASS invalid raster rejected before CAPT output',flush=True)
