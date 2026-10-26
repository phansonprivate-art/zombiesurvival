# Status

## Meilenstein 1 – Phase 0 + 1

### Implementiert und automatisiert getestet

| Funktion | Nachweis |
|---|---|
| Projekt öffnet und importiert fehlerfrei (Godot 4.4.1) | `godot --import` ohne Fehler/Warnungen |
| Hauptmenü mit 3D-Hintergrund, nicht fertige Punkte als „Phase X“ gekennzeichnet | `test_main_menu` |
| Neue Welt mit Name und Seed | `test_world_gameplay`, `test_start_state` |
| Reproduzierbare Weltgenerierung (Gelände, Straßen, Ruinen, Wald, Fels, Erz, Wracks, Kisten) | `test_world_is_reproducible` |
| Spielfigur steht auf dem Gelände, läuft mit WASD | `test_world_gameplay` |
| Eigene Kamera: zoomen, drehen, verschieben, Grenzen, bleibt über dem Gelände | `test_world_gameplay` (Zoom, Höhe) |
| Sammeln mit Reichweite, Abklingzeit, Erschöpfung der Knoten | `test_gather`, `test_world_gameplay` |
| Datengetriebene Gebäude (10 Typen in 3 Kategorien) | `test_data_valid` |
| Platzieren: Raster, Drehen, Überschneidung, Gefälle, Kartengrenze, Siedlungsgebiet, Kosten | `test_build_*`, `test_rotation_footprint` |
| Bauzeit, Abbrechen (volle Erstattung), Abreißen (50 %) | `test_build_place_and_complete`, `test_cancel_and_demolish_refund` |
| Gebäudegesundheit, Schaden, Reparaturkosten, Zerstörung entfernt Funktion | `test_repair` |
| Produktion: Ernte im Umkreis, Umwandlung, Lager voll / fehlende Rohstoffe | `test_lumber_production_and_storage_full`, `test_production_chain` |
| Produktionskette Erz → Metall → Bauteile → Steinmauer (Freischaltung) | `test_production_chain` |
| Lagerkapazität (Grundwert + Lagergebäude) | `test_build_place_and_complete` |
| Weltzeit mit Tagen und Nächten | `test_clock` |
| Pause hält die Weltzeit an | `test_world_gameplay` |
| Zwei Spieler am selben Zustand geben Ressourcen nicht doppelt aus | `test_two_players_cannot_overspend` |
| Speicherformat mit Schema-Version, JSON-Roundtrip | `test_save_roundtrip` |
| Leistungsbudget der Simulation | `test_perf` (0,04 ms / Schritt bei 41 Gebäuden) |

### Implementiert, per Screenshot (Forward+, Software-Vulkan) geprüft

Baumodus mit grün/roter Vorschau und Erntereichweite, Infofenster, Lagerfenster, Karte, Tag/Dämmerung/Nacht, warmes Licht in Gebäuden, Rauch, Verdeckungs-Transparenz, Ruinen, Wracks, Gras mit Wind.

### Nicht geprüft

- **Bildrate auf echter Hardware:** In dieser Umgebung wird in Software gerendert, deshalb wurde keine FPS-Zahl gemessen.
- **Bedienung mit echter Maus/Tastatur in einem Fenster:** Die Eingaben werden in Tests simuliert, also Aktionen, Mausrad und Platzierung über den BuildController. Ein manueller Spieltest unter Windows steht noch aus.

### Bekannte Einschränkungen

- **Kein Speichern/Laden in der Oberfläche:** Das kommt mit Phase 4. Das Format existiert schon und ist getestet. „Zum Hauptmenü“ warnt deshalb, dass die Welt verloren geht.
- **Kein Koop:** Kommt mit Phase 5. Die Architektur ist vorbereitet (Aktionen, Ereignisse, lokale Kameras), eine Netzwerkverbindung gibt es aber noch nicht. **Die Koop-Freigabe ist offen.**
- **Strom, Landwirtschaft, Nahrung, Wasser, Kraftstoff:** Kommen mit Phase 2. Die Ressourcen sind definiert und im Lagerfenster als „Phase 2“ gekennzeichnet.
- **Keine Gegner und Horden:** Kommen mit Phase 3. Nächte sind bisher nur dunkel. Tor und Mauern blockieren schon, und die Kollisionsebene „nur für Gegner“ ist vorbereitet.
- Keine Audiospur.
- Kein automatisches Nachwachsen von Bäumen. Die Karte hat aber gut 1 000 Rohstoffknoten.
- Der Klick auf einen Rohstoff lässt die Figur geradeaus hinlaufen, ohne Wegfindung. Ist sie blockiert, bricht sie mit „Weg blockiert“ ab.

## Nächster Schritt: Phase 2 – Produktion und Strom

1. **Stromnetz (logisch):** `PowerSystem` berechnet pro Tick Erzeugung, Bedarf und Batteriestand. Verbraucher bekommen eine Priorität und werden bei Mangel abgeschaltet (Status `no_power`). Das Feld `power` in `buildings.json` wird dafür ausgewertet.
2. **Gebäude:** Kraftstoffgenerator (verbraucht Kraftstoff), Solaranlage (Leistung nach Tageszeit aus der `WorldClock`), Batteriespeicher, Scheinwerfer als erster Verbraucher.
3. **Landwirtschaft:** Feld mit 2–3 Pflanzen, Wachstumsphasen im `GameState`, Wasserbedarf, Ernte ergibt Nahrung. Wasser kommt aus einem Brunnen bzw. einer Wasserpumpe.
4. **Produktionsübersicht** (Taste P) und eine Strombilanz im HUD.
5. Tests für Strommangel, Batterie, Solarleistung bei Nacht und Wachstum über lange Zeiträume.
