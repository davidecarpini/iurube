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
    assert.equal(d.querySelector('.iurub-save').dataset.saved, 'true', 'confirmed YouTube save fills the bookmark');
  } finally { dom.window.close(); }
});

test('both the original Watch Later notice and a recycled error remain visible', async () => {
  const {dom,d,w,messages} = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    d.querySelector('.iurub-save').click();
    await wait(300);
    const toast = d.querySelector('.fixture-native-notice');
    assert.notEqual(w.getComputedStyle(toast).display, 'none');
    assert.equal(messages.filter(m => m.type === 'youtubeSaveResult' && m.status === 'saved').length, 1);
    toast.textContent = 'Errore di connessione';
    await wait();
    assert.notEqual(w.getComputedStyle(toast).display, 'none');
  } finally { dom.window.close(); }
});

test('a manual YouTube action shares only the confirmed Watch Later state with iurub', async () => {
  const html='<button id="action">Salva in una playlist</button>';
  const {dom,d,w,messages}=await setup(html,'https://m.youtube.com/watch?v=jfKfPfyJRdk',{saveDestination:'youtube'});
  try {
    d.getElementById('action').click();
    const notice=d.createElement('div'); notice.setAttribute('role','status'); notice.textContent='Salvato in Preferiti'; d.body.append(notice);
    await wait();
    assert.notEqual(w.getComputedStyle(notice).display,'none');
    assert.equal(messages.filter(m=>m.type==='youtubeSaveResult').length,0);
    notice.textContent='Salvato in Guarda più tardi';
    await wait();
    assert.notEqual(w.getComputedStyle(notice).display,'none');
    const changes=messages.filter(m=>m.type==='youtubeSaveResult');
    assert.equal(changes.length,1); assert.equal(changes[0].video.id,'jfKfPfyJRdk'); assert.equal(changes[0].saved,true);
  } finally {dom.window.close();}
});

test('a late thumbnail message without a role confirms the tapped card once and remains visible', async () => {
  const html='<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a><button id="menu" aria-label="Menu Azione">Menu</button></ytm-video-with-context-renderer>';
  const {dom,d,w,messages}=await setup(html,'https://m.youtube.com/',{saveDestination:'youtube'});
  try {
    d.getElementById('menu').onclick=()=>{
      d.body.insertAdjacentHTML('beforeend','<div role="dialog"><button id="action">Salva in Guarda più tardi</button></div>');
      d.getElementById('action').onclick=()=>d.querySelector('[role="dialog"]').remove();
    };
    const mark=d.querySelector('.iurub-save');
    mark.click();
    await wait(2400);
    assert.equal(mark.dataset.saved,'false');
    d.body.insertAdjacentHTML('beforeend','<a id="photo-notice" href="/playlist?list=WL" aria-hidden="true"><img alt=""><span>Salvato in <b>Guarda più tardi</b></span></a>');
    await wait();
    assert.equal(mark.dataset.saved,'true');
    assert.notEqual(w.getComputedStyle(d.getElementById('photo-notice')).display,'none');
    assert.equal(messages.filter(m=>m.type==='youtubeSaveResult' && m.status==='saved').length,1);
  } finally {dom.window.close();}
});

test('an unknown existing membership is observed without accidentally removing the video', async () => {
  const { dom, d, w, messages } = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube'});
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
        const toast = d.createElement('div'); toast.setAttribute('role','status'); toast.textContent='Rimosso da Guarda più tardi ';
        undo.onclick=()=>{d.body.append(first);toast.remove();}; toast.append(undo); d.body.append(toast);
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
    assert.ok(messages.some(m=>m.type==='youtubeSaveResult' && m.status==='removed' && m.saved===false));
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
    assert.ok(messages.some(m=>m.type==='youtubeSaveResult' && m.status==='manual'));
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
    assert.equal(button.previousElementSibling, card.querySelector('.media-item-menu'));
    assert.equal(card.querySelectorAll(':scope > .iurub-save').length, 0);
    assert.equal(button.getAttribute('aria-label'), '+ Guarda più tardi');
    assert.equal(button.querySelector('svg').getAttribute('aria-hidden'), 'true');
    assert.equal(w.getComputedStyle(button).width, '44px');
    assert.equal(w.getComputedStyle(button).height, '44px');
    assert.equal(w.getComputedStyle(button).margin, '0px');
    assert.equal(card.querySelectorAll('button[aria-label="Menu Azione"]').length, 1);
  } finally { dom.window.close(); }
});

