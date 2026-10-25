// Rauchtest: Simulation über mehrere Tage + echter Netzwerktest mit zwei Bots.
'use strict';
const assert = require('assert');
const { spawn } = require('child_process');
const path = require('path');
const S = require('../public/shared');
const { Game, TICK } = require('../server/game');

const fakeConn = { send() {}, close() {} };

function simulate() {
  const g = new Game(1234);
  const a = g.addPlayer(fakeConn, 'Anna', '#4fc3f7');
  const b = g.addPlayer(fakeConn, 'Ben', '#4fc3f7');
  assert.notStrictEqual(a.color, b.color, 'Farben müssen eindeutig sein');

  // Basis bauen: Ring aus Holzwänden um das Lager
  g.res.holz = 1000; g.res.stein = 1000; g.res.metall = 1000; g.res.munition = 5000;
  const c = S.MAP / 2;
  let built = 0;
  for (let y = c - 4; y <= c + 4; y++)
    for (let x = c - 4; x <= c + 4; x++) {
      if (Math.max(Math.abs(x - c), Math.abs(y - c)) !== 4) continue;
      const i = y * S.MAP + x;
      if (g.grid[i] !== S.T.EMPTY) g.setTile(i, S.T.EMPTY);
      const type = x === c && y === c - 4 ? S.T.DOOR : S.T.WOOD_WALL;
      a.x = (x + 0.5) * S.TILE; a.y = (y + 2.5) * S.TILE; // in Reichweite, nicht auf der Kachel
      if (Math.abs(y - c) === 4 && y > c) a.y = (y - 2.5) * S.TILE;
      g.handle(a, { t: 'build', i, b: type });
      if (g.grid[i] === type) built++;
    }
  assert.ok(built >= 28, `Wände gebaut: ${built}`);
  a.x = c * S.TILE; a.y = c * S.TILE;
  g.handle(a, { t: 'build', i: (c - 2) * S.MAP + c - 2, b: S.T.TURRET });
  assert.strictEqual(g.grid[(c - 2) * S.MAP + c - 2], S.T.TURRET);
  a.x = b.x = c * S.TILE; a.y = b.y = c * S.TILE;

  // Werkbank
  g.handle(a, { t: 'craft', c: 'shotgun' });
  assert.ok(g.unlocks.shotgun);
  g.handle(a, { t: 'slot', s: 1 });
  assert.strictEqual(a.slot, 1);

  // Ressourcen abbauen
  let tree = -1;
  for (let i = 0; i < S.MAP * S.MAP && tree < 0; i++) if (g.grid[i] === S.T.TREE) tree = i;
  const holz = g.res.holz;
  b.x = (tree % S.MAP) * S.TILE + 16 + 40; b.y = ((tree / S.MAP) | 0) * S.TILE + 16;
  b.slot = 2; b.input.mx = (tree % S.MAP) * S.TILE + 16; b.input.my = ((tree / S.MAP) | 0) * S.TILE + 16;
  b.angle = Math.PI;
  g.fire(b);
  assert.ok(g.res.holz > holz, 'Holz abgebaut');
  b.x = c * S.TILE; b.y = c * S.TILE;

  // Drei Tage durchlaufen, Spieler schießen
  const ticks = Math.ceil(((S.DAY_SECONDS + S.NIGHT_SECONDS) * 3) / TICK);
  let maxZ = 0, worst = 0, nights = 0, wallHits = 0;
  const wallHp = () => { let s = 0; for (let i = 0; i < g.hp.length; i++) if (g.grid[i] === S.T.WOOD_WALL) s += g.hp[i]; return s; };
  const startHp = wallHp();
  let wasNight = false;
  for (let k = 0; k < ticks; k++) {
    for (const p of [a, b]) {
      let near = null, nd = Infinity;
      for (const z of g.zombies) { const d = Math.hypot(z.x - p.x, z.y - p.y); if (d < nd) { nd = d; near = z; } }
      p.input.f = !!near && nd < 400;
      if (near) p.angle = Math.atan2(near.y - p.y, near.x - p.x);
    }
    const t0 = process.hrtime.bigint();
    g.tick(TICK);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    worst = Math.max(worst, ms);
    if (k % 20 === 0) JSON.parse(g.snapshot());
    maxZ = Math.max(maxZ, g.zombies.length);
    const night = S.isNight(g.hour);
    if (night && !wasNight) nights++;
    wasNight = night;
  }
  wallHits = startHp - wallHp();
  for (const z of g.zombies) assert.ok(isFinite(z.x) && isFinite(z.y), 'Zombie-Position gültig');
  assert.ok(g.day >= 4, `Tag ${g.day}`);
  assert.ok(nights >= 3, `Nächte: ${nights}`);
  assert.ok(maxZ > 20, `Zombies max: ${maxZ}`);
  assert.ok(g.kills > 0, `Kills: ${g.kills}`);
  console.log(`Simulation ok: Tag ${g.day}, max ${maxZ} Zombies, ${g.kills} Kills, Wandschaden ${Math.round(wallHits)}, Tode ${a.deaths + b.deaths}, langsamster Tick ${worst.toFixed(1)} ms`);
  assert.ok(worst < 50, 'Tick muss unter 50 ms bleiben');

  g.handle(a, { t: 'chat', m: '/neustart' });
  assert.strictEqual(g.day, 1);
  assert.strictEqual(g.zombies.length, 0);
}

