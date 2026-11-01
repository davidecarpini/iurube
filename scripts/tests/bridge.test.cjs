const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');
const bridge = fs.readFileSync('iurub/Resources/YouTubeBridge.js', 'utf8');
const fixture = fs.readFileSync('iurub/Resources/YouTubeFixture.html', 'utf8');
const wait = (ms = 220) => new Promise(resolve => setTimeout(resolve, ms));
async function setup(html = fixture, url = 'https://m.youtube.com/', config = {}, beforeBridge = () => {}) {
  const dom = new JSDOM(html, { url, runScripts:'dangerously', pretendToBeVisual:true });
  // jsdom has no layout; production visibility still checks hidden/style state.
  dom.window.HTMLElement.prototype.getClientRects = function() { return [{width:100,height:44}]; };
  const messages = [];
  dom.window.webkit = { messageHandlers:{ iurub:{ postMessage: m => messages.push(m) } } };
  dom.window.__iurubConfig = config;
  beforeBridge(dom.window);
  dom.window.eval(bridge);
  await wait();
  return { dom, w:dom.window, d:dom.window.document, messages };
}

test('adds one save control, sends validated metadata and waits for native acknowledgment', async () => {
  const { dom, d, w, messages } = await setup();
  try {
    const card = d.querySelector('ytm-video-with-context-renderer');
    assert.equal(card.querySelectorAll('.iurub-save').length, 1);
    const button = card.querySelector('.iurub-save');
    button.click();
    const save = messages.find(m => m.type === 'save');
    assert.equal(save.video.id, 'jfKfPfyJRdk');
    assert.equal(save.video.title, 'Musica per concentrarsi');
    assert.equal(save.video.channel, 'Canale di prova');
    assert.equal(button.dataset.saved, 'false', 'no optimistic success before disk write');
    w.iurub.configure({shortsEnabled:false, savedIDs:['jfKfPfyJRdk']});
    await wait();
    assert.equal(button.dataset.saved, 'true');
    assert.match(button.textContent, /Salvato/);
    for (let i = 0; i < 4; i++) card.appendChild(d.createElement('span'));
    await wait();
    assert.equal(card.querySelectorAll('.iurub-save').length, 1);
    w.iurub.configure({shortsEnabled:false, savedIDs:[]});
    await wait();
    assert.equal(button.dataset.saved, 'false');
  } finally { dom.window.close(); }
});

test('hides and restores Shorts; blocks clicks and SPA navigation only while disabled', async () => {
  const { dom, d, w, messages } = await setup();
  try {
    const shelf = d.getElementById('short-shelf');
    assert.equal(w.getComputedStyle(shelf).display, 'none');
    const shortLink = shelf.querySelector('a');
    const event = new w.MouseEvent('click', { bubbles:true, cancelable:true });
    shortLink.dispatchEvent(event);
    assert.equal(event.defaultPrevented, true);
    w.history.pushState({}, '', '/shorts/aqz-KE-bpKQ');
    assert.equal(w.location.pathname, '/');
    assert.ok(messages.some(m => m.type === 'blockedShort'));
    w.iurub.configure({shortsEnabled:true, savedIDs:[]});
    await wait();
    assert.notEqual(w.getComputedStyle(shelf).display, 'none');
    w.history.pushState({}, '', '/shorts/aqz-KE-bpKQ');
    assert.equal(w.location.pathname, '/shorts/aqz-KE-bpKQ');
    w.history.replaceState({}, '', '/');
    w.iurub.configure({shortsEnabled:false, savedIDs:[]});
    await wait();
    assert.equal(w.getComputedStyle(shelf).display, 'none');
  } finally { dom.window.close(); }
});

test('handles dynamically added and recycled video cards without stale metadata', async () => {
  const { dom, d, w, messages } = await setup();
  try {
    w.addDynamic();
    await wait();
    const card = d.getElementById('dynamic');
    card.querySelector('.iurub-save').click();
    assert.equal(messages.filter(m => m.type === 'save').at(-1).video.id, 'M7lc1UVf-VE');
    card.querySelector('a').href = '/shorts/aqz-KE-bpKQ';
    card.querySelector('h3').textContent = 'Short riciclato';
    await wait();
    assert.equal(w.getComputedStyle(card).display, 'none');
    card.querySelector('a').href = '/watch?v=jfKfPfyJRdk';
    card.querySelector('h3').textContent = 'Video normale riciclato';
    await wait();
    assert.notEqual(w.getComputedStyle(card).display, 'none');
    card.querySelector('.iurub-save').click();
    const last = messages.filter(m => m.type === 'save').at(-1);
    assert.equal(last.video.id, 'jfKfPfyJRdk');
    assert.equal(last.video.title, 'Video normale riciclato');
    assert.equal(card.querySelectorAll('.iurub-save').length, 1);
  } finally { dom.window.close(); }
});

test('does not mistake hostile origins or malformed links for YouTube videos', async () => {
  const links = ['https://youtube.com.evil.com/watch?v=jfKfPfyJRdk','https://evil@youtube.com/watch?v=jfKfPfyJRdk','/watch?v=bad','javascript:alert(1)','https://youtube.com:8080/watch?v=jfKfPfyJRdk'];
  const html = links.map(h => `<ytm-video-with-context-renderer><a href="${h}">Test</a></ytm-video-with-context-renderer>`).join('');
  const { dom, d } = await setup(html);
  try { assert.equal(d.querySelectorAll('.iurub-save').length, 0); }
  finally { dom.window.close(); }
});