test('compact removal follows the original playlist menu in the same row', async () => {
  const html = '<ytm-playlist-video-renderer><div class="YtmCompactMediaItemHost"><a href="/watch?v=jfKfPfyJRdk"><div>Thumbnail</div></a><div><h3>Video title</h3></div><ytm-bottom-sheet-renderer class="YtmCompactMediaItemMenu"><button aria-label="Menu Azione">Menu</button></ytm-bottom-sheet-renderer></div></ytm-playlist-video-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    const card = d.querySelector('ytm-playlist-video-renderer');
    const button = card.querySelector('.iurub-remove');
    assert.equal(button.previousElementSibling, card.querySelector('.YtmCompactMediaItemMenu'));
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

test('Finestra starts a paused video once, waits for frames, then requests system PiP once', async () => {
  const {dom,d,w} = await playbackSetup({}, {readyState:0});
  try {
    const media=d.querySelector('video'), id='jfKfPfyJRdk';
    let paused=true, plays=0, presentations=0;
    Object.defineProperty(media,'paused',{get:()=>paused});
    media.play=async()=>{plays++; paused=false;};
    media.webkitSupportsPresentationMode=()=>true;
    media.webkitSetPresentationMode=mode=>{assert.equal(mode,'picture-in-picture'); presentations++;};
    assert.equal(w.iurub.manualPiP('M7lc1UVf-VE','tap'),'pending');
    assert.equal(plays,0);
    assert.equal(w.iurub.manualPiP(id,'tap'),'pending');
    assert.equal(w.iurub.manualPiP(id,'tap'),'pending');
    w.playbackState.readyState=3;
    assert.equal(w.iurub.manualPiP(id,'tap'),'requested');
    assert.equal(w.iurub.manualPiP(id,'tap'),'requested');
    assert.equal(plays,1);
    assert.equal(presentations,1);
  } finally { dom.window.close(); }
});

test('Finestra activates the YouTube poster before a video exists and respects unavailable system PiP', async () => {
  const {dom,d,w} = await playbackSetup();
  try {
    const media=d.querySelector('video'), player=d.querySelector('#movie_player'), id='jfKfPfyJRdk';
    media.remove();
    let activations=0, paused=true;
    player.playVideo=()=>{activations++;};
    assert.equal(w.iurub.manualPiP(id,'tap'),'pending');
    assert.equal(w.iurub.manualPiP(id,'tap'),'pending');
    player.append(media);
    Object.defineProperty(media,'paused',{get:()=>paused});
    media.play=async()=>{paused=false;};
    media.disablePictureInPicture=true;
    assert.equal(w.iurub.manualPiP(id,'tap'),'inline');
    assert.equal(activations,1);
    assert.equal(paused,false);
  } finally { dom.window.close(); }
});

test('hidden player keeps only the detached media playing and resumes normal pause on exit', async () => {
  const {dom,d,w,messages} = await playbackSetup();
  try {
    const video = d.querySelector('video'), id = 'jfKfPfyJRdk';
    const extra = d.createElement('audio'); let otherPauses = 0;
    extra.pause = () => otherPauses++; d.body.append(extra);
    Object.defineProperty(video, 'paused', {value:false});
    let request;
    video.webkitPresentationMode = 'inline';
    video.webkitSupportsPresentationMode = () => true;
    video.webkitSetPresentationMode = mode => { request = mode; };
    assert.equal(w.iurub.togglePiP(id), 'requested');
    assert.equal(request, 'picture-in-picture');
    w.iurub.pauseWhenHidden();
    assert.equal(w.playbackState.pauses, 0, 'Home pressed during PiP transition');
    video.webkitPresentationMode = request;
    video.dispatchEvent(new w.Event('webkitpresentationmodechanged'));
    assert.equal(messages.filter(m => m.type === 'mediaControls').at(-1).detached, true);
    w.iurub.pauseWhenHidden();
    assert.equal(w.playbackState.pauses, 0);
    assert.equal(otherPauses, 2);
    assert.equal(w.iurub.togglePiP(id), 'requested');
    video.webkitPresentationMode = request;
    video.dispatchEvent(new w.Event('webkitpresentationmodechanged'));
    w.iurub.pauseWhenHidden();
    assert.equal(w.playbackState.pauses, 1);
    assert.equal(otherPauses, 3);
  } finally { dom.window.close(); }
});

test('leaving the app requests PiP only for the playing video and leaves background audio alone', async () => {
  const {dom,d,w,messages} = await playbackSetup();
  try {
    const video=d.querySelector('video'), id='jfKfPfyJRdk';
    let paused=true, requests=0;
    Object.defineProperty(video, 'paused', {get:()=>paused});
    video.webkitSupportsPresentationMode = () => true;
    video.webkitSetPresentationMode = () => { requests++; };
    w.iurub.enterBackground(id);
    paused=false;
    w.iurub.enterBackground('M7lc1UVf-VE');
    assert.equal(requests, 0);
    video.disablePictureInPicture=true;
    w.iurub.enterBackground(id);
    assert.equal(requests, 0);
    video.disablePictureInPicture=false;
    w.iurub.enterBackground(id);
    w.iurub.enterBackground(id);
    assert.equal(requests, 1);
    assert.equal(w.playbackState.pauses, 0);
    assert.equal(messages.some(m=>m.type==='pipFailed'),false);
  } finally {dom.window.close();}
});

test('a lifecycle pause during handoff resumes only inside the confirmed system window', async () => {
  const {dom,d,w}=await playbackSetup();
  try {
    const media=d.querySelector('video'), id='jfKfPfyJRdk';
    let mode='inline', requests=0, resumes=0;
    Object.defineProperty(media,'paused',{value:true});
    Object.defineProperty(media,'webkitPresentationMode',{get:()=>mode});
    media.webkitSupportsPresentationMode=()=>true;
    media.webkitSetPresentationMode=()=>{requests++;};
    media.play=async()=>{resumes++;};
    w.iurub.enterBackground(id,false);
    assert.equal(requests,0);
    w.iurub.enterBackground(id,true);
    assert.equal(requests,1); assert.equal(resumes,0);
    mode='picture-in-picture';
    media.dispatchEvent(new w.Event('webkitpresentationmodechanged'));
    media.dispatchEvent(new w.Event('enterpictureinpicture'));
    w.iurub.enterBackground(id,true);
    assert.equal(resumes,1); assert.equal(requests,1);
  } finally {dom.window.close();}
});

test('an already floating window resumes at most once on a system-induced Home transition', async () => {
  const {dom,d,w}=await playbackSetup();
  try {
    const media=d.querySelector('video'), id='jfKfPfyJRdk';
    let paused=false, hidden=false, resumes=0, mode='picture-in-picture';
    Object.defineProperty(media,'paused',{get:()=>paused});
    Object.defineProperty(media,'webkitPresentationMode',{get:()=>mode});
    Object.defineProperty(d,'visibilityState',{get:()=>hidden?'hidden':'visible'});
    media.play=async()=>{resumes++;};
    w.iurub.enterBackground(id,true,true);
    paused=true; hidden=true;
    d.dispatchEvent(new w.Event('visibilitychange'));
    media.dispatchEvent(new w.Event('pause'));
    assert.equal(resumes,1);
    w.iurub.foreground();
    w.iurub.enterBackground(id,false,true);
    assert.equal(resumes,1,'a user-paused video must stay paused');
  } finally {dom.window.close();}
});

test('media controls respect site restrictions, the current video, and changes from the site player', async () => {
  const {dom,d,w,messages} = await playbackSetup();
  try {
    const video = d.querySelector('video'), id = 'jfKfPfyJRdk';
    video.disablePictureInPicture = true;
    assert.equal(w.iurub.togglePiP(id), 'unavailable');
    assert.equal(w.iurub.stepSpeed('M7lc1UVf-VE', 1), false);
    video.playbackRate = 1.4;
    video.dispatchEvent(new w.Event('ratechange'));
    assert.equal(messages.filter(m => m.type === 'mediaControls').at(-1).rate, 1.4);
    assert.equal(w.iurub.stepSpeed(id, -1), true);
    assert.equal(video.playbackRate, 1.25);
    w.playbackState.readyState = 0;
    assert.equal(w.iurub.togglePiP(id), 'notReady');
    assert.equal(w.iurub.stepSpeed(id, 1), false);
  } finally { dom.window.close(); }
});

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

const membershipMessages = messages => messages.filter(message => message.type === 'youtubeMembership');

test('filled account bookmark toggles removal through YouTube and confirmed Undo restores it', async () => {
  const { dom, d, w, messages } = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube',savedIDs:['jfKfPfyJRdk']});
  try {
    w.fixtureAccountIDs = ['jfKfPfyJRdk'];
    const bookmark = d.querySelector('.iurub-save');
    assert.equal(bookmark.getAttribute('aria-pressed'), 'true');
    assert.equal(bookmark.getAttribute('aria-label'), 'Rimuovi da Guarda più tardi');
    bookmark.click(); await wait(400);
    assert.equal(w.fixtureAccountIDs.includes('jfKfPfyJRdk'), false);
    assert.equal(bookmark.dataset.saved, 'false');
    const removed = messages.find(message=>message.type==='youtubeSaveResult' && message.status==='removed');
    assert.equal(removed.saved, false);
    assert.equal(removed.video.id, 'jfKfPfyJRdk');
    assert.equal(membershipMessages(messages).at(-1).saved, false);
    d.querySelector('.fixture-native-notice button').click(); await wait(400);
    assert.equal(w.fixtureAccountIDs.includes('jfKfPfyJRdk'), true);
    assert.equal(bookmark.dataset.saved, 'true');
    assert.equal(membershipMessages(messages).at(-1).saved, true);
    assert.equal(messages.some(message=>message.type==='save'), false);
  } finally { dom.window.close(); }
});

test('confirmed native player toggle includes video identity and never updates the device library', async () => {
  const html = fs.readFileSync('iurub/Resources/PlaybackFixture.html','utf8');
  const { dom, w, messages } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {saveDestination:'youtube'});
  try {
    w.iurub.toggleCurrentToYouTube(); await wait(400);
    assert.equal(w.fixtureAccountIDs.includes('jfKfPfyJRdk'), true);
    let result = messages.filter(message=>message.type==='youtubeSaveResult').at(-1);
    assert.equal(result.status, 'saved'); assert.equal(result.saved, true);
    assert.equal(result.video.id, 'jfKfPfyJRdk');
    w.iurub.toggleCurrentToYouTube(); await wait(400);
    result = messages.filter(message=>message.type==='youtubeSaveResult').at(-1);
    assert.equal(result.status, 'removed'); assert.equal(result.saved, false);
    assert.equal(w.fixtureAccountIDs.includes('jfKfPfyJRdk'), false);
    assert.equal(messages.some(message=>message.type==='save'), false);
  } finally { dom.window.close(); }
});

test('removal unchecks only Watch later and leaves other selected playlists intact', async () => {
  const html = '<button id="save" aria-label="Save to playlist">Save</button>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {saveDestination:'youtube',savedIDs:['jfKfPfyJRdk']});
  try {
    d.getElementById('save').onclick = () => {
      d.body.insertAdjacentHTML('beforeend','<div role="dialog"><label><input id="later" type="checkbox" checked>Watch later</label><label><input id="other" type="checkbox" checked>Other playlist</label></div>');
    };
    w.iurub.toggleCurrentToYouTube(); await wait(500);
    assert.equal(d.getElementById('later').checked, false);
    assert.equal(d.getElementById('other').checked, true);
    const result = messages.filter(message=>message.type==='youtubeSaveResult').at(-1);
    assert.equal(result.status, 'removed'); assert.equal(result.saved, false);
  } finally { dom.window.close(); }
});

test('an add-only shortcut cannot confirm removal of a saved video', async () => {
  const html='<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a><button id="menu" aria-label="Menu Azione">Menu</button></ytm-video-with-context-renderer>';
  const {dom,d,messages}=await setup(html,'https://m.youtube.com/',{saveDestination:'youtube',savedIDs:['jfKfPfyJRdk']});
  try {
    let unchecked=false;
    d.getElementById('menu').onclick=()=>{
      d.body.insertAdjacentHTML('beforeend','<div role="menu"><button>Salva in Guarda più tardi</button><button id="lists">Salva in una playlist</button></div>');
      d.getElementById('lists').onclick=()=>{
        d.querySelector('[role="menu"]').remove();
        d.body.insertAdjacentHTML('beforeend','<div role="dialog"><label><input id="wl" type="checkbox" checked>Guarda più tardi</label></div>');
        d.getElementById('wl').onclick=e=>{unchecked=!e.target.checked;};
      };
    };
    const bookmark=d.querySelector('.iurub-save');
    bookmark.click(); await wait(600);
    assert.equal(unchecked,true);
    assert.equal(bookmark.dataset.saved,'false');
    assert.equal(messages.filter(m=>m.type==='youtubeSaveResult').at(-1).status,'removed');
  } finally {dom.window.close();}
});

test('a failed checkbox save never publishes saved=true or fills the bookmark', async () => {
  const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a><button id="menu" aria-label="Menu Azione">Menu</button></ytm-video-with-context-renderer>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    d.getElementById('menu').onclick = () => {
      d.body.insertAdjacentHTML('beforeend','<div role="dialog"><label><input id="later" type="checkbox">Watch later</label></div>');
      d.getElementById('later').onclick = () => w.setTimeout(()=> d.body.insertAdjacentHTML('beforeend','<div role="alert">Errore: impossibile salvare in Guarda più tardi</div>'),50);
    };
    d.querySelector('.iurub-save').click(); await wait(400);
    const result = messages.filter(message=>message.type==='youtubeSaveResult').at(-1);
    assert.equal(result.status, 'failed'); assert.equal(result.saved, undefined);
    assert.equal(membershipMessages(messages).some(message=>message.saved), false);
    assert.equal(d.querySelector('.iurub-save').dataset.saved, 'false');
  } finally { dom.window.close(); }
});

