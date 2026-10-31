(() => {
  "use strict";

  const RAMP = " .:-=+*#%@";
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------------------------------------------------------------- i18n
  const STRINGS = {
    zh: {
      pageTitle: "Snapparazzi — 只錄一個 macOS 視窗",
      skip: "跳到內容",
      navLabel: "頁面區段",
      navUsage: "用法", navFeatures: "功能", navLimits: "注意事項",
      heroTitle: "只錄一個視窗。",
      heroLede: "原生的 macOS 指令列工具。把一個 App 視窗定時截圖，或錄成 MP4，連同那個 App 的聲音；其他視窗和其他 App 的聲音都不會錄進去。",
      installLabel: "在終端機貼上這一行安裝：",
      copy: "[ 複製 ]", copied: "[ 已複製 ]",
      copiedStatus: "已複製安裝指令，貼到終端機執行即可。",
      copyFailed: "無法自動複製，指令已選取，請按 ⌘C。",
      installNote: "需要 macOS 14 以上（錄影需要 15）與 Xcode Command Line Tools。安裝程式會在你的 Mac 上編譯原始碼，裝到 ~/.local/bin。",
      sceneLabel: "示意畫面：一個 macOS 桌面上有四個視窗，被選中的視窗正在錄影。",
      sceneHint: "示意畫面，把游標移到任一個視窗上（或按方向鍵）",
      usageTitle: "三個指令，錄好一個視窗",
      step1: "找到視窗的 ID。其他桌面或全螢幕的視窗也會列出來。",
      step2: "開始錄。--audio system 錄這個 App 的聲音，mic 錄麥克風，both 兩個都錄。",
      step3: "按 Ctrl-C 停止。看到「錄影完成」，影片就存好了。",
      usageNote: "只要截圖：<code>snapparazzi -w 41324 -i 2</code>，每 2 秒存一張 JPG。全部選項請看 <code>snapparazzi --help</code> 與 <code>snapparazzi record --help</code>。",
      featuresTitle: "它會做的事",
      fRecord: "錄成 MP4", fRecordD: "H.264 或 HEVC，1–60 fps。用 <code>--duration</code> 指定秒數，時間到自動停止。",
      fAudio: "聲音", fAudioD: "<code>--audio none | system | mic | both</code>。system 只錄這個 App 的聲音，其他 App 的通知聲不會進來；both 會混成一條音軌。",
      fShots: "定時截圖", fShotsD: "每 0.5 秒以上一張，存成 JPG、HEIC 或 PNG；<code>-m 1280</code> 限制最長邊。",
      fSpaces: "別的桌面與全螢幕", fSpacesD: "視窗在其他桌面或全螢幕也能直接錄；全螢幕的 Chrome 會填滿整個畫面。",
      fStop: "停止", fStopD: "按 Ctrl-C 乾淨停止並顯示摘要；視窗關閉時也會停止並保留已錄的內容。",
      fUpdate: "更新", fUpdateD: "<code>snapparazzi update</code> 查詢並安裝最新版本，<code>--check</code> 只查詢。",
      limitsTitle: "開始前先知道",
      l1: "第一次執行時，到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」允許你用的終端機 App；錄麥克風還要允許「麥克風」。",
      l2: "system 聲音是整個 App 的：同一個瀏覽器的其他分頁也會被錄進去。",
      l3: "Chrome 的視窗不在畫面上時（切到別的桌面）會停止繪製網頁影片，錄到的影片區域會是黑的。要在背景錄，先完全結束 Chrome，再用這行開啟：<code>open -a \"Google Chrome\" --args --disable-backgrounding-occluded-windows</code>",
      l4: "受 DRM 保護的內容可能錄不到畫面或聲音。",
      l5: "一個程序只處理一個視窗。要同時錄好幾個，就開好幾個終端機分頁。",
      closeTitle: "錄完按 Ctrl-C。",
      tagline: "專業地打擾你的視窗。"
    },
    en: {
      pageTitle: "Snapparazzi — record one macOS window",
      skip: "Skip to content",
      navLabel: "Sections",
      navUsage: "Usage", navFeatures: "Features", navLimits: "Limits",
      heroTitle: "One window.",
      heroLede: "A native macOS command-line tool. Screenshot one app window on an interval, or record it to MP4 with that app's sound. Other windows, and other apps' sounds, stay out.",
      installLabel: "Paste this line into Terminal to install:",
      copy: "[ COPY ]", copied: "[ COPIED ]",
      copiedStatus: "Install command copied. Paste it into Terminal and press Return.",
      copyFailed: "Could not copy automatically. The command is selected; press ⌘C.",
      installNote: "Needs macOS 14 or later (15 for recording) and the Xcode Command Line Tools. The installer builds from source on your Mac and installs to ~/.local/bin.",
      sceneLabel: "Illustration: a macOS desktop with four windows; the selected window is being recorded.",
      sceneHint: "Illustration. Point at any window (or use the arrow keys)",
      usageTitle: "Three commands to a recording",
      step1: "Find the window's ID. Windows on other desktops or in full screen are listed too.",
      step2: "Start recording. --audio system records that app's sound, mic the microphone, both records both.",
      step3: "Press Ctrl-C to stop. When you see \"recording saved\", the video is written.",
      usageNote: "Screenshots only: <code>snapparazzi -w 41324 -i 2</code> saves a JPG every 2 seconds. Every option is in <code>snapparazzi --help</code> and <code>snapparazzi record --help</code>.",
      featuresTitle: "What it does",
      fRecord: "Record to MP4", fRecordD: "H.264 or HEVC at 1–60 fps. <code>--duration</code> stops after that many seconds.",
      fAudio: "Sound", fAudioD: "<code>--audio none | system | mic | both</code>. system records only that app, so other apps' alerts stay out; both mixes into one track.",
      fShots: "Timed screenshots", fShotsD: "One every 0.5 s or more, as JPG, HEIC or PNG; <code>-m 1280</code> limits the longest edge.",
      fSpaces: "Other desktops, full screen", fSpacesD: "Windows on another desktop or in full screen record directly; full-screen Chrome fills the whole frame.",
      fStop: "Stopping", fStopD: "Ctrl-C stops cleanly and prints a summary; a closed window stops too and keeps what was recorded.",
      fUpdate: "Updating", fUpdateD: "<code>snapparazzi update</code> checks for and installs the latest release; <code>--check</code> only checks.",
      limitsTitle: "Before you start",
      l1: "On first run, allow your terminal app under System Settings → Privacy & Security → Screen & System Audio Recording, and Microphone too for mic recording.",
      l2: "system sound is the whole app: other tabs of the same browser are recorded too.",
      l3: "Chrome stops drawing web video while its window is not visible (on another desktop), so that part records black. To record in the background, quit Chrome and reopen it with: <code>open -a \"Google Chrome\" --args --disable-backgrounding-occluded-windows</code>",
      l4: "DRM-protected content may record without picture or sound.",
      l5: "One process handles one window. To record several, use one Terminal tab per window.",
      closeTitle: "Ctrl-C when you're done.",
      tagline: "Professionally bothering your windows."
    }
  };

  const store = {
    get() { try { return localStorage.getItem("snapparazzi-lang"); } catch { return null; } },
    set(v) { try { localStorage.setItem("snapparazzi-lang", v); } catch { /* private mode */ } }
  };

  function initialLang() {
    const saved = store.get();
    if (saved === "zh" || saved === "en") return saved;
    const langs = navigator.languages || [navigator.language || ""];
    return langs.some((l) => /^zh/i.test(l)) ? "zh" : "en";
  }

  let lang = initialLang();

  function applyLang(next) {
    lang = next;
    const t = STRINGS[lang];
    document.documentElement.lang = lang === "zh" ? "zh-Hant" : "en";
    document.title = t.pageTitle;
    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.dataset.i18n;
      if (key === "copy" && el.dataset.state === "done") return;
      if (t[key] != null) el.textContent = t[key];
    });
    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      const key = el.dataset.i18nHtml;
      if (t[key] != null) el.innerHTML = t[key];
    });
    document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
      const [attr, key] = el.dataset.i18nAttr.split(":");
      if (t[key] != null) el.setAttribute(attr, t[key]);
    });
    document.querySelectorAll(".lang button").forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    });
    glyphs.forEach((g) => g.render(false));
  }

  document.querySelectorAll(".lang button").forEach((b) => {
    b.addEventListener("click", () => {
      if (b.dataset.lang === lang) return;
      store.set(b.dataset.lang);
      applyLang(b.dataset.lang);
      glyphs.forEach((g) => g.render(true));
    });
  });

  // ---------------------------------------------------------------- copy
  const status = document.getElementById("copy-status");
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const source = document.getElementById(btn.dataset.copy);
      const text = source.textContent.trim();
      try {
        await navigator.clipboard.writeText(text);
        btn.dataset.state = "done";
        btn.textContent = STRINGS[lang].copied;
        status.textContent = STRINGS[lang].copiedStatus;
        clearTimeout(btn._timer);
        btn._timer = setTimeout(() => {
          delete btn.dataset.state;
          btn.textContent = STRINGS[lang].copy;
        }, 2200);
      } catch {
        const range = document.createRange();
        range.selectNodeContents(source);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        status.textContent = STRINGS[lang].copyFailed;
      }
    });
  });

  // ---------------------------------------------------------------- glyph text
  // Draws a heading's text into a small canvas and maps each cell's ink to the
  // density ramp, so the headline is typeset in characters.
  function cellSize(pre) {
    const probe = document.createElement("span");
    probe.textContent = "M".repeat(20);
    pre.appendChild(probe);
    const rect = probe.getBoundingClientRect();
    pre.removeChild(probe);
    const lh = parseFloat(getComputedStyle(pre).lineHeight) || rect.height;
    return { w: rect.width / 20 || 4, h: lh || 7 };
  }

  function makeGlyph(source, pre) {
    const g = { source, pre, cells: null, timer: 0 };
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d", { willReadFrequently: true });

    g.render = (animate) => {
      const raw = source.textContent.trim();
      const latin = !/[\u3400-\u9fff]/.test(raw);
      const text = latin ? raw.toUpperCase() : raw;   // capitals hold up better in glyphs
      g.cutoff = latin ? 0.35 : 0.25;                  // thin CJK strokes need a lower cutoff
      const width = pre.clientWidth || pre.parentElement.clientWidth;
      const cell = cellSize(pre);
      const cols = Math.max(20, Math.floor(width / cell.w));
      const aspect = cell.h / cell.w;            // a cell is this many times taller than wide
      const ss = 4;                              // supersampling per cell
      // Latin in the page's own mono at its widest and heaviest; Chinese in the system face.
      const family = '"Martian Mono", ' + getComputedStyle(document.documentElement).getPropertyValue("--cjk") + ", sans-serif";
      // Break into lines: CJK at the full stop or half way; Latin at the period.
      const lines = splitLines(text);
      // Pick a font size (in canvas px, canvas = cols*ss wide) so the widest line fills the width.
      const cw = cols * ss;
      ctx.font = `800 100px ${family}`;
      if ("fontStretch" in ctx) ctx.fontStretch = "normal";
      // One size for the whole block, or (data-fit="lines") each line filling the
      // width on its own, capped so a short line does not tower over the rest.
      const widths = lines.map((l) => ctx.measureText(l).width);
      const common = Math.floor(100 * (cw * 0.98) / Math.max(...widths));
      const sizes = source.dataset.fit === "lines"
        ? widths.map((w) => Math.min(Math.floor(100 * (cw * 0.98) / w), Math.floor(common * 1.6)))
        : widths.map(() => common);
      const total = sizes.reduce((a, b) => a + b * 1.12, 0);
      const rows = Math.ceil(total / (ss * aspect)) + 1;
      canvas.width = cw;
      canvas.height = Math.ceil(rows * ss * aspect);
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = "#fff";
      ctx.textBaseline = "alphabetic";
      let y = 0;
      lines.forEach((l, i) => {
        ctx.font = `800 ${sizes[i]}px ${family}`;
        if ("fontStretch" in ctx) ctx.fontStretch = "normal";
        ctx.fillText(l, 0, y + sizes[i] * 0.92);
        y += sizes[i] * 1.12;
      });
      const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      const cells = [];
      const ph = ss * aspect;
      for (let r = 0; r < rows; r++) {
        const row = [];
        for (let c = 0; c < cols; c++) {
          let sum = 0, n = 0;
          const y0 = Math.floor(r * ph), y1 = Math.floor((r + 1) * ph);
          for (let y = y0; y < y1; y++) {
            for (let x = c * ss; x < (c + 1) * ss; x++) { sum += data[(y * canvas.width + x) * 4]; n++; }
          }
          row.push(n ? sum / n / 255 : 0);
        }
        cells.push(row);
      }
      // Trim empty trailing rows.
      while (cells.length && cells[cells.length - 1].every((v) => v < 0.04)) cells.pop();
      g.cells = cells;
      if (animate && !reduceMotion) scramble(g); else paint(g, 1);
    };
    return g;
  }

  function splitLines(text) {
    // Mixed Chinese and Latin ("錄完按 Ctrl-C。"): break where the Latin run starts.
    const mixed = text.match(/^([㐀-鿿]+)\s*([A-Za-z].*)$/);
    if (mixed) return [mixed[1], mixed[2]];
    if (/[㐀-鿿]/.test(text)) {
      const chars = [...text];
      if (chars.length <= 5) return [text];
      const mid = Math.ceil(chars.length / 2);
      return [chars.slice(0, mid).join(""), chars.slice(mid).join("")];
    }
    // Latin: one sentence per line, and no line much over a dozen characters,
    // so the letters stay tall enough to read as glyphs.
    const out = [];
    for (const part of text.split(/(?<=\.)\s+/)) {
      const words = part.split(" ");
      if (part.length <= 8 || words.length < 2) { out.push(part); continue; }
      const half = Math.ceil(words.length / 2);
      out.push(words.slice(0, half).join(" "), words.slice(half).join(" "));
    }
    return out;
  }

  function rampChar(v) {
    const i = Math.min(RAMP.length - 1, Math.max(0, Math.round(v * (RAMP.length - 1))));
    return RAMP[i];
  }

  // progress 0..1: columns left of the sweep are resolved, the rest scrambles.
  function paint(g, progress) {
    const cols = g.cells[0] ? g.cells[0].length : 0;
    const edge = progress * (cols + 12);
    let out = "";
    for (const row of g.cells) {
      for (let c = 0; c < row.length; c++) {
        const v = row[c];
        // Three levels only: solid interior, one step down at the edge, else blank.
        if (v < g.cutoff) { out += " "; continue; }
        out += c < edge - 12 || progress >= 1
          ? (v >= 0.7 ? "@" : "%")
          : c < edge ? RAMP[1 + Math.floor(Math.random() * (RAMP.length - 1))] : (Math.random() < 0.15 ? "." : " ");
      }
      out += "\n";
    }
    g.pre.textContent = out;
  }

  function scramble(g) {
    cancelAnimationFrame(g.timer);
    const start = performance.now();
    const dur = 900;
    const step = (now) => {
      const p = Math.min(1, (now - start) / dur);
      const eased = 1 - Math.pow(2, -10 * p);    // exponential ease-out
      paint(g, p >= 1 ? 1 : eased);
      if (p < 1) g.timer = requestAnimationFrame(step);
    };
    g.timer = requestAnimationFrame(step);
  }

  const glyphs = [...document.querySelectorAll("[data-glyph]")].map((source) =>
    makeGlyph(source, document.getElementById("glyph-" + source.dataset.glyph)));

  // ---------------------------------------------------------------- scene
  // A Mac desktop in characters. The target window is drawn dense inside a
  // REC viewfinder; every other window is reduced to the sparse end of the ramp.
  const scene = document.getElementById("scene");
  const liveCmd = document.getElementById("live-cmd");
  const liveTarget = document.getElementById("live-target");

  const WINDOWS = [
    { id: 41324, app: "Google Chrome", title: "Webinar", x: .04, y: .10, w: .54, h: .50, kind: "video" },
    { id: 35239, app: "Calendar", title: "Calendar", x: .55, y: .07, w: .41, h: .42, kind: "calendar" },
    { id: 46635, app: "Terminal", title: "zsh", x: .60, y: .54, w: .37, h: .40, kind: "terminal" },
    { id: 42133, app: "Notes", title: "Notes", x: .06, y: .64, w: .32, h: .30, kind: "notes" }
  ];
  let target = WINDOWS[0];
  let recStart = performance.now();
  let geo = null;     // window rectangles in cells
  let cols = 0, rows = 0, cell = null;

  const TERM_LINES = [
    "$ snapparazzi --list",
    "WINDOW_ID  APP - WINDOW",
    "41324      Google Chrome - Webinar",
    "35239      Calendar - Calendar",
    "46635      Terminal - zsh",
    "42133      Notes - Notes",
    "$ snapparazzi record -w 41324",
    "Recording... press Ctrl-C to stop."
  ];
  const NOTE_LINES = [
    "Recording checklist",
    "- mute other browser tabs",
    "- turn on Do Not Disturb",
    "- find the window ID",
    "- use --audio system",
    "",
    "Ctrl-C when done"
  ];

  function layout() {
    cell = cellSize(scene);
    const width = scene.clientWidth;
    cols = Math.max(40, Math.floor(width / cell.w));
    rows = Math.max(18, Math.round(cols * 0.62 * cell.w / cell.h));
    geo = WINDOWS.map((w) => ({
      w,
      x: Math.round(w.x * cols), y: 1 + Math.round(w.y * (rows - 1)),
      cw: Math.max(14, Math.round(w.w * cols)), ch: Math.max(6, Math.round(w.h * (rows - 1)))
    }));
  }

  // Brightness 0..1 for a window's picture. Drawn through the full ramp when
  // the window is recorded, and squeezed to the sparse end when it is not.
  function contentAt(kind, u, v, t) {
    switch (kind) {
      case "video": {
        // A course-video frame: a lit slide on the left, the presenter on the right.
        if (v > 0.92) return u < 0.06 + ((t * 0.015) % 0.9) ? 1 : 0.3;      // progress bar
        let b = 0.12 + 0.08 * (1 - v);                                       // dim room
        if (u > 0.05 && u < 0.5 && v > 0.08 && v < 0.82) {                    // the slide
          b = 0.62;
          if (v > 0.14 && v < 0.24 && u > 0.09 && u < 0.42) b = 1;           // slide title
          const row = Math.floor((v - 0.32) * 22);
          const len = [0.34, 0.28, 0.36, 0.22, 0.31, 0.26][((row % 6) + 6) % 6];
          if (v > 0.32 && v < 0.76 && row % 2 === 0 && u > 0.09 && u < 0.09 + len) b = 0.3;
        }
        // presenter: head and shoulders, lit from the slide side
        const sway = 0.01 * Math.sin(t * 0.9);
        const hx = (u - 0.76 - sway) * 1.5, hy = (v - 0.34) * 0.85;
        const head = Math.hypot(hx, hy);
        const sx = (u - 0.76 - sway) * 0.9, sy = (v - 1.02) * 1.1;
        const body = Math.hypot(sx, sy);
        const lit = u < 0.76 ? 1 : 0.8;                                     // the slide side is lit
        if (head < 0.19) b = Math.max(b, (0.72 + 0.28 * (1 - head / 0.19)) * lit);
        else if (body < 0.42 && v > 0.6) b = Math.max(b, (0.5 + 0.4 * (1 - body / 0.42)) * lit);
        return Math.min(1, b);
      }
      case "calendar": {
        const gx = u * 7, gy = v * 5;
        const cx = gx % 1, cy = gy % 1;
        let b = (cx < 0.1 || cy < 0.14) ? 0.45 : 0.16;
        if (Math.floor(gx) === 4 && Math.floor(gy) === 2) b = 1;              // today
        if ((Math.floor(gx) + Math.floor(gy) * 3) % 5 === 1 && cy > 0.4 && cy < 0.75) b = Math.max(b, 0.75);
        return b;
      }
      default: return 0;
    }
  }

  function frame(now) {
    if (!geo) layout();
    const t = now / 1000;
    const grid = Array.from({ length: rows }, () => new Array(cols).fill(" "));
    const inv = Array.from({ length: rows }, () => new Uint8Array(cols));
    const put = (x, y, ch, invert) => {
      if (x < 0 || y < 0 || x >= cols || y >= rows) return;
      grid[y][x] = ch;
      inv[y][x] = invert ? 1 : 0;
    };
    const text = (x, y, s, invert, maxLen) => {
      const str = maxLen != null ? s.slice(0, Math.max(0, maxLen)) : s;
      for (let i = 0; i < str.length; i++) put(x + i, y, str[i], invert);
    };

    // Desktop: a slow sparse drift, and the menu bar.
    for (let y = 1; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const n = Math.sin(x * 0.37 + t * 0.4) * Math.cos(y * 0.61 - t * 0.3);
        if (n > 0.93) grid[y][x] = ".";
        else if ((x * 7 + y * 13) % 29 === 0) grid[y][x] = ".";
      }
    }
    for (let x = 0; x < cols; x++) put(x, 0, " ", true);
    text(1, 0, " @  Finder  File  Edit  View  Window  Help", true, cols - 12);
    const clock = new Date();
    const hhmm = String(clock.getHours()).padStart(2, "0") + ":" + String(clock.getMinutes()).padStart(2, "0");
    text(cols - hhmm.length - 2, 0, hhmm, true);

    // Windows, the target last so it sits on top.
    const order = geo.filter((g) => g.w !== target).concat(geo.filter((g) => g.w === target));
    for (const g of order) {
      const live = g.w === target;
      const { x, y, cw, ch } = g;
      // clear the window's area
      for (let yy = y; yy < y + ch; yy++) for (let xx = x; xx < x + cw; xx++) put(xx, yy, " ", false);
      // frame
      const hz = live ? "-" : ".", vt = live ? "|" : ":", co = live ? "+" : ".";
      for (let xx = x + 1; xx < x + cw - 1; xx++) { put(xx, y, hz); put(xx, y + 2, hz); put(xx, y + ch - 1, hz); }
      for (let yy = y + 1; yy < y + ch - 1; yy++) { put(x, yy, vt); put(x + cw - 1, yy, vt); }
      put(x, y, co); put(x + cw - 1, y, co); put(x, y + ch - 1, co); put(x + cw - 1, y + ch - 1, co);
      put(x, y + 2, live ? "+" : ":"); put(x + cw - 1, y + 2, live ? "+" : ":");
      // title bar
      text(x + 2, y + 1, live ? "o o o" : ". . .", false);
      const title = `${g.w.app} - ${g.w.title}`;
      text(x + 9, y + 1, title, false, cw - 11);
      // content
      const ix = x + 1, iy = y + 3, iw = cw - 2, ih = ch - 4;
      if (g.w.kind === "terminal" || g.w.kind === "notes") {
        const lines = g.w.kind === "terminal" ? TERM_LINES : NOTE_LINES;
        const shown = g.w.kind === "terminal" ? Math.min(lines.length, 2 + Math.floor((t * 1.2) % (lines.length + 4))) : lines.length;
        if (live) for (let yy = 0; yy < ih; yy++) for (let xx = 0; xx < iw; xx++) put(ix + xx, iy + yy, ":");
        for (let i = 0; i < Math.min(ih, shown); i++) {
          const line = lines[i];
          for (let k = 0; k < Math.min(iw - 2, line.length); k++) {
            const chr = line[k];
            put(ix + 1 + k, iy + i, live ? (chr === " " ? " " : chr) : (chr === " " ? " " : (k % 3 === 0 ? ":" : ".")), live);
          }
        }
      } else {
        for (let yy = 0; yy < ih; yy++) {
          for (let xx = 0; xx < iw; xx++) {
            const v = contentAt(g.w.kind, xx / iw, yy / ih, t);
            const level = live ? v : Math.min(0.22, v * 0.3);
            if (level > 0.09) put(ix + xx, iy + yy, rampChar(level));
          }
        }
      }
      if (live) {
        // viewfinder corners, one cell outside the window
        const L = x - 1, R = x + cw, T = y - 1, B = y + ch;
        text(L, T, "+--"); put(L, T + 1, "|");
        text(R - 2, T, "--+"); put(R, T + 1, "|");
        text(L, B, "+--"); put(L, B - 1, "|");
        text(R - 2, B, "--+"); put(R, B - 1, "|");
        const secs = Math.floor((now - recStart) / 1000);
        const stamp = `${String(Math.floor(secs / 60)).padStart(2, "0")}:${String(secs % 60).padStart(2, "0")}`;
        const on = reduceMotion || Math.floor(t * 2) % 2 === 0;
        const label = `${on ? " REC " : "     "} ${stamp} `;
        text(R - label.length - 3, T, label, on);
        const idLabel = ` -w ${g.w.id} `;
        text(L + 4, B, idLabel, true);
      }
    }

    // Serialize with inverse runs.
    let html = "";
    for (let y = 0; y < rows; y++) {
      let run = "", runInv = inv[y][0];
      const flush = () => {
        if (!run) return;
        const esc = run.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        html += runInv ? `<span class="inv">${esc}</span>` : esc;
        run = "";
      };
      for (let x = 0; x < cols; x++) {
        if (inv[y][x] !== runInv) { flush(); runInv = inv[y][x]; }
        run += grid[y][x];
      }
      flush();
      html += "\n";
    }
    scene.innerHTML = html;
  }

  // Retype the command when the target changes.
  let typeTimer = 0;
  function retarget(next) {
    if (next === target) return;
    target = next;
    recStart = performance.now();
    liveTarget.textContent = `${next.app} — ${next.title}`;
    const full = `snapparazzi record -w ${next.id} --audio system`;
    clearInterval(typeTimer);
    if (reduceMotion) { liveCmd.textContent = full; paintOnce(); return; }
    const keep = "snapparazzi record -w ";
    let i = keep.length;
    liveCmd.textContent = keep;
    typeTimer = setInterval(() => {
      i++;
      liveCmd.textContent = full.slice(0, i);
      if (i >= full.length) clearInterval(typeTimer);
    }, 28);
  }

  function windowAtCell(cx, cy) {
    // Topmost first: the target is on top, then the reverse draw order.
    const stack = [geo.find((g) => g.w === target)].concat(geo.filter((g) => g.w !== target).reverse());
    return stack.find((g) => cx >= g.x && cx < g.x + g.cw && cy >= g.y && cy < g.y + g.ch);
  }

  function pointerToCell(e) {
    const r = scene.getBoundingClientRect();
    return { cx: Math.floor((e.clientX - r.left) / cell.w), cy: Math.floor((e.clientY - r.top) / cell.h) };
  }

  scene.addEventListener("pointermove", (e) => {
    if (!geo) return;
    const { cx, cy } = pointerToCell(e);
    const hit = windowAtCell(cx, cy);
    if (hit) retarget(hit.w);
  });
  scene.addEventListener("pointerdown", (e) => {
    if (!geo) return;
    const { cx, cy } = pointerToCell(e);
    const hit = windowAtCell(cx, cy);
    if (hit) retarget(hit.w);
  });
  scene.addEventListener("keydown", (e) => {
    const k = e.key;
    if (!["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(k)) return;
    e.preventDefault();
    const i = WINDOWS.indexOf(target);
    const d = k === "ArrowRight" || k === "ArrowDown" ? 1 : -1;
    retarget(WINDOWS[(i + d + WINDOWS.length) % WINDOWS.length]);
  });

  // Run only while visible; reduced motion draws on demand.
  let raf = 0, visible = true, last = 0;
  function loop(now) {
    if (now - last > 66) { frame(now); last = now; }   // ~15 fps is plenty for glyphs
    raf = requestAnimationFrame(loop);
  }
  function paintOnce() { frame(performance.now()); }
  function start() { if (!reduceMotion && !raf && visible && !document.hidden) raf = requestAnimationFrame(loop); }
  function stop() { cancelAnimationFrame(raf); raf = 0; }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      visible ? start() : stop();
    }).observe(scene);
  }
  document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));

  let resizeTimer = 0;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { layout(); paintOnce(); glyphs.forEach((g) => g.render(false)); }, 120);
  });

  // Reveal the closing headline when it scrolls into view.
  if ("IntersectionObserver" in window && !reduceMotion) {
    const close = glyphs.find((g) => g.source.dataset.glyph === "close");
    if (close) {
      const io = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) { close.render(true); io.disconnect(); }
      }, { threshold: 0.4 });
      io.observe(close.pre);
    }
  }

  // Mark the section in view in the top bar.
  if ("IntersectionObserver" in window) {
    const links = new Map([...document.querySelectorAll('.bar nav a[href^="#"]')].map((a) => [a.getAttribute("href").slice(1), a]));
    const spy = new IntersectionObserver((entries) => {
      for (const e of entries) {
        const link = links.get(e.target.id);
        if (!link) continue;
        if (e.isIntersecting) {
          links.forEach((a) => a.removeAttribute("aria-current"));
          link.setAttribute("aria-current", "true");
        } else if (link.getAttribute("aria-current")) {
          link.removeAttribute("aria-current");
        }
      }
    }, { rootMargin: "-40% 0px -55% 0px" });
    links.forEach((_, id) => { const el = document.getElementById(id); if (el) spy.observe(el); });
  }

  function boot() {
    applyLang(lang);
    layout();
    paintOnce();
    glyphs.forEach((g) => g.render(g.source.dataset.glyph === "hero"));
    start();
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(boot); else boot();
})();