test('nested mobile renderers get one button; metadata text is never interpreted as markup', async () => {
  const { dom, d, messages } = await setup('<ytm-rich-item-renderer><ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>&lt;img src=x onerror=alert(1)&gt;</h3></a></ytm-video-with-context-renderer></ytm-rich-item-renderer>');
  try {
    assert.equal(d.querySelectorAll('.iurub-save').length, 1);
    d.querySelector('.iurub-save').click();
    assert.match(messages.find(m => m.type === 'save').video.title, /^<img/);
    assert.equal(d.querySelectorAll('img').length, 0);
  } finally { dom.window.close(); }
});

test('reports current video metadata for the native save button and clears it on Home', async () => {
  const { dom, w, messages } = await setup('<title>A useful video - YouTube</title>', 'https://m.youtube.com/watch?v=jfKfPfyJRdk');
  try {
    assert.equal(w.iurub.currentVideo().id, 'jfKfPfyJRdk');
    assert.equal(w.iurub.currentVideo().title, 'A useful video');
    w.history.pushState({}, '', '/');
    await wait();
    assert.equal(messages.filter(m => m.type === 'current').at(-1).video, null);
  } finally { dom.window.close(); }
});

test('does not create an observer loop after inserting buttons', async () => {
  const { dom, d, w } = await setup();
  try {
    let mutations = 0;
    const observer = new w.MutationObserver(records => mutations += records.length);
    observer.observe(d, {childList:true, subtree:true});
    await wait(500);
    observer.disconnect();
    assert.equal(mutations, 0);
  } finally { dom.window.close(); }
});

test('hides and blocks the real YouTube Shorts bottom tab even when it has no anchor', async () => {
  const html = '<ytm-pivot-bar-renderer><ytm-pivot-bar-item-renderer id="home"><div role="tab">Home</div></ytm-pivot-bar-item-renderer><ytm-pivot-bar-item-renderer id="shorts"><div role="tab" class="pivot-shorts"><span>Shorts</span></div></ytm-pivot-bar-item-renderer></ytm-pivot-bar-renderer>';
  const { dom, d, w, messages } = await setup(html);
  try {
    assert.equal(w.getComputedStyle(d.getElementById('shorts')).display, 'none');
    assert.notEqual(w.getComputedStyle(d.getElementById('home')).display, 'none');
    const event = new w.MouseEvent('click', { bubbles:true, cancelable:true });
    d.querySelector('.pivot-shorts span').dispatchEvent(event);
    assert.equal(event.defaultPrevented, true);
    assert.ok(messages.some(m => m.type === 'blockedShort'));
    w.iurub.configure({shortsEnabled:true, savedIDs:[]});
    await wait();
    assert.notEqual(w.getComputedStyle(d.getElementById('shorts')).display, 'none');
  } finally { dom.window.close(); }
});

test('does not inject controls into Google login or other origins', async () => {
  const { dom, d, w } = await setup(fixture, 'https://accounts.google.com/');
  try {
    assert.equal(w.iurub, undefined);
    assert.equal(d.querySelectorAll('.iurub-save').length, 0);
    assert.equal(d.getElementById('iurub-style'), null);
  } finally { dom.window.close(); }
});


test('account button uses the YouTube menu and never writes the device library', async () => {
  const { dom, d, messages } = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    d.querySelector('.iurub-save').click();
    await wait(400);
    assert.ok(messages.some(m => m.type === 'fixtureAccountSave' && m.id === 'jfKfPfyJRdk'));
    assert.ok(messages.some(m => m.type === 'youtubeSaveResult' && m.status === 'saved'));
    assert.equal(messages.some(m => m.type === 'save'), false);
    assert.equal(d.querySelector('.iurub-save').dataset.saved, 'false', 'local IDs cannot claim account membership');
  } finally { dom.window.close(); }
});

test('account save never removes an existing Watch later entry', async () => {
  const { dom, d, w, messages } = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube',savedIDs:['jfKfPfyJRdk']});
  try {
    w.fixtureAccountIDs = ['jfKfPfyJRdk'];
    d.querySelector('.iurub-save').click();
    await wait(300);
    assert.ok(messages.some(m => m.type === 'youtubeSaveResult' && m.status === 'alreadySaved'));
    assert.equal(messages.some(m => m.type === 'fixtureAccountSave'), false);
    assert.equal(messages.some(m => m.type === 'save'), false);
  } finally { dom.window.close(); }
});

test('account save falls back to a clear prompt when the site menu is unavailable', async () => {
  const { dom, d, messages } = await setup('<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a></ytm-video-with-context-renderer>', 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    d.querySelector('.iurub-save').click();
    await wait();
    assert.ok(messages.some(m => m.type === 'youtubeSaveResult' && m.status === 'manual'));
    assert.equal(messages.some(m => m.type === 'save'), false);
    assert.equal(d.querySelector('.iurub-save').disabled, false);
  } finally { dom.window.close(); }
});

