// Browser-Client: Eingaben, eigene Bewegung (vorhergesagt), Darstellung, HUD, Sound.
(function () {
  'use strict';
  const S = window.SHARED;
  const { TILE, MAP, T, TILES, BUILD_ORDER, WEAPONS, ZOMBIES, CRAFT, PLAYER } = S;
  const INTERP_DELAY = 110;

  // ---------- Zustand ----------
  const state = {
    myId: 0,
    grid: new Uint8Array(MAP * MAP),
    hp: new Float32Array(MAP * MAP),
    snaps: [],
    meta: new Map(),
    res: {},
    unlocks: {},
    hour: 8, day: 1, hordeLeft: 0, kills: 0,
    me: { x: 0, y: 0, angle: 0, hp: 100, dead: false, slot: 0, respawn: 0 },
    buildMode: false,
    buildSel: 0,
    joined: false,
  };
  const fx = { tracers: [], pops: [], particles: [], decals: [], swings: new Map(), turretAngle: new Map(), flashes: [] };
  let hurtFlash = 0;

  // ---------- Canvas ----------
  const canvas = document.getElementById('game');
  const ctx = canvas.getContext('2d');
  const light = document.createElement('canvas');
  const lctx = light.getContext('2d');
  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(2, window.devicePixelRatio || 1);
    W = window.innerWidth; H = window.innerHeight;
    canvas.width = light.width = Math.floor(W * DPR);
    canvas.height = light.height = Math.floor(H * DPR);
  }
  window.addEventListener('resize', resize);
  resize();

  // ---------- Beitreten ----------
  const COLORS = ['#4fc3f7', '#ffb74d', '#ba68c8', '#81c784', '#f06292', '#fff176', '#90a4ae', '#e57373'];
  let chosenColor = localGet('zb-color') || COLORS[(Math.random() * COLORS.length) | 0];
  const colorsEl = document.getElementById('colors');
  for (const c of COLORS) {
    const b = document.createElement('button');
    b.style.background = c;
    b.type = 'button';
    if (c === chosenColor) b.classList.add('sel');
    b.onclick = () => {
      chosenColor = c;
      colorsEl.querySelectorAll('button').forEach((x) => x.classList.toggle('sel', x === b));
    };
    colorsEl.appendChild(b);
  }
  const nameEl = document.getElementById('name');
  nameEl.value = localGet('zb-name') || '';
  nameEl.addEventListener('keydown', (e) => { if (e.key === 'Enter') join(); });
  document.getElementById('play').onclick = join;

  function localGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function localSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* egal */ } }

  let ws = null;
  function join() {
    if (ws) return;
    const name = nameEl.value.trim() || 'Überlebender';
    localSet('zb-name', name);
    localSet('zb-color', chosenColor);
    audio.init();
    ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws');
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', name, color: chosenColor }));
    ws.onmessage = (e) => onMessage(JSON.parse(e.data));
    ws.onclose = () => {
      document.getElementById('lost').classList.remove('hidden');
      document.getElementById('hud').classList.add('hidden');
    };
  }
  function send(o) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); }

  // ---------- Netzwerk ----------
  function onMessage(m) {
    if (m.t === 'welcome') {
      state.myId = m.id;
      for (let i = 0; i < m.grid.length; i++) { state.grid[i] = m.grid[i]; state.hp[i] = m.hp[i]; }
      state.snaps = [];
      fx.decals = [];
      rebuildMinimap();
      if (!state.joined) {
        state.joined = true;
        document.getElementById('join').classList.add('hidden');
        document.getElementById('hud').classList.remove('hidden');
        setTimeout(() => { if (!helpTouched) document.getElementById('help').classList.add('hidden'); }, 25000);
      }
      state.needPos = true;
    } else if (m.t === 'pos') {
      state.me.x = m.x; state.me.y = m.y;
    } else if (m.t === 'meta') {
      state.meta = new Map(m.players.map((p) => [p.id, p]));
      if (!document.getElementById('score').classList.contains('hidden')) renderScore();
    } else if (m.t === 'full') {
      document.getElementById('lostmsg').textContent = 'Der Server ist voll (max. 8 Spieler).';
    } else if (m.t === 's') {
      onSnapshot(m);
    }
  }

  function onSnapshot(m) {
    const now = performance.now();
    const wasNight = S.isNight(state.hour);
    state.hour = m.h; state.day = m.d; state.hordeLeft = m.hl; state.kills = m.k;
    state.res = m.r; state.unlocks = m.u;
    const snap = { at: now, p: new Map(), z: new Map() };
    for (const a of m.p) snap.p.set(a[0], { x: a[1], y: a[2], angle: a[3], hp: a[4], dead: a[5], slot: a[6], respawn: a[7], firing: a[8] });
    for (const a of m.z) snap.z.set(a[0], { x: a[1], y: a[2], type: a[3], hp: a[4], angle: a[5], aggro: a[6] });
    // Verschwundene Zombies hinterlassen Blut (Tod wird zusätzlich als Ereignis gemeldet)
    state.snaps.push(snap);
    while (state.snaps.length > 30) state.snaps.shift();

    const mine = snap.p.get(state.myId);
    if (mine) {
      const me = state.me;
      const wasDead = me.dead;
      me.hp = mine.hp; me.dead = !!mine.dead; me.slot = mine.slot; me.respawn = mine.respawn;
      if (state.needPos || me.dead) { me.x = mine.x; me.y = mine.y; state.needPos = false; }
      if (wasDead && !me.dead) { me.x = mine.x; me.y = mine.y; }
    }
    if (m.tc) {
      for (const [i, type, hp] of m.tc) {
        state.grid[i] = type; state.hp[i] = hp;
        minimapDirty = true;
        setMinimapPixel(i);
      }
    }
    if (m.tr) {
      for (const t of m.tr) {
        fx.tracers.push({ x1: t[0], y1: t[1], x2: t[2], y2: t[3], life: 0.09, turret: !!t[4] });
        if (t[4]) {
          const ti = Math.floor(t[1] / TILE) * MAP + Math.floor(t[0] / TILE);
          fx.turretAngle.set(ti, Math.atan2(t[3] - t[1], t[2] - t[0]));
          audio.at(t[0], t[1], 'turret');
          fx.flashes.push({ x: t[0], y: t[1], life: 0.06 });
        }
      }
    }
    if (m.pp) for (const p of m.pp) fx.pops.push({ x: p[0], y: p[1], text: p[2], color: p[3], life: 1.4 });
    if (m.ev) for (const e of m.ev) onEvent(e);
    if (m.m) for (const text of m.m) chatLine(text);
    if (!wasNight && S.isNight(state.hour)) document.body.classList.add('is-night');
    if (wasNight && !S.isNight(state.hour)) document.body.classList.remove('is-night');
  }

  function onEvent(e) {
    switch (e[0]) {
      case 'shot':
        audio.at(e[1], e[2], e[3] === 'shotgun' ? 'shotgun' : 'shot');
        fx.flashes.push({ x: e[1], y: e[2], life: 0.07 });
        break;
      case 'die':
        fx.decals.push({ x: e[1], y: e[2], r: 10 + Math.random() * 10 + (e[3] === 2 ? 10 : 0), rot: Math.random() * 6, life: 90 });
        if (fx.decals.length > 220) fx.decals.shift();
        burst(e[1], e[2], '#7a1010', 10, 120);
        audio.at(e[1], e[2], 'die');
        break;
      case 'break':
        burst(e[1], e[2], '#8d6e63', 18, 160);
        audio.at(e[1], e[2], 'break');
        break;
      case 'build': audio.at(e[1], e[2], 'build'); break;
      case 'repair': audio.at(e[1], e[2], 'build'); break;
      case 'chop': {
        const c = e[3] === T.TREE ? '#a1887f' : e[3] === T.ROCK ? '#b0bec5' : e[3] === T.SCRAP ? '#bf6c3a' : '#8d6e63';
        burst(e[1], e[2], c, 6, 90);
        audio.at(e[1], e[2], e[3] === T.TREE || e[3] === T.CRATE ? 'chop' : 'clank');
        break;
      }
      case 'loot': audio.at(e[1], e[2], 'loot'); break;
      case 'bash': if (Math.random() < 0.5) audio.at(e[1], e[2], 'bash'); burst(e[1], e[2], '#6d4c41', 2, 60); break;
      case 'hurt':
        if (e[1] === state.myId) { hurtFlash = 0.35; audio.play('hurt', 1); }
        break;
      case 'swing': fx.swings.set(e[1], performance.now()); if (e[1] === state.myId) audio.play('swing', 0.5); break;
      case 'night':
        banner(e[1] ? 'BLUTMOND' : 'DIE HORDE KOMMT', e[1] ? '#ff1744' : '#ff5252');
        audio.play('siren', 0.8);
        break;
      case 'dawn':
        banner('TAG ' + state.day, '#ffe082');
        break;
    }
  }

  function burst(x, y, color, n, speed) {
    for (let k = 0; k < n; k++) {
      const a = Math.random() * Math.PI * 2, s = speed * (0.3 + Math.random() * 0.7);
      fx.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.4 + Math.random() * 0.4, color, size: 2 + Math.random() * 3 });
    }
    if (fx.particles.length > 600) fx.particles.splice(0, fx.particles.length - 600);
  }

  // ---------- Eingabe ----------
  const keys = new Set();
  const mouse = { x: 0, y: 0, down: false, right: false };
  let lastBuildTile = -1;
  let helpTouched = false;
  const chatEl = document.getElementById('chat');

  window.addEventListener('keydown', (e) => {
    if (!state.joined) return;
    if (document.activeElement === chatEl) {
      if (e.key === 'Enter') {
        const text = chatEl.value.trim();
        if (text) send({ t: 'chat', m: text });
        closeChat();
      } else if (e.key === 'Escape') closeChat();
      return;
    }
    const k = e.key.toLowerCase();
    if (e.key === 'Tab') { e.preventDefault(); toggle('score', true); renderScore(); return; }
    if (e.key === 'Enter') { e.preventDefault(); openChat(); return; }
    if (e.key === 'Escape') { state.buildMode = false; toggle('craft', false); refreshBars(); return; }
    if (/^[1-7]$/.test(k)) {
      const n = Number(k) - 1;
      if (state.buildMode) state.buildSel = n;
      else if (n < WEAPONS.length) selectSlot(n);
      refreshBars();
      return;
    }
    if (k === 'b') { state.buildMode = !state.buildMode; refreshBars(); return; }
    if (k === 'c') { toggle('craft'); renderCraft(); return; }
    if (k === 'q') { send({ t: 'heal' }); return; }
    if (k === 'h') { helpTouched = true; toggle('help'); return; }
    keys.add(k);
  });
  window.addEventListener('keyup', (e) => {
    keys.delete(e.key.toLowerCase());
    if (e.key === 'Tab') toggle('score', false);
  });
  window.addEventListener('blur', () => { keys.clear(); mouse.down = false; });

  canvas.addEventListener('mousemove', (e) => {
    mouse.x = e.clientX; mouse.y = e.clientY;
    if (state.buildMode && mouse.down) tryBuild();
    if (state.buildMode && mouse.right) tryDemolish();
  });
  canvas.addEventListener('mousedown', (e) => {
    mouse.x = e.clientX; mouse.y = e.clientY;
    if (e.button === 0) {
      mouse.down = true;
      lastBuildTile = -1;
      if (state.buildMode) tryBuild();
    } else if (e.button === 2) {
      mouse.right = true;
      lastBuildTile = -1;
      if (state.buildMode) tryDemolish();
    }
  });
  window.addEventListener('mouseup', (e) => {
    if (e.button === 0) mouse.down = false;
    if (e.button === 2) mouse.right = false;
  });
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  canvas.addEventListener('wheel', (e) => {
    if (state.buildMode) {
      state.buildSel = (state.buildSel + (e.deltaY > 0 ? 1 : -1) + BUILD_ORDER.length) % BUILD_ORDER.length;
    } else {
      let s = state.me.slot;
      for (let k = 0; k < WEAPONS.length; k++) {
        s = (s + (e.deltaY > 0 ? 1 : -1) + WEAPONS.length) % WEAPONS.length;
        if (!WEAPONS[s].locked || state.unlocks[WEAPONS[s].id]) break;
      }
      selectSlot(s);
    }
    refreshBars();
  }, { passive: true });

  function openChat() {
    chatEl.classList.remove('hidden');
    document.getElementById('chatlog').classList.add('open');
    chatEl.value = '';
    keys.clear();
    chatEl.focus();
  }
  function closeChat() {
    chatEl.blur();
    chatEl.classList.add('hidden');
    document.getElementById('chatlog').classList.remove('open');
  }

  function selectSlot(n) {
    const w = WEAPONS[n];
    if (w.locked && !state.unlocks[w.id]) {
      fx.pops.push({ x: state.me.x, y: state.me.y - 30, text: 'Erst an der Werkbank bauen (C)', color: '#ff8a80', life: 1.4 });
      return;
    }
    state.me.slot = n;
    send({ t: 'slot', s: n });
  }

  function toggle(id, force) {
    const el = document.getElementById(id);
    const show = force == null ? el.classList.contains('hidden') : force;
    el.classList.toggle('hidden', !show);
  }

  const cam = { x: 0, y: 0 };
  function mouseWorld() { return { x: mouse.x + cam.x, y: mouse.y + cam.y }; }
  function mouseTile() {
    const m = mouseWorld();
    const tx = Math.floor(m.x / TILE), ty = Math.floor(m.y / TILE);
    if (tx < 0 || ty < 0 || tx >= MAP || ty >= MAP) return -1;
    return ty * MAP + tx;
  }
  function inBuildRange(i) {
    const cx = (i % MAP) * TILE + 16, cy = ((i / MAP) | 0) * TILE + 16;
    return Math.hypot(cx - state.me.x, cy - state.me.y) <= S.BUILD_RANGE * TILE;
  }
  function tryBuild() {
    const i = mouseTile();
    if (i < 0 || i === lastBuildTile || state.me.dead) return;
    lastBuildTile = i;
    if (state.grid[i] !== T.EMPTY || !inBuildRange(i)) return;
    send({ t: 'build', i, b: BUILD_ORDER[state.buildSel] });
  }
  function tryDemolish() {
    const i = mouseTile();
    if (i < 0 || i === lastBuildTile) return;
    lastBuildTile = i;
    if (TILES[state.grid[i]] && TILES[state.grid[i]].build) send({ t: 'demolish', i });
  }

  // ---------- Simulation (eigener Spieler) ----------
  let sendTimer = 0;
  function update(dt) {
    const me = state.me;
    if (!me.dead) {
      let dx = 0, dy = 0;
      if (keys.has('w') || keys.has('arrowup')) dy--;
      if (keys.has('s') || keys.has('arrowdown')) dy++;
      if (keys.has('a') || keys.has('arrowleft')) dx--;
      if (keys.has('d') || keys.has('arrowright')) dx++;
      if (dx || dy) {
        const l = Math.hypot(dx, dy);
        const r = S.moveCircle(state.grid, me.x, me.y, (dx / l) * PLAYER.speed * dt, (dy / l) * PLAYER.speed * dt, PLAYER.r, true);
        me.x = r.x; me.y = r.y;
      }
    }
    const m = mouseWorld();
    me.angle = Math.atan2(m.y - me.y, m.x - me.x);
    sendTimer -= dt;
    if (sendTimer <= 0) {
      sendTimer = 1 / 30;
      const firing = mouse.down && !state.buildMode && !me.dead;
      send({ t: 'i', x: Math.round(me.x * 10) / 10, y: Math.round(me.y * 10) / 10, a: Math.round(me.angle * 1000) / 1000, f: firing, mx: Math.round(m.x), my: Math.round(m.y) });
    }

    for (const t of fx.tracers) t.life -= dt;
    fx.tracers = fx.tracers.filter((t) => t.life > 0);
    for (const f of fx.flashes) f.life -= dt;
    fx.flashes = fx.flashes.filter((f) => f.life > 0);
    for (const p of fx.pops) { p.life -= dt; p.y -= 26 * dt; }
    fx.pops = fx.pops.filter((p) => p.life > 0);
    for (const p of fx.particles) {
      p.life -= dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.9; p.vy *= 0.9;
    }
    fx.particles = fx.particles.filter((p) => p.life > 0);
    for (const d of fx.decals) d.life -= dt;
    fx.decals = fx.decals.filter((d) => d.life > 0);
    hurtFlash = Math.max(0, hurtFlash - dt);

    // Stöhnen naher Zombies
    if (Math.random() < dt * 0.6) {
      const z = currentZombies();
      let best = null, bd = 500;
      for (const e of z) { const d = Math.hypot(e.x - me.x, e.y - me.y); if (d < bd && e.aggro) { bd = d; best = e; } }
      if (best) audio.at(best.x, best.y, best.type === 2 ? 'roar' : 'groan');
    }
  }

  // ---------- Interpolation ----------
  let cacheAt = -1, cacheP = [], cacheZ = [];
  function interpolated() {
    const now = performance.now();
    if (cacheAt === now) return;
    cacheAt = now;
    const t = now - INTERP_DELAY;
    const snaps = state.snaps;
    cacheP = []; cacheZ = [];
    if (!snaps.length) return;
    let a = snaps[0], b = snaps[0];
    for (let k = snaps.length - 1; k >= 0; k--) {
      if (snaps[k].at <= t) { a = snaps[k]; b = snaps[k + 1] || snaps[k]; break; }
    }
    const span = b.at - a.at;
    const f = span > 0 ? Math.min(1, Math.max(0, (t - a.at) / span)) : 1;
    const lerpAngle = (x, y) => {
      let d = y - x;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      return x + d * f;
    };
    for (const [id, nb] of b.p) {
      const na = a.p.get(id) || nb;
      cacheP.push({ id, x: na.x + (nb.x - na.x) * f, y: na.y + (nb.y - na.y) * f, angle: lerpAngle(na.angle, nb.angle), hp: nb.hp, dead: nb.dead, slot: nb.slot, firing: nb.firing });
    }
    for (const [id, nb] of b.z) {
      const na = a.z.get(id);
      if (!na) { if (f > 0.5) cacheZ.push(Object.assign({ id }, nb)); continue; }
      cacheZ.push({ id, x: na.x + (nb.x - na.x) * f, y: na.y + (nb.y - na.y) * f, type: nb.type, hp: nb.hp, angle: lerpAngle(na.angle, nb.angle), aggro: nb.aggro });
    }
  }
  function currentPlayers() { interpolated(); return cacheP; }
  function currentZombies() { interpolated(); return cacheZ; }

  // ---------- Darstellung ----------
  function hash(x, y) {
    let h = (x * 374761393 + y * 668265263) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }

  function darkness(h) {
    // 0 = hell, ~0.9 = tiefe Nacht
    if (h >= 6.5 && h < 19.5) return 0;
    if (h >= 19.5 && h < 22) return ((h - 19.5) / 2.5) * 0.9;
    if (h >= 4.5 && h < 6.5) return (1 - (h - 4.5) / 2) * 0.9;
    return 0.9;
  }

  function render() {
    const me = state.me;
    const players = currentPlayers();
    const zombies = currentZombies();
    const look = 0.18;
    cam.x = me.x - W / 2 + (mouse.x - W / 2) * look;
    cam.y = me.y - H / 2 + (mouse.y - H / 2) * look;
    // Kamera einrasten, damit Kacheln nicht flimmern
    cam.x = Math.round(cam.x); cam.y = Math.round(cam.y);

    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.fillStyle = '#34502a';
    ctx.fillRect(0, 0, W, H);
    ctx.save();
    ctx.translate(-cam.x, -cam.y);

    const tx0 = Math.max(0, Math.floor(cam.x / TILE) - 1), ty0 = Math.max(0, Math.floor(cam.y / TILE) - 1);
    const tx1 = Math.min(MAP - 1, Math.ceil((cam.x + W) / TILE) + 1), ty1 = Math.min(MAP - 1, Math.ceil((cam.y + H) / TILE) + 1);

    drawGround(tx0, ty0, tx1, ty1);
    // Kartenrand
    ctx.strokeStyle = 'rgba(0,0,0,0.6)';
    ctx.lineWidth = 6;
    ctx.strokeRect(0, 0, MAP * TILE, MAP * TILE);

    for (const d of fx.decals) {
      ctx.globalAlpha = Math.min(1, d.life / 20) * 0.75;
      ctx.fillStyle = '#5a0b0b';
      ctx.beginPath();
      ctx.ellipse(d.x, d.y, d.r, d.r * 0.7, d.rot, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(d.x + Math.cos(d.rot) * d.r, d.y + Math.sin(d.rot) * d.r, d.r * 0.3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    // flache Dinge zuerst
    for (let ty = ty0; ty <= ty1; ty++)
      for (let tx = tx0; tx <= tx1; tx++) {
        const t = state.grid[ty * MAP + tx];
        if (t === T.SPIKES) drawTile(t, tx, ty);
      }
    for (let ty = ty0; ty <= ty1; ty++)
      for (let tx = tx0; tx <= tx1; tx++) {
        const t = state.grid[ty * MAP + tx];
        if (t !== T.EMPTY && t !== T.SPIKES && t !== T.TREE) drawTile(t, tx, ty);
      }

    for (const z of zombies) drawZombie(z);
    for (const p of players) {
      if (p.id === state.myId) drawPlayer(Object.assign({}, p, { x: me.x, y: me.y, angle: me.angle }), true);
      else drawPlayer(p, false);
    }

    // Bäume über Figuren (Baumkronen)
    for (let ty = ty0; ty <= ty1; ty++)
      for (let tx = tx0; tx <= tx1; tx++)
        if (state.grid[ty * MAP + tx] === T.TREE) drawTile(T.TREE, tx, ty);

    for (const p of fx.particles) {
      ctx.globalAlpha = Math.min(1, p.life * 2);
      ctx.fillStyle = p.color;
      ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
    }
    ctx.globalAlpha = 1;

    for (const t of fx.tracers) {
      ctx.strokeStyle = t.turret ? 'rgba(128,216,255,0.9)' : 'rgba(255,236,150,0.95)';
      ctx.lineWidth = t.turret ? 1.5 : 2;
      ctx.beginPath(); ctx.moveTo(t.x1, t.y1); ctx.lineTo(t.x2, t.y2); ctx.stroke();
    }

    if (state.buildMode && !me.dead) drawBuildGhost();
    else drawAimHint();

    ctx.restore();

    drawLighting(players, zombies);

    // Text über der Dunkelheit
    ctx.save();
    ctx.translate(-cam.x, -cam.y);
    for (const p of players) drawNameplate(p.id === state.myId ? Object.assign({}, p, { x: me.x, y: me.y }) : p);
    ctx.font = 'bold 13px system-ui, sans-serif';
    ctx.textAlign = 'center';
    for (const p of fx.pops) {
      ctx.globalAlpha = Math.min(1, p.life);
      ctx.fillStyle = '#000';
      ctx.fillText(p.text, p.x + 1, p.y + 1);
      ctx.fillStyle = p.color;
      ctx.fillText(p.text, p.x, p.y);
    }
    ctx.globalAlpha = 1;
    ctx.restore();

    if (hurtFlash > 0) {
      const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.7);
      g.addColorStop(0, 'rgba(255,0,0,0)');
      g.addColorStop(1, `rgba(200,0,0,${hurtFlash * 1.6})`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
    }
    if (!me.dead && me.hp < 30) {
      const pulse = 0.15 + Math.sin(performance.now() / 200) * 0.08;
      const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.7);
      g.addColorStop(0, 'rgba(120,0,0,0)');
      g.addColorStop(1, `rgba(120,0,0,${pulse})`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
    }
    drawMinimap(players, zombies);
  }

  function drawGround(tx0, ty0, tx1, ty1) {
    const c = MAP / 2;
    for (let ty = ty0; ty <= ty1; ty++) {
      for (let tx = tx0; tx <= tx1; tx++) {
        const x = tx * TILE, y = ty * TILE;
        const h = hash(tx, ty);
        const dc = Math.hypot(tx + 0.5 - c, ty + 0.5 - c);
        if (dc < 5.5 + h * 1.2) {
          ctx.fillStyle = h < 0.5 ? '#5a4a33' : '#55462f';
          ctx.fillRect(x, y, TILE, TILE);
          continue;
        }
        if (h < 0.28) { ctx.fillStyle = '#304a26'; ctx.fillRect(x, y, TILE, TILE); }
        else if (h > 0.86) { ctx.fillStyle = '#39572d'; ctx.fillRect(x, y, TILE, TILE); }
        const h2 = hash(tx + 999, ty - 77);
        if (h2 > 0.82) {
          ctx.strokeStyle = '#4b6e38';
          ctx.lineWidth = 1.5;
          const gx = x + 6 + h2 * 18, gy = y + 8 + h * 16;
          ctx.beginPath();
          ctx.moveTo(gx, gy + 5); ctx.lineTo(gx - 3, gy - 2);
          ctx.moveTo(gx, gy + 5); ctx.lineTo(gx + 1, gy - 4);
          ctx.moveTo(gx, gy + 5); ctx.lineTo(gx + 4, gy - 1);
          ctx.stroke();
        } else if (h2 < 0.015) {
          ctx.fillStyle = h < 0.5 ? '#f8e16c' : '#e7eef5';
          ctx.beginPath(); ctx.arc(x + 16, y + 16, 2.2, 0, Math.PI * 2); ctx.fill();
        }
      }
    }
    // Lagerfeuer in der Mitte (Startpunkt)
    const fx0 = c * TILE, fy0 = c * TILE;
    ctx.fillStyle = '#3a3a3a';
    for (let k = 0; k < 8; k++) {
      const a = (k / 8) * Math.PI * 2;
      ctx.beginPath(); ctx.arc(fx0 + Math.cos(a) * 11, fy0 + Math.sin(a) * 11, 4, 0, Math.PI * 2); ctx.fill();
    }
    const fl = Math.sin(performance.now() / 90) * 1.5;
    ctx.fillStyle = '#ff7043';
    ctx.beginPath(); ctx.arc(fx0, fy0, 7 + fl, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#ffd54f';
    ctx.beginPath(); ctx.arc(fx0, fy0, 3.5 + fl * 0.5, 0, Math.PI * 2); ctx.fill();
  }

  function drawTile(t, tx, ty) {
    const x = tx * TILE, y = ty * TILE, i = ty * MAP + tx;
    const h = hash(tx, ty);
    const info = TILES[t];
    const frac = info ? Math.max(0, state.hp[i] / info.hp) : 1;
    switch (t) {
      case T.TREE: {
        const cx = x + 16 + (h - 0.5) * 6, cy = y + 16 + (hash(ty, tx) - 0.5) * 6;
        const s = 0.75 + frac * 0.25;
        ctx.fillStyle = 'rgba(0,0,0,0.25)';
        ctx.beginPath(); ctx.ellipse(cx + 5, cy + 6, 19 * s, 15 * s, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = h < 0.5 ? '#1f4d1f' : '#24561f';
        ctx.beginPath(); ctx.arc(cx, cy, 19 * s, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = h < 0.5 ? '#2e6b2a' : '#356f26';
        ctx.beginPath(); ctx.arc(cx - 4 * s, cy - 4 * s, 13 * s, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = 'rgba(160,220,120,0.18)';
        ctx.beginPath(); ctx.arc(cx - 7 * s, cy - 7 * s, 6 * s, 0, Math.PI * 2); ctx.fill();
        break;
      }
      case T.ROCK: {
        const cx = x + 16, cy = y + 17;
        ctx.fillStyle = 'rgba(0,0,0,0.25)';
        ctx.beginPath(); ctx.ellipse(cx + 3, cy + 5, 15, 10, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#777d82';
        ctx.beginPath();
        const pts = 7;
        for (let k = 0; k < pts; k++) {
          const a = (k / pts) * Math.PI * 2;
          const r = (11 + hash(tx * 7 + k, ty) * 5) * (0.7 + frac * 0.3);
          const px = cx + Math.cos(a) * r, py = cy + Math.sin(a) * r * 0.85;
          if (k) ctx.lineTo(px, py); else ctx.moveTo(px, py);
        }
        ctx.closePath(); ctx.fill();
        ctx.fillStyle = '#9aa1a6';
        ctx.beginPath(); ctx.ellipse(cx - 3, cy - 4, 6, 4, -0.4, 0, Math.PI * 2); ctx.fill();
        break;
      }
      case T.SCRAP: {
        ctx.save();
        ctx.translate(x + 16, y + 16);
        ctx.rotate(h < 0.5 ? 0.3 : -0.5);
        ctx.fillStyle = 'rgba(0,0,0,0.3)';
        ctx.fillRect(-13, -9, 30, 22);
        ctx.fillStyle = h < 0.33 ? '#7b3f2a' : h < 0.66 ? '#5d6b73' : '#8a6d3b';
        ctx.fillRect(-15, -10, 30, 20);
        ctx.fillStyle = '#20262a';
        ctx.fillRect(-6, -8, 7, 16);
        ctx.fillRect(5, -7, 5, 14);
        ctx.fillStyle = 'rgba(191,108,58,0.6)';
        ctx.fillRect(-14, -9, 5, 4); ctx.fillRect(10, 4, 4, 4);
        ctx.restore();
        break;
      }
      case T.CRATE: {
        ctx.fillStyle = 'rgba(0,0,0,0.3)';
        ctx.fillRect(x + 7, y + 8, 22, 22);
        ctx.fillStyle = '#9c6b3c';
        ctx.fillRect(x + 5, y + 5, 22, 22);
        ctx.strokeStyle = '#5d3b1d';
        ctx.lineWidth = 2;
        ctx.strokeRect(x + 5, y + 5, 22, 22);
        ctx.beginPath(); ctx.moveTo(x + 5, y + 5); ctx.lineTo(x + 27, y + 27); ctx.moveTo(x + 27, y + 5); ctx.lineTo(x + 5, y + 27); ctx.stroke();
        ctx.fillStyle = '#ffd54f';
        ctx.fillRect(x + 14, y + 3, 4, 4);
        break;
      }
      case T.WOOD_WALL:
        ctx.fillStyle = '#7a5230';
        ctx.fillRect(x, y, TILE, TILE);
        ctx.fillStyle = '#8d6238';
        for (let k = 0; k < 4; k++) ctx.fillRect(x + 1, y + 1 + k * 8, TILE - 2, 6);
        ctx.fillStyle = '#4e3420';
        ctx.fillRect(x + 4, y + 3, 2, 2); ctx.fillRect(x + 26, y + 19, 2, 2);
        bevel(x, y);
        break;
      case T.STONE_WALL:
        ctx.fillStyle = '#5e6266';
        ctx.fillRect(x, y, TILE, TILE);
        ctx.fillStyle = '#7d8287';
        for (let r = 0; r < 4; r++) {
          const off = r % 2 ? 8 : 0;
          for (let c = -1; c < 2; c++) ctx.fillRect(x + off + c * 16 + 1, y + r * 8 + 1, 14, 6);
        }
        bevel(x, y);
        break;
      case T.METAL_WALL:
        ctx.fillStyle = '#546e7a';
        ctx.fillRect(x, y, TILE, TILE);
        ctx.fillStyle = '#78909c';
        ctx.fillRect(x + 2, y + 2, TILE - 4, TILE - 4);
        ctx.fillStyle = '#37474f';
        for (const [a, b] of [[5, 5], [25, 5], [5, 25], [25, 25]]) { ctx.beginPath(); ctx.arc(x + a + 1, y + b + 1, 1.8, 0, Math.PI * 2); ctx.fill(); }
        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        ctx.fillRect(x + 2, y + 2, TILE - 4, 3);
        bevel(x, y);
        break;
      case T.DOOR:
        ctx.fillStyle = '#4e3420';
        ctx.fillRect(x, y, TILE, TILE);
        ctx.fillStyle = '#a0703f';
        ctx.fillRect(x + 3, y + 3, TILE - 6, TILE - 6);
        ctx.strokeStyle = '#ffca28';
        ctx.lineWidth = 2;
        ctx.strokeRect(x + 3, y + 3, TILE - 6, TILE - 6);
        ctx.fillStyle = '#5d3b1d';
        ctx.fillRect(x + 14, y + 4, 4, TILE - 8);
        ctx.fillStyle = '#ffca28';
        ctx.beginPath(); ctx.arc(x + 22, y + 16, 2, 0, Math.PI * 2); ctx.fill();
        break;
      case T.SPIKES:
        ctx.fillStyle = 'rgba(40,30,20,0.6)';
        ctx.fillRect(x + 2, y + 2, TILE - 4, TILE - 4);
        ctx.fillStyle = '#b0bec5';
        for (let r = 0; r < 3; r++)
          for (let c = 0; c < 3; c++) {
            const px = x + 6 + c * 10, py = y + 6 + r * 10;
            ctx.beginPath(); ctx.moveTo(px, py - 4); ctx.lineTo(px + 3, py + 3); ctx.lineTo(px - 3, py + 3); ctx.closePath(); ctx.fill();
          }
        break;
      case T.TURRET: {
        ctx.fillStyle = '#37474f';
        ctx.fillRect(x + 1, y + 1, TILE - 2, TILE - 2);
        ctx.fillStyle = '#263238';
        ctx.beginPath(); ctx.arc(x + 16, y + 16, 11, 0, Math.PI * 2); ctx.fill();
        const a = fx.turretAngle.has(i) ? fx.turretAngle.get(i) : performance.now() / 1500 + h * 6;
        ctx.save();
        ctx.translate(x + 16, y + 16);
        ctx.rotate(a);
        ctx.fillStyle = '#90a4ae';
        ctx.fillRect(0, -3, 18, 6);
        ctx.fillStyle = '#607d8b';
        ctx.beginPath(); ctx.arc(0, 0, 7, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
        ctx.fillStyle = state.res.munition > 0 ? '#69f0ae' : '#ff5252';
        ctx.beginPath(); ctx.arc(x + 5, y + 5, 2, 0, Math.PI * 2); ctx.fill();
        break;
      }
      case T.LAMP:
        ctx.fillStyle = 'rgba(0,0,0,0.3)';
        ctx.beginPath(); ctx.arc(x + 18, y + 18, 9, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#455a64';
        ctx.beginPath(); ctx.arc(x + 16, y + 16, 8, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#fff59d';
        ctx.beginPath(); ctx.arc(x + 16, y + 16, 5, 0, Math.PI * 2); ctx.fill();
        break;
    }
    if (info && info.build && frac < 0.99) {
      // Risse und Lebensbalken
      ctx.strokeStyle = 'rgba(0,0,0,0.55)';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      if (frac < 0.7) { ctx.moveTo(x + 6, y + 4); ctx.lineTo(x + 13, y + 14); ctx.lineTo(x + 10, y + 24); }
      if (frac < 0.4) { ctx.moveTo(x + 27, y + 6); ctx.lineTo(x + 19, y + 15); ctx.lineTo(x + 24, y + 28); ctx.moveTo(x + 13, y + 14); ctx.lineTo(x + 19, y + 15); }
      ctx.stroke();
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(x + 3, y + TILE - 6, TILE - 6, 4);
      ctx.fillStyle = frac > 0.5 ? '#66bb6a' : frac > 0.25 ? '#ffca28' : '#ef5350';
      ctx.fillRect(x + 3, y + TILE - 6, (TILE - 6) * frac, 4);
    }
  }

  function bevel(x, y) {
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.fillRect(x, y, TILE, 2);
    ctx.fillRect(x, y, 2, TILE);
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.fillRect(x, y + TILE - 2, TILE, 2);
    ctx.fillRect(x + TILE - 2, y, 2, TILE);
  }

  const ZCOL = [
    { body: '#5f7f48', head: '#7c9a5c', arm: '#4f6b3c' },
    { body: '#7f4a3a', head: '#9b6a55', arm: '#5e352a' },
    { body: '#3f4a33', head: '#5a6847', arm: '#2f3826' },
  ];
  function drawZombie(z) {
    const info = ZOMBIES[z.type];
    const col = ZCOL[z.type];
    const r = info.r;
    const t = performance.now() / 1000;
    const wob = Math.sin(t * (z.type === 1 ? 14 : 7) + z.id) * 3;
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(z.x + 3, z.y + 4, r, r * 0.8, 0, 0, Math.PI * 2); ctx.fill();
    ctx.save();
    ctx.translate(z.x, z.y);
    ctx.rotate(z.angle);
    // ausgestreckte Arme
    ctx.strokeStyle = col.arm;
    ctx.lineWidth = z.type === 2 ? 7 : 4.5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(r * 0.3, -r * 0.7); ctx.lineTo(r * 1.45 + wob, -r * 0.55);
    ctx.moveTo(r * 0.3, r * 0.7); ctx.lineTo(r * 1.45 - wob, r * 0.55);
    ctx.stroke();
    ctx.fillStyle = col.body;
    ctx.beginPath(); ctx.ellipse(0, 0, r * 0.85, r, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = col.head;
    ctx.beginPath(); ctx.arc(r * 0.25, 0, r * 0.6, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(90,10,10,0.6)';
    ctx.beginPath(); ctx.arc(-r * 0.3, r * 0.3, r * 0.25, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    if (z.hp < 100) {
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(z.x - 12, z.y - r - 9, 24, 4);
      ctx.fillStyle = '#e53935';
      ctx.fillRect(z.x - 12, z.y - r - 9, 24 * (z.hp / 100), 4);
    }
  }

  function drawPlayer(p, isMe) {
    const meta = state.meta.get(p.id) || { color: '#fff' };
    if (p.dead) {
      ctx.fillStyle = 'rgba(90,10,10,0.7)';
      ctx.beginPath(); ctx.arc(p.x, p.y, 14, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = meta.color; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(p.x - 7, p.y - 7); ctx.lineTo(p.x + 7, p.y + 7); ctx.moveTo(p.x + 7, p.y - 7); ctx.lineTo(p.x - 7, p.y + 7); ctx.stroke();
      return;
    }
    const r = PLAYER.r;
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.beginPath(); ctx.ellipse(p.x + 3, p.y + 4, r, r * 0.8, 0, 0, Math.PI * 2); ctx.fill();
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.angle);
    const w = WEAPONS[p.slot] || WEAPONS[0];
    if (w.melee) {
      const since = (performance.now() - (fx.swings.get(p.id) || 0)) / 1000;
      const swing = since < 0.25 ? Math.sin((since / 0.25) * Math.PI) * 1.4 - 0.7 : 0.5;
      ctx.save();
      ctx.rotate(swing);
      ctx.fillStyle = '#6d4c41';
      ctx.fillRect(4, 6, 20, 4);
      ctx.fillStyle = '#b0bec5';
      ctx.fillRect(20, 1, 6, 12);
      ctx.restore();
    } else {
      ctx.fillStyle = '#263238';
      if (w.id === 'shotgun') ctx.fillRect(4, -3, 24, 6);
      else ctx.fillRect(6, -2.5, 16, 5);
    }
    ctx.fillStyle = '#1b1b1b';
    ctx.beginPath(); ctx.arc(0, 0, r + 1.5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = meta.color;
    ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.arc(-2, 0, r * 0.55, 0, Math.PI * 2); ctx.fill();
    // Hände
    ctx.fillStyle = '#e0b48a';
    ctx.beginPath(); ctx.arc(9, -6, 3, 0, Math.PI * 2); ctx.arc(9, 6, 3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    if (isMe) {
      ctx.strokeStyle = 'rgba(255,255,255,0.5)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(p.x, p.y, r + 5, 0, Math.PI * 2); ctx.stroke();
    }
  }

  function drawNameplate(p) {
    const meta = state.meta.get(p.id);
    if (!meta) return;
    ctx.font = 'bold 12px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = '#000';
    ctx.fillText(meta.name, p.x + 1, p.y - 23);
    ctx.fillStyle = meta.color;
    ctx.fillText(meta.name, p.x, p.y - 24);
    if (!p.dead && p.id !== state.myId) {
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(p.x - 14, p.y - 20, 28, 4);
      ctx.fillStyle = '#66bb6a';
      ctx.fillRect(p.x - 14, p.y - 20, 28 * (p.hp / 100), 4);
    }
  }

  function drawBuildGhost() {
    const i = mouseTile();
    if (i < 0) return;
    const tx = i % MAP, ty = (i / MAP) | 0;
    const type = BUILD_ORDER[state.buildSel];
    const info = TILES[type];
    const ok = state.grid[i] === T.EMPTY && inBuildRange(i) && S.canAfford(state.res, info.cost);
    const demol = TILES[state.grid[i]] && TILES[state.grid[i]].build;
    ctx.globalAlpha = 0.55;
    if (state.grid[i] === T.EMPTY) drawTile(type, tx, ty);
    ctx.globalAlpha = 1;
    ctx.strokeStyle = demol ? '#ffca28' : ok ? '#c6ff3d' : '#ff5252';
    ctx.lineWidth = 2;
    ctx.strokeRect(tx * TILE + 1, ty * TILE + 1, TILE - 2, TILE - 2);
    // Reichweite
    ctx.strokeStyle = 'rgba(198,255,61,0.15)';
    ctx.setLineDash([6, 6]);
    ctx.beginPath(); ctx.arc(state.me.x, state.me.y, S.BUILD_RANGE * TILE, 0, Math.PI * 2); ctx.stroke();
    ctx.setLineDash([]);
  }

  function drawAimHint() {
    const w = WEAPONS[state.me.slot];
    if (!w || !w.melee || state.me.dead) return;
    const i = mouseTile();
    if (i < 0 || state.grid[i] === T.EMPTY) return;
    const cx = (i % MAP) * TILE + 16, cy = ((i / MAP) | 0) * TILE + 16;
    if (Math.hypot(cx - state.me.x, cy - state.me.y) > 76) return;
    ctx.strokeStyle = 'rgba(255,255,255,0.6)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect((i % MAP) * TILE + 1, ((i / MAP) | 0) * TILE + 1, TILE - 2, TILE - 2);
  }

  function drawLighting(players, zombies) {
    const dark = darkness(state.hour);
    if (dark <= 0.01) return;
    const blood = S.isNight(state.hour) && state.day % S.BLOOD_MOON_EVERY === 0;
    lctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    lctx.globalCompositeOperation = 'source-over';
    lctx.fillStyle = blood ? `rgba(30,0,4,${dark})` : `rgba(4,7,20,${dark})`;
    lctx.fillRect(0, 0, W, H);
    lctx.globalCompositeOperation = 'destination-out';
    const hole = (x, y, r, strength) => {
      const sx = x - cam.x, sy = y - cam.y;
      if (sx < -r || sy < -r || sx > W + r || sy > H + r) return;
      const g = lctx.createRadialGradient(sx, sy, 0, sx, sy, r);
      g.addColorStop(0, `rgba(0,0,0,${strength})`);
      g.addColorStop(0.6, `rgba(0,0,0,${strength * 0.6})`);
      g.addColorStop(1, 'rgba(0,0,0,0)');
      lctx.fillStyle = g;
      lctx.beginPath(); lctx.arc(sx, sy, r, 0, Math.PI * 2); lctx.fill();
    };
    const cone = (x, y, a) => {
      const sx = x - cam.x, sy = y - cam.y, len = 400, spread = 0.42;
      const g = lctx.createRadialGradient(sx, sy, 10, sx, sy, len);
      g.addColorStop(0, 'rgba(0,0,0,0.95)');
      g.addColorStop(0.7, 'rgba(0,0,0,0.6)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      lctx.fillStyle = g;
      lctx.beginPath();
      lctx.moveTo(sx, sy);
      lctx.arc(sx, sy, len, a - spread, a + spread);
      lctx.closePath();
      lctx.fill();
    };
    const me = state.me;
    for (const p of players) {
      if (p.dead) continue;
      const x = p.id === state.myId ? me.x : p.x, y = p.id === state.myId ? me.y : p.y;
      const a = p.id === state.myId ? me.angle : p.angle;
      hole(x, y, 130, 0.9);
      cone(x, y, a);
    }
    const c = (MAP / 2) * TILE;
    hole(c, c, 170 + Math.sin(performance.now() / 120) * 6, 0.85);
    // Lampen im Sichtbereich
    const tx0 = Math.max(0, Math.floor((cam.x - 220) / TILE)), ty0 = Math.max(0, Math.floor((cam.y - 220) / TILE));
    const tx1 = Math.min(MAP - 1, Math.ceil((cam.x + W + 220) / TILE)), ty1 = Math.min(MAP - 1, Math.ceil((cam.y + H + 220) / TILE));
    for (let ty = ty0; ty <= ty1; ty++)
      for (let tx = tx0; tx <= tx1; tx++)
        if (state.grid[ty * MAP + tx] === T.LAMP) hole(tx * TILE + 16, ty * TILE + 16, 230, 0.95);
    for (const f of fx.flashes) hole(f.x, f.y, 90, 0.8);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(light, 0, 0);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    // Glühende Augen im Dunkeln
    if (dark > 0.4) {
      ctx.fillStyle = blood ? '#ff1744' : '#ff3d00';
      for (const z of zombies) {
        if (!z.aggro) continue;
        const sx = z.x - cam.x, sy = z.y - cam.y;
        if (sx < 0 || sy < 0 || sx > W || sy > H) continue;
        const r = ZOMBIES[z.type].r;
        const fx1 = Math.cos(z.angle), fy1 = Math.sin(z.angle);
        const ex = sx + fx1 * r * 0.5, ey = sy + fy1 * r * 0.5;
        ctx.beginPath();
        ctx.arc(ex - fy1 * 3.5, ey + fx1 * 3.5, 1.6, 0, Math.PI * 2);
        ctx.arc(ex + fy1 * 3.5, ey - fx1 * 3.5, 1.6, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  // ---------- Minikarte ----------
  const mini = document.getElementById('minimap');
  const mctx = mini.getContext('2d');
  const mapCanvas = document.createElement('canvas');
  mapCanvas.width = mapCanvas.height = MAP;
  const mapCtx = mapCanvas.getContext('2d');
  const mapImg = mapCtx.createImageData(MAP, MAP);
  let minimapDirty = true;
  const MINI_COL = {
    [T.EMPTY]: [52, 80, 42], [T.TREE]: [28, 70, 28], [T.ROCK]: [130, 135, 140], [T.SCRAP]: [160, 90, 50], [T.CRATE]: [255, 213, 79],
    [T.WOOD_WALL]: [150, 100, 60], [T.STONE_WALL]: [180, 180, 180], [T.METAL_WALL]: [140, 180, 200], [T.DOOR]: [255, 202, 40],
    [T.SPIKES]: [100, 90, 80], [T.TURRET]: [80, 220, 255], [T.LAMP]: [255, 245, 157],
  };
  function setMinimapPixel(i) {
    const c = MINI_COL[state.grid[i]] || [255, 0, 255];
    mapImg.data[i * 4] = c[0]; mapImg.data[i * 4 + 1] = c[1]; mapImg.data[i * 4 + 2] = c[2]; mapImg.data[i * 4 + 3] = 255;
  }
  function rebuildMinimap() {
    for (let i = 0; i < MAP * MAP; i++) setMinimapPixel(i);
    minimapDirty = true;
  }
  let miniTimer = 0;
  function drawMinimap(players, zombies) {
    const now = performance.now();
    if (now - miniTimer < 120) return;
    miniTimer = now;
    if (minimapDirty) { mapCtx.putImageData(mapImg, 0, 0); minimapDirty = false; }
    const s = mini.width / (MAP * TILE);
    mctx.imageSmoothingEnabled = false;
    mctx.drawImage(mapCanvas, 0, 0, mini.width, mini.height);
    const dark = darkness(state.hour);
    if (dark > 0) { mctx.fillStyle = `rgba(4,7,20,${dark * 0.5})`; mctx.fillRect(0, 0, mini.width, mini.height); }
    mctx.fillStyle = '#ff1744';
    for (const z of zombies) mctx.fillRect(z.x * s - 1, z.y * s - 1, 2, 2);
    for (const p of players) {
      const meta = state.meta.get(p.id);
      const x = p.id === state.myId ? state.me.x : p.x, y = p.id === state.myId ? state.me.y : p.y;
      mctx.fillStyle = meta ? meta.color : '#fff';
      mctx.beginPath(); mctx.arc(x * s, y * s, p.id === state.myId ? 3.5 : 2.5, 0, Math.PI * 2); mctx.fill();
    }
    mctx.strokeStyle = 'rgba(255,255,255,0.5)';
    mctx.strokeRect(cam.x * s, cam.y * s, W * s, H * s);
  }

  // ---------- HUD ----------
  const resEl = document.getElementById('res');
  const timeEl = document.getElementById('time');
  const statusEl = document.getElementById('status');
  const hpFill = document.getElementById('hpfill');
  const hpText = document.getElementById('hptext');
  const deadEl = document.getElementById('dead');
  const deadTimer = document.getElementById('deadtimer');
  const RES_ICON = { holz: '🪵', stein: '🪨', metall: '⚙️', munition: '🔸', medkit: '➕' };

  function costText(cost) {
    return Object.keys(cost).map((k) => `${cost[k]} ${S.RES_NAMES[k]}`).join(', ');
  }

  function refreshBars() {
    const hot = document.getElementById('hotbar');
    hot.innerHTML = '';
    WEAPONS.forEach((w, n) => {
      const d = document.createElement('div');
      const locked = w.locked && !state.unlocks[w.id];
      d.className = 'slot' + (!state.buildMode && state.me.slot === n ? ' sel' : '') + (locked ? ' locked' : '');
      d.innerHTML = `<b>${n + 1}</b><span>${w.name}</span><small>${w.melee ? 'Abbauen/Reparieren' : locked ? 'gesperrt' : w.ammo + ' Mun./Schuss'}</small>`;
      d.onclick = () => { state.buildMode = false; selectSlot(n); refreshBars(); };
      hot.appendChild(d);
    });
    const b = document.createElement('div');
    b.className = 'slot' + (state.buildMode ? ' sel' : '');
    b.innerHTML = '<b>B</b><span>Bauen</span><small>Basis errichten</small>';
    b.onclick = () => { state.buildMode = !state.buildMode; refreshBars(); };
    hot.appendChild(b);

    const bar = document.getElementById('buildbar');
    bar.classList.toggle('hidden', !state.buildMode);
    bar.innerHTML = '';
    if (!state.buildMode) return;
    BUILD_ORDER.forEach((type, n) => {
      const info = TILES[type];
      const d = document.createElement('div');
      d.className = 'slot' + (state.buildSel === n ? ' sel' : '') + (S.canAfford(state.res, info.cost) ? '' : ' poor');
      d.title = info.desc || '';
      d.innerHTML = `<b>${n + 1}</b><span>${info.name}</span><small>${costText(info.cost)}</small>`;
      d.onclick = () => { state.buildSel = n; refreshBars(); };
      bar.appendChild(d);
    });
  }

  function renderCraft() {
    const list = document.getElementById('craftlist');
    list.innerHTML = '';
    for (const id in CRAFT) {
      const c = CRAFT[id];
      const done = c.unlock && state.unlocks[c.unlock];
      const btn = document.createElement('button');
      btn.disabled = done || !S.canAfford(state.res, c.cost);
      btn.innerHTML = `<span>${c.name}${done ? ' ✓' : ''}</span><small>${costText(c.cost)}</small>`;
      btn.onclick = () => { send({ t: 'craft', c: id }); setTimeout(renderCraft, 150); };
      list.appendChild(btn);
    }
  }

  function renderScore() {
    const body = document.getElementById('scorebody');
    body.innerHTML = '';
    for (const p of state.meta.values()) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td style="color:${p.color}"></td><td>${p.kills}</td><td>${p.deaths}</td>`;
      tr.firstChild.textContent = p.name + (p.id === state.myId ? ' (du)' : '');
      body.appendChild(tr);
    }
    const tr = document.createElement('tr');
    tr.innerHTML = `<td style="color:var(--muted)">Team gesamt · Tag ${state.day}</td><td>${state.kills}</td><td></td>`;
    body.appendChild(tr);
  }

  let lastResKey = '';
  function updateHud() {
    const r = state.res;
    const key = JSON.stringify(r) + state.buildMode + state.buildSel + state.me.slot + JSON.stringify(state.unlocks);
    if (key !== lastResKey) {
      lastResKey = key;
      resEl.innerHTML = '';
      for (const k of ['holz', 'stein', 'metall', 'munition', 'medkit']) {
        const d = document.createElement('div');
        d.className = 'chip' + (k === 'munition' && (r[k] || 0) < 20 ? ' low' : '');
        d.title = S.RES_NAMES[k];
        d.innerHTML = `<i>${RES_ICON[k]}</i>${r[k] || 0}`;
        resEl.appendChild(d);
      }
      refreshBars();
      if (!document.getElementById('craft').classList.contains('hidden')) renderCraft();
    }
    const h = state.hour;
    const hh = Math.floor(h), mm = Math.floor((h - hh) * 60 / 10) * 10;
    timeEl.textContent = `Tag ${state.day} · ${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    if (S.isNight(h)) {
      const zc = currentZombies().length;
      statusEl.textContent = `NACHT · ${zc} Zombies in der Nähe` + (state.hordeLeft > 0 ? ` · ${state.hordeLeft} kommen noch` : '');
      statusEl.className = 'night';
    } else {
      const s = Math.ceil(S.secondsUntilNight(h));
      const nextBlood = state.day % S.BLOOD_MOON_EVERY === 0;
      statusEl.textContent = `${nextBlood ? 'BLUTMOND' : 'Horde'} in ${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      statusEl.className = s < 30 || nextBlood ? 'night' : '';
    }
    const me = state.me;
    hpFill.style.width = `${me.hp}%`;
    hpText.textContent = `${Math.ceil(me.hp)} HP` + (r.medkit ? ` · Q = Medkit (${r.medkit})` : '');
    deadEl.classList.toggle('hidden', !me.dead);
    if (me.dead) deadTimer.textContent = `Wiederbelebung am Lagerfeuer in ${Math.max(0, me.respawn)} s`;
  }

  function chatLine(text) {
    const log = document.getElementById('chatlog');
    const d = document.createElement('div');
    d.textContent = text;
    log.appendChild(d);
    while (log.children.length > 10) log.removeChild(log.firstChild);
  }

  function banner(text, color) {
    const el = document.getElementById('banner');
    el.textContent = text;
    el.style.color = color;
    el.classList.remove('hidden');
    el.style.animation = 'none';
    void el.offsetWidth;
    el.style.animation = '';
  }

  // ---------- Sound (synthetisch, ohne Dateien) ----------
  const audio = {
    ctx: null, noiseBuf: null, master: null, last: {},
    init() {
      if (this.ctx) return;
      try {
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();
        this.master = this.ctx.createGain();
        this.master.gain.value = 0.35;
        this.master.connect(this.ctx.destination);
        const len = this.ctx.sampleRate;
        this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
        const d = this.noiseBuf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      } catch (e) { this.ctx = null; }
    },
    at(x, y, name) {
      const d = Math.hypot(x - state.me.x, y - state.me.y);
      const v = Math.max(0, 1 - d / 900);
      if (v > 0.02) this.play(name, v);
    },
    noise(dur, freq, vol, type) {
      const c = this.ctx, t = c.currentTime;
      const src = c.createBufferSource();
      src.buffer = this.noiseBuf;
      const f = c.createBiquadFilter();
      f.type = type || 'lowpass';
      f.frequency.value = freq;
      const g = c.createGain();
      g.gain.setValueAtTime(vol, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      src.connect(f); f.connect(g); g.connect(this.master);
      src.start(t, Math.random() * 0.5);
      src.stop(t + dur);
    },
    tone(f1, f2, dur, vol, type) {
      const c = this.ctx, t = c.currentTime;
      const o = c.createOscillator();
      o.type = type || 'sine';
      o.frequency.setValueAtTime(f1, t);
      o.frequency.exponentialRampToValueAtTime(Math.max(1, f2), t + dur);
      const g = c.createGain();
      g.gain.setValueAtTime(vol, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      o.connect(g); g.connect(this.master);
      o.start(t); o.stop(t + dur);
    },
    play(name, v) {
      if (!this.ctx) return;
      const now = performance.now();
      const gap = { groan: 300, roar: 800, bash: 90, turret: 60, die: 40, shot: 30 }[name] || 0;
      if (gap && now - (this.last[name] || 0) < gap) return;
      this.last[name] = now;
      switch (name) {
        case 'shot': this.noise(0.12, 2500, 0.6 * v); this.tone(180, 60, 0.08, 0.3 * v, 'square'); break;
        case 'shotgun': this.noise(0.3, 1400, 0.9 * v); this.tone(120, 40, 0.15, 0.4 * v, 'square'); break;
        case 'turret': this.noise(0.06, 4000, 0.25 * v, 'highpass'); break;
        case 'die': this.tone(260, 70, 0.3, 0.2 * v, 'sawtooth'); this.noise(0.15, 600, 0.3 * v); break;
        case 'groan': this.tone(110 + Math.random() * 40, 70, 0.7, 0.12 * v, 'sawtooth'); break;
        case 'roar': this.tone(80, 40, 1.0, 0.25 * v, 'sawtooth'); this.noise(0.6, 300, 0.2 * v); break;
        case 'break': this.noise(0.4, 900, 0.7 * v); this.tone(90, 40, 0.3, 0.3 * v, 'triangle'); break;
        case 'bash': this.noise(0.08, 500, 0.4 * v); break;
        case 'build': this.tone(320, 260, 0.08, 0.2 * v, 'square'); this.noise(0.06, 1500, 0.2 * v); break;
        case 'chop': this.noise(0.08, 1200, 0.45 * v, 'bandpass'); break;
        case 'clank': this.tone(900, 700, 0.12, 0.15 * v, 'triangle'); this.noise(0.05, 4000, 0.2 * v, 'highpass'); break;
        case 'loot': this.tone(520, 520, 0.08, 0.2 * v, 'square'); setTimeout(() => this.ctx && this.tone(780, 780, 0.12, 0.2 * v, 'square'), 90); break;
        case 'hurt': this.tone(200, 90, 0.2, 0.35 * v, 'square'); break;
        case 'swing': this.noise(0.1, 2000, 0.15 * v, 'bandpass'); break;
        case 'siren': this.tone(300, 600, 1.2, 0.25 * v, 'sawtooth'); setTimeout(() => this.ctx && this.tone(600, 280, 1.4, 0.25 * v, 'sawtooth'), 1200); break;
      }
    },
  };

  // ---------- Hauptschleife ----------
  let last = performance.now();
  let hudTimer = 0;
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (state.joined) {
      update(dt);
      render();
      hudTimer -= dt;
      if (hudTimer <= 0) { hudTimer = 0.1; updateHud(); }
    } else {
      drawTitle(now);
    }
    requestAnimationFrame(frame);
  }

  function drawTitle(now) {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.fillStyle = '#1a2414';
    ctx.fillRect(0, 0, W, H);
    for (let y = 0; y < H / TILE + 1; y++)
      for (let x = 0; x < W / TILE + 1; x++) {
        const h = hash(x, y);
        ctx.fillStyle = h < 0.3 ? '#16200f' : h > 0.95 ? '#22381a' : '#1a2414';
        ctx.fillRect(x * TILE - ((now / 60) % TILE), y * TILE, TILE, TILE);
      }
  }

  requestAnimationFrame(frame);
})();
