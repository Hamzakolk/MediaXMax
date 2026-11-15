const THEMES = {
  dark:  { a: "#1E88FF", b: "#8B5CF6", label: "Dark" },
  light: { a: "#2563EB", b: "#0EA5E9", label: "Light" },
  neon:  { a: "#00F5FF", b: "#FF00E6", label: "Neon" },
};
const ICON_PACKS = {
  dark:  { play: "▶", pause: "❚❚", prev: "⏮", next: "⏭" },
  light: { play: "►", pause: "II", prev: "«", next: "»" },
  neon:  { play: "⏵", pause: "⏸", prev: "⏪", next: "⏩" },
};
let ICON = ICON_PACKS.dark;
const VIZ_LABELS = { spectrum: "Spectrum", wave: "Waveform", vector: "Vectorscope", none: "Off" };
const HWDEC_LABELS = { "auto-safe": "Auto (recommended)", d3d11va: "Direct3D 11", no: "Software" };

let lib = { items: [], playlists: {}, version: 0, channels: [], groups: [], sources: [] };
let libVersion = -1;
let settings = null;
let view = "home";
let playlistName = null;
let visibleList = [];
let player = { playing: false, current: null, index: -1, count: 0 };
let seeking = false;
let addTarget = null;

const $ = (id) => document.getElementById(id);
const api = () => (window.pywebview ? window.pywebview.api : null);

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function fmtTime(s) {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const p = (x) => String(x).padStart(2, "0");
  return h ? `${h}:${p(m)}:${p(sec)}` : `${m}:${p(sec)}`;
}
function fmtSize(n) {
  if (!n) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return n.toFixed(i ? 1 : 0) + " " + u[i];
}

function applyTheme(name) {
  const key = THEMES[name] ? name : "dark";
  const th = THEMES[key];
  document.documentElement.style.setProperty("--a", th.a);
  document.documentElement.style.setProperty("--b", th.b);
  document.body.className = "theme-" + key;
  ICON = ICON_PACKS[key];
  if ($("btn-prev")) $("btn-prev").textContent = ICON.prev;
  if ($("btn-next")) $("btn-next").textContent = ICON.next;
}

function fill(sel, pairs, current) {
  sel.innerHTML = pairs.map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join("");
  sel.value = current;
}

function applySettings() {
  applyTheme(settings.theme);
  fill($("viz"), settings.viz.map((v) => [v, VIZ_LABELS[v]]), settings.viz_current || "spectrum");
  $("set-autoscan").checked = !!settings.auto_scan;
  fill($("set-theme"), Object.keys(THEMES).map((k) => [k, THEMES[k].label]), settings.theme);
  fill($("set-viz"), settings.viz.map((v) => [v, VIZ_LABELS[v]]), settings.viz_current || "spectrum");
  fill($("set-hwdec"), settings.hwdec_modes.map((m) => [m, HWDEC_LABELS[m]]), settings.hwdec);
  $("volume").value = settings.volume;
}

function visibleItems() {
  if (view === "iptv") {
    const g = $("iptv-group").value;
    const q = $("search").value.trim().toLowerCase();
    return lib.channels.filter((c) => (!g || c.group === g) && (!q || c.name.toLowerCase().includes(q)));
  }
  let items = lib.items;
  if (view === "video") items = items.filter((i) => i.kind === "video");
  if (view === "audio") items = items.filter((i) => i.kind === "audio");
  if (view === "playlist" && playlistName) {
    const byPath = new Map(lib.items.map((i) => [i.path, i]));
    items = (lib.playlists[playlistName] || []).map((p) => byPath.get(p)).filter(Boolean);
  }
  const q = $("search").value.trim().toLowerCase();
  if (q) items = items.filter((i) => i.name.toLowerCase().includes(q));
  return items;
}

function channelCardHTML(c) {
  const art = c.logo
    ? `<img src="${esc(c.logo)}" alt="" onerror="this.remove()" />`
    : `<span>${esc(c.name.slice(0, 2).toUpperCase())}</span>`;
  return `<div class="card" data-path="${esc(c.url)}">
    <div class="thumb logo">${art}<span class="live">LIVE</span></div>
    <div class="title">${esc(c.name)}</div>
    <div class="meta">${esc(c.group)}</div>
  </div>`;
}

