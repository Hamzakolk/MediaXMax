import os
import sys
import json
import time
import shutil
import threading
import re
import urllib.request
from urllib.parse import urlparse, quote

import webview

from player import Mpv

APP_NAME = "Media X Max"
FROZEN = getattr(sys, "frozen", False)
APP_DIR = os.path.dirname(sys.executable) if FROZEN else os.path.dirname(os.path.abspath(__file__))
RES_DIR = getattr(sys, "_MEIPASS", APP_DIR)
UI_DIR = os.path.join(RES_DIR, "ui")
DATA_DIR = os.path.join(os.path.expanduser("~"), ".mediaxmax")
LIBRARY_FILE = os.path.join(DATA_DIR, "library.json")
SETTINGS_FILE = os.path.join(DATA_DIR, "settings.json")

VIDEO_EXT = {"mp4", "mkv", "webm", "mov", "avi", "wmv", "m4v", "mpg", "mpeg", "ts", "m2ts", "3gp", "ogv", "vob", "flv"}
AUDIO_EXT = {"mp3", "flac", "wav", "aac", "m4a", "ogg", "opus", "wma", "aiff", "alac", "ape", "dsf", "dff", "wv", "mka"}

THEMES = {
    "dark": {"cmap": "intensity", "c1": "0x1E88FF", "c2": "0x8B5CF6"},
    "light": {"cmap": "cividis", "c1": "0x2563EB", "c2": "0x0EA5E9"},
    "neon": {"cmap": "rainbow", "c1": "0x00F5FF", "c2": "0xFF00E6"},
}
VIZ_NAMES = ("spectrum", "wave", "vector", "none")
HWDEC_MODES = ("auto-safe", "d3d11va", "no")


def find_mpv():
    for p in (os.path.join(RES_DIR, "mpv", "mpv.exe"),
              os.path.join(APP_DIR, "mpv", "mpv.exe"),
              shutil.which("mpv")):
        if p and os.path.isfile(p):
            return p
    return None


def kind_of(path):
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext in VIDEO_EXT:
        return "video"
    if ext in AUDIO_EXT:
        return "audio"
    return None


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else default
    except (OSError, ValueError):
        return default


def save_json(path, data):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


ATTR_RE = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')
MAX_CHANNELS = 20000


def parse_m3u(text, source):
    """Parse an M3U/M3U8 playlist into a list of live channels."""
    channels = []
    pending = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTINF"):
            attrs = dict(ATTR_RE.findall(line))
            name = line.rsplit(",", 1)[-1].strip() if "," in line else ""
            pending = {
                "name": attrs.get("tvg-name") or name or "Channel",
                "group": attrs.get("group-title") or "Other",
                "logo": attrs.get("tvg-logo", ""),
            }
        elif line.startswith("#"):
            continue
        elif line.startswith(("http://", "https://")):
            info = pending or {"name": line, "group": "Other", "logo": ""}
            channels.append({"id": line, "url": line, "name": info["name"], "group": info["group"],
                             "logo": info["logo"], "kind": "live", "source": source})
            pending = None
            if len(channels) >= MAX_CHANNELS:
                break
        else:
            pending = None
    return channels


def dialog(kind):
    fd = getattr(webview, "FileDialog", None)
    if fd is not None:
        return {"open": fd.OPEN, "folder": fd.FOLDER}[kind]
    return {"open": webview.OPEN_DIALOG, "folder": webview.FOLDER_DIALOG}[kind]