test('unconfirmed action and unrelated playlist toast cannot masquerade as a saved Watch later video', async () => {
  const html = '<ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Video</h3></a><button id="menu" aria-label="Menu Azione">Menu</button></ytm-video-with-context-renderer>';
  const { dom, d, messages } = await setup(html, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    d.getElementById('menu').onclick = () => {
      d.body.insertAdjacentHTML('beforeend','<div role="dialog"><button id="action">Salva in Guarda più tardi</button></div>');
      d.getElementById('action').onclick = () => {
        d.querySelector('[role="dialog"]').remove();
        d.body.insertAdjacentHTML('beforeend','<div role="status">Added to Other playlist</div>');
      };
    };
    d.querySelector('.iurub-save').click(); await wait(2400);
    const result = messages.filter(message=>message.type==='youtubeSaveResult').at(-1);
    assert.equal(result.status, 'submitted'); assert.equal(result.saved, undefined);
    assert.equal(membershipMessages(messages).some(message=>message.saved), false);
    assert.equal(d.querySelector('.iurub-save').dataset.saved, 'false');
  } finally { dom.window.close(); }
});

test('stale Watch later cards do not override shared removals, while reinserted Undo cards can confirm membership', async () => {
  const html = '<ytm-playlist-video-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Saved video</h3></a></ytm-playlist-video-renderer>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/playlist?list=WL', {saveDestination:'youtube'});
  try {
    assert.equal(membershipMessages(messages).length, 1);
    assert.equal(membershipMessages(messages)[0].saved, true);
    w.iurub.configure({savedIDs:[],removedIDs:['jfKfPfyJRdk']}); await wait();
    d.body.append(d.createElement('span')); await wait();
    assert.equal(membershipMessages(messages).length, 1, 'configure/scan of stale nodes cannot undo a removal from another tab');
    const row = d.querySelector('ytm-playlist-video-renderer'); row.remove(); d.body.append(row); await wait();
    assert.equal(membershipMessages(messages).length, 2);
    assert.equal(membershipMessages(messages).at(-1).saved, true);
    w.iurub.configure({resetMembership:true,savedIDs:[],removedIDs:[]}); await wait();
    assert.equal(membershipMessages(messages).length, 2, 'account reset does not republish old nodes');
  } finally { dom.window.close(); }
});

