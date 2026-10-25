# Zombie Base

2D-Coop-Survival aus der Vogelperspektive, inspiriert von *7 Days to Die*: Tagsüber sammelt ihr Rohstoffe und baut eine Basis, nachts greift die Horde an. Bis zu 8 Freunde spielen gemeinsam in derselben Welt im Browser.

## Starten

Voraussetzung: [Node.js](https://nodejs.org) ab Version 18. Weitere Pakete braucht es nicht.

```bash
npm start
```

Danach im Browser `http://localhost:3000` öffnen. Die Konsole zeigt außerdem die Adresse für Freunde im selben WLAN, z. B. `http://192.168.1.23:3000`.

Den Port ändert ihr so: `PORT=8080 npm start` (Windows PowerShell: `$env:PORT=8080; npm start`).

## Mit Freunden über das Internet spielen

Einer startet den Server, die anderen öffnen seine Adresse im Browser. Dafür gibt es drei Wege:

1. **Gleiches WLAN:** Die angezeigte `http://192.168.x.x:3000`-Adresse weitergeben. Fragt Windows beim ersten Start nach der Firewall, den Zugriff erlauben.
2. **Tunnel (am einfachsten übers Internet):** z. B. mit [Tailscale](https://tailscale.com) (alle installieren es, dann `http://<tailscale-ip>:3000`) oder einem öffentlichen Tunnel wie `cloudflared tunnel --url http://localhost:3000`. Den ausgegebenen Link verschickt ihr an eure Freunde.
3. **Port-Weiterleitung:** Im Router TCP-Port 3000 auf den PC weiterleiten und Freunden `http://<eure-öffentliche-IP>:3000` geben.

## Steuerung

| Taste | Aktion |
|---|---|
| WASD / Pfeiltasten | Bewegen |
| Maus | Zielen (die Taschenlampe leuchtet in Blickrichtung) |
| Linke Maustaste | Schießen / Abbauen / Bauen |
| 1 / 2 / 3, Mausrad | Pistole / Schrotflinte / Werkzeug |
| B | Baumodus an/aus: 1–7 wählt das Gebäude, Linksklick baut, Rechtsklick reißt ab (50 % zurück) |
| C | Werkbank |
| Q | Medkit benutzen |
| Tab | Spielerliste |
| Enter | Chat |
| H | Hilfe ein/aus |

## Spielprinzip

- **Tag (06:00–22:00, ca. 3,5 Minuten):** Mit dem Werkzeug Bäume fällen (Holz), Felsen abbauen (Stein), Autowracks zerlegen (Metall) und Kisten aufbrechen (Munition, Metall, Medkits). Einzelne Zombies streifen umher.
- **Nacht (22:00–06:00, 2 Minuten):** Die Horde kommt, und mit jeder Nacht wird sie größer. Ab Tag 2 gibt es Renner, ab Tag 3 Kolosse. Nachts sind alle Zombies schneller.
- **Blutmond:** Jede 7. Nacht kommt eine riesige Horde.
- **Zombies sind schlau:** Sie suchen den kürzesten Weg zu euch. Ist alles zugebaut, schlagen sie die schwächste Stelle der Mauer ein. Eine Steinwand hält also länger als eine Holzwand, und Zombies laufen um starke Mauern lieber herum.
- **Werkzeug repariert:** Ein Schlag auf ein beschädigtes Bauteil repariert es für 1 Material.
- **Teamlager:** Alle Rohstoffe und die Munition gehören dem ganzen Team. Geschütztürme verbrauchen ebenfalls Munition aus dem Lager.
- **Tod:** Nach 10 Sekunden steht ihr am Lagerfeuer in der Kartenmitte wieder auf.
- Mit dem Chat-Befehl `/neustart` beginnt eine neue Welt.

### Gebäude

| Gebäude | Kosten | Leben | Besonderheit |
|---|---|---|---|
| Holzwand | 6 Holz | 150 | |
| Steinwand | 6 Stein | 400 | |
| Metallwand | 6 Metall, 2 Stein | 900 | |
| Tor | 10 Holz | 220 | Spieler gehen durch, Zombies nicht |
| Stacheln | 4 Holz, 2 Metall | 100 | Verletzen und bremsen Zombies, begehbar |
| Geschützturm | 15 Metall, 10 Stein | 250 | Schießt automatisch, braucht Munition |
| Lampe | 4 Holz, 2 Metall | 80 | Licht in der Nacht |

## Technik

- `server.js`: HTTP-Server und Spielschleife mit 20 Ticks pro Sekunde. Der Server ist autoritativ (Zombies, Schaden, Bauen).
- `server/game.js`: Simulation. Die Zombies folgen einem Dijkstra-Flussfeld, in dem Wände je nach Lebenspunkten unterschiedlich viel „kosten“.
- `server/ws.js`: Eigener schlanker WebSocket-Server, deshalb ist kein `npm install` nötig.
- `public/`: Browser-Client mit Canvas. Die eigene Bewegung wird lokal vorhergesagt, andere Spieler und Zombies werden interpoliert. Die Sounds werden per Web Audio erzeugt.
- `public/shared.js`: Werte und Kollision, die Server und Client gemeinsam nutzen. Hier lässt sich das Balancing anpassen.

Test: `npm test` simuliert drei Spieltage und verbindet zwei Bots über das Netzwerk.