test('native account save selects only Watch later in the real-style playlist chooser', async () => {
  const html = '<button id="save" aria-label="Save to playlist">Save</button>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {saveDestination:'youtube'});
  try {
    d.getElementById('save').onclick = () => {
      d.body.insertAdjacentHTML('beforeend', '<div role="dialog"><label><input id="other" type="checkbox">Other playlist</label><label><input id="later" type="checkbox">Watch later</label><button id="done">Done</button></div>');
      d.getElementById('done').onclick = () => d.body.insertAdjacentHTML('beforeend','<div role="status">Added to Watch later</div>');
    };
    w.iurub.saveCurrentToYouTube();
    await wait(400);
    assert.equal(d.getElementById('later').checked, true);
    assert.equal(d.getElementById('other').checked, false);
    assert.ok(messages.some(m => m.type === 'youtubeSaveResult' && m.status === 'saved'));
  } finally { dom.window.close(); }
});

test('one-tap removal delegates to the matching YouTube menu and preserves Undo', async () => {
  const html = '<ytm-playlist-video-renderer id="one"><a href="/watch?v=jfKfPfyJRdk"><h3>First</h3></a><button aria-label="Menu Azione">Menu</button></ytm-playlist-video-renderer><ytm-playlist-video-renderer id="two"><a href="/watch?v=M7lc1UVf-VE"><h3>Second</h3></a></ytm-playlist-video-renderer>';
  const { dom, d, messages } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const first = d.getElementById('one');
    let removeCalls = 0;
    first.querySelector('button[aria-label="Menu Azione"]').onclick = () => {
      const menu = d.createElement('div'); menu.setAttribute('role','dialog');
      const item = d.createElement('button'); item.textContent = 'Rimuovi da Guarda più tardi';
      item.onclick = () => {
        removeCalls++; first.remove(); menu.remove();
        const undo = d.createElement('button'); undo.id='youtube-undo'; undo.textContent='Annulla';
        undo.onclick=()=>{d.body.append(first);undo.remove();}; d.body.append(undo);
      };
      menu.append(item); d.body.append(menu);
    };
    assert.equal(d.querySelectorAll('.iurub-remove').length, 2);
    assert.equal(d.querySelectorAll('.iurub-save').length, 0);
    first.querySelector('.iurub-remove').click();
    await wait(300);
    assert.equal(removeCalls, 1);
    assert.equal(d.getElementById('one'), null);
    assert.ok(d.getElementById('two'));
    assert.ok(messages.some(m=>m.type==='youtubeRemoveResult' && m.status==='submitted'));
    d.getElementById('youtube-undo').click();
    await wait();
    assert.ok(d.getElementById('one'));
    assert.equal(d.querySelectorAll('#one .iurub-remove').length, 1);
  } finally { dom.window.close(); }
});

test('watch pages with a playlist parameter do not offer removal on unrelated recommendations', async () => {
  const { dom, d } = await setup(fixture, 'https://m.youtube.com/watch?v=jfKfPfyJRdk&list=WL', {saveDestination:'youtube'});
  try {
    assert.equal(d.querySelectorAll('.iurub-remove').length, 0);
    assert.ok(d.querySelector('.iurub-save'));
  } finally { dom.window.close(); }
});

test('missing removal menu does not delete the card or modify local storage', async () => {
  const html='<ytm-playlist-video-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Keep me</h3></a></ytm-playlist-video-renderer>';
  const { dom, d, messages } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    d.querySelector('.iurub-remove').click();
    await wait();
    assert.ok(d.querySelector('ytm-playlist-video-renderer'));
    assert.ok(messages.some(m=>m.type==='youtubeRemoveResult' && m.status==='manual'));
    assert.equal(messages.some(m=>m.type==='save'), false);
  } finally { dom.window.close(); }
});

for (const state of ['Non selezionato', 'Selezionato', 'Stato sconosciuto']) {
  test(`mobile toggleable playlist entry: ${state}`, async () => {
    const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk">Video</a><button id="menu" aria-label="Menu Azione">Menu</button></ytm-video-with-context-renderer>';
    const { dom, d, messages } = await setup(html, 'https://m.youtube.com/', {saveDestination:'youtube'});
    try {
      let laterClicks = 0, otherClicks = 0;
      d.getElementById('menu').onclick = () => {
        d.body.insertAdjacentHTML('beforeend', '<bottom-sheet-container role="dialog"><ytm-menu-item><button id="playlist">Salva in una playlist</button></ytm-menu-item></bottom-sheet-container>');
        d.getElementById('playlist').onclick = () => {
          d.querySelector('bottom-sheet-container').innerHTML = `<yt-sheet-view-model><toggleable-list-item-view-model><yt-list-item-view-model role="presentation"><div><button role="menuitem" id="later" aria-label="Watch later, Privata, ${state}">Watch later</button></div></yt-list-item-view-model></toggleable-list-item-view-model><toggleable-list-item-view-model><button role="menuitem" id="other" aria-label="Other, Privata, Non selezionato">Other</button></toggleable-list-item-view-model></yt-sheet-view-model>`;
          d.getElementById('later').onclick = () => {
            laterClicks++;
            d.body.insertAdjacentHTML('beforeend','<div role="status">Aggiunto a Guarda più tardi</div>');
          };
          d.getElementById('other').onclick = () => { otherClicks++; };
        };
      };
      d.querySelector('.iurub-save').click();
      await wait(400);
      assert.equal(laterClicks, state === 'Non selezionato' ? 1 : 0);
      assert.equal(otherClicks, 0);
      const status = state === 'Non selezionato' ? 'saved' : state === 'Selezionato' ? 'alreadySaved' : 'choose';
      assert.ok(messages.some(m => m.type === 'youtubeSaveResult' && m.status === status));
      assert.equal(messages.some(m => m.type === 'save'), false);
    } finally { dom.window.close(); }
  });
}