function renderSources() {
  $("iptv-sources").innerHTML = lib.sources.map((s) =>
    `<span class="chip">${esc(s.name)} · ${s.count}<button data-src="${esc(s.name)}" title="Remove">✕</button></span>`
  ).join("");
  const cur = $("iptv-group").value;
  fill($("iptv-group"), [["", "All groups"]].concat(lib.groups.map((g) => [g, g])), cur);
}

function renderGrid() {
  visibleList = visibleItems();
  if (view === "iptv") {
    $("iptv-bar").classList.remove("hidden");
    renderSources();
    $("view-title").textContent = "IPTV";
    $("view-count").textContent = `${visibleList.length} channels`;
    $("btn-del-pl").classList.add("hidden");
    $("grid").innerHTML = visibleList.length
      ? visibleList.slice(0, 500).map(channelCardHTML).join("")
      : `<div class="muted" style="padding:30px">Add an M3U playlist to see channels.</div>`;
    markPlaying();
    return;
  }
  $("iptv-bar").classList.add("hidden");
  const titles = { home: "Library", video: "Video", audio: "Music", playlist: playlistName || "Playlist" };
  $("view-title").textContent = titles[view] || "Library";
  $("view-count").textContent = `${visibleList.length} items`;
  $("btn-del-pl").classList.toggle("hidden", view !== "playlist");
  const inPl = view === "playlist";
  $("grid").innerHTML = visibleList.length
    ? visibleList.map((it) => cardHTML(it, inPl)).join("")
    : `<div class="muted" style="padding:30px">Nothing here yet. Click "Add files" or "Add folder".</div>`;
  markPlaying();
}

function cardHTML(it, inPlaylist) {
  const ext = (it.ext || "").toUpperCase();
  const icon = it.kind === "audio" ? "♪" : "▶";
  const removeBtn = inPlaylist
    ? `<button data-rmpl="${esc(it.path)}" title="Remove from playlist">✕</button>`
    : `<button data-del="${esc(it.path)}" title="Remove from library">✕</button>`;
  return `<div class="card" data-path="${esc(it.path)}">
    <div class="thumb">${icon}<span class="badge">${esc(ext)}</span></div>
    <div class="actions">
      <button data-addto="${esc(it.path)}" title="Add to playlist">+</button>
      ${removeBtn}
    </div>
    <div class="title">${esc(it.name)}</div>
    <div class="meta">${it.kind === "audio" ? "Audio" : "Video"} · ${fmtSize(it.size)}</div>
  </div>`;
}

function markPlaying() {
  document.querySelectorAll(".card").forEach((c) => c.classList.toggle("playing", c.dataset.path === player.current));
}

function renderSidebar() {
  $("cnt-home").textContent = lib.items.length;
  $("cnt-video").textContent = lib.items.filter((i) => i.kind === "video").length;
  $("cnt-audio").textContent = lib.items.filter((i) => i.kind === "audio").length;
  $("cnt-iptv").textContent = lib.channels.length;
  const names = Object.keys(lib.playlists);
  $("pl-list").innerHTML = names.map((n) =>
    `<button class="nav-item ${view === "playlist" && playlistName === n ? "active" : ""}" data-pl="${esc(n)}"><span>${esc(n)}</span><b>${(lib.playlists[n] || []).length}</b></button>`
  ).join("");
}

function renderHero() {
  if (!player.playing || !player.current) {
    $("hero").classList.add("hidden");
    return;
  }
  const it = lib.items.find((i) => i.path === player.current);
  $("hero").classList.remove("hidden");
  $("hero-kind").textContent = it && it.kind === "audio" ? "Now playing · Music" : "Now playing · Video";
  $("hero-title").textContent = player.name || (it ? it.name : "");
  if (player.live) $("hero-kind").textContent = "Now playing · Live";
  $("hero-sub").textContent = player.live ? "Live stream plays in the Media X Max player window." : it && it.kind === "audio"
    ? "Visualizer runs in the Media X Max player window."
    : "Video plays in the Media X Max player window.";
}

function renderPlayer() {
  $("np-title").textContent = player.playing ? (player.name || "") : "Nothing playing";
  $("np-sub").textContent = player.playing ? `${player.index + 1} / ${player.count}` : "Pick something from your library";
  $("btn-play").textContent = player.paused === false ? ICON.pause : ICON.play;
  $("seek").disabled = !!player.live;
  if (player.live) {
    $("t-now").textContent = "LIVE";
    $("t-end").textContent = "";
  }
  if (!seeking && !player.live) {
    const dur = player.duration || 0;
    $("seek").value = dur ? Math.round((player.time / dur) * 1000) : 0;
    $("t-now").textContent = fmtTime(player.time);
    $("t-end").textContent = fmtTime(dur);
  }
  if (!seeking && document.activeElement !== $("volume")) $("volume").value = player.volume ?? 100;
}

