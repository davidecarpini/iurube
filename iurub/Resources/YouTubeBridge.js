(() => {
  'use strict';
  if (window.iurub) return;
  const originHost = new URL(document.baseURI).hostname.toLowerCase();
  if (!(originHost === 'youtube.com' || originHost.endsWith('.youtube.com'))) return;
  const initial = window.__iurubConfig || {};
  let shortsEnabled = Boolean(initial.shortsEnabled);
  let savedIDs = new Set(initial.savedIDs || []);
  let scanQueued = false;
  let lastCurrent = '';
  const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
  const CARD = [
    'ytm-video-with-context-renderer', 'ytm-video-renderer', 'ytm-compact-video-renderer',
    'ytm-grid-video-renderer', 'ytm-rich-item-renderer', 'ytm-reel-item-renderer',
    'ytd-rich-item-renderer', 'ytd-video-renderer', 'ytd-compact-video-renderer',
    'ytd-grid-video-renderer', 'yt-lockup-view-model', 'ytm-shorts-lockup-view-model',
    'ytm-shorts-lockup-view-model-v2'
  ].join(',');
  const SHORT_SHELF = [
    'ytm-reel-shelf-renderer', 'ytd-reel-shelf-renderer', 'ytd-rich-shelf-renderer[is-shorts]',
    'ytm-shorts-lockup-view-model', 'ytm-shorts-lockup-view-model-v2',
    'ytm-reel-item-renderer', 'ytd-reel-item-renderer', '.pivot-shorts',
    'ytm-pivot-bar-item-renderer:has(.pivot-shorts)', '[data-iurub-short]'
  ].join(',');

  function post(type, payload = {}) {
    window.webkit?.messageHandlers?.iurub?.postMessage({ type, ...payload });
  }
  function parseLink(raw) {
    try {
      const u = new URL(raw, 'https://m.youtube.com');
      if (!['https:', 'http:'].includes(u.protocol) || u.username || u.password || (u.port && u.port !== '443')) return null;
      const host = u.hostname.toLowerCase();
      if (!(host === 'youtube.com' || host.endsWith('.youtube.com') || host === 'youtu.be' || host === 'www.youtu.be')) return null;
      const parts = u.pathname.split('/').filter(Boolean);
      const short = parts[0] === 'shorts';
      let id = null;
      if (host === 'youtu.be' || host === 'www.youtu.be') id = parts.length === 1 ? parts[0] : null;
      else if (u.pathname === '/watch') id = u.searchParams.get('v');
      else if (['shorts', 'embed', 'live'].includes(parts[0]) && parts.length === 2) id = parts[1];
      return VIDEO_ID.test(id || '') ? { id, isShort: short, url: `https://m.youtube.com/${short ? 'shorts/' + id : 'watch?v=' + id}` } : null;
    } catch { return null; }
  }
  function isShortRoute(raw) {
    try {
      const u = new URL(raw, location.href);
      return (u.hostname === 'youtube.com' || u.hostname.endsWith('.youtube.com')) && /^\/shorts(?:\/|$)/.test(u.pathname);
    } catch { return false; }
  }
  function clean(text, max = 300) { return (text || '').replace(/\s+/g, ' ').trim().slice(0, max); }
  function metadata(card, anchor, link) {
    const titleNode = card.querySelector('h3, h4, [id="video-title"], .yt-lockup-metadata-view-model__title, .media-item-headline, [role="heading"]');
    const channelNode = card.querySelector('.ytm-badge-and-byline-item-byline, .ytm-badge-and-byline-item, .yt-content-metadata-view-model__metadata-row, .yt-lockup-metadata-view-model__metadata, .byline, #channel-name, .ytm-video-with-context-renderer-title a[href^="/@"]');
    return { ...link, title: clean(titleNode?.textContent || anchor.getAttribute('title') || anchor.getAttribute('aria-label') || anchor.textContent), channel: clean(channelNode?.textContent, 120) };
  }
  function installStyle() {
    if (document.getElementById('iurub-style')) return;
    const style = document.createElement('style');
    style.id = 'iurub-style';
    style.textContent = `
      html.iurub-no-shorts ${SHORT_SHELF.split(',').join(',html.iurub-no-shorts ')} { display:none !important; }
      html.iurub-no-shorts a[href^="/shorts/"], html.iurub-no-shorts a[href*="youtube.com/shorts/"] { display:none !important; }
      .iurub-save { box-sizing:border-box; display:flex; align-items:center; justify-content:center; gap:6px; min-height:44px; margin:8px 12px 12px; padding:10px 14px; border:1px solid #e84a3838; border-radius:12px; background:#fff5f2; color:#aa3022; font:600 13px -apple-system,BlinkMacSystemFont,sans-serif; cursor:pointer; position:relative; z-index:2; -webkit-tap-highlight-color:transparent; }
      .iurub-save:focus-visible { outline:3px solid #e84a38; outline-offset:2px; }
      .iurub-save[data-saved="true"] { color:#396548; border-color:#487b4933; background:#f1f7ef; }
      @media(prefers-color-scheme:dark) { .iurub-save { background:#33211d; color:#ffae9e; border-color:#995346; } .iurub-save[data-saved="true"] { background:#1e3025; color:#a4d2b1; } }
    `;
    (document.head || document.documentElement).appendChild(style);
  }
  function updateButton(button, id) {
    const saved = savedIDs.has(id);
    const label = saved ? '✓ Salvato in Guarda più tardi' : '+ Guarda più tardi';
    if (button.textContent !== label) button.textContent = label;
    button.dataset.saved = String(saved);
    button.setAttribute('aria-label', label);
  }
  function scan() {
    scanQueued = false;
    if (!document.documentElement) return;
    installStyle();
    document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
    // Re-evaluate labels on recycled cards: a card once used for a Short can later hold a normal video.
    document.querySelectorAll('[data-iurub-short]').forEach(n => n.removeAttribute('data-iurub-short'));
    document.querySelectorAll('.pivot-shorts').forEach(node => {
      (node.closest('ytm-pivot-bar-item-renderer') || node).setAttribute('data-iurub-short', 'true');
    });
    document.querySelectorAll('[role="tab"],ytm-chip-cloud-chip-renderer,yt-chip-cloud-chip-renderer,yt-tab-shape').forEach(node => {
      if (/^shorts$/i.test(clean(node.getAttribute('aria-label') || node.textContent))) node.setAttribute('data-iurub-short', 'true');
    });
    document.querySelectorAll('a[href]').forEach(anchor => {
      const raw = anchor.getAttribute('href');
      if (isShortRoute(raw)) {
        const container = anchor.closest(CARD + ',ytm-pivot-bar-item-renderer,ytm-pivot-bar-item,ytm-pivot-bar-item-view-model,ytd-guide-entry-renderer,ytd-mini-guide-entry-renderer,[role="tab"]') || anchor;
        container.setAttribute('data-iurub-short', 'true');
      }
    });
    document.querySelectorAll(CARD).forEach(card => {
      // Use the innermost renderer; otherwise nested wrappers receive duplicate buttons.
      if (card.querySelector(CARD)) return;
      const candidates = Array.from(card.querySelectorAll('a[href]'));
      const anchor = candidates.find(a => parseLink(a.getAttribute('href')));
      const link = anchor && parseLink(anchor.getAttribute('href'));
      let button = Array.from(card.children).find(n => n.classList?.contains('iurub-save'));
      if (!link) { button?.remove(); return; }
      if (!button) {
        button = document.createElement('button');
        button.className = 'iurub-save';
        button.type = 'button';
        button.addEventListener('click', event => {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
          const current = button.__iurubVideo;
          if (!current || (!shortsEnabled && current.isShort)) return;
          // Native code acknowledges persistence before we display a saved state.
          post('save', { video: current });
        });
        card.appendChild(button);
      }
      button.__iurubVideo = metadata(card, anchor, link);
      button.dataset.videoId = link.id;
      updateButton(button, link.id);
    });
    reportCurrent();
  }
  function scheduleScan() {
    if (scanQueued) return;
    scanQueued = true;
    setTimeout(scan, 80);
  }
  function currentVideo() {
    const link = parseLink(location.href);
    if (!link) return null;
    const title = document.querySelector('ytm-slim-video-metadata-section-renderer h1, ytm-slim-video-metadata-section-renderer h2, h1.ytd-watch-metadata, .slim-video-information-title, meta[property="og:title"]');
    const channel = document.querySelector('ytm-slim-owner-renderer .slim-owner-channel-name, ytm-slim-owner-renderer .slim-owner-icon-and-title, #owner #channel-name');
    return { ...link, title: clean(title?.getAttribute('content') || title?.textContent || document.title.replace(/\s*[-–]\s*YouTube$/, '')), channel: clean(channel?.textContent, 120) };
  }
  function reportCurrent() {
    const current = currentVideo();
    const serialized = JSON.stringify(current);
    if (serialized !== lastCurrent) {
      lastCurrent = serialized;
      post('current', { video: current });
    }
  }
  function checkRoute() {
    if (!shortsEnabled && isShortRoute(location.href)) {
      post('blockedShort');
      location.replace('https://m.youtube.com/');
      return;
    }
    scheduleScan();
  }
  document.addEventListener('click', event => {
    const anchor = event.target.closest?.('a[href]');
    if (!shortsEnabled && ((anchor && isShortRoute(anchor.href)) || event.target.closest?.('[data-iurub-short],.pivot-shorts'))) {
      event.preventDefault(); event.stopImmediatePropagation(); post('blockedShort');
    }
  }, true);
  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function(state, title, url) {
      if (url && !shortsEnabled && isShortRoute(url)) { post('blockedShort'); return; }
      const result = original.apply(this, arguments);
      scheduleScan();
      return result;
    };
  }
  window.addEventListener('popstate', checkRoute);
  window.addEventListener('pageshow', checkRoute);
  document.addEventListener('yt-navigate-finish', checkRoute);
  document.addEventListener('yt-page-data-updated', scheduleScan);
  window.iurub = {
    configure(config) {
      shortsEnabled = Boolean(config.shortsEnabled);
      savedIDs = new Set(config.savedIDs || []);
      if (document.documentElement) document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
      checkRoute();
    },
    currentVideo,
    pause() { document.querySelectorAll('video,audio').forEach(media => media.pause()); }
  };
  if (document.documentElement) {
    document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
    installStyle();
  }
  const observer = new MutationObserver(scheduleScan);
  observer.observe(document, { childList:true, subtree:true, attributes:true, attributeFilter:['href'] });
  document.addEventListener('DOMContentLoaded', checkRoute, { once:true });
  checkRoute();
})();