test('removal clicks the nested YouTube button rather than its noninteractive renderer', async () => {
  const html = '<ytm-playlist-video-renderer><a href="/watch?v=jfKfPfyJRdk">Video</a><ytm-bottom-sheet-renderer><button id="menu" aria-label="Menu Azione">Menu</button></ytm-bottom-sheet-renderer></ytm-playlist-video-renderer>';
  const { dom, d } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    let removals = 0;
    d.getElementById('menu').onclick = () => {
      d.body.insertAdjacentHTML('beforeend','<bottom-sheet-container role="dialog"><ytm-menu-service-item-renderer><ytm-menu-item><button id="remove">Rimuovi da Guarda più tardi</button></ytm-menu-item></ytm-menu-service-item-renderer></bottom-sheet-container>');
      d.getElementById('remove').onclick = () => { removals++; };
    };
    d.querySelector('.iurub-remove').click();
    await wait(300);
    assert.equal(removals, 1);
  } finally { dom.window.close(); }
});

test('hides the entire YouTube bottom navigation, including after dynamic updates and enabling Shorts', async () => {
  const { dom, d, w } = await setup();
  try {
    const bar = d.querySelector('ytm-pivot-bar-renderer');
    assert.equal(w.getComputedStyle(bar).display, 'none');
    w.iurub.configure({shortsEnabled:true, savedIDs:[]});
    await wait();
    assert.equal(w.getComputedStyle(bar).display, 'none');
    assert.notEqual(w.getComputedStyle(d.querySelector('#short-shelf')).display, 'none');
    bar.remove();
    d.body.insertAdjacentHTML('beforeend','<ytm-pivot-bar-renderer><button>Tu</button></ytm-pivot-bar-renderer><button id="page-action">Home del canale</button>');
    await wait();
    assert.equal(w.getComputedStyle(d.querySelector('ytm-pivot-bar-renderer')).display, 'none');
    assert.notEqual(w.getComputedStyle(d.getElementById('page-action')).display, 'none');
  } finally { dom.window.close(); }
});

test('compact bookmark shares the real mobile metadata row with the original menu', async () => {
  const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><div class="thumbnail">Thumbnail</div></a><div class="media-item-details"><div class="media-channel">Avatar</div><div class="media-item-info"><div class="media-item-metadata"><a href="/watch?v=jfKfPfyJRdk"><h3>Video title</h3></a></div><ytm-bottom-sheet-renderer class="media-item-menu"><button aria-label="Menu Azione">Menu</button></ytm-bottom-sheet-renderer></div></div></ytm-video-with-context-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    const card = d.querySelector('ytm-video-with-context-renderer');
    const button = card.querySelector('.iurub-save');
    assert.equal(button.parentElement, card.querySelector('.media-item-info'));
    assert.equal(button.nextElementSibling, card.querySelector('.media-item-menu'));
    assert.equal(card.querySelectorAll(':scope > .iurub-save').length, 0);
    assert.equal(button.getAttribute('aria-label'), '+ Guarda più tardi');
    assert.equal(button.querySelector('svg').getAttribute('aria-hidden'), 'true');
    assert.equal(w.getComputedStyle(button).width, '44px');
    assert.equal(w.getComputedStyle(button).height, '44px');
    assert.equal(w.getComputedStyle(button).margin, '0px');
    assert.equal(card.querySelectorAll('button[aria-label="Menu Azione"]').length, 1);
  } finally { dom.window.close(); }
});

test('compact removal stays in the existing playlist action column instead of below the thumbnail', async () => {
  const html = '<ytm-playlist-video-renderer><div class="YtmCompactMediaItemHost"><a href="/watch?v=jfKfPfyJRdk"><div>Thumbnail</div></a><div><h3>Video title</h3></div><ytm-bottom-sheet-renderer class="YtmCompactMediaItemMenu"><button aria-label="Menu Azione">Menu</button></ytm-bottom-sheet-renderer></div></ytm-playlist-video-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const card = d.querySelector('ytm-playlist-video-renderer');
    const button = card.querySelector('.iurub-remove');
    assert.equal(button.parentElement, card.querySelector('.YtmCompactMediaItemMenu'));
    assert.equal(card.querySelectorAll(':scope > .iurub-remove').length, 0);
    assert.equal(w.getComputedStyle(button).height, '44px');
    assert.equal(w.getComputedStyle(button).margin, '0px');
    assert.equal(button.getAttribute('aria-label'), 'Rimuovi da Guarda più tardi');
    w.iurub.configure({shortsEnabled:false,savedIDs:[]});
    await wait();
    assert.equal(card.querySelectorAll('.iurub-remove').length, 1);
  } finally { dom.window.close(); }
});

