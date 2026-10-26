# AFTERLIGHT

Koop-Aufbau- und Survivalspiel in einer postapokalyptischen Welt, schräge Vogelperspektive, Godot 4 / GDScript.

**Stand: Meilenstein 1 (Phase 0 + 1).** Ein Spieler kann eine kleine Basis aufbauen: Rohstoffe sammeln, Gebäude platzieren, Produktion laufen lassen, Tag und Nacht erleben. Was fertig, getestet und offen ist, steht in [`docs/STATUS.md`](docs/STATUS.md).

## Starten

1. **Godot 4.4** (Standard-Version, nicht .NET) von https://godotengine.org/download installieren. Getestet mit 4.4.1.
2. Godot öffnen → **Importieren** → `afterlight/project.godot` auswählen.
3. **F5** startet das Spiel im Hauptmenü → **Neue Welt**.

Beim ersten Öffnen importiert Godot das Projekt einmalig, das dauert ein paar Sekunden.

### Als Windows-Programm exportieren

Im Editor: *Projekt → Exportieren → Windows Desktop → Projekt exportieren*. Godot fragt beim ersten Mal nach den Export-Vorlagen (*Editor → Export-Vorlagen verwalten → Herunterladen*). Die Vorlage `export_presets.cfg` ist schon eingerichtet und packt die Spieldaten (`data/*.json`) mit ein.

## Steuerung

| Taste | Aktion |
|---|---|
| **W A S D** | Spielfigur bewegen (relativ zur Kamera), **Shift** rennen |
| **Linksklick** auf Baum, Fels, Erz, Wrack, Kiste | hinlaufen und sammeln (läuft weiter, bis erschöpft) |
| **F** | nächstgelegenen Rohstoff sammeln |
| **Linksklick** auf Gebäude | Gebäudeinfo (Zustand, Produktion, Reparieren, Abreißen) |
| **B** | Baumenü |
| im Baumodus: **Linksklick** / **R** / **Rechtsklick** | bauen / drehen / abbrechen |
| **Mausrad** | zoomen |
| **Q / E** oder **rechte Maustaste ziehen** | Kamera drehen |
| **Pfeiltasten** oder **mittlere Maustaste ziehen** | Kamera verschieben |
| **Leertaste** | Kamera wieder auf die eigene Figur |
| **I** oder **Tab** | Lagerbestand |
| **M** | Karte |
| **Esc** | Fenster schließen / Pause / Einstellungen |

## Spielablauf (aktueller Stand)

- Ihr startet am **Zentralen Lager** auf einem Plateau. Rundherum: Wald, Felsen, Erzadern, Straßen mit Autowracks, Ruinen mit Versorgungskisten.
- **Sammeln:** Bäume → Holz, Felsen → Stein, Erz → Erz, Wracks → Metall (+ Chance auf Elektronik), Kisten → gemischte Beute.
- **Bauen** im Siedlungsgebiet (24 m um bestehende Gebäude). Die Kosten werden beim Baubeginn abgezogen, das Gebäude wächst im Gerüst. Abbrechen erstattet alles, Abreißen die Hälfte.
- **Produktionskette:** Holzfällerstation, Steinbruch und Erzabbau ernten Rohstoffe in ihrem Umkreis. Der Schmelzofen macht aus Erz und Holz Metall, die Werkstatt aus Holz und Metall Bauteile. Für Bauteile wird die Steinmauer freigeschaltet.
- **Lager** haben Grenzen. Ist ein Lager voll, pausiert die Produktion und das Gebäude zeigt den Grund an.
- **Tag/Nacht:** Ein Tag dauert 8 Minuten, eine Nacht 4 Minuten. Horden kommen erst mit Phase 3.

## Tests

```bash
godot --headless --path afterlight -s res://tests/run_tests.gd
```

Die Tests prüfen Datendefinitionen, Weltgenerierung, Bauen, Produktion, Sammeln, Zeit, Speicherformat, zwei Spieler am selben Lager, ein Leistungsbudget sowie Hauptmenü und Spielwelt als echte Szenen. Der Exit-Code ist 0, wenn alles besteht.

Screenshots zur Sichtprüfung (mit Fenster, nicht headless):

```bash
godot --path afterlight -s res://tests/screenshot.gd -- ./screenshots
```

## Projektstruktur

```
afterlight/
├── project.godot            Projekt, Autoloads (GameData, Session, Settings)
├── data/                    Spieldaten als JSON: Ressourcen, Gebäude, Welt/Knoten
├── scenes/                  main/main_menu, world/world, player/player
├── scripts/
│   ├── core/                Spiellogik ohne Szenen: GameState, Economy, WorldClock,
│   │                        BuildingSystem, ProductionSystem, GatherSystem, Session, Settings
│   ├── world/               Weltgenerator, Gelände, Modelle, Materialien, Licht, Darstellung
│   ├── player/              Spielfigur, Kamera
│   ├── building/            Platzierungsmodus
│   └── ui/                  Hauptmenü, HUD, Baumenü, Infofenster, Lager, Karte, Pause, Einstellungen
├── shaders/grass.gdshader   Gras mit Wind
├── tests/                   automatisierte Tests, Screenshot-Skript
└── docs/                    ARCHITECTURE.md, STATUS.md
```
