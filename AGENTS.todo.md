# AGENTS.todo.md — tf3-auto-vehicle-color

Kurzes Protokoll der Entscheidungen und ihres Stands. `[x]` umgesetzt,
`[ ]` offen. „Verworfen" = nicht wieder einführen (die Begründung steht
dort, damit der nächste Agent den alten Stand nicht für gültig hält).

## Umgesetzt

- [x] Streng ereignisgetrieben, kein Polling (Rule 0): `update()` enthält
      nur die Subscription und die Einmal-Korrektur.
- [x] GUI-Hook beobachtet `api.cmd` (observe-only, Loop-sicher): Kauf,
      Zuweisung, Linienfarbe, Fahrzeugtausch.
- [x] GUI → Engine über `makeScriptingSendEventCmd`; der **Event-Name**
      muss abonniert sein (`events.lua` als einzige Quelle für id + Name).
- [x] `ComponentType`-Namen UPPER_SNAKE (`COLOR`, `TRANSPORT_VEHICLE`,
      `LINE`), abgesichert durch `sync.resolveComponentTypes`.
- [x] Depot-Fahrzeuge werden mitgefärbt (sonst nie „sofort nach Kauf").
- [x] Erstmaliges Färben, wenn das Fahrzeug noch keine Color-Komponente hat.
- [x] Kein Command während Engine-Events (sonst Fatal-Assertion + Stutter).
- [x] Einmalige Korrektur beim Session-Start (verifiziert: 1277/1277
      Fahrzeuge, 224 Linien), Marker im geteilten Script-State.
- [x] Keine stillen No-ops: jeder Fall nennt einen Grund.
- [x] Fahrzeugtausch wird beobachtet: `watch.CALLBACKLESS =
      { makeVehicleReplaceCmd = true }` (user-Entscheid 2026-10-08). Die
      Vanilla-GUI schickt den Replace callback-los
      (`vehicle_react_util.tl:407`), der Hook hängt nur dafür seinen
      eigenen Erfolgs-Callback an.
- [x] Fahrzeugtausch im Spiel gemessen (2026-10-08, Save 1 mit aktiver
      Mod): 52× `committed: makeVehicleReplaceCmd`, 52× Notify, 52×
      `recolored 1/1 via entity …` (`recolored-first-time`), 0 Fehlschläge,
      0 Assertions. Der Replace setzt die Color-Komponente zurück — genau
      der Fall, für den der Recolor da ist.

## Offen

- [ ] Einzelner Farbeimer im Fahrzeugfenster
      (`vehicle_eow.script.tl:150`, callback-los) wird bewusst NICHT
      beobachtet — manuelles Färben wird nicht synchron angekämpft
      (geltende Regel). Nur falls der User das ändern will.

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