async function refreshLibrary(force) {
  const a = api();
  if (!a) return;
  const data = await a.library();
  if (force || data.version !== libVersion) {
    lib = data;
    lib.channels = data.channels || [];
    lib.groups = data.groups || [];
    lib.sources = data.sources || [];
    libVersion = data.version;
    renderSidebar();
    renderGrid();
    renderHero();
  }
}

async function tick() {
  const a = api();
  if (!a) return;
  const before = player.current;
  const s = await a.state();
  player = Object.assign(player, s);
  if (s.current && s.current !== before) {
    renderHero();
  }
  if (s.error === "mpv_missing") showError("mpv not found. Install mpv or build with the mpv folder.");
  if (s.error === "mpv_failed") showError("mpv could not start.");
  renderPlayer();
  markPlaying();
}

function showError(text) {
  $("np-sub").textContent = text;
}

function setView(v, plName) {
  view = v;
  playlistName = plName || null;
  document.querySelectorAll("[data-view]").forEach((el) => el.classList.toggle("active", el.dataset.view === v));
  $("search").placeholder = v === "iptv" ? "Search channels" : "Search your library";
  renderSidebar();
  renderGrid();
}

async function playPath(path) {
  const a = api();
  const r = await a.play(path, visibleList.map((i) => i.path || i.url));
  if (!r.ok) showError(r.error === "mpv_missing" ? "mpv not found." : "mpv could not start.");
  tick();
}

function openAddTo(path) {
  addTarget = path;
  const names = Object.keys(lib.playlists);
  $("addto-list").innerHTML = names.length
    ? names.map((n) => `<button data-to="${esc(n)}">${esc(n)}</button>`).join("")
    : `<div class="muted">No playlists yet. Create one with the + in the sidebar.</div>`;
  $("addto-dialog").showModal();
}

