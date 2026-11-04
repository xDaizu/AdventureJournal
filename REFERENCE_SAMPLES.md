# Reference samples (M0)

What the game actually sends, captured with [AJProbe](../AJProbe/README.md). Compare against these when porting (M1–M3). In-game data wins over the docs.

## Classic Era 1.15.9 (build 70576, `esES`), 2026-11-04

Character Volgajin, Zandalar Tribe. Open world only (Durotar, Valle de los Retos): no group, no dungeon, no whisper, no blue loot yet.

### Environment

- `GetBuildInfo()`: `1.15.9`, `70576`, `Oct 22 2026`, `11509`. `WOW_PROJECT_ID` = `2` (`WOW_PROJECT_CLASSIC` exists, `WOW_PROJECT_CAMELOT` does not).
- **`issecretvalue` exists on Classic Era** and returned false for every value seen. The `issecretvalue ~= nil and issecretvalue(v)` guard is still correct.
- Present: `C_Item.GetItemInfo`, `GetItemInfo`, `C_Item.RequestLoadItemDataByID`, `C_AddOns.GetAddOnMetadata`, `Settings` (+ `RegisterVerticalLayoutCategory`, `RegisterCanvasLayoutCategory`), `UISpecialFrames`, `BackdropTemplateMixin`, `CreateScrollBoxListLinearView`, `ScrollUtil`, `C_EventUtils.IsEventValid`, `C_Map.GetBestMapForUnit`, `C_Timer.After`, `C_GameRules`, `C_DamageMeter`, `GetQuestLogTitle`, `GetNumQuestLogEntries`.
- **Missing:** `C_QuestLog.GetTitleForQuestID`, the global `GetAddOnMetadata`, `InterfaceOptions_AddCategory`.
- Events: all registered except **`MINIMAP_ZONE_CHANGED`** and **`LEARNED_SPELL_IN_TAB`** ("Attempt to register unknown event"). The modern `LEARNED_SPELL_IN_SKILL_LINE` exists. `ITEM_DATA_LOAD_RESULT`, `ENCOUNTER_START/END`, `BOSS_KILL`, `PLAYER_LEVEL_UP` all exist.

### Loot strings (`esES`)

| Global | Value |
|---|---|
| `LOOT_ITEM_SELF` | `Recibes botín: %s.` |
| `LOOT_ITEM_SELF_MULTIPLE` | `Recibes el botín: %sx%d.` |
| `LOOT_ITEM_PUSHED_SELF` | `Recibes: %s.` |
| `LOOT_ITEM_PUSHED_SELF_MULTIPLE` | `Has recibido: %sx%d` |
| `LOOT_ITEM` | `%s recibe el botín: %s.` |
| `LOOT_ITEM_MULTIPLE` | `%s recibe el botín: %sx%d.` |

### `CHAT_MSG_LOOT` (own loot)

```
arg1  = "Recibes botín: |cff9d9d9d|Hitem:7098::::::::1::::::::::|h[Colmillo astillado]|h|r."
arg5  = "Volgajin"   (player name, no realm)
arg11 = line ID (increments)
17 arguments in total
```

- Colour prefix is `|cffRRGGBB` (grey `9d9d9d`, white `ffffffff`). No `|cnIQ` form on Classic Era.
- AdventureJournal's current pattern `|c%x+|Hitem:.-|h%[.-%]|h|r` matches.
- `GetItemInfo` and `C_Item.GetItemInfo` return the same name, link and quality.
- Not captured yet: a group member's loot, a multiple-item message, a blue item.

### `QUEST_TURNED_IN`

- Payload: `questID, xpReward, moneyReward` → `4641, 40, 0`.
- `C_QuestLog.GetTitleForQuestID` is missing. A quest-log scan **at the event** finds the title ("Tu lugar en el mundo"). **1 s later the quest is gone from the log.** The title lookup must stay synchronous inside the handler.

### `PLAYER_ENTERING_WORLD`

- Fresh login: `isInitialLogin = true, isReloadingUi = false`. `GetRealZoneText()` returned **nil** at this point.
- `/reload`: `false, true`. Zone text was available.

### Other events

- `GOSSIP_SHOW`: arg1 nil. `UnitName("npc")` → `"Gornek"`, realm nil.
- `PLAYER_DEAD`: no arguments. Fired while `InCombatLockdown()` was true.
- `ZONE_CHANGED_NEW_AREA` fired once at login. `ZONE_CHANGED` fired on each subzone change. Neither has arguments.
- `PLAYER_ALIVE` also fires at login, not only after a resurrection. The M4b importer must not read it as "came back to life".

### Chat (`CHAT_MSG_SAY`, `CHAT_MSG_YELL`)

- Author (arg 2) includes the realm with no spaces: `Volgajin-ZandalarTribe`. Strip the realm for display.
- Language (arg 3) is localized: `Orco`.
- arg 12 is the author's GUID; it matched `UnitGUID("player")` for own lines.

### Exporter

Ran `ExportarDiario.py`'s `find_database` + `export_text` on the real file: it parsed correctly. WoW wrote accented characters as raw UTF-8 (no `\ddd` escapes), and the output is valid UTF-8.

## Forever 1.60.1

To capture in M3.