test('only Watch later hides its hero, while preserving rows and restoring other page headers after navigation', async () => {
  const html = '<yt-page-header-renderer><h1>Playlist hero</h1><img alt="Large thumbnail"></yt-page-header-renderer><ytm-playlist-video-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>First video stays</h3></a></ytm-playlist-video-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const hero = d.querySelector('yt-page-header-renderer');
    const row = d.querySelector('ytm-playlist-video-renderer');
    assert.equal(w.getComputedStyle(hero).display, 'none');
    assert.notEqual(w.getComputedStyle(row).display, 'none');
    w.history.pushState({},'', '/playlist?list=another-playlist');
    await wait();
    assert.notEqual(w.getComputedStyle(hero).display, 'none');
    assert.equal(d.querySelectorAll('.iurub-remove').length, 0);
    w.history.pushState({},'', '/watch?v=jfKfPfyJRdk&list=WL');
    await wait();
    assert.notEqual(w.getComputedStyle(hero).display, 'none');
    w.history.pushState({},'', '/playlist?list=WL');
    await wait();
    d.body.insertAdjacentHTML('afterbegin','<yt-page-header-renderer id="new-hero">New hero</yt-page-header-renderer>');
    await wait();
    assert.equal(w.getComputedStyle(d.getElementById('new-hero')).display, 'none');
    assert.notEqual(w.getComputedStyle(row).display, 'none');
  } finally { dom.window.close(); }
});


test('icon controls work when Trusted Types forbids innerHTML assignments', async () => {
  const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a></ytm-video-with-context-renderer>';
  const { dom, d } = await setup(html, 'https://m.youtube.com/', {}, w => {
    const original = Object.getOwnPropertyDescriptor(w.Element.prototype, 'innerHTML');
    Object.defineProperty(w.Element.prototype, 'innerHTML', {set(value) {
      if (this.tagName === 'BUTTON') throw new TypeError('TrustedHTML required');
      original.set.call(this, value);
    }});
  });
  try {
    const button = d.querySelector('.iurub-save');
    assert.equal(button.getAttribute('aria-label'), '+ Guarda più tardi');
    assert.equal(button.querySelectorAll('svg path').length, 1);
  } finally { dom.window.close(); }
});


test('authenticated Watch later v2 hero is hidden while toolbar and every playlist row remain', async () => {
  const html = '<ytm-mobile-topbar-renderer><button>Indietro</button></ytm-mobile-topbar-renderer><ytm-playlist-header-renderer-v2><div class="playlist-immersive-header-container"><div class="playlist-immersive-header-content"><ytm-hero-playlist-thumbnail-renderer><img alt="Hero thumbnail"></ytm-hero-playlist-thumbnail-renderer><h1 class="amsterdam-playlist-title-wrapper">Guarda più tardi</h1><a href="/watch?v=jfKfPfyJRdk&list=WL">Riproduci tutto</a></div></div></ytm-playlist-header-renderer-v2><ytm-playlist-video-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>First video stays</h3></a></ytm-playlist-video-renderer><ytm-playlist-video-renderer><a href="/watch?v=M7lc1UVf-VE"><h3>Second video stays</h3></a></ytm-playlist-video-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const hero = d.querySelector('ytm-playlist-header-renderer-v2');
    assert.equal(w.getComputedStyle(hero).display, 'none');
    assert.notEqual(w.getComputedStyle(d.querySelector('ytm-mobile-topbar-renderer')).display, 'none');
    for (const row of d.querySelectorAll('ytm-playlist-video-renderer')) {
      assert.notEqual(w.getComputedStyle(row).display, 'none');
      assert.ok(row.querySelector('.iurub-remove'));
    }
    w.history.pushState({},'', '/playlist?list=another-playlist');
    await wait();
    assert.notEqual(w.getComputedStyle(hero).display, 'none');
  } finally { dom.window.close(); }
});


test('Watch later restores readable toolbar title and themed icons after removing the immersive hero', async () => {
  const html = '<style>.topbar-transparent-background .mobile-topbar-title { opacity:0; visibility:hidden; display:none; } .topbar-transparent-background button {color:white}</style><ytm-mobile-topbar-renderer class="topbar-transparent-background"><header class="mobile-topbar-header"><h1 class="mobile-topbar-title">Guarda più tardi</h1><button aria-label="Cerca"><c3-icon>Search</c3-icon></button></header></ytm-mobile-topbar-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const title = d.querySelector('.mobile-topbar-title');
    assert.equal(w.getComputedStyle(title).opacity, '1');
    assert.equal(w.getComputedStyle(title).visibility, 'visible');
    assert.equal(w.getComputedStyle(title).display, 'block');
    const rules = Array.from(d.getElementById('iurub-style').sheet.cssRules);
    const iconRule = rules.find(r => r.selectorText?.includes('ytm-mobile-topbar-renderer c3-icon'));
    assert.match(iconRule.style.color, /--yt-spec-text-primary/);
    assert.equal(iconRule.style.getPropertyPriority('color'), 'important');
    w.history.pushState({},'', '/playlist?list=another-playlist');
    await wait();
    assert.equal(w.getComputedStyle(title).opacity, '0', 'other immersive playlists keep their native toolbar');
  } finally { dom.window.close(); }
});

