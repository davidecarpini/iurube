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
  const accountMembership = new Map();
  const reportedMembership = new Map();
  const observedWatchLaterCards = new WeakMap();
  let undoCandidate = null;
  let pendingNotice = null;
  let menuSource = null;
  mergeMembership(initial);
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
      html.iurub-mini, html.iurub-mini body { background:#000 !important; overflow:hidden !important; }
      html.iurub-mini [data-iurub-player-path] { position:static !important; transform:none !important; contain:none !important; clip-path:none !important; overflow:visible !important; }
      html.iurub-mini [data-iurub-player-path] > :not([data-iurub-player-path]):not([data-iurub-mini-video]) { visibility:hidden !important; }
      html.iurub-mini video[data-iurub-mini-video] { position:fixed !important; inset:0 !important; z-index:2147483647 !important; width:100% !important; height:min(100%,56.25vw) !important; max-width:none !important; max-height:none !important; margin:0 !important; transform:none !important; object-fit:contain !important; visibility:visible !important; background:black; }

      html.iurub-watch-page [data-iurub-watch-recommendations] { display:none !important; }
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
      .iurub-save[data-saved="false"] { color:var(--yt-spec-text-primary,#272727); }
      :is(.iurub-save,.iurub-remove)[data-saved="true"] { color:#c34230; }
      :is(.iurub-save,.iurub-remove)[data-saved="true"] svg { fill:currentColor; }
      :is(.iurub-save,.iurub-remove)::before { background:transparent; }
      .iurub-action-label { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip-path:inset(50%); white-space:nowrap; border:0; }
      .iurub-inline-details { display:flex !important; align-items:flex-start; min-width:0; }
      .iurub-inline-details > :is(.media-item-metadata,.ytLockupMetadataViewModelTextContainer,.yt-lockup-metadata-view-model__text-container) { flex:1 1 0% !important; min-width:0; margin-inline-end:0 !important; }
      .iurub-inline-details > .iurub-native-menu { position:relative !important; inset:auto !important; margin:0 !important; flex:0 0 44px !important; width:44px !important; height:44px; display:flex !important; justify-content:center; align-items:center; }
      .iurub-inline-details > .iurub-native-menu :is(button,[role="button"]) { margin:0 !important; }
      .iurub-inline-details > :is(.iurub-save,.iurub-remove) { align-self:flex-start; }
      .iurub-minimal-card:not([data-iurub-watch-recommendations]):not([data-iurub-short]) { display:grid; grid-template-columns:minmax(0,1fr) auto auto; align-items:start; }
      .iurub-minimal-card > :not(.iurub-native-menu,.iurub-save,.iurub-remove) { grid-column:1; }
      .iurub-minimal-card > .iurub-native-menu { grid-area:1/2; }
      .iurub-minimal-card > :is(.iurub-save,.iurub-remove) { grid-area:1/3; }
      html.iurub-inline-comments body { position:static !important; overflow-y:auto !important; }
      html.iurub-inline-comments ytm-engagement-panel:has(.engagement-panel-comments-section) { position:relative !important; display:block; inset:auto !important; width:100% !important; height:auto !important; transform:none !important; }
      html.iurub-inline-comments .engagement-panel-comments-section { height:max(320px, 68dvh) !important; max-height:none !important; }
      html.iurub-inline-comments .engagement-panel-comments-section > ytw-scrim { display:none !important; }
      html.iurub-inline-comments .YtmCommentSimpleboxRendererHost { padding:4px 12px !important; margin:0 !important; }
      html.iurub-inline-comments .YtmCommentSimpleboxRendererInput { min-height:32px !important; }
      html.iurub-inline-comments [data-iurub-comments-preview] { display:none !important; }
      @media(prefers-color-scheme:dark) { .iurub-save, .iurub-remove { color:#ff9487; } .iurub-save::before, .iurub-remove::before { background:#ff81751c; } .iurub-save[data-saved="false"] { color:var(--yt-spec-text-primary,#f1f1f1); } :is(.iurub-save,.iurub-remove)[data-saved="true"] { color:#ff9487; } }
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
  function mergeMembership(config) {
    if (config.resetMembership === true) {
      accountMembership.clear(); reportedMembership.clear(); pendingNotice = null; menuSource = null; undoCandidate = null;
      // Existing cards may be stale after an account change; configure is not evidence.
    }
    for (const id of Array.isArray(config.savedIDs) ? config.savedIDs : []) if (VIDEO_ID.test(id)) { accountMembership.set(id, true); reportedMembership.set(id, true); }
    for (const id of Array.isArray(config.removedIDs) ? config.removedIDs : []) if (VIDEO_ID.test(id)) { accountMembership.set(id, false); reportedMembership.set(id, false); }
  }
  function rememberMembership(video, saved) {
    if (!accountSaving || !video || !VIDEO_ID.test(video.id || '') || typeof saved !== 'boolean') return;
    accountMembership.set(video.id, saved);
    document.querySelectorAll('.iurub-save,.iurub-remove').forEach(button => {
      if (button.dataset.videoId === video.id) updateButton(button, video.id);
    });
    if (reportedMembership.get(video.id) !== saved) {
      reportedMembership.set(video.id, saved);
      post('youtubeMembership', {video, saved});
    }
  }
  function accountResult(status, video, saved) {
    post('youtubeSaveResult', {status, video, ...(typeof saved === 'boolean' ? {saved} : {})});
  }
  const toastHost = 'ytm-notification-action-bottom-bar-renderer,ytm-notification-multi-action-renderer,ytm-notification-text-renderer,ytm-notification-action-renderer,yt-notification-action-renderer,ytd-notification-action-renderer,tp-yt-paper-toast,ytm-toast-renderer,yt-snackbar-view-model,.notification-action-response,.notification-action-bottom-bar';
  const noticeSelector = toastHost + ',[role="status"],[role="alert"]';
  // The visual toast can be aria-hidden when a separate live region announces the same text.
  function noticeIsRendered(node) {
    return node.isConnected && !node.closest('[hidden]') && node.getClientRects().length > 0 &&
      getComputedStyle(node).display !== 'none' && getComputedStyle(node).visibility !== 'hidden';
  }
  const notifications = () => Array.from(document.querySelectorAll(noticeSelector)).filter(noticeIsRendered);
  const noticeText = n => clean(n.textContent || n.getAttribute('aria-label'), 500);
  const notificationSnapshot = () => new Map(notifications().map(n => [n, noticeText(n)]));
  const freshNotifications = before => notifications().filter(n => before.get(n) !== noticeText(n)).map(noticeText);
  const failureNotice = text => /\b(error|failed|unable|cannot|couldn.t|impossibile|errore|riprova)\b|not (?:added|saved|removed)|non (?:salvat|aggiunt|rimoss)/i.test(text);
  const savedNotice = text => watchLaterText.test(text) && /added|saved|aggiunt[oa]|salvat[oa]/i.test(text) && !failureNotice(text);
  const removedNotice = text => watchLaterText.test(text) && /removed|rimoss[oa]|rimozione/i.test(text) && !failureNotice(text);
  // Some mobile layouts omit the list name in the confirmation for the selected WL action.
  function confirmsPlaylistEdit(text, desired) {
    if (failureNotice(text)) return false;
    if (desired ? savedNotice(text) : removedNotice(text)) return true;
    return desired ? /^(?:video )?(?:salvato|aggiunto alla playlist|saved|added to playlist)(?:[.! ]*(?:annulla|undo|visualizza|view))?[.! ]*$/i.test(text)
      : /^(?:video )?(?:rimosso(?: dalla playlist)?|removed(?: from playlist)?)(?:[.! ]*(?:annulla|undo))?[.! ]*$/i.test(text);
  }
  function trackNotice(edit) {
    pendingNotice?.observer.disconnect();
    if (pendingNotice) clearTimeout(pendingNotice.timer);
    pendingNotice = edit;
    edit.observer = new MutationObserver(records => {
      if (window.document?.documentElement && pendingNotice === edit) inspectNoticeChanges(records);
    });
    edit.observer.observe(document, {childList:true, subtree:true, characterData:true, attributes:true,
      attributeFilter:['hidden','aria-hidden','aria-label','class','style','open']});
    edit.timer = setTimeout(() => {
      edit.observer.disconnect();
      if (pendingNotice === edit) pendingNotice = null;
    }, 15000);
    return edit;
  }
  function beginPlaylistEdit(video, desired) {
    return trackNotice({video, desired, before:notificationSnapshot()});
  }
  function captureSitePlaylistAction(event) {
    if (!accountSaving || savingToAccount || event.target.closest?.('.iurub-save,.iurub-remove')) return;
    const control = event.target.closest?.(actionSelector + ',' + playlistChoiceSelector);
    if (!control) return;
    const card = control.closest(CARD);
    const anchor = card && Array.from(card.querySelectorAll('a[href]')).find(a => parseLink(a.href));
    const video = anchor && metadata(card, anchor, parseLink(anchor.href));
    if (video) menuSource = {video, url:location.href, until:Date.now() + 20000};
    const label = labelOf(control);
    if (!watchLaterText.test(label) && !/^(?:save|salva)(?:$| (?:to|in|nella) .*playlist)/i.test(label)) return;
    // A site's own Save command can select another list. Only an explicitly
    // named Watch Later confirmation can change our bookmark or replace its toast.
    const source = video || (menuSource?.url === location.href && Date.now() < menuSource.until ? menuSource.video : currentVideo());
    trackNotice({video:source, before:notificationSnapshot()});
  }
  // The mobile confirmation with a thumbnail can be an ordinary unlabelled div.
  // Match newly inserted result text, never a pre-existing video title or a menu command.
  const explicitResult = /^(?:(?:video\s+)?(?:salvat[oa]|aggiunt[oa]|rimoss[oa])\s+(?:in|a|da|dalla?)|(?:video\s+)?(?:added to|saved to|removed from))\s+["“«]?(?:guarda pi[uù] tardi|watch later)["”»]?(?:[.!\s]*(?:annulla|undo|visualizza|view|modifica|edit))?[.!\s]*$/i;
  function publishEdit(edit, saved) {
    if (pendingNotice !== edit || edit.reported) return;
    edit.reported = true;
    edit.observer.disconnect();
    if (edit.video) {
      rememberMembership(edit.video, saved);
      undoCandidate = {video:edit.video, saved:!saved, expires:Date.now()+15000};
    }
    accountResult(edit.undo ? 'undone' : saved ? 'saved' : 'removed', edit.video, saved);
  }
  function inspectNoticeChanges(records) {
    const edit = pendingNotice;
    if (!edit || edit.reported) return;
    const labels = freshNotifications(edit.before);
    if (labels.some(failureNotice)) { edit.failed = true; edit.observer.disconnect(); return; }
    if (edit.failed) return;
    for (const record of records) {
      const changed = record.type === 'childList' ? record.addedNodes : [record.target];
      for (const node of changed) {
        const el = node.nodeType === 1 ? node : node.parentElement;
        if (!el || !el.isConnected || el.closest('script,style,h1,h2,h3,h4,[role="menu"],.iurub-save,.iurub-remove,' + CARD)) continue;
        // Bound this read to a single small message, including text split across spans.
        for (const candidate of [el, el.parentElement]) {
          if (!candidate || candidate.childElementCount > 8 || candidate.matches('html,body')) continue;
          const text = (candidate.textContent || '').trim().normalize('NFC').replace(/\s+/g,' ');
          if (text.length <= 140 && explicitResult.test(text) && noticeIsRendered(candidate)) labels.push(text);
        }
      }
    }
    for (const text of labels) {
      const saved = savedNotice(text);
      const state = saved ? true : removedNotice(text) ? false : undefined;
      if (state !== undefined && (edit.desired === undefined || edit.desired === state)) {
        publishEdit(edit, state);
        return;
      }
    }
  }
  const directWatchLater = () => menuRoots().flatMap(controls).find(n => watchLaterText.test(labelOf(n)) && /save|add|salva|aggiungi|remove|rimuovi/i.test(labelOf(n)));
  const directState = node => /remove|rimuovi/i.test(labelOf(node)) ? true : /save|add|salva|aggiungi/i.test(labelOf(node)) ? false : null;
  function dismissChooser() {
    const close = menuRoots().flatMap(controls).find(n => /^(close|chiudi|done|fine)$/i.test(labelOf(n)));
    close?.click();
  }
  async function transitionEvidence(before, desired, allowUndo = false, edit = null) {
    const started = Date.now();
    return await until(() => {
      if (edit?.failed) return 'failed';
      if (edit?.reported) return 'confirmed';
      const notices = freshNotifications(before);
      if (notices.some(failureNotice)) return 'failed';
      if (notices.some(text => confirmsPlaylistEdit(text, desired))) return 'confirmed';
      if (allowUndo && notices.some(text => /^(?:action )?undone|^annullat[oa]|annullamento (?:riuscito|completato)/i.test(text))) return 'confirmed';
      // Wait for a changed control to settle; detached chooser state is not proof.
      if (Date.now() - started >= 250) {
        const choice = watchLaterChoice();
        if (choice && selectionState(choice) === desired) return 'confirmed';
        const direct = directWatchLater();
        if (direct && directState(direct) === desired) return 'confirmed';
      }
      return null;
    }, 2200);
  }
  async function finishAccountChange(edit) {
    const evidence = await transitionEvidence(edit.before, edit.desired, false, edit);
    if (pendingNotice !== edit) return;
    if (evidence === 'confirmed') {
      publishEdit(edit, edit.desired);
      dismissChooser();
    } else {
      if (evidence === 'failed') pendingNotice = null;
      // A timeout is not a denial. A later site message can still settle this edit.
      accountResult(evidence === 'failed' ? 'failed' : 'submitted', edit.video);
    }
  }
  async function chooseCheckbox(video, desired, existing) {
    const checkbox = existing || await until(watchLaterChoice);
    if (!checkbox) { accountResult('choose', video); return; }
    const selected = selectionState(checkbox);
    if (selected === null) { accountResult('choose', video); return; }
    rememberMembership(video, selected);
    if (selected === desired) {
      accountResult(desired ? 'alreadySaved' : 'alreadyRemoved', video, selected);
      dismissChooser(); return;
    }
    const edit = beginPlaylistEdit(video, desired);
    checkbox.click();
    const confirm = menuRoots().flatMap(controls).find(n => /^(done|save|fine|salva)$/i.test(labelOf(n)));
    confirm?.click();
    await finishAccountChange(edit);
  }
  async function chooseWatchLater(video, desired, opening) {
    const entry = await until(() => {
      if (opening.reported || opening.failed) return {handled:true};
      const checkbox = watchLaterChoice();
      if (checkbox) return {checkbox};
      const direct = directWatchLater();
      if (direct && (desired || directState(direct))) return {direct};
      const playlist = menuRoots().flatMap(controls).find(n =>
        /save to (?:a )?playlist|salva (?:in una|nella|in) playlist|salva in una raccolta/i.test(labelOf(n)));
      return playlist ? {playlist} : null;
    });
    if (entry?.handled) return;
    if (!entry) { accountResult('submitted', video); return; }
    if (entry.direct) {
      const selected = directState(entry.direct);
      if (selected === null) { accountResult('choose', video); return; }
      rememberMembership(video, selected);
      if (selected === desired) {
        accountResult(desired ? 'alreadySaved' : 'alreadyRemoved', video, selected);
        dismissChooser(); return;
      }
      const edit = beginPlaylistEdit(video, desired);
      entry.direct.click();
      await finishAccountChange(edit);
    } else if (entry.playlist) {
      entry.playlist.click();
      await chooseCheckbox(video, desired);
    } else await chooseCheckbox(video, desired, entry.checkbox);
  }
  function cardMenu(card) {
    return controls(card).find(n => /action menu|menu azion[ei]|menu delle azioni|altre azioni|more actions/i.test(labelOf(n)))
      || card.querySelector('button[aria-haspopup="true"], ytm-menu-renderer button, ytm-menu-renderer .icon-button, ytm-bottom-sheet-renderer button');
  }
  async function saveThroughYouTube(card, video, button, requestedState) {
    if (savingToAccount || !video || !VIDEO_ID.test(video.id || '') || (!shortsEnabled && video.isShort)) return;
    savingToAccount = true;
    const desired = typeof requestedState === 'boolean' ? requestedState : accountMembership.get(video.id) !== true;
    if (button) button.disabled = true;
    try {
      let opener = card ? cardMenu(card) : controls(document).find(n => /^(save.*playlist|salva.*playlist)$/i.test(labelOf(n)));
      if (!opener && !card) {
        const actions = document.querySelector('ytm-slim-video-action-bar-renderer, ytm-slim-video-metadata-section-renderer, #above-the-fold #actions');
        if (actions) opener = controls(actions).find(n => /^(save|salva)$/i.test(labelOf(n)));
      }
      if (!opener) { accountResult('manual', video); return; }
      const opening = beginPlaylistEdit(video, desired);
      opener.click();
      await chooseWatchLater(video, desired, opening);
    } catch { accountResult('manual', video); }
    finally { savingToAccount = false; if (button) button.disabled = false; }
  }
  function togglePlaylistRow(card, button) {
    const anchor = Array.from(card.querySelectorAll('a[href]')).find(a => parseLink(a.href));
    const link = anchor && parseLink(anchor.href);
    if (link) saveThroughYouTube(card, metadata(card, anchor, link), button);
  }
  function observeAccountContext(event) {
    if (!accountSaving || event.target.closest?.('.iurub-save,.iurub-remove')) return;
    const control = event.target.closest?.('button,[role="button"],[role="menuitem"]');
    const accountAction = control && /^(switch accounts?|cambia account|cambia profilo|sign out|log out|esci|sign in|log in|accedi|use youtube signed out|usa youtube senza eseguire l.accesso)$/i.test(labelOf(control));
    let accountLink = false;
    const anchor = event.target.closest?.('a[href]');
    if (anchor) {
      try {
        const url = new URL(anchor.href, location.href);
        if (['https:', 'http:'].includes(url.protocol) && !url.username && !url.password) accountLink = url.hostname === 'accounts.google.com' || ((url.hostname === 'youtube.com' || url.hostname.endsWith('.youtube.com')) && /^\/(?:signin|logout|feed\/library)\/?$/.test(url.pathname));
      } catch {}
    }
    if (accountAction || accountLink) post('youtubeAccountContextChanged');
  }
  function observeUndo(event) {
    const control = event.target.closest?.('button,[role="button"]');
    if (!control || !/^(undo|annulla)$/i.test(labelOf(control)) || !undoCandidate || Date.now() > undoCandidate.expires) return;
    const container = control.closest(noticeSelector) || control.parentElement;
    if (!container || (!control.closest(noticeSelector) && !explicitResult.test(clean(container.textContent, 200)))) return;
    const context = undoCandidate;
    const before = notificationSnapshot();
    const undoEdit = trackNotice({video:context.video, desired:context.saved, before, undo:true});
    undoCandidate = null;
    // YouTube owns Undo; a confirming update, rather than the click, is evidence.
    setTimeout(async () => {
      if (await transitionEvidence(before, context.saved, true, undoEdit) === 'confirmed' && !undoEdit.reported && pendingNotice === undoEdit) publishEdit(undoEdit, context.saved);
    }, 0);
  }
  function setBookmarkLabel(button, label) {
    if (!button.querySelector('svg')) {
      // DOM construction also works with YouTube's Trusted Types policy.
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      for (const [name, value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true'})) svg.setAttribute(name, value);
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', 'M7 3h10a1 1 0 0 1 1 1v17l-6-4-6 4V4a1 1 0 0 1 1-1Z'); svg.append(path);
      const text = document.createElement('span'); text.className = 'iurub-action-label';
      button.append(svg, text);
    }
    const text = button.querySelector('.iurub-action-label');
    if (text.textContent !== label) text.textContent = label;
    if (button.getAttribute('aria-label') !== label) button.setAttribute('aria-label', label);
    button.title = label;
  }
  function placeAction(card, button) {
    // YouTube positions the overflow menu absolutely on several mobile renderers.
    // Give its original wrapper and our button separate slots in the metadata row.
    const menu = card.querySelector('.YtmCompactMediaItemMenu,.ytLockupMetadataViewModelMenuButton,.yt-lockup-metadata-view-model__menu-button,.media-item-menu')
      || card.querySelector('ytm-menu-renderer,ytm-bottom-sheet-renderer') || cardMenu(card);
    const row = menu?.parentElement || card.querySelector('.media-item-info,yt-lockup-metadata-view-model') || card;
    if (row === card) row.classList.add('iurub-minimal-card');
    else row.classList.add('iurub-inline-details');
    if (menu) {
      menu.classList.add('iurub-native-menu');
      if (menu.nextElementSibling !== button) menu.after(button);
    } else if (button.parentElement !== row) row.append(button);
  }
  function updateButton(button, id) {
    const saved = accountSaving ? accountMembership.get(id) === true : savedIDs.has(id);
    const label = saved ? (accountSaving ? 'Rimuovi da Guarda più tardi' : '✓ Salvato in Guarda più tardi') : '+ Guarda più tardi';
    setBookmarkLabel(button, label);
    button.dataset.saved = String(saved);
    button.setAttribute('aria-pressed', String(saved));
  }
  const watchComments = 'ytm-comments-entry-point-header-renderer,ytm-comment-section-renderer,ytm-comment-thread-renderer,ytm-comments-header-renderer,ytd-comments,ytd-comment-thread-renderer,comments-entry-point-teaser-view-model,yt-comment-teaser-carousel-item-view-model,yt-comments-entry-point-header-view-model';
  const watchProtected = watchComments + ',ytm-slim-video-metadata-section-renderer,ytm-slim-video-action-bar-renderer,ytm-slim-owner-renderer,ytm-structured-description-content-renderer,ytm-expandable-video-description-body-renderer,ytm-playlist-panel-renderer,ytd-playlist-panel-renderer,ytm-engagement-panel-section-list-renderer,ytd-engagement-panel-section-list-renderer,#movie_player,#player,ytm-player,.html5-video-player,[role="dialog"],[role="menu"]';
  let commentsVideo = null, commentsAttempts = 0, nextCommentsAttempt = 0;
  function showWatchComments(watchPage) {
    const id = watchPage && trackPlayback ? parseLink(location.href)?.id : null;
    if (commentsVideo !== id) {
      commentsVideo = id; commentsAttempts = 0; nextCommentsAttempt = 0;
    }
    const panel = id && document.querySelector('ytm-engagement-panel .engagement-panel-comments-section');
    const open = Boolean(panel && visible(panel));
    document.documentElement.classList.toggle('iurub-inline-comments', open);
    if (!id || miniEnabled) return;
    const teaser = document.querySelector('ytm-comments-entry-point-header-renderer,comments-entry-point-teaser-view-model,yt-comments-entry-point-header-view-model');
    const carousel = teaser?.closest('yt-video-metadata-carousel-view-model');
    const preview = carousel && carousel.querySelectorAll('yt-carousel-item-view-model').length <= 1 ? carousel : teaser;
    if (open || document.querySelector('ytm-comment-section-renderer:not([hidden]) ytm-comment-thread-renderer,ytd-comments ytd-comment-thread-renderer')) {
      commentsAttempts = 3; // Respect a subsequent manual dismissal.
      if (preview && open) preview.setAttribute('data-iurub-comments-preview','');
      return;
    }
    if (!preview || !visible(preview) || commentsAttempts >= 3 || Date.now() < nextCommentsAttempt) return;
    const button = 'button:not([disabled]),[role="button"]:not([aria-disabled="true"])';
    const target = teaser.closest(button) || teaser.querySelector(button)
      || Array.from(preview.querySelectorAll(button)).find(n => /comment/i.test(labelOf(n))) || teaser;
    if (!target || !visible(target)) return;
    commentsAttempts++;
    nextCommentsAttempt = Date.now() + 1500;
    target.click();
    if (commentsAttempts < 3) setTimeout(scheduleScan, 1550);
  }
  function simplifyWatchPage() {
    const watchPage = location.pathname === '/watch' && Boolean(parseLink(location.href));
    document.documentElement.classList.toggle('iurub-watch-page', watchPage);
    document.querySelectorAll('[data-iurub-watch-recommendations]').forEach(node => node.removeAttribute('data-iurub-watch-recommendations'));
    showWatchComments(watchPage);
    if (!watchPage) return;
    // The authenticated mobile layout keeps metadata and the comments teaser
    // inside .related-chips-slot-wrapper. Never hide that entire wrapper.
    const sections = document.querySelectorAll('ytm-item-section-renderer,ytm-watch-next-secondary-results-renderer,ytd-watch-next-secondary-results-renderer,#related');
    sections.forEach(section => {
      if (section.closest(watchProtected) || section.querySelector(watchProtected)) return;
      if (section.getAttribute('section-identifier') === 'related-items' || section.matches('ytm-watch-next-secondary-results-renderer,ytd-watch-next-secondary-results-renderer,#related') || section.querySelector('ytm-related-chip-cloud-renderer,' + CARD)) section.setAttribute('data-iurub-watch-recommendations', 'true');
    });
    document.querySelectorAll(CARD + ',ytm-related-chip-cloud-renderer').forEach(card => {
      if (!card.closest(watchProtected)) card.setAttribute('data-iurub-watch-recommendations', 'true');
    });
  }
  function scan() {
    scanQueued = false;
    if (!document.documentElement) return;
    installStyle();
    simplifyWatchPage();
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
        if (observedWatchLaterCards.get(card) !== link.id) {
          observedWatchLaterCards.set(card, link.id);
          rememberMembership(metadata(card, anchor, link), true);
        }
        card.querySelector('.iurub-save')?.remove();
        if (!removeButton) {
          removeButton = document.createElement('button'); removeButton.type = 'button';
          removeButton.className = 'iurub-remove';
          removeButton.addEventListener('click', event => {
            event.preventDefault(); event.stopPropagation(); event.stopImmediatePropagation();
            togglePlaylistRow(card, removeButton);
          });
        }
        removeButton.dataset.videoId = link.id;
        updateButton(removeButton, link.id);
        placeAction(card, removeButton);
        return;
      }
      removeButton?.remove();
      let button = card.querySelector('.iurub-save');
      if (!link) { button?.remove(); card.classList.remove('iurub-minimal-card'); return; }
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
      placeAction(card, button);
      button.__iurubVideo = metadata(card, anchor, link);
      button.dataset.videoId = link.id;
      updateButton(button, link.id);
    });
    reportCurrent();
    if (miniEnabled) setMiniPlayer(true);
    reportMediaControls();
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
  const speeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  const detached = media => Boolean(media && (media.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === media));
  let lastControls = '', enteringPiP = null, backgroundHandoff = null;
  let miniEnabled = false, miniElement = null;
  function setMiniPlayer(enabled) {
    miniEnabled = trackPlayback && Boolean(enabled);
    const media = miniEnabled ? mainVideo() : null;
    if (miniElement !== media) {
      document.querySelectorAll('[data-iurub-player-path],[data-iurub-mini-video]').forEach(n => {
        n.removeAttribute('data-iurub-player-path'); n.removeAttribute('data-iurub-mini-video');
      });
      if (media) {
        media.setAttribute('data-iurub-mini-video','');
        for (let p=media.parentElement; p && p !== document.documentElement; p=p.parentElement) p.setAttribute('data-iurub-player-path','');
      }
      miniElement = media;
    }
    document.documentElement.classList.toggle('iurub-mini', Boolean(media));
  }
  function resumeIfInterruptedDuringHandoff(request) {
    const media = request.media;
    if (!request.continuePlaying || !media.paused || media.ended || !detached(media) ||
        mainVideo() !== media || request.id !== parseLink(location.href)?.id || navigator.audioSession?.state === 'interrupted') return;
    request.continuePlaying = false;
    media.play().catch(() => {});
  }
  function resumeDetachedRequest() {
    const request = enteringPiP;
    if (request && detached(request.media)) {
      enteringPiP = null;
      resumeIfInterruptedDuringHandoff(request);
      if (!request.continuePlaying && backgroundHandoff?.media === request.media) backgroundHandoff.continuePlaying = false;
    }
    // iOS can deliver its inline pause after the presentation-mode event, even
    // when a PiP window was already open. Only cover the actual app-exit interval.
    if (backgroundHandoff && document.visibilityState === 'hidden' && performance.now() < backgroundHandoff.expires) {
      resumeIfInterruptedDuringHandoff(backgroundHandoff);
    }
  }
  function reportMediaControls() {
    const id = parseLink(location.href)?.id;
    if (!trackPlayback || !id) return;
    const media = mainVideo();
    resumeDetachedRequest();
    const rate = media?.readyState >= 1 && Number.isFinite(media.playbackRate) ? media.playbackRate : null;
    const state = {id, session:playbackSession, rate, detached:detached(media), playing:Boolean(media && !media.paused && !media.ended), ended:Boolean(media?.ended)};
    const key = JSON.stringify(state);
    if (key !== lastControls) { lastControls = key; post('mediaControls', state); }
  }
  function stepSpeed(id, direction) {
    const media = mainVideo();
    if (!trackPlayback || parseLink(location.href)?.id !== id || !media || media.readyState < 1 || ![-1,1].includes(direction)) return false;
    const next = direction > 0 ? speeds.find(r => r > media.playbackRate) : [...speeds].reverse().find(r => r < media.playbackRate);
    if (next == null) return false;
    try { media.playbackRate = next; reportMediaControls(); return media.playbackRate === next; } catch { return false; }
  }
  function togglePiP(id, notifyFailure = true, wasPlayingAtHandoff = false) {
    const media = mainVideo();
    if (!trackPlayback || parseLink(location.href)?.id !== id || !media || media.readyState < 2) return 'notReady';
    const active = detached(media);
    if (!active && (media.disablePictureInPicture || document.permissionsPolicy?.allowsFeature?.('picture-in-picture') === false)) return 'unavailable';
    const webkitAPI = typeof media.webkitSetPresentationMode === 'function' &&
      media.webkitSupportsPresentationMode?.(active ? 'inline' : 'picture-in-picture');
    if (!webkitAPI && !(active ? typeof document.exitPictureInPicture === 'function' :
      document.pictureInPictureEnabled && typeof media.requestPictureInPicture === 'function')) return 'unavailable';
    if (!active && (media.ended || (media.paused && !wasPlayingAtHandoff))) return 'playFirst';
    const request = {media, id, continuePlaying:!active && (!media.paused || wasPlayingAtHandoff)};
    enteringPiP = active ? null : request;
    const failed = () => {
      if (parseLink(location.href)?.id !== id || mainVideo() !== media || detached(media) !== active) return;
      if (enteringPiP === request) enteringPiP = null;
      if (notifyFailure) post('pipFailed', {id, session:playbackSession});
    };
    try {
      if (webkitAPI) media.webkitSetPresentationMode(active ? 'inline' : 'picture-in-picture');
      else (active ? document.exitPictureInPicture() : media.requestPictureInPicture()).catch(failed);
      setTimeout(() => {
        if (enteringPiP !== request) return;
        if (!detached(media)) failed();
        enteringPiP = null;
      }, 2200);
      reportMediaControls();
      return 'requested';
    } catch { enteringPiP = null; return 'unavailable'; }
  }
  for (const event of ['playing','play','pause','ended','loadedmetadata','emptied','ratechange','webkitpresentationmodechanged','enterpictureinpicture','leavepictureinpicture']) {
    document.addEventListener(event, reportMediaControls, true);
  }
  function enterBackground(id, wasPlayingAtHandoff = false, leavingApp = false) {
    if (!trackPlayback || parseLink(location.href)?.id !== id) return;
    reportPlayback(true);
    const media = mainVideo();
    if (!media || media.ended || (media.paused && !wasPlayingAtHandoff)) return;
    if (leavingApp && backgroundHandoff?.media !== media) {
      backgroundHandoff = {id, media, continuePlaying:true, expires:performance.now()+2500};
    }
    if (detached(media)) {
      resumeDetachedRequest();
      return;
    }
    if (enteringPiP?.media === media) return;
    // Ask WebKit for the system window if possible. Let the site's playing media
    // retain ownership if a lifecycle suspension raced the native snapshot.
    togglePiP(id, false, wasPlayingAtHandoff);
  }
  if (trackPlayback) {
    try { if (navigator.audioSession?.type === 'auto') navigator.audioSession.type = 'playback'; } catch {}
  }
  document.addEventListener('playing', event => {
    const id = parseLink(location.href)?.id;
    if (!trackPlayback || !id || event.target !== mainVideo()) return;
    const media = event.target;
    if ('autoPictureInPicture' in media && !media.disablePictureInPicture) media.autoPictureInPicture = true;
  }, true);
  function pauseWhenHidden() {
    reportPlayback(true);
    const primary = mainVideo();
    document.querySelectorAll('video,audio').forEach(media => {
      if (!(trackPlayback && media === primary && (detached(media) || enteringPiP?.media === media))) media.pause();
    });
    return true;
  }
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
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') { reportPlayback(true); resumeDetachedRequest(); }
    else { backgroundHandoff = null; }
  });
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
    captureSitePlaylistAction(event);
    observeUndo(event);
    observeAccountContext(event);
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
      if (accountSaving) mergeMembership(config);
      if ('routeVideoOpens' in config) routeVideoOpens = Boolean(config.routeVideoOpens);
      if ('trackPlayback' in config) trackPlayback = Boolean(config.trackPlayback);
      if (config.resume) restorePlayback(config.resume);
      if (document.documentElement) document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
      checkRoute();
    },
    currentVideo,
    stepSpeed,
    togglePiP,
    setMiniPlayer,
    returnToWatchPage() {
      setMiniPlayer(false);
      if (trackPlayback && location.pathname === '/watch') requestAnimationFrame(() => window.scrollTo(0, 0));
    },
    pauseWhenHidden,
    enterBackground,
    foreground() { backgroundHandoff = null; },
    playbackSnapshot,
    restorePlayback,
    adoptPlayback,
    saveCurrentToYouTube() { saveThroughYouTube(null, currentVideo(), null); },
    toggleCurrentToYouTube() { saveThroughYouTube(null, currentVideo(), null); },
    pause() { enteringPiP = null; backgroundHandoff = null; reportPlayback(true); document.querySelectorAll('video,audio').forEach(media => media.pause()); }
  };
  if (document.documentElement) {
    document.documentElement.classList.toggle('iurub-no-shorts', !shortsEnabled);
    installStyle();
  }
  if (initial.resume) restorePlayback(initial.resume);
  const observer = new MutationObserver(records => {
    if (!window.document?.documentElement) return;
    if (records.every(record => record.type === 'characterData')) return;
    for (const record of records) for (const node of record.removedNodes) {
      if (node.nodeType !== 1) continue;
      if (node.matches(CARD)) observedWatchLaterCards.delete(node);
      node.querySelectorAll(CARD).forEach(card => observedWatchLaterCards.delete(card));
    }
    scheduleScan();
  });
  observer.observe(document, { childList:true, characterData:true, subtree:true, attributes:true, attributeFilter:['href','aria-label'] });
  document.addEventListener('DOMContentLoaded', checkRoute, { once:true });
  checkRoute();
})();
