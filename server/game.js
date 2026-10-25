// Spielsimulation: Welt, Tag/Nacht, Zombies, Bauen, Kämpfen. Läuft nur auf dem Server.
'use strict';
const S = require('../public/shared');
const { TILE, MAP, T, TILES, WEAPONS, ZOMBIES, CRAFT, PLAYER } = S;

const TICK = 1 / 20;
const N = MAP * MAP;
const CENTER = (MAP / 2) * TILE;
const MAX_ZOMBIES = 260;
const RESPAWN_SECONDS = 10;
const COLORS = ['#4fc3f7', '#ffb74d', '#ba68c8', '#81c784', '#f06292', '#fff176', '#90a4ae', '#e57373'];

function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function valueNoise(rand, size) {
  const g = new Float32Array((size + 1) * (size + 1));
  for (let i = 0; i < g.length; i++) g[i] = rand();
  return (x, y) => {
    const x0 = Math.floor(x), y0 = Math.floor(y);
    const fx = x - x0, fy = y - y0;
    const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    const at = (a, b) => g[(((b % size) + size) % size) * (size + 1) + (((a % size) + size) % size)];
    const top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * sx;
    const bot = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * sx;
    return top + (bot - top) * sy;
  };
}

// Binärer Min-Heap für Dijkstra (typisierte Arrays, keine Allokationen pro Lauf)
class Heap {
  constructor(cap) {
    this.idx = new Int32Array(cap);
    this.pri = new Float32Array(cap);
    this.size = 0;
  }
  clear() { this.size = 0; }
  push(i, p) {
    const a = this.idx, b = this.pri;
    if (this.size >= a.length) return;
    let n = this.size++;
    while (n > 0) {
      const parent = (n - 1) >> 1;
      if (b[parent] <= p) break;
      a[n] = a[parent]; b[n] = b[parent];
      n = parent;
    }
    a[n] = i; b[n] = p;
  }
  pop() {
    const a = this.idx, b = this.pri;
    const top = a[0];
    this.lastP = b[0];
    const n0 = --this.size;
    if (n0 > 0) {
      const li = a[n0], lp = b[n0];
      let n = 0;
      for (;;) {
        const l = 2 * n + 1, r = l + 1;
        let m = n, mp = lp;
        if (l < n0 && b[l] < mp) { m = l; mp = b[l]; }
        if (r < n0 && b[r] < mp) { m = r; }
        if (m === n) break;
        a[n] = a[m]; b[n] = b[m];
        n = m;
      }
      a[n] = li; b[n] = lp;
    }
    return top;
  }
}

class Game {
  constructor(seed) {
    this.players = new Map();
    this.nextPlayerId = 1;
    this.reset(seed);
  }

  reset(seed) {
    this.seed = seed == null ? (Math.random() * 1e9) | 0 : seed;
    this.rand = rng(this.seed);
    this.grid = new Uint8Array(N);
    this.hp = new Float32Array(N);
    this.flow = new Float32Array(N).fill(Infinity);
    this.dirty = new Set();
    this.turrets = new Map(); // Kachelindex -> Abklingzeit
    this.zombies = [];
    this.nextZombieId = 1;
    this.res = { holz: 30, stein: 10, metall: 8, munition: 80, medkit: 1 };
    this.unlocks = { shotgun: false };
    this.hour = 8;
    this.day = 1;
    this.hordeLeft = 0;
    this.hordeTimer = 0;
    this.wanderTimer = 0;
    this.flowTimer = 0;
    this.regrowTimer = 0;
    this.kills = 0;
    this.fx = { tr: [], pp: [], ev: [] };
    this.messages = [];
    this.generate();
    for (const p of this.players.values()) this.respawn(p, true);
    this.fullSync = true;
  }

  // ---------- Welt ----------

  generate() {
    const rand = this.rand;
    const forest = valueNoise(rand, 16);
    const rocks = valueNoise(rand, 16);
    const c = MAP / 2;
    for (let y = 0; y < MAP; y++) {
      for (let x = 0; x < MAP; x++) {
        const d = Math.hypot(x - c, y - c);
        if (d < 8) continue;
        const i = y * MAP + x;
        const f = forest(x / 9, y / 9);
        const r = rocks(x / 7 + 50, y / 7 + 50);
        if (f > 0.64 && rand() < 0.6) this.setTile(i, T.TREE);
        else if (r > 0.74 && rand() < 0.55) this.setTile(i, T.ROCK);
        else if (rand() < 0.012) this.setTile(i, T.TREE);
        else if (rand() < 0.0035) this.setTile(i, T.SCRAP);
      }
    }
    // Startgebiet: ein paar Ressourcen in Reichweite
    const near = (t, count, dmin, dmax) => {
      for (let k = 0; k < count; k++) {
        const a = rand() * Math.PI * 2, d = dmin + rand() * (dmax - dmin);
        const i = Math.floor(c + Math.sin(a) * d) * MAP + Math.floor(c + Math.cos(a) * d);
        if (this.grid[i] === T.EMPTY) this.setTile(i, t);
      }
    };
    near(T.TREE, 14, 9, 15);
    near(T.ROCK, 6, 10, 16);
    near(T.SCRAP, 3, 10, 16);
    near(T.CRATE, 3, 9, 14);
    let crates = 0;
    while (crates < 45) {
      const x = (rand() * MAP) | 0, y = (rand() * MAP) | 0;
      if (Math.hypot(x - c, y - c) < 16) continue;
      const i = y * MAP + x;
      if (this.grid[i] !== T.EMPTY) continue;
      this.setTile(i, T.CRATE);
      crates++;
    }
    this.initialCounts = this.countTiles();
  }