function wire() {
  document.querySelectorAll("[data-view]").forEach((el) =>
    el.addEventListener("click", () => setView(el.dataset.view)));
  $("search").addEventListener("input", renderGrid);

  $("grid").addEventListener("click", async (e) => {
    const addto = e.target.closest("[data-addto]");
    if (addto) { e.stopPropagation(); return openAddTo(addto.dataset.addto); }
    const del = e.target.closest("[data-del]");
    if (del) { e.stopPropagation(); await api().remove_item(del.dataset.del); return refreshLibrary(true); }
    const rm = e.target.closest("[data-rmpl]");
    if (rm) { e.stopPropagation(); await api().playlist_remove(playlistName, rm.dataset.rmpl); return refreshLibrary(true); }
    const card = e.target.closest(".card");
    if (card) playPath(card.dataset.path);
  });

  $("iptv-sources").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-src]");
    if (!b) return;
    await api().iptv_remove_source(b.dataset.src);
    refreshLibrary(true);
  });
  $("iptv-group").addEventListener("change", renderGrid);
  $("btn-m3u-file").addEventListener("click", async () => {
    const r = await api().iptv_add_file();
    if (!r.ok && r.error !== "cancelled") showError("Could not read that playlist.");
    refreshLibrary(true);
  });
  $("btn-m3u-url").addEventListener("click", () => { $("m3u-url").value = ""; $("m3u-dialog").showModal(); });
  $("m3u-cancel").addEventListener("click", () => $("m3u-dialog").close());
  $("btn-xtream").addEventListener("click", () => {
    ["xt-server", "xt-user", "xt-pass", "xt-name"].forEach((id) => ($(id).value = ""));
    $("xt-dialog").showModal();
  });
  $("xt-cancel").addEventListener("click", () => $("xt-dialog").close());
  $("xt-save").addEventListener("click", async () => {
    const server = $("xt-server").value.trim();
    const user = $("xt-user").value.trim();
    const pass = $("xt-pass").value;
    const name = $("xt-name").value.trim();
    if (!server || !user || !pass) return;
    $("xt-pass").value = "";
    const r = await api().iptv_add_xtream(server, user, pass, name);
    $("xt-dialog").close();
    if (!r.ok) {
      const msgs = { auth: "Wrong username or password.", empty: "That server has no live channels.", invalid: "Check the server address.", download: "Could not reach that server." };
      showError(msgs[r.error] || "Could not add that server.");
    }
    refreshLibrary(true);
  });
  $("m3u-save").addEventListener("click", async () => {
    const url = $("m3u-url").value.trim();
    if (!url) return;
    const r = await api().iptv_add_url(url);
    $("m3u-dialog").close();
    if (!r.ok) showError(r.error === "empty" ? "No channels found in that playlist." : "Could not download that playlist.");
    refreshLibrary(true);
  });

  $("pl-list").addEventListener("click", (e) => {
    const b = e.target.closest("[data-pl]");
    if (b) setView("playlist", b.dataset.pl);
  });

  $("btn-files").addEventListener("click", async () => { await api().add_files(); refreshLibrary(true); });
  $("btn-folder").addEventListener("click", async () => { await api().add_folder(); refreshLibrary(true); });

  $("btn-new-pl").addEventListener("click", () => { $("pl-name").value = ""; $("pl-dialog").showModal(); });
  $("pl-cancel").addEventListener("click", () => $("pl-dialog").close());
  $("pl-save").addEventListener("click", async () => {
    const name = $("pl-name").value.trim();
    if (!name) return;
    await api().playlist_create(name);
    $("pl-dialog").close();
    refreshLibrary(true);
  });
  $("btn-del-pl").addEventListener("click", async () => {
    if (!playlistName) return;
    await api().playlist_delete(playlistName);
    setView("home");
    refreshLibrary(true);
  });

  $("addto-list").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-to]");
    if (!b || !addTarget) return;
    await api().playlist_add(b.dataset.to, addTarget);
    $("addto-dialog").close();
    refreshLibrary(true);
  });
  $("addto-close").addEventListener("click", () => $("addto-dialog").close());

  $("btn-play").addEventListener("click", () => api().toggle());
  $("btn-prev").addEventListener("click", () => api().prev());
  $("btn-next").addEventListener("click", () => api().next());

  const seek = $("seek");
  seek.addEventListener("pointerdown", () => { seeking = true; });
  seek.addEventListener("input", () => {
    $("t-now").textContent = fmtTime((seek.value / 1000) * (player.duration || 0));
  });
  seek.addEventListener("change", () => {
    api().seek((seek.value / 1000) * (player.duration || 0));
    seeking = false;
  });

  $("volume").addEventListener("input", () => api().set_volume(parseInt($("volume").value, 10)));
  $("speed").addEventListener("change", () => api().set_speed(parseFloat($("speed").value)));
  $("viz").addEventListener("change", async () => {
    settings = await api().set_viz($("viz").value);
    applySettings();
  });

  $("btn-settings").addEventListener("click", () => $("settings-dialog").showModal());
  $("set-close").addEventListener("click", () => $("settings-dialog").close());
  $("tb-min").addEventListener("click", () => api()?.minimize());
  $("tb-max").addEventListener("click", () => api()?.toggle_maximize());
  $("tb-close").addEventListener("click", () => api()?.hide_to_tray());
  $("set-autoscan").addEventListener("change", async () => {
    settings = await api().set_auto_scan($("set-autoscan").checked);
  });
  $("set-scan-now").addEventListener("click", async () => {
    const r = await api().scan_now();
    showError(`Scan done: ${r.added} files found`);
    refreshLibrary(true);
  });
  $("set-theme").addEventListener("change", async () => {
    settings = await api().set_theme($("set-theme").value);
    applySettings();
  });
  $("set-viz").addEventListener("change", async () => {
    settings = await api().set_viz($("set-viz").value);
    applySettings();
  });
  $("set-hwdec").addEventListener("change", async () => {
    settings = await api().set_hwdec($("set-hwdec").value);
    applySettings();
  });

  document.addEventListener("keydown", (e) => {
    if (e.target.matches("input, select, textarea")) return;
    if (e.code === "Space") { e.preventDefault(); api().toggle(); }
    if (!player.live && e.code === "ArrowRight") api().seek((player.time || 0) + 5);
    if (!player.live && e.code === "ArrowLeft") api().seek(Math.max(0, (player.time || 0) - 5));
  });
}

async function boot() {
  settings = await api().get_settings();
  applySettings();
  wire();
  await refreshLibrary(true);
  setInterval(() => refreshLibrary(false), 2000);
  setInterval(tick, 400);
}

window.addEventListener("pywebviewready", boot);
