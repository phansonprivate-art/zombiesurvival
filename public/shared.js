// Gemeinsame Konstanten und Logik für Server (require) und Client (<script>).
(function (root) {
  'use strict';

  const TILE = 32;
  const MAP = 128;

  const T = {
    EMPTY: 0,
    TREE: 1,
    ROCK: 2,
    SCRAP: 3,
    CRATE: 4,
    WOOD_WALL: 10,
    STONE_WALL: 11,
    METAL_WALL: 12,
    DOOR: 13,
    SPIKES: 14,
    TURRET: 15,
    LAMP: 16,
  };

  const RES_NAMES = { holz: 'Holz', stein: 'Stein', metall: 'Metall', munition: 'Munition', medkit: 'Medkits' };

  const TILES = {
    [T.TREE]: { name: 'Baum', hp: 100, res: 'holz', yield: 4, resource: true },
    [T.ROCK]: { name: 'Fels', hp: 120, res: 'stein', yield: 4, resource: true },
    [T.SCRAP]: { name: 'Autowrack', hp: 120, res: 'metall', yield: 3, resource: true },
    [T.CRATE]: { name: 'Kiste', hp: 30, loot: true },
    [T.WOOD_WALL]: { name: 'Holzwand', hp: 150, cost: { holz: 6 }, build: true },
    [T.STONE_WALL]: { name: 'Steinwand', hp: 400, cost: { stein: 6 }, build: true },
    [T.METAL_WALL]: { name: 'Metallwand', hp: 900, cost: { metall: 6, stein: 2 }, build: true },
    [T.DOOR]: { name: 'Tor', hp: 220, cost: { holz: 10 }, build: true, desc: 'Nur Spieler kommen durch' },
    [T.SPIKES]: { name: 'Stacheln', hp: 100, cost: { holz: 4, metall: 2 }, build: true, desc: 'Verletzen und bremsen Zombies' },
    [T.TURRET]: { name: 'Geschützturm', hp: 250, cost: { metall: 15, stein: 10 }, build: true, desc: 'Schießt automatisch, braucht Munition' },
    [T.LAMP]: { name: 'Lampe', hp: 80, cost: { holz: 4, metall: 2 }, build: true, desc: 'Licht in der Nacht' },
  };

  const BUILD_ORDER = [T.WOOD_WALL, T.STONE_WALL, T.METAL_WALL, T.DOOR, T.SPIKES, T.TURRET, T.LAMP];
  const BUILD_RANGE = 6; // in Kacheln

  const WEAPONS = [
    { id: 'pistol', name: 'Pistole', dmg: 26, cd: 0.28, ammo: 1, pellets: 1, spread: 0.03, range: 520 },
    { id: 'shotgun', name: 'Schrotflinte', dmg: 14, cd: 0.8, ammo: 2, pellets: 7, spread: 0.32, range: 280, locked: true },
    { id: 'tool', name: 'Werkzeug', dmg: 28, cd: 0.4, melee: true, range: 56 },
  ];

  const ZOMBIES = [
    { id: 'walker', name: 'Schlurfer', hp: 60, speed: 52, nightSpeed: 80, r: 12, dmg: 10, wallDmg: 14, atkCd: 1.0 },
    { id: 'runner', name: 'Renner', hp: 40, speed: 95, nightSpeed: 135, r: 11, dmg: 7, wallDmg: 7, atkCd: 0.7 },
    { id: 'brute', name: 'Koloss', hp: 320, speed: 38, nightSpeed: 55, r: 18, dmg: 28, wallDmg: 60, atkCd: 1.4 },
  ];

  const CRAFT = {
    ammo: { name: 'Munition x20', cost: { metall: 3 }, give: { munition: 20 } },
    medkit: { name: 'Medkit', cost: { metall: 3, holz: 2 }, give: { medkit: 1 } },
    shotgun: { name: 'Schrotflinte freischalten', cost: { metall: 25, holz: 10 }, unlock: 'shotgun' },
  };

  const PLAYER = { r: 12, speed: 170, hp: 100 };

  // Tageszeit: 06:00–22:00 Tag (DAY_SECONDS), 22:00–06:00 Nacht (NIGHT_SECONDS)
  const DAY_SECONDS = 210;
  const NIGHT_SECONDS = 120;
  const BLOOD_MOON_EVERY = 7;

  function isNight(hour) { return hour >= 22 || hour < 6; }
  function hourRate(hour) { return isNight(hour) ? 8 / NIGHT_SECONDS : 16 / DAY_SECONDS; }

  // Sekunden bis 22:00 (nur am Tag sinnvoll)
  function secondsUntilNight(hour) {
    if (isNight(hour)) return 0;
    return (22 - hour) / (16 / DAY_SECONDS);
  }

  function blocks(type, isPlayer) {
    if (type === T.EMPTY || type === T.SPIKES) return false;
    if (type === T.DOOR) return !isPlayer;
    return true;
  }

  function blocksBullets(type) {
    return type === T.TREE || type === T.ROCK || type === T.SCRAP || type === T.CRATE;
  }

  function canAfford(res, cost) {
    for (const k in cost) if ((res[k] || 0) < cost[k]) return false;
    return true;
  }

  // Kreis gegen Kachelraster: bewegen und aus festen Kacheln herausschieben.
  function moveCircle(grid, x, y, dx, dy, r, isPlayer) {
    x += dx;
    y += dy;
    for (let pass = 0; pass < 2; pass++) {
      const x0 = Math.floor((x - r) / TILE), x1 = Math.floor((x + r) / TILE);
      const y0 = Math.floor((y - r) / TILE), y1 = Math.floor((y + r) / TILE);
      for (let ty = y0; ty <= y1; ty++) {
        for (let tx = x0; tx <= x1; tx++) {
          if (tx < 0 || ty < 0 || tx >= MAP || ty >= MAP) continue;
          if (!blocks(grid[ty * MAP + tx], isPlayer)) continue;
          const rx = tx * TILE, ry = ty * TILE;
          const cx = Math.max(rx, Math.min(x, rx + TILE));
          const cy = Math.max(ry, Math.min(y, ry + TILE));
          let ox = x - cx, oy = y - cy;
          const d2 = ox * ox + oy * oy;
          if (d2 >= r * r) continue;
          if (d2 > 0.0001) {
            const d = Math.sqrt(d2);
            x += (ox / d) * (r - d);
            y += (oy / d) * (r - d);
          } else {
            // Mittelpunkt in der Kachel: entlang der kleinsten Überlappung raus
            const left = x - rx, right = rx + TILE - x, top = y - ry, bottom = ry + TILE - y;
            const m = Math.min(left, right, top, bottom);
            if (m === left) x = rx - r;
            else if (m === right) x = rx + TILE + r;
            else if (m === top) y = ry - r;
            else y = ry + TILE + r;
          }
        }
      }
    }
    const max = MAP * TILE;
    x = Math.max(r, Math.min(max - r, x));
    y = Math.max(r, Math.min(max - r, y));
    return { x, y };
  }

  const SHARED = {
    TILE, MAP, T, TILES, RES_NAMES, BUILD_ORDER, BUILD_RANGE, WEAPONS, ZOMBIES, CRAFT, PLAYER,
    DAY_SECONDS, NIGHT_SECONDS, BLOOD_MOON_EVERY,
    isNight, hourRate, secondsUntilNight, blocks, blocksBullets, canAfford, moveCircle,
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = SHARED;
  else root.SHARED = SHARED;
})(this);