async function playbackSetup(config = {}, stateOverrides = {}) {
  const html = '<title>Video in riproduzione - YouTube</title><div id="movie_player" class="html5-video-player"><video class="html5-main-video"></video></div>';
  return setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {trackPlayback:true, ...config}, w => {
    const media = w.document.querySelector('video');
    const state = w.playbackState = {position:0, duration:300, readyState:4, seeking:false, ended:false, autoConfirm:true, seeks:0, pauses:0, ...stateOverrides};
    for (const key of ['duration','readyState','seeking','ended']) Object.defineProperty(media, key, {get:()=>state[key]});
    Object.defineProperty(media, 'currentTime', {get:()=>state.position, set:position=>{
      state.position = position; state.seeks++;
      if (state.autoConfirm) media.dispatchEvent(new w.Event('seeked'));
      else state.seeking = true;
    }});
    media.pause = () => { state.pauses++; media.dispatchEvent(new w.Event('pause')); };
    w.Date.now = () => state.now ?? 10000;
  });
}
const playbackMessages = messages => messages.filter(message => message.type === 'playback');

test('browse capture routes a video with metadata and timestamp without entering the web player', async () => {
  const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk&t=1m42s"><h3>Un video utile</h3></a><div class="byline">Il canale</div></ytm-video-with-context-renderer>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/', {routeVideoOpens:true});
  try {
    let siteClicks = 0;
    d.querySelector('a').onclick = () => siteClicks++;
    const click = new w.MouseEvent('click', {bubbles:true,cancelable:true});
    d.querySelector('h3').dispatchEvent(click);
    assert.equal(click.defaultPrevented, true);
    assert.equal(siteClicks, 0);
    assert.equal(w.location.pathname, '/');
    const opened = messages.find(message=>message.type==='openVideo');
    assert.equal(opened.video.id, 'jfKfPfyJRdk');
    assert.equal(opened.video.title, 'Un video utile');
    assert.equal(opened.video.channel, 'Il canale');
    assert.equal(opened.startSeconds, 102);
    messages.length = 0;
    d.querySelector('.iurub-save').click();
    assert.ok(messages.some(message=>message.type==='save'));
    assert.equal(messages.some(message=>message.type==='openVideo'), false);
  } finally { dom.window.close(); }
});

test('browse routing preserves account actions and Shorts preference, and handles SPA fallback', async () => {
  const { dom, d, w, messages } = await setup('<a id="account" href="/feed/library">Account</a><a id="short" href="/shorts/aqz-KE-bpKQ">Short</a><button id="action">Menu</button>', 'https://m.youtube.com/', {routeVideoOpens:true});
  try {
    d.getElementById('action').click();
    assert.equal(messages.some(message=>message.type==='openVideo'), false);
    w.history.pushState({}, '', '/feed/library');
    assert.equal(w.location.pathname, '/feed/library');
    const shortClick = new w.MouseEvent('click', {bubbles:true,cancelable:true});
    d.getElementById('short').dispatchEvent(shortClick);
    assert.equal(shortClick.defaultPrevented, true);
    assert.ok(messages.some(message=>message.type==='blockedShort'));
    assert.equal(messages.some(message=>message.type==='openVideo'), false);
    w.history.pushState({}, '', '/watch?v=M7lc1UVf-VE&start=42');
    assert.equal(w.location.pathname, '/feed/library');
    assert.equal(messages.filter(message=>message.type==='openVideo').at(-1).startSeconds, 42);
    w.iurub.configure({shortsEnabled:true});
    d.getElementById('short').dispatchEvent(new w.MouseEvent('click', {bubbles:true,cancelable:true}));
    assert.equal(messages.filter(message=>message.type==='openVideo').at(-1).video.id, 'aqz-KE-bpKQ');
    w.history.replaceState({}, '', '/watch?v=jfKfPfyJRdk&t=oops');
    assert.equal(messages.filter(message=>message.type==='openVideo').at(-1).startSeconds, undefined);
    w.iurub.configure({routeVideoOpens:false});
    w.history.pushState({}, '', '/watch?v=M7lc1UVf-VE');
    assert.equal(w.location.search, '?v=M7lc1UVf-VE');
  } finally { dom.window.close(); }
});

test('playback progress is throttled but pause, background and completion flush immediately', async () => {
  const { dom, d, w, messages } = await playbackSetup();
  try {
    const media = d.querySelector('video'), state = w.playbackState;
    assert.equal(playbackMessages(messages).length, 1);
    state.position = 12; state.now = 11000;
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(playbackMessages(messages).length, 1);
    state.now = 15000;
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(playbackMessages(messages).at(-1).position, 12);
    state.position = 42; state.now = 15001;
    w.iurub.pause();
    assert.equal(playbackMessages(messages).at(-1).position, 42);
    assert.equal(state.pauses, 1);
    state.position = 43;
    w.dispatchEvent(new w.Event('pagehide'));
    assert.equal(playbackMessages(messages).at(-1).position, 43);
    state.position = 44;
    Object.defineProperty(d, 'visibilityState', {get:()=> 'hidden'});
    d.dispatchEvent(new w.Event('visibilitychange'));
    assert.equal(playbackMessages(messages).at(-1).position, 44);
    state.position = 300; state.ended = true;
    media.dispatchEvent(new w.Event('ended'));
    assert.equal(playbackMessages(messages).at(-1).ended, true);
    assert.equal(playbackMessages(messages).at(-1).duration, 300);
  } finally { dom.window.close(); }
});

