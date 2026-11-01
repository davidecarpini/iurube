(() => {
  'use strict';
  if (window.iurub) return;
  const originHost = new URL(document.baseURI).hostname.toLowerCase();
  if (!(originHost === 'youtube.com' || originHost.endsWith('.youtube.com'))) return;
  const initial = window.__iurubConfig || {};
  const accountSaving = initial.saveDestination === 'youtube';
  // Ordinary configuration cannot relabel a document. History restoration uses
  // the explicit URL-checked adoption API below.
  let playbackSession = typeof initial.playbackSession === 'string' ? initial.playbackSession : undefined;
  let savingToAccount = false;
  let shortsEnabled = Boolean(initial.shortsEnabled);
  let savedIDs = new Set(initial.savedIDs || []);
  let routeVideoOpens = Boolean(initial.routeVideoOpens);
  let trackPlayback = Boolean(initial.trackPlayback);
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
      ytm-pivot-bar-renderer, .pivot-bar-renderer { display:none !important; }
      ytm-app { padding-bottom:0 !important; }
      html.iurub-no-shorts ${SHORT_SHELF.split(',').join(',html.iurub-no-shorts ')} { display:none !important; }
      html.iurub-no-shorts a[href^="/shorts/"], html.iurub-no-shorts a[href*="youtube.com/shorts/"] { display:none !important; }
      html.iurub-watch-later yt-page-header-renderer,
      html.iurub-watch-later ytm-playlist-header-renderer,
      html.iurub-watch-later ytm-playlist-header-renderer-v2,
      html.iurub-watch-later ytd-playlist-header-renderer { display:none !important; }
      html.iurub-watch-later { --iurub-toolbar-background:#fff; --iurub-toolbar-foreground:#0f0f0f; }
      html.iurub-watch-later ytm-mobile-topbar-renderer,
      html.iurub-watch-later ytm-mobile-topbar-renderer .mobile-topbar-header { background:var(--yt-spec-base-background,var(--iurub-toolbar-background)) !important; color:var(--yt-spec-text-primary,var(--iurub-toolbar-foreground)) !important; }
      html.iurub-watch-later ytm-mobile-topbar-renderer .mobile-topbar-title { display:block !important; opacity:1 !important; visibility:visible !important; }
      html.iurub-watch-later ytm-mobile-topbar-renderer .mobile-topbar-title,
      html.iurub-watch-later ytm-mobile-topbar-renderer button,
      html.iurub-watch-later ytm-mobile-topbar-renderer c3-icon { color:var(--yt-spec-text-primary,var(--iurub-toolbar-foreground)) !important; }
      @media(prefers-color-scheme:dark) { html.iurub-watch-later { --iurub-toolbar-background:#0f0f0f; --iurub-toolbar-foreground:#f1f1f1; } }
      .iurub-save, .iurub-remove { box-sizing:border-box; display:inline-flex; flex:0 0 44px; align-items:center; justify-content:center; width:44px; height:44px; min-width:44px; min-height:44px; margin:0; padding:0; border:0; border-radius:50%; background:transparent; color:#ef3e32; cursor:pointer; position:relative; z-index:2; -webkit-tap-highlight-color:transparent; }
      .iurub-save::before, .iurub-remove::before { content:""; position:absolute; inset:5px; border-radius:50%; background:#ff3b3010; }
      .iurub-save svg, .iurub-remove svg { position:relative; width:20px; height:20px; pointer-events:none; }
      .iurub-save:active::before, .iurub-remove:active::before { background:#ff3b3025; }
      .iurub-save:disabled, .iurub-remove:disabled { opacity:.45; }
      .iurub-save:focus-visible, .iurub-remove:focus-visible { outline:3px solid #e84a38; outline-offset:-3px; }
      .iurub-save[data-saved="true"] { color:#396548; }
      .iurub-save[data-saved="true"]::before { background:#487b4918; }
      .iurub-action-label { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip-path:inset(50%); white-space:nowrap; border:0; }
      .iurub-inline-details { display:flex !important; align-items:flex-start; }
      .iurub-inline-details > .media-item-metadata, .iurub-inline-details > .ytLockupMetadataViewModelTextContainer { flex:1 1 auto; min-width:0; }
      .iurub-inline-details > .iurub-save { align-self:flex-start; }
      .iurub-stacked-menu { display:flex !important; flex-direction:column; align-items:center; flex-shrink:0; overflow:visible; }
      .iurub-compact-card { position:relative; }
      .iurub-compact-card > .iurub-save, .iurub-compact-card > .iurub-remove { position:absolute; right:4px; bottom:4px; }
      .iurub-compact-card > a > h3, .iurub-compact-card > h3, .iurub-compact-card > .byline { padding-inline-end:48px; }
      @media(prefers-color-scheme:dark) { .iurub-save, .iurub-remove { color:#ff9487; } .iurub-save::before, .iurub-remove::before { background:#ff81751c; } .iurub-save[data-saved="true"] { color:#a4d2b1; } }
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
  const actionIcons = {
    save: 'M7 3h10a1 1 0 0 1 1 1v17l-6-4-6 4V4a1 1 0 0 1 1-1Z',
    remove: 'M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 11v6M14 11v6'
  };
  function setActionIcon(button, action, label) {
    if (!button.querySelector('svg')) {
      // DOM construction also works with YouTube's Trusted Types policy.
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      for (const [name, value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true'})) svg.setAttribute(name, value);
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', actionIcons[action]); svg.append(path);
      const text = document.createElement('span'); text.className = 'iurub-action-label';
      button.append(svg, text);
    }
    const text = button.querySelector('.iurub-action-label');
    if (text.textContent !== label) text.textContent = label;
    button.setAttribute('aria-label', label);
    button.title = label;
  }
  function placeAction(card, button, removing) {
    // Current mobile layouts put the title/avatar and menu in these rows.
    // Insert alongside the site's menu without moving or replacing its controls.
    const menu = card.querySelector('.YtmCompactMediaItemMenu, .ytLockupMetadataViewModelMenuButton, .media-item-menu');
    const details = card.querySelector('.media-item-info, yt-lockup-metadata-view-model');
    if (removing && menu) {
      menu.classList.add('iurub-stacked-menu');
      if (button.parentElement !== menu) menu.append(button);
      card.classList.remove('iurub-compact-card');
    } else if (!removing && details && menu && menu.parentElement === details) {
      details.classList.add('iurub-inline-details');
      menu.classList.remove('iurub-stacked-menu');
      if (button.parentElement !== details) details.insertBefore(button, menu);
      card.classList.remove('iurub-compact-card');
    } else {
      // Unknown or minimal layouts keep the control inside the existing card,
      // never add a separate block underneath its thumbnail and description.
      card.classList.add('iurub-compact-card');
      if (button.parentElement !== card) card.append(button);
    }
  }
  function updateButton(button, id) {
    const saved = !accountSaving && savedIDs.has(id);
    const label = saved ? '✓ Salvato in Guarda più tardi' : '+ Guarda più tardi';
    setActionIcon(button, 'save', label);
    button.dataset.saved = String(saved);
  }
  function scan() {
    scanQueued = false;
    if (!document.documentElement) return;
    installStyle();
    document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
    const inWatchLater = (location.pathname === '/playlist' && new URL(location.href).searchParams.get('list') === 'WL') || document.documentElement.dataset.fixturePlaylist === 'true';
    document.documentElement.classList.toggle('iurub-watch-later', inWatchLater);
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
      let removeButton = card.querySelector('.iurub-remove');
      if (accountSaving && inWatchLater && link) {
        card.querySelector('.iurub-save')?.remove();
        if (!removeButton) {
          removeButton = document.createElement('button'); removeButton.type = 'button';
          removeButton.className = 'iurub-remove';
          setActionIcon(removeButton, 'remove', 'Rimuovi da Guarda più tardi');
          removeButton.addEventListener('click', event => {
            event.preventDefault(); event.stopPropagation(); event.stopImmediatePropagation();
            removeThroughYouTube(card, removeButton);
          });
        }
        placeAction(card, removeButton, true);
        return;
      }
      removeButton?.remove();
      let button = card.querySelector('.iurub-save');
      if (!link) { button?.remove(); card.classList.remove('iurub-compact-card'); return; }
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
      }
      placeAction(card, button, false);
      button.__iurubVideo = metadata(card, anchor, link);
      button.dataset.videoId = link.id;
      updateButton(button, link.id);
    });
    reportCurrent();
    applyResume();
    reportPlayback();
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
  function startSeconds(raw) {
    try {
      const url = new URL(raw, location.href);
      const value = url.searchParams.get('t') ?? url.searchParams.get('start') ?? new URLSearchParams(url.hash.slice(1)).get('t');
      if (value === null) return undefined;
      let seconds;
      if (/^\d+(?:\.\d+)?$/.test(value)) seconds = Number(value);
      else {
        const parts = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?$/.exec(value);
        if (!parts || !parts.slice(1).some(Boolean)) return undefined;
        seconds = Number(parts[1] || 0) * 3600 + Number(parts[2] || 0) * 60 + Number(parts[3] || 0);
      }
      return Number.isFinite(seconds) && seconds >= 0 && seconds <= 31536000 ? seconds : undefined;
    } catch { return undefined; }
  }
  let lastRoutedOpen = { key:'', time:0 };
  function routeVideo(raw, anchor) {
    if (!routeVideoOpens) return false;
    let link;
    try { link = parseLink(new URL(raw, location.href).href); } catch { return false; }
    if (!link || (!shortsEnabled && link.isShort)) return false;
    if (!anchor) anchor = Array.from(document.querySelectorAll('a[href]')).find(a => parseLink(a.href)?.id === link.id);
    const card = anchor?.closest(CARD);
    const video = card ? metadata(card, anchor, link) : {
      ...link,
      title: clean(anchor?.getAttribute('title') || anchor?.getAttribute('aria-label') || anchor?.textContent || 'Video YouTube'),
      channel: ''
    };
    const position = startSeconds(raw);
    const key = link.id + ':' + String(position);
    if (lastRoutedOpen.key !== key || Date.now() - lastRoutedOpen.time > 300) {
      lastRoutedOpen = {key, time:Date.now()};
      post('openVideo', {video, ...(position === undefined ? {} : {startSeconds:position})});
    }
    return true;
  }

  let boundMedia = null;
  let boundVideoID = null;
  let awaitingMetadata = false;
  let pendingResume = null;
  let appliedResumeKey = null;
  let lastProgressTime = -Infinity;
  let lastProgress = '';
  const mainVideo = () => document.querySelector('#movie_player video') || document.querySelector('video.html5-main-video') || document.querySelector('video');
  const unavailablePlayback = media => !media || document.querySelector('.ad-showing, .ad-interrupting, .html5-video-player.ytp-live') || !Number.isFinite(media.duration) || media.duration <= 0;
  function bindMedia(media, metadataReady = false) {
    const id = parseLink(location.href)?.id;
    if (!id || !media) return;
    if (boundMedia !== media) {
      boundMedia = media; boundVideoID = id; awaitingMetadata = false;
      lastProgressTime = -Infinity; lastProgress = '';
    } else if (metadataReady) {
      boundVideoID = id; awaitingMetadata = false;
    } else if (!awaitingMetadata && boundVideoID === null) boundVideoID = id;
  }
  function applyResume(confirmedSeek = false) {
    if (!trackPlayback || !pendingResume) return;
    const media = mainVideo();
    const id = parseLink(location.href)?.id;
    bindMedia(media);
    if (id !== pendingResume.id || boundVideoID !== id || awaitingMetadata || unavailablePlayback(media) || media.readyState < 1) return;
    const target = Math.min(pendingResume.position, media.duration);
    if (Math.abs(media.currentTime - target) <= 0.5 && !media.seeking && (!pendingResume.attempted || confirmedSeek)) {
      appliedResumeKey = pendingResume.key;
      pendingResume = null;
      return;
    }
    if (pendingResume.attempted && (media.seeking || (Math.abs(media.currentTime - target) <= 0.5 && !confirmedSeek))) return;
    // Set before assigning: a deterministic test media element can emit seeked synchronously.
    pendingResume.attempted = true;
    try { media.currentTime = target; } catch { pendingResume.attempted = false; }
  }
  function restorePlayback(resume) {
    if (!resume || !VIDEO_ID.test(resume.id || '') || !Number.isFinite(resume.position) || resume.position < 0 || resume.position > 31536000) return false;
    const key = resume.id + ':' + resume.position;
    if (key === appliedResumeKey || key === pendingResume?.key) return true;
    pendingResume = {id:resume.id, position:resume.position, key, attempted:false};
    applyResume();
    return true;
  }
  function adoptPlayback(adoption) {
    if (!trackPlayback || !adoption || typeof adoption.session !== 'string' || !adoption.session.trim() || !VIDEO_ID.test(adoption.id || '') || adoption.id !== parseLink(location.href)?.id || !Number.isFinite(adoption.position) || adoption.position < 0 || adoption.position > 31536000) return false;
    // URL observation and didFinish may both adopt the same restored document.
    // A generation represents one restoration intent; never seek it twice.
    if (playbackSession === adoption.session) return true;
    playbackSession = adoption.session;
    boundMedia = null; boundVideoID = null; awaitingMetadata = false;
    pendingResume = null; appliedResumeKey = null;
    lastProgressTime = -Infinity; lastProgress = '';
    const restored = restorePlayback({id:adoption.id, position:adoption.position});
    reportPlayback(true);
    return restored;
  }
  function playbackSnapshot() {
    if (!trackPlayback) return null;
    const media = mainVideo();
    const id = parseLink(location.href)?.id;
    bindMedia(media);
    if (!id || boundVideoID !== id || awaitingMetadata || pendingResume || unavailablePlayback(media) || media.readyState < 2 || media.seeking || !Number.isFinite(media.currentTime) || media.currentTime < 0) return null;
    return {id, position:Math.min(media.currentTime, media.duration), duration:media.duration, ended:Boolean(media.ended), ...(playbackSession === undefined ? {} : {session:playbackSession})};
  }
  function reportPlayback(force = false, ended = false) {
    const snapshot = playbackSnapshot();
    if (!snapshot) return;
    if (ended) snapshot.ended = true;
    const now = Date.now();
    const serialized = JSON.stringify(snapshot);
    if (!force && now - lastProgressTime < 5000) return;
    if (force && serialized === lastProgress && now - lastProgressTime < 500) return;
    lastProgressTime = now; lastProgress = serialized;
    post('playback', snapshot);
  }
  function playbackEvent(event) {
    if (!trackPlayback || event.target !== mainVideo()) return;
    if (event.type === 'emptied') { boundVideoID = null; awaitingMetadata = true; return; }
    bindMedia(event.target, event.type === 'loadedmetadata');
    applyResume(['seeked', 'canplay', 'timeupdate'].includes(event.type));
    // A seek can finish after a pause/background flush; persist its final position too.
    reportPlayback(event.type === 'pause' || event.type === 'ended' || (event.type === 'seeked' && event.target.paused), event.type === 'ended');
  }
  for (const name of ['loadedmetadata', 'canplay', 'timeupdate', 'seeked', 'pause', 'ended', 'emptied']) document.addEventListener(name, playbackEvent, true);
  window.addEventListener('pagehide', () => reportPlayback(true));
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') reportPlayback(true); });
  function checkRoute() {
    if (!shortsEnabled && isShortRoute(location.href)) {
      post('blockedShort');
      location.replace('https://m.youtube.com/');
      return;
    }
    scheduleScan();
  }
  document.addEventListener('click', event => {
    const target = event.target;
    const anchor = target.closest?.('a[href]');
    if (!shortsEnabled && ((anchor && isShortRoute(anchor.href)) || target.closest?.('[data-iurub-short],.pivot-shorts'))) {
      event.preventDefault(); event.stopImmediatePropagation(); post('blockedShort'); return;
    }
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey || event.button > 0 || target.closest?.('.iurub-save,.iurub-remove,button,[role="button"],[role="menuitem"]')) return;
    if (anchor && routeVideo(anchor.href, anchor)) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function(state, title, url) {
      if (url && !shortsEnabled && isShortRoute(url)) { post('blockedShort'); return; }
      if (url && routeVideo(url)) return;
      const previousID = parseLink(location.href)?.id;
      const nextID = url ? parseLink(new URL(url, location.href).href)?.id : previousID;
      if (trackPlayback && previousID !== nextID) reportPlayback(true);
      const result = original.apply(this, arguments);
      if (previousID !== nextID) { boundVideoID = null; awaitingMetadata = true; lastProgressTime = -Infinity; lastProgress = ''; }
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
      if ('shortsEnabled' in config) shortsEnabled = Boolean(config.shortsEnabled);
      if ('savedIDs' in config) savedIDs = new Set(config.savedIDs || []);
      if ('routeVideoOpens' in config) routeVideoOpens = Boolean(config.routeVideoOpens);
      if ('trackPlayback' in config) trackPlayback = Boolean(config.trackPlayback);
      if (config.resume) restorePlayback(config.resume);
      if (document.documentElement) document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
      checkRoute();
    },
    currentVideo,
    playbackSnapshot,
    restorePlayback,
    adoptPlayback,
    saveCurrentToYouTube() { saveThroughYouTube(null, currentVideo(), null); },
    pause() { reportPlayback(true); document.querySelectorAll('video,audio').forEach(media => media.pause()); }
  };
  if (document.documentElement) {
    document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
    installStyle();
  }
  if (initial.resume) restorePlayback(initial.resume);
  const observer = new MutationObserver(scheduleScan);
  observer.observe(document, { childList:true, subtree:true, attributes:true, attributeFilter:['href'] });
  document.addEventListener('DOMContentLoaded', checkRoute, { once:true });
  checkRoute();
})();
