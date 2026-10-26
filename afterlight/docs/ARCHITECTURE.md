# Architektur

## Grundsatz: Logik und Darstellung sind getrennt

```
 Eingabe (Maus/Tastatur)                     Darstellung (3D, HUD)
        │                                            ▲
        ▼                                            │ Ereignisse
 Session.submit(aktion) ──► GameState.apply_action ──┤ (building_added, stock_changed, …)
                            GameState.tick(dt)  ─────┘
```

- **`GameState`** (`scripts/core/game_state.gd`) ist der vollständige, autoritative Spielzustand einer Welt: Zeit, Lager, Gebäude, Rohstoffknoten, Spieler. Er hat keine Szenenknoten und ist dadurch ohne Grafik testbar.
- **Regeln** liegen in zustandslosen Systemen mit statischen Funktionen: `BuildingSystem` (Platzieren, Bau, Abriss, Reparatur, Schaden), `ProductionSystem` (Ernte- und Umwandlungsgebäude), `GatherSystem` (Sammeln durch Spieler). `Economy` hält den gemeinsamen Bestand, `WorldClock` die Weltzeit.
- **Jede Zustandsänderung** erzeugt ein Ereignis. Die **`Session`** (Autoload) reicht es als Signal `state_event` weiter. Die Welt-Szene (`world.gd`) und das HUD reagieren nur auf diese Ereignisse und verändern den Zustand nie direkt.
- **Spieleraktionen** sind Dictionaries wie `{"type": "build", "def": "storage", "cell": [x, y], "rot": 1}`. Sie werden immer im `GameState` geprüft: Kosten, Belegung, Gefälle, Siedlungsgebiet, Reichweite und Abklingzeit. Clientangaben gelten nie ungeprüft, die Reichweite beim Sammeln etwa wird mit der Spielerposition im Zustand gemessen.

## Warum so? (Koop ab Phase 5)

Der Host-basierte Koop braucht genau diese Trennung:

- Der **Host** besitzt den `GameState` und führt `tick()` aus.
- **Clients** schicken ihre Aktionen per RPC an `Session.submit()` auf dem Host. Der Host prüft sie mit denselben Funktionen wie im Einzelspieler.
- Die **Ereignisse** aus `take_events()` verteilt der Host an alle Clients. Deren Darstellung bleibt unverändert, weil sie heute schon nur auf Ereignisse reagiert.
- **Kameras** (`CameraRig`) sind rein lokal und werden nie synchronisiert. So kann keine Kamera die eines anderen Spielers verändern.

Dass Ressourcen nicht doppelt ausgegeben werden, ist schon jetzt getestet (`test_two_players_cannot_overspend`): zwei Spieler am selben Zustand und mit demselben Bestand.

## Daten statt Code

Alle Gebäude, Ressourcen und Rohstoffknoten sind in `data/*.json` definiert und werden von `GameData` beim Start geladen und geprüft: unbekannte Ressourcen in Kosten, unbekannte Kategorien, kaputte Freischalt-Verweise. Ein neues Gebäude braucht einen JSON-Eintrag und ein Modell in `ModelFactory.building()`.

Felder einer Gebäudedefinition: `id, name, category, description, model, footprint, cost, build_time, health, repair_cost_factor, placement{buildable, unique, max_slope}, storage{capacity_bonus}, production, power, unlock{buildings[]}, passable_for_players`.

Die Felder `power` (Strom) und `unlock.research` (Forschung) sind vorgesehen und werden mit Phase 2 und Phase 6 ausgewertet.

JSON statt Godot-`.tres` wurde gewählt, weil die Dateien lesbar und diff-freundlich sind und sich gleich als Speicher- und Netzwerkformat eignen. Ein Test prüft sie bei jedem Lauf.

## Welt

- `WorldGenerator.generate(seed)` erzeugt Höhen (Plateau in der Mitte, Hügel zum Rand), zwei Straßen, Ruinen, Wracks, Kisten, Wälder, Felsen und Erzadern. Gleicher Seed ergibt die gleiche Welt, das ist per Prüfsumme getestet.
- Die Karte ist 72 × 72 Kacheln groß (2 m pro Kachel, also 144 m × 144 m), mit einem Höhenraster von 1 m.
- Gespeichert werden nur Seed und Änderungen: Restmengen der Rohstoffknoten, Gebäude, Lager, Zeit und Spieler. Das Gelände wird beim Laden aus dem Seed neu erzeugt.

## Speicherformat (vorbereitet für Phase 4)

`GameState.to_dict()` / `from_dict()` mit `schema: 1`. Ein unbekanntes Schema wird abgelehnt. Der Roundtrip über JSON ist getestet. Phase 4 ergänzt den Speicher-Service: `user://worlds/<id>/`, temporäre Datei mit anschließendem Umbenennen, Autosave und Weltauswahl.

## Darstellung

- **Art-Set:** Alle Modelle sind prozedural aus stilisierten Grundformen gebaut (`ModelFactory`): Stämme, Satteldächer, unregelmäßige Felsen, Ruinen mit abgebrochenen Wänden. Materialien kommen zentral aus `Palette`, Meshes werden zwischengespeichert und geteilt. Externe Assets mit Lizenzfragen gibt es nicht.
- **Gelände:** Höhenmesh mit Vertexfarben (Gras, trockenes Gras, Erde, Straße, Fels am Hang), dazu HeightMapShape3D als Kollision.
- **Gras und Büsche:** MultiMesh mit wenigen Draw-Calls für tausende Büschel. Das Gras hat einen Wind-Shader.
- **Licht:** `DayNight` steuert Sonne, Mond, Himmel, Nebel und Sättigung nach der Weltzeit. Fenster, Laternen und Schmelzofen leuchten nachts warm.
- **Verdeckung:** Objekte zwischen Kamera und Spielfigur werden halbtransparent (Strahltest alle 0,15 s).

## Kollisionsebenen

| Ebene | Wert | Inhalt |
|---|---|---|
| 1 | 1 | Gelände |
| 2 | 2 | feste Hindernisse (Gebäude, Bäume, Felsen, Ruinen) – Spieler kollidiert |
| 3 | 4 | Auswahl per Mausklick |
| 4 | 8 | nur für Gegner fest (Torflügel), vorbereitet für Phase 3 |

## Performance (gemessen)

- Simulationsschritt mit 41 Gebäuden: **0,04 ms** (Ziel < 1 ms), siehe `tests/test_perf.gd`
- Weltgenerierung: etwa 0,3 s; Aufbau der Welt-Szene: etwa 0,4 s
- Darstellung der Basis aus mittlerer Höhe: etwa 700 Draw-Calls und 4 300 Objekte pro Bild

Die Bildrate auf echter Hardware ist noch nicht gemessen, weil die Testumgebung in Software rendert. Wenn die Draw-Calls zum Problem werden, sind die Bäume der erste Kandidat für MultiMesh.
