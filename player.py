import os
import json
import time
import uuid
import threading
import subprocess


class Mpv:
    """Controls a mpv window over its JSON IPC named pipe (Windows)."""

    def __init__(self, exe, hwdec="auto-safe"):
        self.pipe = r"\\.\pipe\mediaxmax-" + uuid.uuid4().hex[:10]
        args = [
            exe, "--idle=yes", "--force-window=yes", "--keep-open=yes", "--osc=no",
            "--vo=gpu-next", f"--hwdec={hwdec}", "--title=Media X Max",
            f"--input-ipc-server={self.pipe}", "--no-terminal",
        ]
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, creationflags=flags)
        self.f = self._connect()
        self.lock = threading.Lock()
        self.next_id = 1
        self.waiters = {}
        self.results = {}
        threading.Thread(target=self._reader, daemon=True).start()

    def _connect(self):
        for _ in range(100):
            try:
                return open(self.pipe, "r+b", buffering=0)
            except OSError:
                if self.proc.poll() is not None:
                    raise RuntimeError("mpv exited early")
                time.sleep(0.1)
        raise RuntimeError("could not connect to mpv")

    def _reader(self):
        buf = b""
        while True:
            try:
                chunk = self.f.read(4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                rid = msg.get("request_id")
                if rid is not None and rid in self.waiters:
                    self.results[rid] = msg
                    self.waiters.pop(rid).set()

    def _send(self, obj):
        data = (json.dumps(obj) + "\n").encode("utf-8")
        with self.lock:
            self.f.write(data)

    def command(self, *args):
        self._send({"command": list(args)})

    def set(self, prop, value):
        self.command("set_property", prop, value)

    def get(self, prop, default=None):
        with self.lock:
            rid = self.next_id
            self.next_id += 1
        ev = threading.Event()
        self.waiters[rid] = ev
        self._send({"command": ["get_property", prop], "request_id": rid})
        if not ev.wait(1.0):
            self.waiters.pop(rid, None)
            return default
        msg = self.results.pop(rid, {})
        return msg.get("data", default) if msg.get("error") == "success" else default

    def state(self):
        return {
            "time": self.get("time-pos", 0) or 0,
            "duration": self.get("duration", 0) or 0,
            "paused": bool(self.get("pause", True)),
            "volume": self.get("volume", 100),
            "speed": self.get("speed", 1.0),
            "eof": bool(self.get("eof-reached", False)),
        }

    def alive(self):
        return self.proc.poll() is None

    def close(self):
        try:
            self.proc.kill()
        except OSError:
            pass