class Api:
    def __init__(self):
        self.window = None
        self.mpv = None
        self.mpv_error = None
        self.settings = {"theme": "dark", "auto_scan": False, "viz": "spectrum", "hwdec": "auto-safe", "volume": 100}
        self.settings.update(load_json(SETTINGS_FILE, {}))
        if self.settings.get("theme") not in THEMES:
            self.settings["theme"] = "dark"
        self.quitting = False
        self.maximized = False
        self.scanning = False
        data = load_json(LIBRARY_FILE, {})
        self.items = data.get("items", {})
        self.playlists = data.get("playlists", {})
        self.channels = data.get("channels", {})
        self.sources = data.get("sources", [])
        self.version = 1
        self.queue = []
        self.index = -1
        self.current = None
        self.last_load = 0.0

    # ----- persistence -----
    def _save_library(self):
        save_json(LIBRARY_FILE, {"items": self.items, "playlists": self.playlists,
                                 "channels": self.channels, "sources": self.sources})
        self.version += 1

    def _save_settings(self):
        save_json(SETTINGS_FILE, self.settings)

    # ----- player -----
    def _player(self):
        if self.mpv is not None and self.mpv.alive():
            return self.mpv
        exe = find_mpv()
        if not exe:
            self.mpv_error = "mpv_missing"
            return None
        try:
            self.mpv = Mpv(exe, self.settings["hwdec"])
            self.mpv.set("volume", self.settings["volume"])
            self.mpv_error = None
        except Exception:
            self.mpv = None
            self.mpv_error = "mpv_failed"
        return self.mpv

    def _viz(self, kind):
        if kind != "audio" or self.settings["viz"] == "none":
            return ""
        t = THEMES[self.settings["theme"]]
        name = self.settings["viz"]
        if name == "spectrum":
            return (f"[aid1]asplit[ao][a];[a]showspectrum=s=1280x720:mode=combined:slide=scroll"
                    f":scale=log:color={t['cmap']},format=yuv420p[vo]")
        if name == "wave":
            return (f"[aid1]asplit[ao][a];[a]showwaves=s=1280x720:mode=cline:rate=60"
                    f":colors={t['c1']}|{t['c2']},format=yuv420p[vo]")
        if name == "vector":
            return "[aid1]asplit[ao][a];[a]avectorscope=s=720x720,format=yuv420p[vo]"
        return ""

    def _load_current(self, m):
        path = self.queue[self.index]
        kind = self._kind(path)
        self.current = path
        self.last_load = time.time()
        m.command("loadfile", path, "replace")
        m.set("lavfi-complex", self._viz(kind))

    def play(self, path, context=None):
        m = self._player()
        if m is None:
            return {"ok": False, "error": self.mpv_error}
        ctx = context if context and path in context else [path]
        self.queue = list(ctx)
        self.index = self.queue.index(path)
        self._load_current(m)
        return {"ok": True}

    def toggle(self):
        if self.mpv and self.mpv.alive():
            self.mpv.command("cycle", "pause")

    def next(self):
        if self.mpv and self.mpv.alive() and self.index < len(self.queue) - 1:
            self.index += 1
            self._load_current(self.mpv)

    def prev(self):
        if not (self.mpv and self.mpv.alive()):
            return
        if self.mpv.get("time-pos", 0) and self.mpv.get("time-pos", 0) > 3:
            self.mpv.command("seek", 0, "absolute")
        elif self.index > 0:
            self.index -= 1
            self._load_current(self.mpv)

    def seek(self, seconds):
        if self.mpv and self.mpv.alive():
            self.mpv.command("seek", float(seconds), "absolute")

    def set_volume(self, value):
        self.settings["volume"] = max(0, min(130, int(value)))
        self._save_settings()
        if self.mpv and self.mpv.alive():
            self.mpv.set("volume", self.settings["volume"])

    def set_speed(self, value):
        if self.mpv and self.mpv.alive():
            self.mpv.set("speed", float(value))

    def set_viz(self, name):
        if name in VIZ_NAMES:
            self.settings["viz"] = name
            self._save_settings()
            self._apply_viz()
        return self.get_settings()

    def set_theme(self, name):
        if name in THEMES:
            self.settings["theme"] = name
            self._save_settings()
            self._apply_viz()
        return self.get_settings()

    def set_hwdec(self, mode):
        if mode in HWDEC_MODES:
            self.settings["hwdec"] = mode
            self._save_settings()
            if self.mpv and self.mpv.alive():
                self.mpv.set("hwdec", mode)
        return self.get_settings()

    def _apply_viz(self):
        if self.mpv and self.mpv.alive() and self.current:
            kind = self._kind(self.current)
            self.mpv.set("lavfi-complex", self._viz(kind))

    def state(self):
        m = self.mpv
        if m is None or not m.alive() or self.current is None:
            return {"playing": False, "current": None, "index": -1, "count": len(self.queue),
                    "error": self.mpv_error}
        s = m.state()
        # Auto-advance when a file ends (ignore the first moments after a load)
        if (s["eof"] and time.time() - self.last_load > 1.5 and self.index < len(self.queue) - 1
                and self._kind(self.current) != "live"):
            self.index += 1
            self._load_current(m)
            s = m.state()
        item = self.items.get(self.current, {})
        return {
            "playing": True,
            "current": self.current,
            "name": self._name(self.current),
            "kind": self._kind(self.current),
            "index": self.index,
            "count": len(self.queue),
            "time": s["time"],
            "duration": s["duration"],
            "paused": s["paused"],
            "volume": s["volume"],
            "speed": s["speed"],
            "error": None,
        }

    # ----- library -----
    def _add_file(self, path):
        kind = kind_of(path)
        if not kind:
            return False
        ext = os.path.splitext(path)[1].lower().lstrip(".")
        try:
            size = os.path.getsize(path)
        except OSError:
            size = 0
        self.items[path] = {"path": path, "name": os.path.splitext(os.path.basename(path))[0],
                            "kind": kind, "ext": ext, "size": size}
        return True

    def add_files(self):
        if self.window is None:
            return 0
        paths = self.window.create_file_dialog(dialog("open"), allow_multiple=True,
                                               file_types=("Media files (*.mp4;*.mkv;*.webm;*.mov;*.avi;*.mp3;*.flac;*.wav;*.m4a;*.ogg;*.opus)",))
        added = sum(1 for p in (paths or []) if self._add_file(p))
        if added:
            self._save_library()
        return added

    def add_folder(self):
        if self.window is None:
            return 0
        paths = self.window.create_file_dialog(dialog("folder"))
        if not paths:
            return 0
        added = 0
        for root, dirs, files in os.walk(paths[0]):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files:
                if self._add_file(os.path.join(root, name)):
                    added += 1
        if added:
            self._save_library()
        return added

    def remove_item(self, path):
        self.items.pop(path, None)
        for name in self.playlists:
            self.playlists[name] = [p for p in self.playlists[name] if p != path]
        self._save_library()

    def library(self):
        items = sorted(self.items.values(), key=lambda i: i["name"].lower())
        channels = sorted(self.channels.values(), key=lambda c: (c["group"].lower(), c["name"].lower()))
        groups = sorted({c["group"] for c in channels}, key=str.lower)
        return {"items": items, "playlists": self.playlists, "version": self.version,
                "channels": channels, "groups": groups, "sources": self.sources}

    # ----- playlists -----
    def playlist_create(self, name):
        name = (name or "").strip()
        if name and name not in self.playlists:
            self.playlists[name] = []
            self._save_library()
        return self.library()

    def playlist_delete(self, name):
        self.playlists.pop(name, None)
        self._save_library()
        return self.library()

    def playlist_add(self, name, path):
        if name in self.playlists and path not in self.playlists[name]:
            self.playlists[name].append(path)
            self._save_library()
        return True

    def playlist_remove(self, name, path):
        if name in self.playlists:
            self.playlists[name] = [p for p in self.playlists[name] if p != path]
            self._save_library()
        return True

    # ----- helpers -----
    def _kind(self, path):
        if path in self.items:
            return self.items[path].get("kind", "video")
        if path in self.channels:
            return "live"
        return kind_of(path) or "video"

    def _name(self, path):
        if path in self.items:
            return self.items[path].get("name", os.path.basename(path))
        if path in self.channels:
            return self.channels[path]["name"]
        return os.path.basename(path)

    # ----- IPTV (M3U playlists) -----
    def _add_source(self, name, text):
        return self._store_source(name, parse_m3u(text, name))

    def _store_source(self, name, channels):
        if not channels:
            return {"ok": False, "error": "empty"}
        self.sources = [x for x in self.sources if x["name"] != name]
        for cid in [c for c, v in self.channels.items() if v["source"] == name]:
            del self.channels[cid]
        for c in channels:
            self.channels[c["id"]] = c
        self.sources.append({"name": name, "count": len(channels)})
        self._save_library()
        return {"ok": True, "count": len(channels)}

    def iptv_add_url(self, url):
        url = (url or "").strip()
        if not url.startswith(("http://", "https://")):
            return {"ok": False, "error": "invalid"}
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Media X Max"})
            with urllib.request.urlopen(req, timeout=20) as r:
                text = r.read(20 * 1024 * 1024).decode("utf-8", errors="replace")
        except Exception:
            return {"ok": False, "error": "download"}
        p = urlparse(url)
        return self._add_source((p.netloc + p.path)[:60], text)

    def iptv_add_file(self):
        if self.window is None:
            return {"ok": False, "error": "cancelled"}
        paths = self.window.create_file_dialog(dialog("open"),
                                               file_types=("Playlists (*.m3u;*.m3u8)",))
        if not paths:
            return {"ok": False, "error": "cancelled"}
        try:
            with open(paths[0], "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            return {"ok": False, "error": "read"}
        return self._add_source(os.path.basename(paths[0]), text)

    def _xtream_get(self, base, user, pw, action=None):
        url = f"{base}/player_api.php?username={quote(user)}&password={quote(pw)}"
        if action:
            url += f"&action={action}"
        req = urllib.request.Request(url, headers={"User-Agent": "Media X Max"})
        with urllib.request.urlopen(req, timeout=25) as r:
            return json.loads(r.read(50 * 1024 * 1024).decode("utf-8", errors="replace"))

    def iptv_add_xtream(self, server, username, password, name=""):
        """Add a live-TV panel that uses the Xtream-style login (server + username + password)."""
        base = (server or "").strip().rstrip("/")
        user = (username or "").strip()
        pw = password or ""
        if not base.startswith(("http://", "https://")) or not user or not pw:
            return {"ok": False, "error": "invalid"}
        try:
            info = self._xtream_get(base, user, pw)
            auth = (info.get("user_info") or {}).get("auth")
            if str(auth) not in ("1", "True", "true"):
                return {"ok": False, "error": "auth"}
            cats = self._xtream_get(base, user, pw, "get_live_categories") or []
            streams = self._xtream_get(base, user, pw, "get_live_streams") or []
        except Exception:
            return {"ok": False, "error": "download"}
        if isinstance(streams, dict):
            streams = list(streams.values())
        if isinstance(cats, dict):
            cats = list(cats.values())
        group_of = {str(c.get("category_id")): c.get("category_name") or "Other"
                    for c in cats if isinstance(c, dict)}
        src = name.strip() or f"{urlparse(base).netloc} ({user})"
        channels = []
        for st in streams:
            if not isinstance(st, dict) or st.get("stream_id") is None:
                continue
            sid = st["stream_id"]
            url = f"{base}/live/{quote(user)}/{quote(pw)}/{sid}.ts"
            channels.append({"id": url, "url": url, "name": st.get("name") or f"Channel {sid}",
                             "group": group_of.get(str(st.get("category_id")), "Other"),
                             "logo": st.get("stream_icon") or "", "kind": "live", "source": src})
            if len(channels) >= MAX_CHANNELS:
                break
        return self._store_source(src, channels)

    def iptv_remove_source(self, name):
        for cid in [c for c, v in self.channels.items() if v["source"] == name]:
            del self.channels[cid]
        self.sources = [x for x in self.sources if x["name"] != name]
        self._save_library()
        return True

    # ----- settings -----
    def get_settings(self):
        return dict(self.settings, viz_current=self.settings["viz"], themes=list(THEMES), viz=list(VIZ_NAMES),
                    hwdec_modes=list(HWDEC_MODES), mpv_found=find_mpv() is not None)


    # ----- scan options -----
    def set_auto_scan(self, value):
        self.settings["auto_scan"] = bool(value)
        self._save_settings()
        return self.get_settings()

    def scan_now(self):
        added = self.scan_default_folders()
        return {"ok": True, "added": added}

    # ----- automatic scan of the usual media folders -----
    def scan_default_folders(self):
        if self.scanning:
            return 0
        self.scanning = True
        added = 0
        try:
            home = os.path.expanduser("~")
            roots = [os.path.join(home, "Music"), os.path.join(home, "Videos"), os.path.join(home, "Downloads")]
            for root in roots:
                if not os.path.isdir(root):
                    continue
                for dirpath, dirnames, filenames in os.walk(root):
                    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
                    for name in filenames:
                        if name.startswith("."):
                            continue
                        if self._add_file(os.path.join(dirpath, name)):
                            added += 1
            if added:
                self._save_library()
        finally:
            self.scanning = False
        return added

    # ----- window and tray -----
    def minimize(self):
        if self.window is not None:
            self.window.minimize()

    def toggle_maximize(self):
        if self.window is None:
            return
        try:
            if self.maximized:
                self.window.restore()
            else:
                self.window.maximize()
            self.maximized = not self.maximized
        except Exception:
            pass

    def hide_to_tray(self):
        if self.window is not None:
            self.window.hide()

    def show_window(self):
        if self.window is not None:
            self.window.show()

    def quit_app(self):
        self.quitting = True
        if self.window is not None:
            self.window.destroy()

    def on_closing(self):
        # Closing the window hides it; music keeps playing from the tray.
        if self.quitting:
            return True
        if self.window is not None:
            self.window.hide()
        return False

    def shutdown(self):
        if self.mpv:
            self.mpv.close()


def _tray_image():
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((4, 4, 60, 60), radius=14, fill=(139, 92, 246, 255))
    d.polygon([(24, 18), (24, 46), (48, 32)], fill=(255, 255, 255, 255))
    return img


def start_tray(api):
    try:
        import pystray
    except Exception:
        return None
    menu = pystray.Menu(
        pystray.MenuItem("Show", lambda icon, item: api.show_window(), default=True),
        pystray.MenuItem("Play / Pause", lambda icon, item: api.toggle()),
        pystray.MenuItem("Next", lambda icon, item: api.next()),
        pystray.MenuItem("Previous", lambda icon, item: api.prev()),
        pystray.MenuItem("Quit", lambda icon, item: (icon.stop(), api.quit_app())),
    )
    icon = pystray.Icon("MediaXMax", _tray_image(), APP_NAME, menu)
    threading.Thread(target=icon.run, daemon=True).start()
    return icon


def main():
    api = Api()
    window = webview.create_window(
        APP_NAME,
        url=os.path.join(UI_DIR, "index.html"),
        js_api=api,
        width=1360,
        height=860,
        min_size=(1100, 700),
        background_color="#0B0B14",
        frameless=True,
    )
    api.window = window
    window.events.closing += api.on_closing
    window.events.closed += api.shutdown
    start_tray(api)
    if api.settings.get("auto_scan"):
        threading.Thread(target=api.scan_default_folders, daemon=True).start()
    webview.start(debug=False)


if __name__ == "__main__":
    main()
