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

To capture in M3. What is already known from AJProbe's first Forever file (2026-11-05, esES, read for M6; shapes only, names and numbers replaced):

| Event | Text as the game sent it |
|---|---|
| `CHAT_MSG_SYSTEM` | `<Name> se une al grupo.` / `<Name> deja el grupo.` / `Dejas el grupo.` / `Tu grupo se ha disuelto.` / `Has invitado a <Name> a unirse a tu grupo.` / `<Name> rechaza la invitación a tu grupo.` / `Has solicitado unirte al grupo de <Name>.` (plain text, no player link) |
| `CHAT_MSG_SYSTEM` | `Has aprendido un nuevo hechizo: \|cff71d5ff\|Hspell:ID:0\|h[Name (Rango N)]\|h\|r.` and `Has aprendido una nueva facultad: ...` (the esES word for an ability) |
| `GROUP_JOINED` / `GROUP_LEFT` | `(1, "Party-...")`: category 1 = home group. Fired when the group was **formed** (at the invitation, before anybody accepted), and `GROUP_LEFT` 4 s later when the invitation was refused. No names. The instance category (2) was not seen |
| `CHAT_MSG_COMBAT_FACTION_CHANGE` | `Tu reputación con <Faction> ha aumentado en N.` (Classic Era words it `... ha aumentado. (+N)`) |
| `CHAT_MSG_SKILL` | `Tu habilidad en <Skill> ha subido a N.` / `Has ganado la siguiente habilidad: <Skill>` |
| `CHAT_MSG_COMBAT_XP_GAIN` | `<Mob> muere, obtienes N experiencia.` / `Obtienes N experiencia.`, with ` (+N bonus de grupo)` or ` (+N bonus por grupo)` appended. No entry type uses it (user's choice) |
| `PLAYER_LEVEL_UP` | `level` = the new level (2 to 6 in the first session) |

Never captured: the sentence for a change of standing ("Eres ahora ... con ..."), the raid join and leave strings, the passive-ability string, anything from an instance group.


## QUEST_ACCEPTED on Forever (2026-11-05, AJProbe, T4a)

`a = { questID }`: a single argument, the quest ID (1470, 364), with the title the probe looked up (`title`). It is preceded by a `CHAT_MSG_SYSTEM` record in the same second (the "Misión aceptada" line). Classic Era's `(questLogIndex, questID)` is documented by Warcraft Wiki but has not been seen in a record. No `ERR_GUILD_*` message appears in any recorded file.

## Mounts and achievements on Forever (`/dump`, 2026-11-05, T4b)

- `/dump C_MountJournal and C_MountJournal.GetMountIDs` printed a function.
- `/dump C_MountJournal.GetMountInfoByID(C_MountJournal.GetMountIDs()[1])` printed 13 values: 1 "Carnero gris" (name), 2 `6777` (spellID), 3 `132248` (icon), 4 `false` (isActive), 5 `false` (isUsable), 6 `0` (sourceType), 7 `false` (isFavorite), 8 `true` (isFactionSpecific), 9 `1` (faction), 10 `false` (shouldHideOnChar), 11 `false` (**isCollected**; the character did not have this mount), 12 `21` (mountID), 13 `false` (isForDragonriding).
- `/dump GetAchievementInfo(6)` printed `empty result`. The global exists (a missing function would be an error), and 6 is not an achievement on this client. The order of the returns for a real achievement has not been seen.
- AJProbe's Forever file lists `ACHIEVEMENT_EARNED` as a registered event, with no record of one (no achievement was earned during capture).