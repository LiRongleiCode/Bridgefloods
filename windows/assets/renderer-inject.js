((cssText, artDataUrl, themeConfig) => {
  const STATE_KEY = "__CODEX_DREAM_SKIN_STATE__";
  const DISABLED_KEY = "__CODEX_DREAM_SKIN_DISABLED__";
  const STYLE_ID = "codex-dream-skin-style";
  const CHROME_ID = "codex-dream-skin-chrome";
  const VERSION = "1.2.0";
  const THEME = themeConfig && typeof themeConfig === "object" ? themeConfig : {};
  const REQUESTED_STYLE = ["adaptive", "light", "dark"].includes(THEME.style)
    ? THEME.style
    : "adaptive";
  const THEME_VARIABLES = [
    "--dream-art",
    "--dream-canvas-wash",
    "--dream-main",
    "--dream-panel",
    "--dream-panel-strong",
    "--dream-panel-soft",
    "--dream-ink",
    "--dream-muted",
    "--dream-line",
    "--dream-line-strong",
    "--dream-hover",
    "--dream-accent",
    "--dream-accent-contrast",
    "--dream-shadow",
    "--dream-scrollbar",
    "--dream-image-luminance",
  ];

  window[DISABLED_KEY] = false;
  const previous = window[STATE_KEY];
  previous?.observer?.disconnect();
  if (previous?.timer) clearInterval(previous.timer);
  if (previous?.scheduler?.timeout) clearTimeout(previous.scheduler.timeout);

  const objectUrlFromDataUrl = (value) => {
    const match = /^data:([^;,]+);base64,(.*)$/s.exec(value);
    if (!match) throw new Error("Invalid Dream Skin artwork data URL");
    const binary = atob(match[2]);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return URL.createObjectURL(new Blob([bytes], { type: match[1] }));
  };

  const artUrl = objectUrlFromDataUrl(artDataUrl);
  if (previous?.artUrl && previous.artUrl !== artUrl) URL.revokeObjectURL(previous.artUrl);

  const fallbackPalette = {
    tone: "light",
    luminance: 0.72,
  };

  const analyzeArtwork = (url) => new Promise((resolve) => {
    const image = new Image();
    image.decoding = "async";
    image.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        const size = 48;
        canvas.width = size;
        canvas.height = size;
        const context = canvas.getContext("2d", { willReadFrequently: true });
        if (!context) throw new Error("Canvas 2D context is unavailable");
        const insetX = image.naturalWidth * 0.08;
        const insetY = image.naturalHeight * 0.08;
        const sampleWidth = image.naturalWidth * 0.84;
        const sampleHeight = image.naturalHeight * 0.84;
        context.drawImage(image, insetX, insetY, sampleWidth, sampleHeight, 0, 0, size, size);
        const pixels = context.getImageData(0, 0, size, size).data;
        let luminanceTotal = 0;
        let lightPixels = 0;
        let darkPixels = 0;
        let samples = 0;

        const linear = (channel) => {
          const value = channel / 255;
          return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
        };

        for (let index = 0; index < pixels.length; index += 4) {
          if (pixels[index + 3] < 64) continue;
          const luminance = 0.2126 * linear(pixels[index])
            + 0.7152 * linear(pixels[index + 1])
            + 0.0722 * linear(pixels[index + 2]);
          luminanceTotal += luminance;
          if (luminance >= 0.62) lightPixels += 1;
          if (luminance <= 0.22) darkPixels += 1;
          samples += 1;
        }

        if (!samples) throw new Error("Artwork has no visible pixels");
        const luminance = luminanceTotal / samples;
        const tone = luminance >= 0.46 || lightPixels > darkPixels * 1.35 ? "light" : "dark";
        resolve({ tone, luminance });
      } catch {
        resolve(fallbackPalette);
      }
    };
    image.onerror = () => resolve(fallbackPalette);
    image.src = url;
  });

  const variablesForPalette = ({ tone, luminance }) => {
    const light = tone === "light";
    return {
      "--dream-canvas-wash": light ? "rgba(248, 250, 252, .18)" : "rgba(2, 6, 12, .28)",
      "--dream-main": light ? "rgba(248, 250, 252, .42)" : "rgba(5, 10, 16, .48)",
      "--dream-panel": light ? "rgba(255, 255, 255, .68)" : "rgba(12, 18, 26, .68)",
      "--dream-panel-strong": light ? "rgba(255, 255, 255, .82)" : "rgba(12, 18, 26, .82)",
      "--dream-panel-soft": light ? "rgba(255, 255, 255, .50)" : "rgba(12, 18, 26, .50)",
      "--dream-ink": light ? "#172033" : "#f8fafc",
      "--dream-muted": light ? "#4b5565" : "#cbd5e1",
      "--dream-line": light ? "rgba(15, 23, 42, .14)" : "rgba(255, 255, 255, .16)",
      "--dream-line-strong": light ? "rgba(15, 23, 42, .24)" : "rgba(255, 255, 255, .28)",
      "--dream-hover": light ? "rgba(15, 23, 42, .08)" : "rgba(255, 255, 255, .10)",
      "--dream-accent": light ? "#1f2937" : "#f8fafc",
      "--dream-accent-contrast": light ? "#ffffff" : "#111827",
      "--dream-shadow": light ? "rgba(15, 23, 42, .18)" : "rgba(0, 0, 0, .42)",
      "--dream-scrollbar": light ? "rgba(15, 23, 42, .28)" : "rgba(255, 255, 255, .30)",
      "--dream-image-luminance": Number(luminance).toFixed(3),
    };
  };

  const applyPalette = (root, palette) => {
    const tone = REQUESTED_STYLE === "adaptive" ? palette.tone : REQUESTED_STYLE;
    root.setAttribute("data-dream-style", REQUESTED_STYLE);
    root.setAttribute("data-dream-tone", tone);
    root.style.colorScheme = tone;
    for (const [name, value] of Object.entries(variablesForPalette({ ...palette, tone }))) {
      root.style.setProperty(name, value);
    }
  };

  const state = {
    artUrl,
    cleanup: null,
    ensure: null,
    observer: null,
    palette: fallbackPalette,
    scheduler: { timeout: null },
    style: REQUESTED_STYLE,
    timer: null,
    version: VERSION,
  };

  const ensure = () => {
    if (window[DISABLED_KEY]) return;
    const root = document.documentElement;
    if (!root) return;
    root.classList.add("codex-dream-skin");
    root.style.setProperty("--dream-art", `url("${artUrl}")`);
    applyPalette(root, state.palette);

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      (document.head || root).appendChild(style);
    }
    if (style.dataset.dreamVersion !== VERSION) {
      style.textContent = cssText;
      style.dataset.dreamVersion = VERSION;
    }

    const shellMain = document.querySelector("main.main-surface") || document.querySelector("main");
    const home = document.querySelector('[role="main"]:has([data-testid="home-icon"])');
    for (const candidate of document.querySelectorAll('[role="main"].dream-home')) {
      if (candidate !== home) candidate.classList.remove("dream-home");
    }
    if (home) home.classList.add("dream-home");

    if (!shellMain || !document.body) return;
    shellMain.classList.toggle("dream-home-shell", Boolean(home));
    let chrome = document.getElementById(CHROME_ID);
    if (!chrome || chrome.parentElement !== document.body) {
      chrome?.remove();
      chrome = document.createElement("div");
      chrome.id = CHROME_ID;
      chrome.setAttribute("aria-hidden", "true");
      document.body.appendChild(chrome);
    }
    if (chrome.dataset.dreamVersion !== VERSION) {
      chrome.innerHTML = '<div class="dream-brand"><b></b><small></small></div>';
      chrome.dataset.dreamVersion = VERSION;
    }
    chrome.querySelector(".dream-brand b").textContent = THEME.promoTitle || THEME.name || "Codex Dream Skin";
    chrome.querySelector(".dream-brand small").textContent = THEME.promoSub || THEME.brandSubtitle || "ADAPTIVE NEUTRAL";
    const shellBox = shellMain.getBoundingClientRect();
    chrome.style.left = `${Math.round(shellBox.left)}px`;
    chrome.style.top = `${Math.round(shellBox.top)}px`;
    chrome.style.width = `${Math.round(shellBox.width)}px`;
    chrome.style.height = `${Math.round(shellBox.height)}px`;
    chrome.classList.toggle("dream-home-shell", Boolean(home));
  };

  const cleanup = () => {
    window[DISABLED_KEY] = true;
    const root = document.documentElement;
    root?.classList.remove("codex-dream-skin");
    root?.removeAttribute("data-dream-style");
    root?.removeAttribute("data-dream-tone");
    if (root) {
      root.style.removeProperty("color-scheme");
      for (const name of THEME_VARIABLES) root.style.removeProperty(name);
    }
    document.querySelectorAll(".dream-home").forEach((node) => node.classList.remove("dream-home"));
    document.querySelectorAll(".dream-home-shell").forEach((node) => node.classList.remove("dream-home-shell"));
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    state.observer?.disconnect();
    if (state.timer) clearInterval(state.timer);
    if (state.scheduler.timeout) clearTimeout(state.scheduler.timeout);
    URL.revokeObjectURL(state.artUrl);
    if (window[STATE_KEY] === state) delete window[STATE_KEY];
    return true;
  };

  state.ensure = ensure;
  state.cleanup = cleanup;
  const scheduleEnsure = () => {
    if (state.scheduler.timeout) clearTimeout(state.scheduler.timeout);
    state.scheduler.timeout = setTimeout(() => {
      state.scheduler.timeout = null;
      ensure();
    }, 180);
  };
  state.observer = new MutationObserver(scheduleEnsure);
  state.observer.observe(document.documentElement, { childList: true, subtree: true });
  state.timer = setInterval(ensure, 5000);
  window[STATE_KEY] = state;

  ensure();
  analyzeArtwork(artUrl).then((palette) => {
    if (window[STATE_KEY] !== state || window[DISABLED_KEY]) return;
    state.palette = palette;
    ensure();
  });

  return { installed: true, version: VERSION, style: REQUESTED_STYLE, adaptiveTheme: REQUESTED_STYLE === "adaptive" };
})(__DREAM_CSS_JSON__, __DREAM_ART_JSON__, __DREAM_THEME_JSON__)