  countTiles() {
    const c = {};
    for (let i = 0; i < N; i++) c[this.grid[i]] = (c[this.grid[i]] || 0) + 1;
    return c;
  }

  setTile(i, type, hp) {
    this.grid[i] = type;
    this.hp[i] = type === T.EMPTY ? 0 : hp != null ? hp : TILES[type].hp;
    if (type === T.TURRET) this.turrets.set(i, 0);
    else this.turrets.delete(i);
    this.dirty.add(i);
  }

  damageTile(i, amount) {
    if (this.grid[i] === T.EMPTY) return false;
    this.hp[i] -= amount;
    this.dirty.add(i);
    if (this.hp[i] <= 0) {
      const type = this.grid[i];
      this.setTile(i, T.EMPTY);
      if (TILES[type].build) this.fx.ev.push(['break', (i % MAP) * TILE + 16, ((i / MAP) | 0) * TILE + 16]);
      return true;
    }
    return false;
  }

  tileAt(x, y) {
    const tx = Math.floor(x / TILE), ty = Math.floor(y / TILE);
    if (tx < 0 || ty < 0 || tx >= MAP || ty >= MAP) return -1;
    return ty * MAP + tx;
  }

  regrow() {
    const counts = this.countTiles();
    const want = [[T.TREE, 8], [T.ROCK, 3], [T.SCRAP, 2], [T.CRATE, 2]];
    for (const [type, n] of want) {
      if ((counts[type] || 0) >= (this.initialCounts[type] || 0) * 0.85) continue;
      for (let k = 0, placed = 0; k < 60 && placed < n; k++) {
        const x = (this.rand() * MAP) | 0, y = (this.rand() * MAP) | 0;
        const i = y * MAP + x;
        if (this.grid[i] !== T.EMPTY) continue;
        if (Math.hypot(x - MAP / 2, y - MAP / 2) < 14) continue;
        let ok = true;
        for (const p of this.players.values()) if (Math.hypot(p.x - x * TILE, p.y - y * TILE) < 500) ok = false;
        if (!ok || this.nearStructure(x, y, 3)) continue;
        this.setTile(i, type);
        placed++;
      }
    }
  }

  nearStructure(tx, ty, r) {
    for (let y = ty - r; y <= ty + r; y++)
      for (let x = tx - r; x <= tx + r; x++) {
        if (x < 0 || y < 0 || x >= MAP || y >= MAP) continue;
        const t = this.grid[y * MAP + x];
        if (TILES[t] && TILES[t].build) return true;
      }
    return false;
  }

  // ---------- Spieler ----------