test('shared membership fills and clears account icons without treating missing IDs as evidence', async () => {
  const { dom, d, w, messages } = await setup(fixture, 'https://m.youtube.com/', {saveDestination:'youtube'});
  try {
    const bookmark = d.querySelector('.iurub-save');
    w.iurub.configure({savedIDs:['jfKfPfyJRdk']}); await wait();
    assert.equal(bookmark.getAttribute('aria-pressed'), 'true');
    assert.equal(w.getComputedStyle(bookmark.querySelector('svg')).fill, 'currentColor');
    w.iurub.configure({savedIDs:[]}); await wait();
    assert.equal(bookmark.dataset.saved, 'true', 'a partial set does not establish absence');
    w.iurub.configure({removedIDs:['jfKfPfyJRdk']}); await wait();
    assert.equal(bookmark.getAttribute('aria-pressed'), 'false');
    assert.equal(membershipMessages(messages).length, 0, 'incoming configuration is not newly observed evidence');
  } finally { dom.window.close(); }
});

test('watch page hides authenticated recommendations but preserves title, player and modern comments teaser', async () => {
  const html = '<ytm-watch><div id="movie_player"><video></video></div><div class="watch-below-the-player"><ytm-single-column-watch-next-results-renderer><div class="related-chips-slot-wrapper"><ytm-slim-video-metadata-section-renderer><h1>Video title</h1><button>Mi piace</button></ytm-slim-video-metadata-section-renderer><ytm-item-section-renderer id="comments"><lazy-list><yt-comment-teaser-carousel-item-view-model><comments-entry-point-teaser-view-model><button id="expand-comments">Commenti</button></comments-entry-point-teaser-view-model></yt-comment-teaser-carousel-item-view-model></lazy-list></ytm-item-section-renderer></div><ytm-item-section-renderer id="recommendations" class="scwnr-content single-column-watch-next-modern-panels"><ytm-related-chip-cloud-renderer>Tutti</ytm-related-chip-cloud-renderer><div class="related-chips-sentinel"></div><lazy-list><ytm-video-with-context-renderer><a href="/watch?v=M7lc1UVf-VE"><h3>Recommended video</h3></a></ytm-video-with-context-renderer></lazy-list></ytm-item-section-renderer></ytm-single-column-watch-next-results-renderer></div></ytm-watch>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk');
  try {
    assert.equal(w.getComputedStyle(d.getElementById('recommendations')).display, 'none');
    for (const selector of ['#movie_player','ytm-slim-video-metadata-section-renderer','.related-chips-slot-wrapper','#comments','#expand-comments']) assert.notEqual(w.getComputedStyle(d.querySelector(selector)).display, 'none');
    let opened = false; d.getElementById('expand-comments').onclick = () => opened = true;
    d.getElementById('expand-comments').click(); assert.equal(opened, true);
    w.history.pushState({},'', '/'); await wait();
    assert.notEqual(w.getComputedStyle(d.getElementById('recommendations')).display, 'none');
    w.history.pushState({},'', '/watch?v=jfKfPfyJRdk'); await wait();
    d.getElementById('recommendations').insertAdjacentHTML('beforeend','<ytm-video-with-context-renderer id="new-recommendation"><a href="/watch?v=aqz-KE-bpKQ">Dynamic video</a></ytm-video-with-context-renderer>'); await wait();
    assert.equal(w.getComputedStyle(d.getElementById('recommendations')).display, 'none');
    assert.equal(w.getComputedStyle(d.getElementById('new-recommendation')).display, 'none');
  } finally { dom.window.close(); }
});

