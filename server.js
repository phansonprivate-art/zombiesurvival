// Startpunkt: HTTP-Server für den Client + WebSocket für das Coop-Spiel.
'use strict';
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { handleUpgrade } = require('./server/ws');
const { Game, TICK } = require('./server/game');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC = path.join(__dirname, 'public');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml' };

const server = http.createServer((req, res) => {
  const url = decodeURIComponent((req.url || '/').split('?')[0]);
  const file = path.normalize(path.join(PUBLIC, url === '/' ? 'index.html' : url));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Nicht gefunden'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
});

const game = new Game();
const clients = new Set();

server.on('upgrade', (req, socket) => {
  const conn = handleUpgrade(req, socket);
  if (!conn) return;
  const client = { conn, player: null };
  clients.add(client);
  conn.on('message', (text) => {
    let msg;
    try { msg = JSON.parse(text); } catch (e) { return; }
    if (!client.player) {
      if (msg.t !== 'join') return;
      const p = game.addPlayer(conn, msg.name, msg.color);
      if (!p) {
        conn.send(JSON.stringify({ t: 'full' }));
        return conn.close();
      }
      client.player = p;
      conn.send(game.welcome(p));
      broadcastMeta();
      return;
    }
    game.handle(client.player, msg);
  });
  conn.on('close', () => {
    clients.delete(client);
    if (client.player) {
      game.removePlayer(client.player.id);
      broadcastMeta();
    }
  });
});

function broadcastMeta() {
  const m = game.meta();
  for (const c of clients) if (c.player) c.conn.send(m);
}

let last = process.hrtime.bigint();
let acc = 0;
let metaTimer = 0;
setInterval(() => {
  const now = process.hrtime.bigint();
  acc += Number(now - last) / 1e9;
  last = now;
  if (acc > 0.25) acc = 0.25;
  let ticked = false;
  while (acc >= TICK) {
    acc -= TICK;
    game.tick(TICK);
    ticked = true;
  }
  if (!ticked) return;
  if (game.fullSync) {
    game.fullSync = false;
    game.dirty.clear();
    for (const c of clients) if (c.player) c.conn.send(game.welcome(c.player));
  }
  const snap = game.snapshot();
  for (const c of clients) {
    if (!c.player) continue;
    const p = c.player;
    if (p.correct) {
      p.correct = false;
      c.conn.send(JSON.stringify({ t: 'pos', x: p.x, y: p.y }));
    }
    c.conn.send(snap, true);
  }
  metaTimer += TICK;
  if (metaTimer > 1) { metaTimer = 0; broadcastMeta(); }
}, 1000 * TICK / 2);

server.listen(PORT, () => {
  console.log('\n  ZOMBIE BASE läuft!\n');
  console.log(`  Auf diesem PC:      http://localhost:${PORT}`);
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) {
      if (a.family === 'IPv4' && !a.internal) console.log(`  Freunde im WLAN:    http://${a.address}:${PORT}`);
    }
  }
  console.log('\n  Freunde über das Internet: siehe README.md (Port-Weiterleitung oder Tunnel).\n');
});
