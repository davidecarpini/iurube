const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');
const bridge = fs.readFileSync('iurub/Resources/YouTubeBridge.js', 'utf8');
const fixture = fs.readFileSync('iurub/Resources/YouTubeFixture.html', 'utf8');
const wait = (ms = 220) => new Promise(resolve => setTimeout(resolve, ms));
async function setup(html = fixture, url = 'https://m.youtube.com/', config = {}) {
  const dom = new JSDOM(html, { url, runScripts:'dangerously', pretendToBeVisual:true });
  // jsdom has no layout; production visibility still checks hidden/style state.
  dom.window.HTMLElement.prototype.getClientRects = function() { return [{width:100,height:44}]; };
  const messages = [];
  dom.window.webkit = { messageHandlers:{ iurub:{ postMessage: m => messages.push(m) } } };
  dom.window.__iurubConfig = config;
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