test('mixed watch sections retain expandable comments and never hide video links inside comment threads', async () => {
  const html = '<ytm-item-section-renderer id="mixed"><ytm-comments-entry-point-header-renderer><button>Commenti</button></ytm-comments-entry-point-header-renderer><ytm-comment-section-renderer id="comment-thread"><ytm-video-with-context-renderer id="comment-reference"><a href="/watch?v=M7lc1UVf-VE">A cited video</a></ytm-video-with-context-renderer></ytm-comment-section-renderer><ytm-video-with-context-renderer id="recommended"><a href="/watch?v=aqz-KE-bpKQ">Suggested</a></ytm-video-with-context-renderer></ytm-item-section-renderer>';
  const { dom, d, w } = await setup(html, 'https://m.youtube.com/watch?v=jfKfPfyJRdk');
  try {
    assert.notEqual(w.getComputedStyle(d.getElementById('mixed')).display, 'none');
    assert.notEqual(w.getComputedStyle(d.getElementById('comment-thread')).display, 'none');
    assert.notEqual(w.getComputedStyle(d.getElementById('comment-reference')).display, 'none');
    assert.equal(w.getComputedStyle(d.getElementById('recommended')).display, 'none');
  } finally { dom.window.close(); }
});


test('official account controls invalidate hints without reading credentials or treating video titles as account actions', async () => {
  const html = '<button id="switch">Cambia account</button><button id="signout" aria-label="Sign out">Exit</button><a id="google" href="https://accounts.google.com/ServiceLogin">Google</a><a id="profile" href="/feed/library">Tu</a><a id="hostile" href="https://accounts.google.com.evil.test/signin">Example</a><ytm-video-with-context-renderer><a href="/watch?v=jfKfPfyJRdk"><h3>Accedi</h3></a></ytm-video-with-context-renderer>';
  const { dom, d, w, messages } = await setup(html, 'https://m.youtube.com/', {saveDestination:'youtube',savedIDs:['jfKfPfyJRdk'],routeVideoOpens:true});
  try {
    // Prevent jsdom navigation after the capture handler; native YouTube owns navigation.
    d.querySelectorAll('a').forEach(anchor=>anchor.addEventListener('click',event=>event.preventDefault()));
    for (const id of ['switch','signout','google','profile']) d.getElementById(id).click();
    assert.equal(messages.filter(message=>message.type==='youtubeAccountContextChanged').length, 4);
    d.getElementById('hostile').click(); d.querySelector('h3').click();
    assert.equal(messages.filter(message=>message.type==='youtubeAccountContextChanged').length, 4);
    w.iurub.configure({resetMembership:true,savedIDs:[],removedIDs:[]}); await wait();
    assert.equal(d.querySelector('.iurub-save').dataset.saved, 'false');
    assert.equal(membershipMessages(messages).length, 0);
    const event = messages.find(message=>message.type==='youtubeAccountContextChanged');
    assert.deepEqual(Object.keys(event), ['type']);
  } finally { dom.window.close(); }
});