async function network() {
  const port = 3900 + ((Math.random() * 90) | 0);
  const proc = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { env: Object.assign({}, process.env, { PORT: String(port) }), stdio: ['ignore', 'pipe', 'inherit'] });
  await new Promise((res) => proc.stdout.once('data', res));
  try {
    const html = await (await fetch(`http://localhost:${port}/`)).text();
    assert.ok(html.includes('ZOMBIE'), 'index.html wird ausgeliefert');
    const bot = (name) => new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://localhost:${port}/ws`);
      const got = { snaps: 0, welcome: null, meta: null };
      ws.onopen = () => ws.send(JSON.stringify({ t: 'join', name }));
      ws.onerror = reject;
      ws.onmessage = (e) => {
        const m = JSON.parse(e.data);
        if (m.t === 'welcome') got.welcome = m;
        if (m.t === 'meta') got.meta = m;
        if (m.t === 's') { got.snaps++; got.last = m; }
      };
      got.ws = ws;
      setTimeout(() => resolve(got), 300);
    });
    const [b1, b2] = await Promise.all([bot('Bot1'), bot('Bot2')]);
    assert.ok(b1.welcome && b2.welcome, 'welcome erhalten');
    assert.strictEqual(b1.welcome.grid.length, S.MAP * S.MAP);
    const me = b1.last.p.find((p) => p[0] === b1.welcome.id);
    // Bewegen, schießen, bauen
    for (let k = 0; k < 10; k++) {
      b1.ws.send(JSON.stringify({ t: 'i', x: me[1] + k * 4, y: me[2], a: 0, f: true, mx: me[1] + 100, my: me[2] }));
      await new Promise((r) => setTimeout(r, 40));
    }
    const ti = Math.floor(me[2] / S.TILE + 2) * S.MAP + Math.floor(me[1] / S.TILE);
    b1.ws.send(JSON.stringify({ t: 'build', i: ti, b: S.T.WOOD_WALL }));
    b1.ws.send(JSON.stringify({ t: 'chat', m: 'Hallo Team' }));
    b1.ws.send('kein json');
    await new Promise((r) => setTimeout(r, 400));
    const p2 = b2.last.p.find((p) => p[0] === b1.welcome.id);
    assert.ok(p2[1] > me[1], 'Bot2 sieht Bot1 laufen');
    assert.ok(b2.meta.players.length === 2, 'zwei Spieler in meta');
    assert.ok(b2.snaps > 10, `Snapshots: ${b2.snaps}`);
    console.log(`Netzwerk ok: ${b2.snaps} Snapshots, Bot1 bewegt von x=${me[1]} auf x=${p2[1]}, Munition ${b2.last.r.munition}`);
    b1.ws.close(); b2.ws.close();
  } finally {
    proc.kill();
  }
}

simulate();
network().then(() => console.log('Alle Tests bestanden.'), (e) => { console.error(e); process.exit(1); });