  addPlayer(conn, name, color) {
    if (this.players.size >= 8) return null;
    const id = this.nextPlayerId++;
    const used = new Set([...this.players.values()].map((p) => p.color));
    if (!/^#[0-9a-fA-F]{6}$/.test(color || '') || used.has(color)) color = COLORS.find((c) => !used.has(c)) || '#ffffff';
    const p = {
      id, conn, color,
      name: String(name || 'Überlebender').replace(/[<>]/g, '').trim().slice(0, 16) || 'Überlebender',
      x: CENTER, y: CENTER, angle: 0, hp: PLAYER.hp, dead: false, respawn: 0,
      input: { f: false, mx: CENTER, my: CENTER }, lastInput: Date.now(),
      slot: 0, cd: 0, lastHurt: 0, regen: 0, kills: 0, deaths: 0,
    };
    this.players.set(id, p);
    this.respawn(p, true);
    this.say(`${p.name} ist dem Spiel beigetreten.`);
    return p;
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    this.say(`${p.name} hat das Spiel verlassen.`);
  }

  respawn(p, initial) {
    for (let k = 0; k < 200; k++) {
      const a = this.rand() * Math.PI * 2, d = this.rand() * 3 * TILE;
      const x = CENTER + Math.cos(a) * d, y = CENTER + Math.sin(a) * d;
      const i = this.tileAt(x, y);
      if (i >= 0 && !S.blocks(this.grid[i], true)) {
        p.x = x; p.y = y;
        break;
      }
    }
    p.dead = false;
    p.hp = PLAYER.hp;
    p.respawn = 0;
    p.correct = true;
    if (!initial) this.say(`${p.name} ist wieder da.`);
  }

  hurtPlayer(p, dmg) {
    if (p.dead) return;
    p.hp -= dmg;
    p.lastHurt = this.time;
    this.fx.ev.push(['hurt', p.id]);
    if (p.hp <= 0) {
      p.hp = 0;
      p.dead = true;
      p.deaths++;
      p.respawn = RESPAWN_SECONDS;
      this.say(`${p.name} wurde von Zombies zerrissen!`);
    }
  }

  say(text) {
    this.messages.push(text);
  }

  // ---------- Eingaben vom Client ----------

  handle(p, msg) {
    if (!msg || typeof msg !== 'object') return;
    switch (msg.t) {
      case 'i': return this.onInput(p, msg);
      case 'slot': {
        const s = msg.s | 0;
        if (s < 0 || s >= WEAPONS.length) return;
        if (WEAPONS[s].locked && !this.unlocks[WEAPONS[s].id]) return;
        p.slot = s;
        return;
      }
      case 'build': return this.build(p, msg.i | 0, msg.b | 0);
      case 'demolish': return this.demolish(p, msg.i | 0);
      case 'craft': return this.craft(p, String(msg.c));
      case 'heal': return this.heal(p);
      case 'chat': return this.chat(p, String(msg.m || ''));
    }
  }

  onInput(p, m) {
    const now = Date.now();
    const elapsed = Math.min(0.5, (now - p.lastInput) / 1000);
    p.lastInput = now;
    if (typeof m.a === 'number' && isFinite(m.a)) p.angle = m.a;
    p.input.f = !!m.f;
    if (isFinite(m.mx) && isFinite(m.my)) { p.input.mx = +m.mx; p.input.my = +m.my; }
    if (p.dead || !isFinite(m.x) || !isFinite(m.y)) return;
    // Bewegung kommt vom Client (flüssig), der Server prüft Tempo und Kollision.
    let dx = m.x - p.x, dy = m.y - p.y;
    const dist = Math.hypot(dx, dy);
    const max = PLAYER.speed * elapsed * 1.35 + 12;
    if (dist > max) {
      dx *= max / dist; dy *= max / dist;
      p.correct = true;
    }
    const r = S.moveCircle(this.grid, p.x, p.y, dx, dy, PLAYER.r, true);
    if (Math.hypot(r.x - m.x, r.y - m.y) > 3) p.correct = true;
    p.x = r.x; p.y = r.y;
  }

  build(p, i, type) {
    if (p.dead || i < 0 || i >= N) return;
    const info = TILES[type];
    if (!info || !info.build) return;
    if (this.grid[i] !== T.EMPTY) return;
    const tx = i % MAP, ty = (i / MAP) | 0;
    const cx = tx * TILE + 16, cy = ty * TILE + 16;
    if (Math.hypot(cx - p.x, cy - p.y) > S.BUILD_RANGE * TILE) return;
    if (!S.canAfford(this.res, info.cost)) return this.pop(cx, cy, 'Zu wenig Material', '#ff8a80');
    // Nicht auf Spieler oder Zombies bauen (außer Stacheln, die sind begehbar)
    if (type !== T.SPIKES) {
      for (const q of this.players.values())
        if (!q.dead && this.circleInTile(q.x, q.y, PLAYER.r, tx, ty)) return;
      for (const z of this.zombies)
        if (this.circleInTile(z.x, z.y, ZOMBIES[z.type].r, tx, ty)) return;
    }
    for (const k in info.cost) this.res[k] -= info.cost[k];
    this.setTile(i, type);
    this.fx.ev.push(['build', cx, cy]);
  }

  circleInTile(x, y, r, tx, ty) {
    const cx = Math.max(tx * TILE, Math.min(x, tx * TILE + TILE));
    const cy = Math.max(ty * TILE, Math.min(y, ty * TILE + TILE));
    return (x - cx) ** 2 + (y - cy) ** 2 < r * r;
  }

  demolish(p, i) {
    if (p.dead || i < 0 || i >= N) return;
    const type = this.grid[i];
    const info = TILES[type];
    if (!info || !info.build) return;
    const cx = (i % MAP) * TILE + 16, cy = ((i / MAP) | 0) * TILE + 16;
    if (Math.hypot(cx - p.x, cy - p.y) > S.BUILD_RANGE * TILE) return;
    const frac = this.hp[i] / info.hp;
    const parts = [];
    for (const k in info.cost) {
      const back = Math.floor(info.cost[k] * 0.5 * frac);
      this.res[k] += back;
      if (back) parts.push(`+${back} ${S.RES_NAMES[k]}`);
    }
    this.setTile(i, T.EMPTY);
    this.pop(cx, cy, parts.join(' ') || 'abgerissen', '#cfd8dc');
  }

  craft(p, id) {
    const c = CRAFT[id];
    if (!c) return;
    if (c.unlock && this.unlocks[c.unlock]) return;
    if (!S.canAfford(this.res, c.cost)) return this.pop(p.x, p.y - 30, 'Zu wenig Material', '#ff8a80');
    for (const k in c.cost) this.res[k] -= c.cost[k];
    if (c.give) for (const k in c.give) this.res[k] += c.give[k];
    if (c.unlock) {
      this.unlocks[c.unlock] = true;
      this.say(`${p.name} hat die Schrotflinte gebaut! (Taste 2)`);
    }
    this.pop(p.x, p.y - 30, c.name, '#b9f6ca');
  }

  heal(p) {
    if (p.dead || this.res.medkit <= 0 || p.hp >= PLAYER.hp) return;
    this.res.medkit--;
    p.hp = Math.min(PLAYER.hp, p.hp + 55);
    this.pop(p.x, p.y - 30, '+55 HP', '#69f0ae');
  }

  chat(p, text) {
    text = text.replace(/[<>]/g, '').trim().slice(0, 140);
    if (!text) return;
    if (text === '/neustart') {
      this.say(`${p.name} hat die Welt neu gestartet.`);
      this.reset();
      return;
    }
    // Nur zum Testen: ZB_DEBUG=1 node server.js, dann z. B. "/zeit 21.9"
    const zeit = /^\/zeit (\d+(\.\d+)?)$/.exec(text);
    if (zeit && process.env.ZB_DEBUG) {
      this.hour = Math.min(23.99, +zeit[1]);
      return;
    }
    this.say(`${p.name}: ${text}`);
  }

  pop(x, y, text, color) {
    this.fx.pp.push([x | 0, y | 0, text, color || '#fff']);
  }

  // ---------- Kampf ----------

  fire(p) {
    const w = WEAPONS[p.slot];
    if (w.melee) return this.swing(p, w);
    if (this.res.munition < w.ammo) {
      p.cd = 0.5;
      this.pop(p.x, p.y - 30, 'Keine Munition! (C: Werkbank)', '#ff8a80');
      return;
    }
    this.res.munition -= w.ammo;
    p.cd = w.cd;
    for (let k = 0; k < w.pellets; k++) {
      const a = p.angle + (this.rand() - 0.5) * 2 * w.spread;
      this.hitscan(p, p.x + Math.cos(p.angle) * 14, p.y + Math.sin(p.angle) * 14, a, w.range, w.dmg);
    }
    this.fx.ev.push(['shot', p.x | 0, p.y | 0, w.id]);
    // Schüsse sind laut
    for (const z of this.zombies) if (!z.aggro && Math.hypot(z.x - p.x, z.y - p.y) < 520) z.aggro = true;
  }

  hitscan(owner, x, y, a, range, dmg) {
    const dx = Math.cos(a), dy = Math.sin(a);
    let best = range, hit = null;
    // erste Kachel, die Kugeln aufhält
    for (let t = 0; t < range; t += 8) {
      const i = this.tileAt(x + dx * t, y + dy * t);
      if (i < 0) { best = t; break; }
      if (S.blocksBullets(this.grid[i])) { best = t; break; }
    }
    for (const z of this.zombies) {
      const r = ZOMBIES[z.type].r;
      const ox = z.x - x, oy = z.y - y;
      const proj = ox * dx + oy * dy;
      if (proj < 0 || proj > best) continue;
      const perp2 = ox * ox + oy * oy - proj * proj;
      if (perp2 > r * r) continue;
      const t = proj - Math.sqrt(r * r - perp2);
      if (t < best) { best = Math.max(0, t); hit = z; }
    }
    this.fx.tr.push([x | 0, y | 0, (x + dx * best) | 0, (y + dy * best) | 0]);
    if (hit) this.hurtZombie(hit, dmg, owner, dx * 6, dy * 6);
  }

  swing(p, w) {
    p.cd = w.cd;
    const ax = Math.cos(p.angle), ay = Math.sin(p.angle);
    let hits = 0;
    for (const z of this.zombies) {
      const ox = z.x - p.x, oy = z.y - p.y;
      const d = Math.hypot(ox, oy);
      if (d > w.range + ZOMBIES[z.type].r) continue;
      if (d > 1 && (ox * ax + oy * ay) / d < 0.35) continue;
      this.hurtZombie(z, w.dmg, p, (ox / (d || 1)) * 22, (oy / (d || 1)) * 22);
      if (++hits >= 3) break;
    }
    this.fx.ev.push(['swing', p.id]);
    if (hits) return;
    const i = this.tileAt(p.input.mx, p.input.my);
    if (i < 0) return;
    const type = this.grid[i];
    if (type === T.EMPTY) return;
    const cx = (i % MAP) * TILE + 16, cy = ((i / MAP) | 0) * TILE + 16;
    if (Math.hypot(cx - p.x, cy - p.y) > 76) return;
    const info = TILES[type];
    if (info.resource) {
      const broke = this.damageTile(i, 25);
      const amount = broke ? info.yield + 2 : info.yield;
      this.res[info.res] += amount;
      this.pop(cx, cy - 10, `+${amount} ${S.RES_NAMES[info.res]}`, '#ffe082');
      this.fx.ev.push(['chop', cx, cy, type]);
    } else if (info.loot) {
      if (this.damageTile(i, 15)) this.loot(cx, cy);
      else this.fx.ev.push(['chop', cx, cy, type]);
    } else if (info.build) {
      // Werkzeug repariert eigene Bauten
      if (this.hp[i] >= info.hp) return this.pop(cx, cy - 10, 'Unbeschädigt', '#cfd8dc');
      const mat = Object.keys(info.cost)[0];
      if (this.res[mat] < 1) return this.pop(cx, cy - 10, `Kein ${S.RES_NAMES[mat]}`, '#ff8a80');
      this.res[mat] -= 1;
      this.hp[i] = Math.min(info.hp, this.hp[i] + Math.max(25, info.hp * 0.12));
      this.dirty.add(i);
      this.pop(cx, cy - 10, 'Repariert', '#80d8ff');
      this.fx.ev.push(['repair', cx, cy]);
    }
  }

  loot(x, y) {
    const r = this.rand;
    const got = {
      munition: 10 + ((r() * 25) | 0),
      metall: 2 + ((r() * 6) | 0),
      holz: r() < 0.5 ? 3 + ((r() * 6) | 0) : 0,
      medkit: r() < 0.3 ? 1 : 0,
    };
    const parts = [];
    for (const k in got) if (got[k]) { this.res[k] += got[k]; parts.push(`+${got[k]} ${S.RES_NAMES[k]}`); }
    this.pop(x, y - 10, parts.join('  '), '#ffd54f');
    this.fx.ev.push(['loot', x, y]);
  }

  hurtZombie(z, dmg, owner, kx, ky) {
    z.hp -= dmg;
    z.aggro = true;
    if (kx || ky) {
      const r = S.moveCircle(this.grid, z.x, z.y, kx, ky, ZOMBIES[z.type].r, false);
      z.x = r.x; z.y = r.y;
    }
    if (z.hp <= 0 && !z.dead) {
      z.dead = true;
      this.kills++;
      if (owner) owner.kills++;
      this.fx.ev.push(['die', z.x | 0, z.y | 0, z.type]);
      // Chance auf Beute
      if (this.rand() < 0.25) {
        const n = 3 + ((this.rand() * 6) | 0);
        this.res.munition += n;
        this.pop(z.x, z.y - 10, `+${n} Munition`, '#ffd54f');
      }
    }
  }

  // ---------- Zombies ----------

  tileCost(i) {
    const t = this.grid[i];
    if (t === T.EMPTY) return 1;
    if (t === T.SPIKES) return 5;
    const info = TILES[t];
    if (!info.build) return Infinity; // Bäume, Felsen, Kisten: drumherum laufen
    return 1 + this.hp[i] / 8; // Wände: je stärker, desto eher wird ein Umweg gesucht
  }

  computeFlow() {
    const dist = this.flow;
    dist.fill(Infinity);
    const heap = this.heap || (this.heap = new Heap(N * 8));
    heap.clear();
    for (const p of this.players.values()) {
      if (p.dead) continue;
      const i = this.tileAt(p.x, p.y);
      if (i < 0) continue;
      dist[i] = 0;
      heap.push(i, 0);
    }
    const cost = this.costBuf || (this.costBuf = new Float32Array(N));
    for (let i = 0; i < N; i++) cost[i] = this.tileCost(i);
    const passable = (i) => cost[i] <= 5;
    while (heap.size) {
      const u = heap.pop();
      const du = heap.lastP;
      if (du > dist[u]) continue;
      const ux = u % MAP, uy = (u / MAP) | 0;
      const cu = du === 0 ? 1 : cost[u];
      for (let oy = -1; oy <= 1; oy++) {
        for (let ox = -1; ox <= 1; ox++) {
          if (!ox && !oy) continue;
          const vx = ux + ox, vy = uy + oy;
          if (vx < 0 || vy < 0 || vx >= MAP || vy >= MAP) continue;
          const v = vy * MAP + vx;
          if (cost[v] === Infinity) continue;
          let step = cu;
          if (ox && oy) {
            // diagonal nur, wenn beide Nachbarn frei sind (keine Ecken schneiden)
            if (!passable(uy * MAP + vx) || !passable(vy * MAP + ux) || !passable(u) || !passable(v)) continue;
            step *= 1.414;
          }
          const nd = du + step;
          if (nd < dist[v]) {
            dist[v] = nd;
            heap.push(v, nd);
          }
        }
      }
    }
  }

  spawnZombie(type, aggro, minD, maxD, around) {
    if (this.zombies.length >= MAX_ZOMBIES) return false;
    for (let k = 0; k < 30; k++) {
      const a = this.rand() * Math.PI * 2;
      const d = minD + this.rand() * (maxD - minD);
      const x = around.x + Math.cos(a) * d, y = around.y + Math.sin(a) * d;
      const i = this.tileAt(x, y);
      if (i < 0 || this.grid[i] !== T.EMPTY) continue;
      if (aggro && this.flow[i] === Infinity) continue;
      let tooClose = false;
      for (const p of this.players.values()) if (!p.dead && Math.hypot(p.x - x, p.y - y) < minD * 0.8) tooClose = true;
      if (tooClose) continue;
      const info = ZOMBIES[type];
      this.zombies.push({
        id: this.nextZombieId++, type, x, y, hp: info.hp, aggro, wander: !aggro,
        atkCd: 0, wt: 0, wx: 0, wy: 0, angle: 0, dead: false,
      });
      return true;
    }
    return false;
  }

  pickType(night) {
    const day = this.day;
    const blood = night && day % S.BLOOD_MOON_EVERY === 0;
    const r = this.rand();
    const bruteChance = day >= 3 ? Math.min(0.18, 0.04 + day * 0.012) * (blood ? 1.6 : 1) : 0;
    const runnerChance = day >= 2 ? Math.min(0.4, 0.12 + day * 0.03) * (night ? 1 : 0.4) : 0;
    if (r < bruteChance) return 2;
    if (r < bruteChance + runnerChance) return 1;
    return 0;
  }

  alivePlayers() {
    return [...this.players.values()].filter((p) => !p.dead);
  }

  spawning(dt) {
    const alive = this.alivePlayers();
    if (!alive.length) return;
    const night = S.isNight(this.hour);
    if (night && this.hordeLeft > 0) {
      this.hordeTimer -= dt;
      if (this.hordeTimer <= 0) {
        const blood = this.day % S.BLOOD_MOON_EVERY === 0;
        this.hordeTimer = blood ? 0.35 : 0.7;
        const burst = 1 + ((this.rand() * (blood ? 4 : 3)) | 0);
        for (let k = 0; k < burst && this.hordeLeft > 0; k++) {
          const target = alive[(this.rand() * alive.length) | 0];
          if (this.spawnZombie(this.pickType(true), true, 750, 1100, target)) this.hordeLeft--;
        }
      }
    }
    // Herumirrende Zombies am Tag (und nachts zusätzlich)
    this.wanderTimer -= dt;
    if (this.wanderTimer <= 0) {
      this.wanderTimer = 1.5;
      const target = Math.min(40, 6 + this.day * 3) * Math.min(2, 0.6 + alive.length * 0.4);
      const wanderers = this.zombies.reduce((n, z) => n + (z.wander ? 1 : 0), 0);
      if (wanderers < target) {
        const p = alive[(this.rand() * alive.length) | 0];
        this.spawnZombie(this.pickType(night), false, 650, 1000, p);
      }
    }
  }

  updateZombies(dt) {
    const night = S.isNight(this.hour);
    const alive = this.alivePlayers();
    // Räumliches Raster für Abstoßung
    const cell = new Map();
    for (const z of this.zombies) {
      const k = ((z.x / 40) | 0) * 1000 + ((z.y / 40) | 0);
      let a = cell.get(k);
      if (!a) cell.set(k, (a = []));
      a.push(z);
    }
    for (const z of this.zombies) {
      if (z.dead) continue;
      const info = ZOMBIES[z.type];
      z.atkCd -= dt;
      let speed = night ? info.nightSpeed : info.speed;
      const ci = this.tileAt(z.x, z.y);
      if (ci >= 0 && this.grid[ci] === T.SPIKES) {
        speed *= 0.45;
        z.hp -= 18 * dt;
        this.damageTile(ci, 3 * dt);
        if (z.hp <= 0) { this.hurtZombie(z, 0, null); continue; }
      }
      let near = null, nd = Infinity;
      for (const p of alive) {
        const d = Math.hypot(p.x - z.x, p.y - z.y);
        if (d < nd) { nd = d; near = p; }
      }
      if (!z.aggro && near && nd < (night ? 420 : 300)) z.aggro = true;
      if (z.aggro && !near) z.aggro = false;

      let mx = 0, my = 0;
      if (!z.aggro) {
        z.wt -= dt;
        if (z.wt <= 0) {
          z.wt = 2 + this.rand() * 4;
          const a = this.rand() * Math.PI * 2;
          const still = this.rand() < 0.35;
          z.wx = still ? 0 : Math.cos(a); z.wy = still ? 0 : Math.sin(a);
        }
        mx = z.wx * speed * 0.4; my = z.wy * speed * 0.4;
      } else {
        const flowHere = ci >= 0 ? this.flow[ci] : Infinity;
        if (nd < 56 || flowHere < 1.5 || flowHere === Infinity) {
          // direkt auf den Spieler zu
          mx = ((near.x - z.x) / (nd || 1)) * speed;
          my = ((near.y - z.y) / (nd || 1)) * speed;
        } else {
          const cx = ci % MAP, cy = (ci / MAP) | 0;
          let best = -1, bv = flowHere;
          for (let oy = -1; oy <= 1; oy++)
            for (let ox = -1; ox <= 1; ox++) {
              if (!ox && !oy) continue;
              const nx = cx + ox, ny = cy + oy;
              if (nx < 0 || ny < 0 || nx >= MAP || ny >= MAP) continue;
              const ni = ny * MAP + nx;
              if (ox && oy && (S.blocks(this.grid[cy * MAP + nx], false) || S.blocks(this.grid[ny * MAP + cx], false))) continue;
              if (this.flow[ni] < bv) { bv = this.flow[ni]; best = ni; }
            }
          if (best >= 0) {
            const tx = (best % MAP) * TILE + 16, ty = ((best / MAP) | 0) * TILE + 16;
            if (S.blocks(this.grid[best], false)) {
              // Wand im Weg: hinlaufen und draufhauen
              const bx = best % MAP, by = (best / MAP) | 0;
              const ex = Math.max(bx * TILE, Math.min(z.x, bx * TILE + TILE));
              const ey = Math.max(by * TILE, Math.min(z.y, by * TILE + TILE));
              if (Math.hypot(z.x - ex, z.y - ey) < info.r + 5) {
                if (z.atkCd <= 0) {
                  z.atkCd = info.atkCd;
                  this.damageTile(best, info.wallDmg);
                  this.fx.ev.push(['bash', tx, ty]);
                }
                z.angle = Math.atan2(ty - z.y, tx - z.x);
              } else {
                const d = Math.hypot(tx - z.x, ty - z.y) || 1;
                mx = ((tx - z.x) / d) * speed; my = ((ty - z.y) / d) * speed;
              }
            } else {
              const d = Math.hypot(tx - z.x, ty - z.y) || 1;
              mx = ((tx - z.x) / d) * speed; my = ((ty - z.y) / d) * speed;
            }
          }
        }
        if (near && nd < info.r + PLAYER.r + 6 && z.atkCd <= 0) {
          z.atkCd = info.atkCd;
          this.hurtPlayer(near, info.dmg);
        }
      }

      // Abstoßung von anderen Zombies
      const kx = (z.x / 40) | 0, ky = (z.y / 40) | 0;
      for (let ox = -1; ox <= 1; ox++)
        for (let oy = -1; oy <= 1; oy++) {
          const a = cell.get((kx + ox) * 1000 + ky + oy);
          if (!a) continue;
          for (const o of a) {
            if (o === z) continue;
            const dx = z.x - o.x, dy = z.y - o.y;
            const rr = info.r + ZOMBIES[o.type].r;
            const d2 = dx * dx + dy * dy;
            if (d2 > 0 && d2 < rr * rr) {
              const d = Math.sqrt(d2);
              const push = ((rr - d) / d) * 0.5 / dt * 0.5;
              mx += dx * push; my += dy * push;
            }
          }
        }
      // nicht in Spieler hineinlaufen
      if (near) {
        const dx = z.x - near.x, dy = z.y - near.y, rr = info.r + PLAYER.r;
        const d = Math.hypot(dx, dy);
        if (d > 0 && d < rr) { mx += (dx / d) * (rr - d) / dt; my += (dy / d) * (rr - d) / dt; }
      }

      if (mx || my) {
        const ms = Math.hypot(mx, my), cap = speed * 2;
        if (ms > cap) { mx *= cap / ms; my *= cap / ms; }
        const r = S.moveCircle(this.grid, z.x, z.y, mx * dt, my * dt, info.r, false);
        z.x = r.x; z.y = r.y;
        if (z.aggro || ms > 1) z.angle = Math.atan2(my, mx);
      }
    }
    // Tote und weit entfernte Wanderer entfernen
    this.zombies = this.zombies.filter((z) => {
      if (z.dead) return false;
      if (z.wander && !z.aggro) {
        for (const p of alive) if (Math.hypot(p.x - z.x, p.y - z.y) < 1700) return true;
        return false;
      }
      return true;
    });
  }

  updateTurrets(dt) {
    for (const [i, cd] of this.turrets) {
      const ncd = cd - dt;
      if (ncd > 0) { this.turrets.set(i, ncd); continue; }
      const x = (i % MAP) * TILE + 16, y = ((i / MAP) | 0) * TILE + 16;
      let best = null, bd = 300;
      for (const z of this.zombies) {
        const d = Math.hypot(z.x - x, z.y - y);
        if (d < bd) { bd = d; best = z; }
      }
      if (!best) { this.turrets.set(i, 0.2); continue; }
      if (this.res.munition <= 0) { this.turrets.set(i, 1); continue; }
      this.res.munition--;
      this.turrets.set(i, 0.45);
      const a = Math.atan2(best.y - y, best.x - x);
      this.hitscanTurret(x, y, a, best);
    }
  }

  hitscanTurret(x, y, a, target) {
    this.fx.tr.push([x | 0, y | 0, target.x | 0, target.y | 0, 1]);
    this.hurtZombie(target, 20, null, Math.cos(a) * 4, Math.sin(a) * 4);
  }

  // ---------- Zeit ----------

  updateTime(dt) {
    const before = this.hour;
    this.hour += S.hourRate(this.hour) * dt;
    if (this.hour >= 24) this.hour -= 24;
    if (before < 22 && this.hour >= 22) {
      const blood = this.day % S.BLOOD_MOON_EVERY === 0;
      const players = Math.max(1, this.alivePlayers().length);
      this.hordeLeft = Math.round((10 + this.day * 7) * (0.7 + players * 0.3) * (blood ? 2.5 : 1));
      this.hordeTimer = 2;
      this.say(blood ? `BLUTMOND! Nacht ${this.day}: Eine riesige Horde kommt!` : `Nacht ${this.day} bricht herein. Die Horde kommt!`);
      this.fx.ev.push(['night', blood ? 1 : 0]);
    }
    if (before < 6 && this.hour >= 6) {
      this.day++;
      this.hordeLeft = 0;
      this.say(`Tag ${this.day}. Ihr habt die Nacht überlebt!`);
      this.fx.ev.push(['dawn']);
      // Horden-Zombies verlieren am Morgen das Interesse
      for (const z of this.zombies) if (!z.wander) { z.wander = true; z.aggro = this.rand() < 0.5; }
    }
  }

  // ---------- Haupt-Tick ----------

  tick(dt) {
    this.time = (this.time || 0) + dt;
    this.updateTime(dt);
    for (const p of this.players.values()) {
      if (p.dead) {
        p.respawn -= dt;
        if (p.respawn <= 0) this.respawn(p);
        continue;
      }
      p.cd -= dt;
      if (p.input.f && p.cd <= 0) this.fire(p);
      if (this.time - p.lastHurt > 6 && p.hp < PLAYER.hp) p.hp = Math.min(PLAYER.hp, p.hp + 2 * dt);
    }
    this.flowTimer -= dt;
    if (this.flowTimer <= 0) {
      this.flowTimer = 0.4;
      this.computeFlow();
    }
    this.spawning(dt);
    this.updateZombies(dt);
    this.updateTurrets(dt);
    this.regrowTimer -= dt;
    if (this.regrowTimer <= 0) {
      this.regrowTimer = 25;
      this.regrow();
    }
  }

  welcome(p) {
    return JSON.stringify({
      t: 'welcome', id: p.id, seed: this.seed,
      grid: Array.from(this.grid), hp: Array.from(this.hp, (v) => Math.ceil(v)),
    });
  }

  snapshot() {
    const tc = [];
    for (const i of this.dirty) tc.push([i, this.grid[i], Math.ceil(this.hp[i])]);
    this.dirty.clear();
    const snap = {
      t: 's',
      h: Math.round(this.hour * 1000) / 1000,
      d: this.day,
      hl: this.hordeLeft,
      k: this.kills,
      r: this.res,
      u: this.unlocks,
      p: [...this.players.values()].map((p) => [
        p.id, Math.round(p.x), Math.round(p.y), Math.round(p.angle * 100) / 100,
        Math.ceil(p.hp), p.dead ? 1 : 0, p.slot, Math.ceil(p.respawn), p.input.f ? 1 : 0,
      ]),
      z: this.zombies.map((z) => [
        z.id, Math.round(z.x), Math.round(z.y), z.type,
        Math.max(0, Math.round((z.hp / ZOMBIES[z.type].hp) * 100)), Math.round(z.angle * 10) / 10, z.aggro ? 1 : 0,
      ]),
    };
    if (tc.length) snap.tc = tc;
    if (this.fx.tr.length) snap.tr = this.fx.tr;
    if (this.fx.pp.length) snap.pp = this.fx.pp;
    if (this.fx.ev.length) snap.ev = this.fx.ev;
    if (this.messages.length) snap.m = this.messages;
    this.fx = { tr: [], pp: [], ev: [] };
    this.messages = [];
    return JSON.stringify(snap);
  }

  meta() {
    return JSON.stringify({
      t: 'meta',
      players: [...this.players.values()].map((p) => ({ id: p.id, name: p.name, color: p.color, kills: p.kills, deaths: p.deaths })),
    });
  }
}

module.exports = { Game, TICK };