test('the player opens comments for each watch video and respects a manual close', async () => {
  const teaser = '<ytm-comments-entry-point-header-renderer><button id="comments">Commenti</button></ytm-comments-entry-point-header-renderer>';
  let opens = 0;
  const { dom, d, w } = await setup(teaser, 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {trackPlayback:true}, win => {
    win.document.getElementById('comments').onclick = () => {
      opens++;
      win.document.body.insertAdjacentHTML('beforeend', '<ytm-engagement-panel><ytm-engagement-panel-section-list-renderer class="engagement-panel-comments-section"><ytm-comment-thread-renderer>First</ytm-comment-thread-renderer><ytm-comment-thread-renderer>Second</ytm-comment-thread-renderer></ytm-engagement-panel-section-list-renderer></ytm-engagement-panel>');
    };
  });
  try {
    assert.equal(opens, 1);
    assert.equal(d.querySelectorAll('ytm-comment-thread-renderer').length, 2);
    assert.ok(d.documentElement.classList.contains('iurub-inline-comments'));
    d.querySelector('ytm-engagement-panel').remove();
    w.iurub.configure({trackPlayback:true});
    await wait(1650);
    assert.equal(opens, 1);
    assert.ok(!d.documentElement.classList.contains('iurub-inline-comments'));
    w.history.pushState({}, '', '/watch?v=aqz-KE-bpKQ');
    await wait();
    assert.equal(opens, 2);
    assert.ok(d.documentElement.classList.contains('iurub-inline-comments'));
  } finally { dom.window.close(); }
});

