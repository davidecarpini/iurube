(() => {
  'use strict';
  if (window.iurub) return;
  const originHost = new URL(document.baseURI).hostname.toLowerCase();
  if (!(originHost === 'youtube.com' || originHost.endsWith('.youtube.com'))) return;
  const initial = window.__iurubConfig || {};
  const accountSaving = initial.saveDestination === 'youtube';
  let savingToAccount = false;
  let shortsEnabled = Boolean(initial.shortsEnabled);
  let savedIDs = new Set(initial.savedIDs || []);
  let scanQueued = false;
  let lastCurrent = '';
  const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
  const CARD = [
    'ytm-video-with-context-renderer', 'ytm-video-renderer', 'ytm-compact-video-renderer',
    'ytm-playlist-video-renderer', 'ytd-playlist-video-renderer', 'ytm-grid-video-renderer', 'ytm-rich-item-renderer', 'ytm-reel-item-renderer',
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
      .iurub-remove { display:inline-flex; align-items:center; min-height:44px; margin:4px 12px 10px; padding:8px 14px; border:1px solid #e84a3838; border-radius:12px; background:#fff5f2; color:#aa3022; font:600 13px -apple-system,BlinkMacSystemFont,sans-serif; cursor:pointer; }
      .iurub-save:focus-visible, .iurub-remove:focus-visible { outline:3px solid #e84a38; outline-offset:2px; }
      .iurub-save[data-saved="true"] { color:#396548; border-color:#487b4933; background:#f1f7ef; }
      @media(prefers-color-scheme:dark) { .iurub-save, .iurub-remove { background:#33211d; color:#ffae9e; border-color:#995346; } .iurub-save[data-saved="true"] { background:#1e3025; color:#a4d2b1; } }
    `;
    (document.head || document.documentElement).appendChild(style);
  }
  // Delegate to the site's visible controls. No credentials or private APIs are read.
  const menuSelector = '[role="dialog"], [role="menu"], ytm-menu-popup-renderer, ytm-bottom-sheet-renderer, yt-sheet-view-model, ytm-add-to-playlist-renderer, ytd-add-to-playlist-renderer, tp-yt-paper-dialog';
  const actionSelector = 'button, [role="button"], [role="menuitem"], ytm-menu-service-item-renderer, ytm-menu-navigation-item-renderer, yt-list-item-view-model';
  const watchLaterText = /watch later|guarda pi[uù] tardi/i;
  const visible = node => Boolean(node && !node.hidden && !node.closest('[hidden],[aria-hidden="true"]') && getComputedStyle(node).display !== 'none' && getComputedStyle(node).visibility !== 'hidden' && node.getClientRects().length);
  const labelOf = node => clean(node?.getAttribute('aria-label') || node?.textContent, 500);
  // Renderer wrappers may contain the actual button; click that button, not its parent.
  const controls = root => Array.from(root.querySelectorAll(actionSelector)).filter(n => visible(n) && !n.closest('.iurub-save,.iurub-remove') &&
    !Array.from(n.querySelectorAll('button,[role="button"],[role="menuitem"]')).some(visible));
  const menuRoots = () => Array.from(document.querySelectorAll(menuSelector)).filter(visible);
  const playlistChoiceSelector = '[role="checkbox"], input[type="checkbox"], [role="menuitemcheckbox"], toggleable-list-item-view-model [role="menuitem"]';
  const watchLaterChoice = () => menuRoots().flatMap(root => Array.from(root.querySelectorAll(playlistChoiceSelector)))
    .find(n => visible(n) && watchLaterText.test(labelOf(n) + ' ' + labelOf(n.closest('label, ytm-playlist-add-to-option-renderer, ytd-playlist-add-to-option-renderer'))));
  function selectionState(node) {
    if (node.matches('input[type="checkbox"]')) return node.checked;
    for (const attribute of ['aria-checked', 'aria-selected', 'aria-pressed']) {
      if (node.getAttribute(attribute) === 'true') return true;
      if (node.getAttribute(attribute) === 'false') return false;
    }
    // Current mobile YouTube announces selection in the menu item's accessible label.
    const label = labelOf(node);
    if (/\b(not selected|non selezionat[oa]|unselected|unchecked|deselezionat[oa])\b/i.test(label)) return false;
    if (/\b(selected|selezionat[oa]|checked)\b/i.test(label)) return true;
    return null;
  }
  async function until(read, ms = 2500) {
    const end = Date.now() + ms;
    do { const value = read(); if (value) return value; await new Promise(r => setTimeout(r, 100)); } while (Date.now() < end);
    return null;
  }
  function accountResult(status) { post('youtubeSaveResult', { status }); }
  const notifications = () => Array.from(document.querySelectorAll('[role="status"], [role="alert"], ytm-notification-text-renderer, tp-yt-paper-toast, yt-notification-action-renderer')).filter(visible);
  const notificationSnapshot = () => new Map(notifications().map(n => [n, labelOf(n)]));
  async function finishAccountSave(before) {
    const confirmed = await until(() => notifications()
      .find(n => before.get(n) !== labelOf(n) && /added|saved|aggiunto|aggiunta|salvato|salvata/i.test(labelOf(n)) && !/not |non |impossibile|error/i.test(labelOf(n))), 2200);
    accountResult(confirmed ? 'saved' : 'submitted');
  }
  async function chooseWatchLater() {
    const entry = await until(() => {
      const checkbox = watchLaterChoice();
      if (checkbox) return { checkbox };
      for (const root of menuRoots()) {
        const direct = controls(root).find(n => watchLaterText.test(labelOf(n)) && /save|add|salva|aggiungi|remove|rimuovi/i.test(labelOf(n)));
        if (direct) return { direct };
        const playlist = controls(root).find(n => /save to playlist|salva (in una|nella|in) playlist|salva in una raccolta/i.test(labelOf(n)));
        if (playlist) return { playlist };
      }
      return null;
    });
    if (!entry) { accountResult('manual'); return; }
    if (entry.direct) {
      if (/remove|rimuovi/i.test(labelOf(entry.direct))) { accountResult('alreadySaved'); return; }
      const before = notificationSnapshot();
      entry.direct.click();
      await finishAccountSave(before);
    } else if (entry.playlist) {
      entry.playlist.click();
      // Wait for the chooser instead of clicking the same menu entry again.
      await chooseCheckbox();
    } else { await chooseCheckbox(entry.checkbox); }
  }
  async function chooseCheckbox(existing) {
    const checkbox = existing || await until(watchLaterChoice);
    if (!checkbox) { accountResult('choose'); return; }
    const selected = selectionState(checkbox);
    if (selected === true) { accountResult('alreadySaved'); return; }
    if (selected === null) { accountResult('choose'); return; }
    const before = notificationSnapshot();
    checkbox.click();
    const confirm = menuRoots().flatMap(controls).find(n => /^(done|save|fine|salva)$/i.test(labelOf(n)));
    if (confirm) confirm.click();
    await finishAccountSave(before);
  }
  function cardMenu(card) {
    return controls(card).find(n => /action menu|menu azion[ei]|menu delle azioni|altre azioni|more actions/i.test(labelOf(n)))
      || card.querySelector('button[aria-haspopup="true"], ytm-menu-renderer button, ytm-menu-renderer .icon-button, ytm-bottom-sheet-renderer button');
  }
  async function removeThroughYouTube(card, button) {
    if (savingToAccount) return;
    savingToAccount = true; button.disabled = true;
    try {
      const opener = cardMenu(card);
      if (!opener) { post('youtubeRemoveResult', {status:'manual'}); return; }
      opener.click();
      const remove = await until(() => menuRoots().flatMap(controls).find(n => watchLaterText.test(labelOf(n)) && /remove|rimuovi/i.test(labelOf(n))));
      if (!remove) { post('youtubeRemoveResult', {status:'manual'}); return; }
      remove.click();
      // YouTube updates the row and exposes its own Undo; never remove a row optimistically.
      post('youtubeRemoveResult', {status:'submitted'});
    } catch { post('youtubeRemoveResult', {status:'manual'}); }
    finally { savingToAccount = false; button.disabled = false; }
  }
  async function saveThroughYouTube(card, video, button) {
    if (savingToAccount || (!shortsEnabled && video?.isShort)) return;
    savingToAccount = true;
    if (button) button.disabled = true;
    try {
      let opener;
      if (card) {
        opener = cardMenu(card);
      } else {
        opener = controls(document).find(n => /^(save.*playlist|salva.*playlist)$/i.test(labelOf(n)));
      }
      if (!opener) { accountResult('manual'); return; }
      opener.click();
      await chooseWatchLater();
    } catch { accountResult('manual'); }
    finally { savingToAccount = false; if (button) button.disabled = false; }
  }
  function updateButton(button, id) {
    const saved = !accountSaving && savedIDs.has(id);
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
      const inWatchLater = (location.pathname === '/playlist' && new URL(location.href).searchParams.get('list') === 'WL') || document.documentElement.dataset.fixturePlaylist === 'true';
      let removeButton = Array.from(card.children).find(n => n.classList?.contains('iurub-remove'));
      if (accountSaving && inWatchLater && link) {
        card.querySelector('.iurub-save')?.remove();
        if (!removeButton) {
          removeButton = document.createElement('button'); removeButton.type = 'button';
          removeButton.className = 'iurub-remove'; removeButton.textContent = 'Rimuovi';
          removeButton.setAttribute('aria-label', 'Rimuovi da Guarda più tardi');
          removeButton.addEventListener('click', event => {
            event.preventDefault(); event.stopPropagation(); event.stopImmediatePropagation();
            removeThroughYouTube(card, removeButton);
          });
          card.append(removeButton);
        }
        return;
      }
      removeButton?.remove();
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
          if (accountSaving) { saveThroughYouTube(card, current, button); return; }
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
    saveCurrentToYouTube() { saveThroughYouTube(null, currentVideo(), null); },
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
