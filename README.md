# AdventureJournal ("Diario de Aventuras")

Developer documentation. Players get the Spanish guide in [LEEME.txt](LEEME.txt).

AdventureJournal is a narrative diary that runs automatically. It listens to game events (quests, bosses, deaths, loot, places, NPCs, whispers), turns each one into a short first-person paragraph in Spanish, and saves the paragraphs per character, grouped into *jornadas* (one jornada per login). Players read the diary in a book-style window in game, and an external Python script can export it to a `.txt` file.

- Original author: ChemaE. Released version: `1.1.0-Era`. In development: `1.2.0-dev` (dual-client port, see the [roadmap](ROADMAP.md)).
- UI language: Spanish only, hard-coded (no localization layer).

## Supported clients

**This addon must work on both WoW Forever and WoW Classic Era from one codebase.** It is the one exception to the workspace rule "target the Mainline API only" in [CLAUDE.md](../CLAUDE.md).

| Client | Version (local) | Interface | Game type | API family | Install folder | Status |
|---|---|---|---|---|---|---|
| **WoW Forever** | 1.60.1.70755 | `16001` | `forever` (alias `camelot`) | Mainline (Midnight 12.x), with secret values | `_forever_` | **Not ported yet.** Loads through a provisional TOC since 2026-11-04; expect errors inside dungeons (see [Roadmap](#roadmap)) |
| **WoW Classic Era** | 1.15.9.70576 | `11509` | `vanilla` | Classic | `_classic_era_` | Works. Smoke-tested in game 2026-11-04; known bugs in the [bug log](ROADMAP.md#bug-log) |

Retail (Midnight), Anniversary/TBC and MoP Classic are **not** targets. The addon should not load on them.

All changes must keep both clients working. A change that fixes Forever and breaks Classic Era, or the other way round, is a regression.

## Files

| File | Purpose |
|---|---|
| `AdventureJournal_Vanilla.toc` | Manifest for Classic Era (`## Interface: 11509`). See [TOC strategy](#toc-strategy). |
| `AdventureJournal_Forever.toc` | Manifest for Forever (`16001`), same file list, plus `IconTexture` and `Category`. |
| `Compat.lua` | Client detection (`ns.IS_FOREVER`, `ns.IS_CLASSIC_ERA`), `ns.IsSecret`, `ns.SafeString`, and **every** API call that differs between clients (`ns.GetPlace`, `ns.GetQuestTitle`, `ns.GetItemInfoSafe`, `ns.UnitNameSafe`, `ns.RegisterEventSafe`, ...). Other files only call these wrappers. |
| `Database.lua` | `ns.EnsureDatabase()`, `ns.SCHEMA_VERSION`, and (from M4) migrations. Caches the table as `ns.DB`. |
| `Narrative.lua` | Moods and Spanish prose templates: `ns.ChooseMood`, `ns.ComposeEntry`. |
| `Events.lua` | Event registration and handlers (one function per event), `ns.AddEntry`, session start/end. |
| `UI.lua` | The book window: `ns.ToggleUI`, `ns.OpenAtDay`, `ns.SelectDay`, `ns.RefreshUI`. |
| `Commands.lua` | Slash commands, the key-binding globals, `AdventureJournal_ToggleUI`. |
| `Bindings.xml` | Key binding action `ADVENTUREJOURNAL_TOGGLE`, which calls the global `AdventureJournal_ToggleUI()`. |
| `ExportarDiario.py` / `.bat` | Out-of-game exporter: parses the SavedVariables file and writes `Diario_<Character>.txt`. |
| `LEEME.txt` | Player guide in Spanish (install, commands, export). Still describes Classic Era only. |
| `README.md` | This file. |
| `ROADMAP.md` | Milestone plan, backlog, bug-fix process and bug log. |
| `REFERENCE_SAMPLES.md` | Raw event payloads and API availability observed in game (captured with [AJProbe](../AJProbe/README.md)). |

## How it works

### Lifecycle

1. `ADDON_LOADED` (own name): `EnsureDatabase()` creates or normalises `AdventureJournalDB`.
2. `PLAYER_LOGIN`: `StartSession()` increments `currentDay` and creates a new jornada. A `/reload` also fires `PLAYER_LOGIN`, so it also starts a new jornada (known issue).
3. Gameplay events: each one calls `AddEntry(type, text, extra)`. This builds an entry, generates its prose, adds it to the current jornada, refreshes the UI if it is open, and prints a line to chat.
4. `PLAYER_LOGOUT`: stores `endedAt` on the current jornada.

### Logged events

| Entry type | Source events | Notes |
|---|---|---|
| `QUEST` | `QUEST_TURNED_IN` | Repeats of the same quest ID within 3 s are ignored. The title comes from `C_QuestLog.GetTitleForQuestID`, falling back to the quest log, then to the quest ID. |
| `BOSS` | `BOSS_KILL`, `ENCOUNTER_END` (`success == 1`) | Repeats of the same name within 5 s are ignored, because both events can fire for one kill. |
| `DEATH` | `PLAYER_DEAD` | |
| `LOOT` | `CHAT_MSG_LOOT`, plus `GET_ITEM_INFO_RECEIVED` for items not yet cached | Only quality ≥ 3 (rare or better). Parses the first item link in the message. Currently also logs group members' loot. |
| `DISCOVERY` | `ZONE_CHANGED*`, `MINIMAP_ZONE_CHANGED` | Fires whenever "subzone, zone" changes. This includes places the player has already visited. |
| `NPC` | `GOSSIP_SHOW` | Uses `UnitName("npc")`. Repeats of the same NPC within 20 s are ignored. |
| `CHAT` | `CHAT_MSG_WHISPER` | Stores the **sender name only**, never the message text. This stays the default. Storing conversation text is planned as an **opt-in, off by default** RP feature ([ROADMAP M4b](ROADMAP.md#m4b-backfill-from-ajprobe-and-rp-conversations--m)). |

Events are registered through `pcall`, so a missing event on one client does not stop the addon from loading.

### Prose

`ChooseMood(type)` returns a fixed mood for `DEATH`, `BOSS`, `LOOT` and `DISCOVERY`, and a random one from `MOODS` for the other types. `ComposeEntry(entry)` fills a Spanish template for the entry type. `QUEST` has three variants, chosen with `seed % 3`. The finished prose is stored in the entry, so the text does not change when it is read later.

### SavedVariables schema (`SavedVariablesPerCharacter: AdventureJournalDB`)

```lua
AdventureJournalDB = {
  version    = 1,
  currentDay = <number>,          -- index of the latest jornada
  days = {
    [n] = {
      startedAt = "YYYY-MM-DD HH:MM:SS",
      endedAt   = "YYYY-MM-DD HH:MM:SS", -- set on PLAYER_LOGOUT, may be missing after a crash
      dateLabel = "DD/MM/YYYY",
      events = {
        {
          type, text, prose,           -- type is QUEST|BOSS|DEATH|LOOT|DISCOVERY|NPC|CHAT
          place, zone, subZone,
          time = "HH:MM:SS", timestamp = <epoch>,
          characterProfile, contextualTone, seed,
          -- type-specific extras:
          questID,                     -- QUEST
          itemID, itemLink, itemQuality -- LOOT
        },
      },
    },
  },
}
```

Each client keeps its own `WTF` folder (`_forever_\WTF\...` and `_classic_era_\WTF\...`). Diaries are **not shared** between Forever and Classic Era characters. The schema itself must stay identical on both clients, so the exporter and any future migration code work on either one. If the schema changes, bump `version` and migrate in `EnsureDatabase()`.

### UI and commands

- `AdventureJournalBookFrame` is an open book: the jornada index on the left (newest first), the selected jornada's prose on the right, and previous/next buttons. It is created on first use.
- Slash commands: `/diario` or `/journal` (toggle), `/diario hoy` (latest jornada), `/diario anterior` (the one before it).
- Key binding: "Diario de Aventuras → Abrir / cerrar el diario". There is no default key.

## Dual-client compatibility

### TOC strategy

Ship **one TOC per client**, each listing the same Lua files:

```
AdventureJournal/
├── AdventureJournal_Vanilla.toc   ## Interface: 11509   (Classic Era)
├── AdventureJournal_Forever.toc   ## Interface: 16001   (WoW Forever)
└── ...
```

- Each client picks its own suffixed TOC. There is no plain `AdventureJournal.toc`, so other clients (retail, TBC, MoP) load nothing. See [docs/toc-and-detection.md](../docs/toc-and-detection.md).
- Neither TOC lists `Bindings.xml`: the client loads it by itself, and listing it logs `Unrecognized XML: Binding` (observed, bug #10).
- With no `_Mainline`/`_Standard` TOC and no plain `.toc`, retail does not load the addon.
- With separate TOCs, each interface number can be bumped on its own when either client patches.
- A single TOC with `## Interface: 16001, 11509` is an alternative, but Classic Era's support for multi-interface TOCs has not been checked on this machine. Use separate TOCs unless that is confirmed in game.
- Both TOCs must declare `## SavedVariablesPerCharacter: AdventureJournalDB`. The Forever TOC can also add `IconTexture`, `Category` and `AddonCompartmentFunc` (the function must be global).

### Coding rules for shared code

1. **Detect features, not clients.** Check that an API exists before calling it (`if C_Item and C_Item.GetItemInfo then ...`), and keep a fallback. Use `WOW_PROJECT_ID` only when behaviour really has to differ:
   ```lua
   local _, _, _, toc = GetBuildInfo()
   ns.IS_CLASSIC_ERA = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
   ns.IS_FOREVER = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
                   or (toc > 16000 and toc < 20000)
   ```
2. **Guard every external value against secrets.** `issecretvalue` exists on Forever, and also on Classic Era 1.15.9, where it always returns false (observed in M0). The wrapper below is still needed, in case a client lacks the function:
   ```lua
   local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
   ```
   On Forever, unit names, chat messages and chat senders can arrive as secrets inside instances. Check `IsSecret` **before** any comparison, `string.match`, `tonumber`, `#` or table-key use. Replace secrets with a neutral fallback or skip the entry, and never pass a secret to `AddEntry` (secrets are saved as `nil`).
3. **Use only APIs that exist on both clients, or wrap them.** Put client-specific code in small helper functions (for example `GetItemQuality`, `GetQuestTitle`) so the event handlers stay the same on both clients.
4. **Item links differ.** Classic Era colours links with `|cffRRGGBB`. Recent Mainline builds may use quality tags such as `|cnIQ4:`. Match the link body only (`|Hitem:.-|h%[.-%]|h`), never the colour prefix. The exporter's `clean()` must strip both forms.
5. **Lua 5.1 on both clients.** No `goto`, no `//`, no `utf8`.
6. **No combat automation.** The addon only records what happened; keep it that way (workspace rule 6).

### APIs used, by client

Entries marked "verify" have not been checked in game. Confirm them with `/dump` or `/api` and update this table. Classic Era entries marked "observed" were checked in M0 ([REFERENCE_SAMPLES.md](REFERENCE_SAMPLES.md)).

| Need | Classic Era 1.15.9 | Forever 1.60.1 |
|---|---|---|
| Item quality / link | Both `C_Item.GetItemInfo` and `GetItemInfo` exist and agree (observed) | `C_Item.GetItemInfo` (the global `GetItemInfo` may be missing) |
| Item cache callback | `GET_ITEM_INFO_RECEIVED`; `ITEM_DATA_LOAD_RESULT` also exists (observed) | `GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT` (verify) |
| Quest title | `C_QuestLog.GetTitleForQuestID` is **missing**. `GetQuestLogTitle` loop works, but only synchronously inside `QUEST_TURNED_IN` (observed) | `C_QuestLog.GetTitleForQuestID` |
| Boss kill | `BOSS_KILL`, `ENCOUNTER_END` | Same. Payload may be secret during encounters (verify) |
| NPC name | `UnitName("npc")` | Same. **Can be secret in instances** |
| Loot / whisper text | Plain strings. Links use `\|cffRRGGBB` (observed for loot) | **Secret inside instances** |
| Zone text | `GetRealZoneText`, `GetSubZoneText`. `GetRealZoneText()` is nil at `PLAYER_LOGIN` on a fresh login (observed). `MINIMAP_ZONE_CHANGED` does not exist | Same |
| Frames | `BackdropTemplate`, `UIPanel*Template` | Same |
| Textures and glyphs | `Interface\QuestFrame\QuestBG` (not checked yet). `◀`/`▶` render as **empty squares** (observed) | Verify that both still render on the modern client |
| Options panel (future) | `Settings` API exists; `InterfaceOptions_AddCategory` is missing (observed) | `Settings` API |

## Development and testing

Link the repo folder into **both** clients with directory junctions (PowerShell, no admin rights needed):

```powershell
foreach ($flavor in "_forever_", "_classic_era_") {
  New-Item -ItemType Junction `
    -Path   "D:\Games\Battle.net\World of Warcraft\$flavor\Interface\AddOns\AdventureJournal" `
    -Target "D:\Projects\wow-addons\AdventureJournal"
}
```

Before any in-game test, run the local checks (Lua 5.1 syntax, and a scripted session against stubbed WoW globals, compared with the accepted reports). See [tools/README.md](../tools/README.md):

```
cd tools && npm test
```

A deliberate behaviour change needs `npm run update-expected`, and the diff of `tools/expected/` should show exactly that change.

Test checklist before calling a change done:

- [ ] Loads with no Lua errors on **Classic Era** and on **Forever** (`/console scriptErrors 1`).
- [ ] Not shown as "out of date" on either client.
- [ ] On each client: turn in a quest, open an NPC gossip window, change subzone, die, and loot a blue item. Each one produces an entry.
- [ ] On Forever, **inside a dungeon**: talk to an NPC, receive a whisper, see loot messages, and kill a boss. No errors, and no `nil` entries after `/reload`.
- [ ] The book UI opens, scrolls and pages on both clients. Textures and arrows render.
- [ ] The exporter reads SavedVariables from both `WTF` folders.

## Exporter

`ExportarDiario.bat` runs `py -3 ExportarDiario.py`, which opens a file picker. Select the character's `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\AdventureJournal.lua` from either client. It writes `Diario_<Character>.txt` next to that file. Close the game first, because WoW only writes SavedVariables on logout or `/reload`. The parser is a minimal Lua-table reader. It handles what WoW's serialiser writes, but it is not a full Lua parser.

## Roadmap

The milestone plan (M0 Classic Era baseline → M7 release 1.2.0), the backlog, the bug-fix process and the bug log are in [ROADMAP.md](ROADMAP.md).