test('a delayed comments entry opens without selecting adjacent carousel actions', async () => {
  const {dom, d} = await setup('<main></main>', 'https://m.youtube.com/watch?v=jfKfPfyJRdk', {trackPlayback:true});
  try {
    const clicks = [];
    d.querySelector('main').innerHTML = '<yt-video-metadata-carousel-view-model><button>Capitoli</button><button aria-label="Commenti">Commenti</button><yt-carousel-item-view-model><comments-entry-point-teaser-view-model>Una preview</comments-entry-point-teaser-view-model></yt-carousel-item-view-model></yt-video-metadata-carousel-view-model>';
    d.querySelectorAll('button').forEach(n => n.onclick = () => clicks.push(n.textContent));
    await wait();
    assert.deepEqual(clicks, ['Commenti']);
  } finally { dom.window.close(); }
});

test('saving a video as a guest requests sign-in without changing the playlist', async () => {
  const {dom, d, messages} = await setup(undefined, 'https://m.youtube.com/', {saveDestination:'youtube'}, w => {
    w.ytcfg = {get: name => name === 'LOGGED_IN' ? false : undefined};
  });
  try {
    const bookmark = d.querySelector('.iurub-save');
    bookmark.click();
    assert.equal(messages.filter(m => m.type === 'requestSignIn').length, 1);
    assert.equal(bookmark.getAttribute('aria-pressed'), 'false');
    assert.ok(!messages.some(m => m.type === 'youtubeSaveResult'));
  } finally { dom.window.close(); }
});
