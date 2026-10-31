const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');
const bridge = fs.readFileSync('iurub/Resources/YouTubeBridge.js', 'utf8');
const fixture = fs.readFileSync('iurub/Resources/YouTubeFixture.html', 'utf8');
const wait = (ms = 220) => new Promise(resolve => setTimeout(resolve, ms));
async function setup(html = fixture, url = 'https://m.youtube.com/', config = {}) {
  const dom = new JSDOM(html, { url, runScripts:'dangerously', pretendToBeVisual:true });
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