test('progress ignores ads, live video, invalid duration and media that is not ready', async () => {
  const { dom, d, w, messages } = await playbackSetup({}, {readyState:0});
  try {
    const media = d.querySelector('video'), player = d.getElementById('movie_player'), state = w.playbackState;
    assert.equal(w.iurub.playbackSnapshot(), null);
    assert.equal(playbackMessages(messages).length, 0);
    state.readyState = 4;
    for (const duration of [NaN, Infinity, 0]) {
      state.duration = duration;
      assert.equal(w.iurub.playbackSnapshot(), null);
    }
    state.duration = 300; state.position = 20;
    for (const className of ['ad-showing', 'ad-interrupting', 'ytp-live']) {
      player.classList.add(className);
      media.dispatchEvent(new w.Event('pause'));
      assert.equal(w.iurub.playbackSnapshot(), null);
      assert.equal(playbackMessages(messages).length, 0);
      player.classList.remove(className);
    }
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(playbackMessages(messages).at(-1).position, 20);
    w.iurub.configure({trackPlayback:false});
    assert.equal(w.iurub.playbackSnapshot(), null);
  } finally { dom.window.close(); }
});

test('resume blocks zero/stale progress until seek confirmation and routine configuration does not re-seek', async () => {
  const resume = {id:'jfKfPfyJRdk',position:42};
  const { dom, d, w, messages } = await playbackSetup({resume}, {autoConfirm:false});
  try {
    const media = d.querySelector('video'), state = w.playbackState;
    assert.equal(state.position, 42);
    assert.equal(state.seeks, 1);
    assert.equal(w.iurub.playbackSnapshot(), null);
    assert.equal(playbackMessages(messages).length, 0);
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(playbackMessages(messages).length, 0);
    state.seeking = false;
    media.dispatchEvent(new w.Event('seeked'));
    assert.equal(playbackMessages(messages).at(-1).position, 42);
    state.position = 67;
    w.iurub.configure({resume, shortsEnabled:false, savedIDs:[]});
    assert.equal(state.seeks, 1);
    assert.equal(w.iurub.playbackSnapshot().position, 67);
    assert.equal(w.iurub.restorePlayback({id:'bad',position:30}), false);
    assert.equal(w.iurub.restorePlayback({id:'jfKfPfyJRdk',position:NaN}), false);
    assert.equal(w.iurub.restorePlayback({id:'jfKfPfyJRdk',position:-1}), false);
  } finally { dom.window.close(); }
});

test('resume waits for content after an advertisement and never seeks an unrelated video', async () => {
  const { dom, d, w, messages } = await playbackSetup({}, {readyState:0});
  try {
    const media = d.querySelector('video'), player = d.getElementById('movie_player'), state = w.playbackState;
    player.classList.add('ad-showing');
    state.readyState = 4;
    w.iurub.restorePlayback({id:'jfKfPfyJRdk',position:42});
    media.dispatchEvent(new w.Event('loadedmetadata'));
    assert.equal(state.seeks, 0);
    assert.equal(playbackMessages(messages).length, 0);
    player.classList.remove('ad-showing');
    media.dispatchEvent(new w.Event('canplay'));
    assert.equal(state.position, 42);
    assert.equal(w.iurub.playbackSnapshot().position, 42);
    w.iurub.restorePlayback({id:'M7lc1UVf-VE',position:99});
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(state.position, 42);
    assert.equal(w.iurub.playbackSnapshot(), null);
  } finally { dom.window.close(); }
});

test('a player SPA transition cannot attach the old video time to the new video ID', async () => {
  const { dom, d, w, messages } = await playbackSetup({}, {position:73});
  try {
    const media = d.querySelector('video'), state = w.playbackState;
    w.history.pushState({}, '', '/watch?v=M7lc1UVf-VE');
    assert.equal(w.iurub.playbackSnapshot(), null);
    media.dispatchEvent(new w.Event('timeupdate'));
    assert.equal(playbackMessages(messages).some(message=>message.id==='M7lc1UVf-VE'), false);
    state.position = 9;
    media.dispatchEvent(new w.Event('loadedmetadata'));
    assert.equal(w.iurub.playbackSnapshot().id, 'M7lc1UVf-VE');
    assert.equal(w.iurub.playbackSnapshot().position, 9);
  } finally { dom.window.close(); }
});

