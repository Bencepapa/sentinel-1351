import socket, subprocess, time, re, sys
VICE=r'C:\C64\GTK3VICE-3.7-win64\bin\x64sc.exe'
PORT=6510
def launch(media, extra=()):
    return subprocess.Popen([VICE,'-remotemonitor','-warp','-sound','-sounddev','dummy','-autostart',media,*extra])
class Mon:
    def __init__(s):
        for _ in range(60):
            try: s.k=socket.create_connection(('127.0.0.1',PORT)); break
            except OSError: time.sleep(0.5)
        else: raise SystemExit('no monitor')
        s.k.settimeout(5); s.read()
    def read(s):
        b=b''; s.k.settimeout(1.0)
        while True:
            try: c=s.k.recv(65536)
            except socket.timeout: break
            if not c: break
            b+=c; s.k.settimeout(0.25)
        return b.decode('latin1')
    def cmd(s,c):
        s.k.sendall(c.encode()+b'\n'); return s.read()
