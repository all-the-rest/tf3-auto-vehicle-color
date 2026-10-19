# AGENTS.todo.md — tf3-auto-vehicle-color

Protokoll der **offenen** Arbeit. Erledigtes wird gelöscht (Historie in
Git). „Verworfen" = nicht wieder einführen (die Begründung steht dort,
damit der nächste Agent den alten Stand nicht für gültig hält).

## Offen

- [ ] TODO: Einzel-Farbeimer im Fahrzeugfenster
      (`gui/entity_window/vehicle/vehicle_eow.script.tl:150`) ebenfalls
      beobachten? Der Command ist callback-los, der Hook sieht ihn
      deshalb nicht. Geltende Regel ist „manuelles Färben wird nicht
      synchron angekämpft" — der Eimer würde die Linienfarbe sofort
      zurücksetzen. Zu entscheiden (user), dann ggf.
      `makeEntitySetColorCmd` in `watch.CALLBACKLESS` aufnehmen, analog
      zum Replace (Loop-Sicherheit bleibt: Notify-Commands sind nicht
      watched und callback-los).

## Verworfen

- **Ankunfts-Fallback**: Commands während Engine-Events sind verboten
  (`BeginModification: Assertion '!m_betweenChanges' failed` → Fatal-Error
  pro Aufruf, Stutter bei 1277 Fahrzeugen). Stattdessen Einmal-Korrektur.
- **Tick-/N-Tick-Sweeps, `os.clock`-Throttles, Revision-Caches,
  `guiUpdate`-Polling**: verworfen, Rule 0.
- **Der GUI-Hook liest Engine-Komponenten**: tut er nicht; der frühere
  Fehlschlag war der camelCase-Key, nicht der GUI-State. Bridge über
  Scripting-Event ist bewiesen — nicht ohne Grund umbauen.
- **Erfundene APIs**: `game.interface.*`, `api.cmd.make.*`, Event-Namen
  `line.changed` / `api.cmd.SetLine` (in TF3 nicht vorhanden, 0 Treffer).
- **Umgekehrte Regel** (unanimous Fahrzeugfarbe → Linienfarbe),
  user-Entscheid 2026-10-07: widerspricht „Linienfarbe gewinnt immer".
  Manuelles Färben wird sofort überschrieben, also kann der Spieler nie
  Unanimität herstellen — die Regel hätte keinen Auslöser.