test('deterministic playback fixture restores, advances and completes using public media events', async () => {
  const html = fs.readFileSync('iurub/Resources/PlaybackFixture.html', 'utf8');
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {trackPlayback:true,resume:{id:'jfKfPfyJRdk',position:21}});
  try {
    assert.equal(d.getElementById('position').textContent, 'Posizione: 21 s');
    assert.equal(w.iurub.playbackSnapshot().position, 21);
    d.getElementById('advance').click();
    assert.equal(d.getElementById('position').textContent, 'Posizione: 42 s');
    assert.equal(playbackMessages(messages).at(-1).position, 42);
    d.getElementById('finish').click();
    assert.equal(playbackMessages(messages).at(-1).ended, true);
    assert.equal(playbackMessages(messages).at(-1).position, 300);
    assert.equal(d.querySelector('video').getAttribute('src'), null);
  } finally { dom.window.close(); }
});


test('a seek finishing while paused persists its final position inside the throttle window', async () => {
  const { dom, d, w, messages } = await playbackSetup();
  try {
    const media = d.querySelector('video'), state = w.playbackState;
    state.position = 81; state.now = 10050; state.seeking = true;
    media.dispatchEvent(new w.Event('pause'));
    assert.equal(playbackMessages(messages).at(-1).position, 0);
    state.seeking = false;
    media.dispatchEvent(new w.Event('seeked'));
    assert.equal(playbackMessages(messages).at(-1).position, 81);
  } finally { dom.window.close(); }
});


test('playback snapshots retain their initial document generation when native configuration changes', async () => {
  const { dom, d, w, messages } = await playbackSetup({playbackSession:'document-generation-one'}, {position:42});
  try {
    assert.equal(w.iurub.playbackSnapshot().session, 'document-generation-one');
    assert.equal(playbackMessages(messages).at(-1).session, 'document-generation-one');
    w.iurub.configure({playbackSession:'document-generation-two',trackPlayback:true});
    w.playbackState.position = 81;
    d.querySelector('video').dispatchEvent(new w.Event('pause'));
    assert.equal(w.iurub.playbackSnapshot().session, 'document-generation-one');
    assert.equal(playbackMessages(messages).at(-1).session, 'document-generation-one');
  } finally { dom.window.close(); }
});


test('history adoption validates the current video, restores once and preserves its new generation against ordinary configuration', async () => {
  const { dom, d, w, messages } = await playbackSetup({playbackSession:'original-document'}, {position:12});
  try {
    const adoption = {id:'jfKfPfyJRdk',position:42,session:'restored-document'};
    for (const invalid of [
      {...adoption,id:'M7lc1UVf-VE'}, {...adoption,id:'bad'},
      {...adoption,session:''}, {...adoption,session:'   '}, {...adoption,session:42},
      {...adoption,position:-1}, {...adoption,position:NaN}
    ]) assert.equal(w.iurub.adoptPlayback(invalid), false);
    assert.equal(w.iurub.playbackSnapshot().session, 'original-document');
    assert.equal(w.playbackState.position, 12);
    assert.equal(w.playbackState.seeks, 0);
    assert.equal(w.iurub.adoptPlayback(adoption), true);
    assert.equal(w.iurub.playbackSnapshot().session, 'restored-document');
    assert.equal(playbackMessages(messages).at(-1).session, 'restored-document');
    assert.equal(w.playbackState.position, 42);
    assert.equal(w.playbackState.seeks, 1);
    w.playbackState.position = 48;
    assert.equal(w.iurub.adoptPlayback(adoption), true);
    assert.equal(w.iurub.adoptPlayback({...adoption,position:43}), true);
    assert.equal(w.playbackState.position, 48);
    assert.equal(w.playbackState.seeks, 1);
    w.iurub.configure({playbackSession:'original-document'});
    d.querySelector('video').dispatchEvent(new w.Event('pause'));
    assert.equal(playbackMessages(messages).at(-1).session, 'restored-document');
    assert.equal(w.iurub.adoptPlayback({...adoption,position:48,session:'already-at-target'}), true);
    assert.equal(w.playbackState.seeks, 1);
    assert.equal(playbackMessages(messages).at(-1).session, 'already-at-target');
    w.iurub.configure({trackPlayback:false});
    assert.equal(w.iurub.adoptPlayback({...adoption,session:'browse-document'}), false);
  } finally { dom.window.close(); }
});

test('history adoption suppresses progress until the restored seek is confirmed', async () => {
  const { dom, d, w, messages } = await playbackSetup({playbackSession:'old-generation'}, {position:95,autoConfirm:false});
  try {
    assert.equal(w.iurub.adoptPlayback({id:'jfKfPfyJRdk',position:8,session:'back-generation'}), true);
    assert.equal(w.iurub.playbackSnapshot(), null);
    assert.equal(w.playbackState.seeks, 1);
    assert.equal(w.iurub.adoptPlayback({id:'jfKfPfyJRdk',position:8,session:'back-generation'}), true);
    assert.equal(w.playbackState.seeks, 1);
    assert.equal(playbackMessages(messages).at(-1).session, 'old-generation');
    w.playbackState.seeking = false;
    d.querySelector('video').dispatchEvent(new w.Event('seeked'));
    assert.equal(w.iurub.playbackSnapshot().position, 8);
    assert.equal(playbackMessages(messages).at(-1).session, 'back-generation');
  } finally { dom.window.close(); }
});
