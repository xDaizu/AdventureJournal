# AdventureJournal ("Diario de Aventuras")

Developer documentation. Players get the Spanish guide in [LEEME.txt](LEEME.txt).

AdventureJournal is a narrative diary that runs automatically. It listens to game events (quests, bosses, deaths, loot, places, NPCs, whispers), turns each one into a short first-person paragraph in Spanish, and saves the paragraphs per character, grouped into *jornadas* (one jornada per login). Players read the diary in a book-style window in game, and an external Python script can export it to a `.txt` file.

- Original author: ChemaE. Released version: `1.1.0-Era`. In development: `1.2.0-dev` (dual-client port, see the [roadmap](ROADMAP.md)). Milestone state: M0–M2, M4, M4b (backfill from AJProbe, opt-in RP conversations) and M5 (options, mood in the book, ScrollBox index, Forever addon-menu entry) are tested in game on Classic Era and tagged; the M4b import and live party capture have also run on real Forever data. M3 (the rest of the Forever checks) is in progress.
- UI language: Spanish only, hard-coded (no localization layer).

## Supported clients

**This addon must work on both WoW Forever and WoW Classic Era from one codebase.** It is the one exception to the workspace rule "target the Mainline API only" in [CLAUDE.md](../CLAUDE.md).

| Client | Version (local) | Interface | Game type | API family | Install folder | Status |
|---|---|---|---|---|---|---|
| **WoW Forever** | 1.60.1.70755 | `16001` | `forever` (alias `camelot`) | Mainline (Midnight 12.x), with secret values | `_forever_` | Secret guards written in M2 but **not verified in game** (launch is 2026-11-05; checked in M3). First thing to run there: `/diario diag` |
| **WoW Classic Era** | 1.15.9.70576 | `11509` | `vanilla` | Classic | `_classic_era_` | Works. Smoke-tested in game 2026-11-04 (M0, and again after the M1 restructure); known bugs in the [bug log](ROADMAP.md#bug-log) |

Retail (Midnight), Anniversary/TBC and MoP Classic are **not** targets. The addon should not load on them.

All changes must keep both clients working. A change that fixes Forever and breaks Classic Era, or the other way round, is a regression.

## Files

| File | Purpose |
|---|---|
| `AdventureJournal_Vanilla.toc` | Manifest for Classic Era (`## Interface: 11509`). See [TOC strategy](#toc-strategy). |
| `AdventureJournal_Forever.toc` | Manifest for Forever (`16001`), same file list, plus `IconTexture`, `Category` and `AddonCompartmentFunc` (the Vanilla TOC has no such line). |
| `Compat.lua` | Client detection (`ns.IS_FOREVER`, `ns.IS_CLASSIC_ERA`), `ns.IsSecret`, `ns.SafeString`, the debug state (`ns.debug`, `ns.Debug`, `ns.Describe`, simulated secrets via `ns.Taint`), and **every** API call that differs between clients (`ns.GetPlace`, `ns.GetQuestTitle`, `ns.GetItemInfoSafe`, `ns.UnitNameSafe`, `ns.RegisterEventSafe`, ...). Other files only call these wrappers. |
| `Database.lua` | `ns.EnsureDatabase()`, `ns.SCHEMA_VERSION`, migrations, `ns.DEFAULT_SETTINGS`, the entry-type table `ns.TYPE_INFO`, and the settings helpers (`ns.GetSetting`, `ns.SetSetting`, `ns.IsTypeEnabled`, `ns.SetTypeEnabled`, `ns.TypeFromWord`). Caches the table as `ns.DB`. |
| `Narrative.lua` | Moods and Spanish prose templates: `ns.ChooseMood`, `ns.ComposeEntry`. |
| `Events.lua` | Event registration and handlers (one function per event), `ns.AddEntry`, session start/end, and the dispatcher that runs each handler under `pcall` (error isolation, debug output). |
| `Conversations.lua` | M4b: the opt-in RP conversation log: the chat filter ported from AJProbe, `ns.UpdateConversationEvents` (events are registered only while the option is on), and the text formatting the book uses. |
| `Import.lua` | M4b: `/diario importar`. Reads AJProbe's records (`AJProbeDB`, read only), plans and then applies the backfill; `ns.PlanImport`, `ns.ApplyImport`, `ns.RunImport`. |
| `UI.lua` | The book window: `ns.ToggleUI`, `ns.OpenAtDay`, `ns.SelectDay`, `ns.RefreshUI`. The jornada index is a ScrollBox when the client has it (functions, templates and a clean build), otherwise the original one-Button-per-jornada list (see [UI and commands](#ui-and-commands)). |
| `Options.lua` | The options panel (Settings API, canvas layout) and `ns.OpenOptions`. Never required: if it cannot be built, every option is still reachable by slash command. |
| `Commands.lua` | Slash commands (including `/diario diag` and `/diario debug`), the key-binding globals, `AdventureJournal_ToggleUI`, and `AdventureJournal_OnAddonCompartmentClick` (Forever's addon menu). |
| `Bindings.xml` | Key binding action `ADVENTUREJOURNAL_TOGGLE`, which calls the global `AdventureJournal_ToggleUI()`. |
| `ExportarDiario.py` / `.bat` | Out-of-game exporter: parses the SavedVariables file and writes `Diario_<Character>.txt`. |
| `LEEME.txt` | Player guide in Spanish (install, commands, export). Still describes Classic Era only. |
| `README.md` | This file. |
| `ROADMAP.md` | Milestone plan, backlog, bug-fix process and bug log. |
| `M3_RUNBOOK.md` | Step-by-step for the first Forever session (what to type, what you should see, what to send back). |
| `REFERENCE_SAMPLES.md` | Raw event payloads and API availability observed in game (captured with [AJProbe](../AJProbe/README.md)). |

## How it works

### Lifecycle

1. `ADDON_LOADED` (own name): `EnsureDatabase()` creates or normalises `AdventureJournalDB` and migrates older schemas.
2. `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`: the first one of the session calls `StartSession()`. A real login increments `currentDay` and creates a new jornada. A `/reload` continues the current jornada (`endedAt` is cleared again). Later firings (loading screens) do nothing.
3. Gameplay events: each one calls `AddEntry(type, text, extra)`. This builds an entry, generates its prose, adds it to the current jornada, refreshes the UI if it is open, and prints a line to chat.
4. `PLAYER_LOGOUT`: stores `endedAt` on the current jornada.

### Logged events

| Entry type | Source events | Notes |
|---|---|---|
| `QUEST` | `QUEST_TURNED_IN` | Repeats of the same quest ID within 3 s are ignored. The title comes from `C_QuestLog.GetTitleForQuestID`, falling back to the quest log, then to the quest ID. |
| `BOSS` | `BOSS_KILL`, `ENCOUNTER_END` (`success == 1`) | Repeats of the same name within 5 s are ignored, because both events can fire for one kill. |
| `DEATH` | `PLAYER_DEAD` | |
| `LOOT` | `CHAT_MSG_LOOT`, plus `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` for items not yet cached | Only the player's own loot (messages matching the locale's `LOOT_ITEM_SELF*` / `LOOT_ITEM_PUSHED_SELF*` strings) and only quality ≥ 3 (rare or better). Parses the first item link in the message. |
| `DISCOVERY` | `ZONE_CHANGED*`, `MINIMAP_ZONE_CHANGED` | Only the first time a "subzone, zone" is seen (`visited`). Ignored while the zone text is nil or secret. Zone-only places count too: "Durotar" and "Valle de los Retos, Durotar" are different places. |
| `NPC` | `GOSSIP_SHOW` | Uses `UnitName("npc")`. Repeats of the same NPC within 20 s are ignored. |
| `CHAT` | `CHAT_MSG_WHISPER` | Stores the **sender name only**, never the message text. This is the default and is unchanged. The text of conversations is a separate **opt-in, off by default** feature ([Backfill and conversations](#backfill-and-conversations-m4b)). |

Each type can be switched off in the options (M5, `settings.types`). `AddEntry` is the single gate: a disabled type is dropped there, **after** the handler has updated its dedupe state and `visited`, so switching a type back on does not replay what happened while it was off, and the secret guards are unchanged. `CHAT_MSG_LOOT` returns early when `LOOT` is off, so no item lookups are requested.

Events are registered through `pcall`, so a missing event on one client does not stop the addon from loading. Each handler also runs under `pcall` (see [Error isolation](#error-isolation)).

### Secret values (M2, written blind)

Inside instances Forever may hand the handlers secret values. Every handler checks `ns.IsSecret` before touching a payload, and a secret never reaches `AddEntry` or SavedVariables:

| Handler | When the value is secret |
|---|---|
| `GOSSIP_SHOW` | NPC name becomes "un habitante de la zona" (so NPCs seen within 20 s collapse into one entry) |
| `CHAT_MSG_WHISPER` | Sender becomes "alguien" |
| `CHAT_MSG_LOOT` | Message skipped: the item cannot be read |
| `BOSS_KILL` | Name becomes "una criatura temible" |
| `ENCOUNTER_END` | Secret `success`: skipped (`BOSS_KILL` covers kills). Secret name with a readable `success == 1`: "una criatura temible" |
| `QUEST_TURNED_IN` | Secret quest ID: neutral title |
| `GET_ITEM_INFO_RECEIVED`, `ITEM_DATA_LOAD_RESULT` | Ignored |
| `ZONE_CHANGED*` | Secret zone text: no `DISCOVERY` entry |
| `CHAT_MSG_*` of the conversation log (M4b, only while the option is on) | A secret text or author: the line is skipped. A secret GUID or language is dropped from the line (a `/say` with a secret GUID is skipped: nobody can tell who wrote it) |
| `/diario importar` | Reads AJProbe's `[SECRET]` markers: neutral text (NPC, boss, quest, whisper sender) or the record is skipped (loot, `ENCOUNTER_END` success, place, chat line) |

Whether Forever really makes each of these secret is **verify in M3**; the guards only make the addon safe if it does.

### Error isolation

One failing handler never stops the others. The first error per event name goes to the game's error handler (visible with `/console scriptErrors 1` or BugSack, text starts with `AdventureJournal: error en el manejador de <EVENT>`). Repeats are only counted. `/diario diag` lists them.

### Prose

`ChooseMood(type)` returns a fixed mood for `DEATH`, `BOSS`, `LOOT` and `DISCOVERY`, and a random one from `MOODS` for the other types. `ComposeEntry(entry)` fills a Spanish template for the entry type. `QUEST` has three variants, chosen with `seed % 3`. The finished prose is stored in the entry, so the text does not change when it is read later.

### Backfill and conversations (M4b)

Two features that read or store more than the live diary does. Both are described in [ROADMAP M4b](ROADMAP.md#m4b-backfill-from-ajprobe-and-rp-conversations--m).

**`/diario importar [prueba]`** (`Import.lua`) fills the diary from AJProbe, which has recorded every diary-worthy event since the first Forever day. It only **reads** `AJProbeDB` (a global that exists while AJProbe is enabled; without it the command says so and changes nothing) and never modifies it. It works in two steps, `PlanImport` (reads, decides, mutates nothing) and `ApplyImport`, so `prueba` can print the same summary without saving, and an error while planning leaves the diary untouched.

- Only this character's records: AJProbe tags each one with `c = "Name-GetRealmName()"`.
- Sessions come from the log's `PLAYER_ENTERING_WORLD` records: `login = true` starts one, reloads and loading screens do not (the M4 rule).
- A record goes into the narrowest existing jornada whose time range holds it (3 s tolerance); a record in none, and any session with no jornada, gets a new jornada (`source = "ajprobe"`). New jornadas are inserted in time order, so later jornadas can move up a number; the current jornada stays last. **Existing entries and jornadas are never modified or deleted.**
- Mapping: quests, NPC talks, deaths, own loot of quality 3 or better (same locale patterns as live play), boss kills (`BOSS_KILL`, successful `ENCOUNTER_END`), first visits to places (`visited`; a zone-only place is skipped once a subzone of that zone is known, bug #16) and whispers (the sender-only `CHAT` entry). Entry types switched off in the options are skipped. Everything else AJProbe logs (XP, reputation, skills, level-ups...) has no entry type yet.
- Duplicates: the same type and subject within a few seconds of an existing entry (NPC 20 s, whisper 1 s, others 5 s) is the same event. That is what makes a second run add nothing.
- `[SECRET]` markers become neutral text or the record is skipped. Imported entries carry `source = "ajprobe"`.
- The summary says how many records were read, entries added, duplicates and secrets skipped. Loot whose quality is not cached yet is requested: repeat the command a few seconds later.
- With the conversations option on, `AJProbeDB.chat` is imported too (same dedupe, also against lines captured live).

**Conversations** (`Conversations.lua`) store other players' words, so they are **off by default** and switched on by `/diario conversaciones on` or the options panel. While off, nothing is registered, captured, imported or shown; what was stored stays in the file. While on, the diary keeps in each jornada's `conversations` list: whispers (in and out, Battle.net), party and raid chat from anyone, and `/say`, `/yell` and emotes only from the player, group members and friends. The book gets a button that switches between the events and the conversations of the jornada (100 lines per page). Inside instances on Forever chat is secret and cannot be stored: such lines are skipped, show nothing and never raise an error. Storing at most 5000 lines per jornada is a runaway guard.

### SavedVariables schema (`SavedVariablesPerCharacter: AdventureJournalDB`)

```lua
AdventureJournalDB = {
  version    = 2,
  currentDay = <number>,          -- index of the latest jornada
  visited    = { ["Subzone, Zone"] = true, ... },  -- v2: places already logged as a DISCOVERY
  settings   = {                                   -- v2; defaults merged on every load (see below)
    chat          = "important",  -- "all" | "important" | "off"
    types         = { QUEST = true, BOSS = true, DEATH = true, LOOT = true,
                      DISCOVERY = true, NPC = true, CHAT = true },  -- which types are logged
    showProfile   = false,        -- show the mood (characterProfile) in the book's entry header
    conversations = false,        -- M4b: record RP conversations (opt-in, off by default)
  },
  days = {
    [n] = {
      startedAt = "YYYY-MM-DD HH:MM:SS",
      endedAt   = "YYYY-MM-DD HH:MM:SS", -- set on PLAYER_LOGOUT, may be missing after a crash
      dateLabel = "DD/MM/YYYY",
      source    = "ajprobe",         -- M4b, optional: only on jornadas created by /diario importar
      startTs, endTs,                -- M4b, optional: epochs, only on those jornadas
      events = {
        {
          type, text, prose,           -- type is QUEST|BOSS|DEATH|LOOT|DISCOVERY|NPC|CHAT
          place, zone, subZone,
          time = "HH:MM:SS", timestamp = <epoch>,
          characterProfile, contextualTone, seed,
          -- type-specific extras:
          questID,                     -- QUEST
          itemID, itemLink, itemQuality, -- LOOT
          source = "ajprobe",          -- M4b, optional: entries added by /diario importar
        },
      },
      conversations = {              -- M4b, optional: exists only once a line was stored
        { time = "HH:MM:SS", timestamp = <epoch>, channel = "WHISPER", -- the event name without CHAT_MSG_
          who = "Name", rel = "me|group|friend|bnfriend", lang = "Orco", text = "...", place = "Subzone, Zone",
          source = "ajprobe" },       -- rel, lang and source are optional
      },
    },
  },
}
```

Each client keeps its own `WTF` folder (`_forever_\WTF\...` and `_classic_era_\WTF\...`). Diaries are **not shared** between Forever and Classic Era characters. The schema itself must stay identical on both clients, so the exporter and any future migration code work on either one. If the schema changes, bump `version` and migrate in `EnsureDatabase()`. **M5 added keys to `settings` without a schema bump** (the version stays 2): `EnsureDatabase` fills in any missing setting from `ns.DEFAULT_SETTINGS` on every load and replaces a value of the wrong type, and a type missing from `settings.types` counts as on. Diaries saved at v1 or at v2 before M5 load unchanged and keep their own values (checked in the harness: the migration scenario for v1, the 250-jornada diary for pre-M5 v2). **v1 → v2 (M4):** adds `visited` (seeded from the diary's existing DISCOVERY entries) and `settings`; existing jornadas are untouched. **M4b added `conversations`, `source`, `startTs` and `endTs` without a schema bump** (the version stays 2): they are optional, nothing needs a migration, v1 and v2 diaries (with or without M5 settings) load unchanged (harness), and the code that reads a jornada treats a missing `conversations` as empty. The exporter (M6) must learn them.

### UI and commands

- `AdventureJournalBookFrame` is an open book: the jornada index on the left (newest first), the selected jornada's prose on the right, and previous/next buttons. It is created on first use.
- Slash commands: `/diario` or `/journal` (toggle), `/diario hoy` (latest jornada), `/diario anterior` (the one before it), `/diario chat [todo|importante|nada]` (what is echoed to the chat window; default `importante` = boss kills, deaths, epic loot).
- Options (M5). Every option has a slash command **and** a control in the panel; both change the same `settings`:
  - `/diario opciones` (also `options`, `config`): opens the panel (Esc > Opciones > AddOns > Diario de Aventuras). If it cannot be opened, the command says why and lists the commands below.
  - `/diario chat [todo|importante|nada]`: chat echo.
  - `/diario tipos`: lists which entry types are logged. `/diario tipos <misiones|jefes|muertes|botin|lugares|pnj|susurros> <on|off>` (the English type names `quest`, `boss`, ... also work).
  - `/diario animo [on|off]` (also `mood`): show the mood next to each entry's time in the book. Off by default, so the book looks as before M5. Entries saved before the mood existed have no `characterProfile` and render without it.
  - `/diario conversaciones [on|off]` (also `conversations`, `conv`): record RP conversations (M4b). Off by default; the panel's *Guardar las conversaciones de rol* check box does the same. The chat events are registered only while it is on.
  - `/diario importar` and `/diario importar prueba` (also `import`, `test`): the AJProbe backfill, or a dry run that only counts (M4b, see [Backfill and conversations](#backfill-and-conversations-m4b)).
- Options panel: Settings API, **canvas** layout (our own frame, plain widgets), registered with `RegisterCanvasLayoutCategory` + `RegisterAddOnCategory` and opened with `Settings.OpenToCategory` (tried with the category ID, then the category object). It deliberately avoids `RegisterAddOnSetting` / `CreateCheckbox` / `CreateDropdown`, whose signatures are not known (they exist on Classic Era 1.15.9, observed; the call signatures cannot be observed). Whether `OpenToCategory` takes an ID on 1.15.9 and Forever is checked by the smoke test: **verify in game**.
- Book index: a ScrollBox (`WowScrollBoxList` + `MinimalScrollBar` + `CreateScrollBoxListLinearView`, rows are `UIPanelButtonTemplate` buttons) creates frames only for the visible rows, so 250+ jornadas cost the same as 10. It is used only if the functions and both templates exist and the whole build succeeds; otherwise the original ScrollFrame with one Button per jornada is built, and `/diario diag` says which one and why. Observed on Classic Era 1.15.9: functions, templates and a full test build all work (`/diario diag`, "prueba de ScrollBox: OK"). How the real rows look and scroll is not observable offline: **verify in game**. Forever: **verify in M3**.
- With the conversations option on, a button at the bottom of the book switches between the jornada's events and its conversations; long conversation lists get `< Antes` / `Después >` buttons. With the option off the button is hidden and no conversation text is ever shown. The jornada index shows the count of whatever the book is showing.
- Escape closes the book.
- Forever's addon menu (the minimap button): the Forever TOC has `## AddonCompartmentFunc: AdventureJournal_OnAddonCompartmentClick`, a global that toggles the book. The Vanilla TOC has no such line. Whether the entry appears and works on Forever: **verify in M3/M5**.
- Developer commands:
  - `/diario diag`: client, interface, DB, API branches, registered events, handler errors. Run it first on a new client.
  - `/diario debug on` / `off`: print every handled event's payload (`[SECRET]` for secrets) and every fallback taken. Session only.
  - `/diario debug secrets` (`off` to stop): simulate secret values, mainly for Classic Era. Also turns debug on. `/diario debug off` or `/reload` turns everything off.
  - `/diario debug demo` (`off` to stop): the book shows 250 generated jornadas (20 entries each, every other one without a mood) to try the index. They live in memory only: not saved, never mixed into your diary (entries made meanwhile still go to the real one). `/diario debug off` or `/reload` also removes them.
  - `/diario debug buttons`: forces the old button index, to test the fallback. Only counts if typed **before** the book is first opened after `/reload`.
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
- Both TOCs must declare `## SavedVariablesPerCharacter: AdventureJournalDB`. The Forever TOC adds `IconTexture`, `Category` and `AddonCompartmentFunc` (the function must be global; `AdventureJournal_OnAddonCompartmentClick` exists on both clients but only the Forever TOC names it). Both list `Options.lua` between `UI.lua` and `Commands.lua`.

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
| Item quality / link | Both `C_Item.GetItemInfo` and `GetItemInfo` exist and agree (observed). `C_Item` is tried first | `C_Item.GetItemInfo` (the global `GetItemInfo` may be missing; verify) |
| Item cache callback | `GET_ITEM_INFO_RECEIVED`; `ITEM_DATA_LOAD_RESULT` also exists (observed). Both are registered; the first to arrive wins | Both registered when the client knows them; **verify in M3** which one fires |
| Quest title | `C_QuestLog.GetTitleForQuestID` is **missing**. `GetQuestLogTitle` loop works, but only synchronously inside `QUEST_TURNED_IN` (observed) | `C_QuestLog.GetTitleForQuestID` |
| Boss kill | `BOSS_KILL`, `ENCOUNTER_END` | Same. Payload may be secret during encounters (verify) |
| NPC name | `UnitName("npc")` | Same. **Can be secret in instances** |
| Loot / whisper text | Plain strings. Links use `\|cffRRGGBB` (observed for loot) | **Secret inside instances** |
| Zone text | `GetRealZoneText`, `GetSubZoneText`. `GetRealZoneText()` is nil at `PLAYER_LOGIN` on a fresh login (observed). `MINIMAP_ZONE_CHANGED` does not exist | Same |
| Frames | `BackdropTemplate`, `UIPanel*Template` | Same |
| Textures and glyphs | `Interface\QuestFrame\QuestBG` (not checked yet). `◀`/`▶` rendered as **empty squares** (observed); the buttons now read `< Anterior` / `Siguiente >` | Verify that the `QuestBG` texture renders on the modern client |
| Options panel | Observed in game (`/run` check, 2026-11-04): `Settings.RegisterAddOnCategory`, `OpenToCategory`, `RegisterAddOnSetting`, `RegisterProxySetting`, `CreateCheckbox`, `CreateDropdown`, `VarType` and `SettingsPanel` all exist, plus `RegisterCanvasLayoutCategory` / `RegisterVerticalLayoutCategory` (M0); `InterfaceOptions_AddCategory` is missing. Templates `UICheckButtonTemplate`, `InterfaceOptionsCheckButtonTemplate` and `UIPanelButtonTemplate` work. **Call signatures are not observable**; the canvas path used here needs only the category functions and `OpenToCategory` | `Settings` API (**verify in M3**). Expected to match the Mainline docs: [api-quick-reference.md](../docs/api-quick-reference.md) |
| ScrollBox | `CreateScrollBoxListLinearView`, `CreateDataProvider`, `ScrollUtil.InitScrollBoxListWithScrollBar` and the templates `WowScrollBoxList` and `MinimalScrollBar` all work; a full build in a hidden frame succeeded (observed). Row layout and scrolling: verify in game | **Verify in M3** (`/diario diag` runs the same probe) |
| Date parsing (import) | `time{year=...}` converts the saved local-time strings back to epochs; checked by converting back, with the stored epochs as fallback. `/diario diag` shows "Lectura de fechas" (**verify in game**) | Same (**verify in M3**) |
| Chat for conversations | `CHAT_MSG_WHISPER`, `_WHISPER_INFORM`, `_BN_WHISPER`, `_BN_WHISPER_INFORM`, `_PARTY(_LEADER)`, `_RAID(_LEADER)`, `_SAY`, `_YELL`, `_EMOTE`, `_TEXT_EMOTE` all register (observed in AJProbe's `env.events`). The GUID is argument 12, the Battle.net sender ID argument 13; the author carries the realm (observed). AJProbe's data shows `rel = "me"` working; the friend and Battle.net lookups (`C_FriendList.IsFriend`, `C_BattleNet.*`) have not been seen to return anything yet (**verify in game**) | Same events. **Text and author may be secret in instances** (verify in M3). `C_FriendList` / `C_BattleNet` signatures: verify |
| Group lookups (conversations) | `UnitGUID`, `GetNumGroupMembers`, `IsInRaid` | Same; unit GUIDs may be secret inside instances (guarded) |
| Addon menu entry | `AddonCompartmentFrame` does not exist (observed); the Vanilla TOC does not use it | `AddonCompartmentFunc` in the TOC, a global callback. **Verify in M3/M5** that the entry appears and the click opens the book |
| Chat log | `/chatlog` produced no `WoWChatLog.txt` (observed 2026-11-04, also after closing the game); do not rely on it to copy diagnostics, use screenshots | **Verify in M3** |

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

A deliberate behaviour change needs `npm run update-expected`, and the diff of `tools/expected/` should show exactly that change. Scenarios per client: normal play, a session with secret values in an instance (`scenario_secrets.lua`), a schema v1 diary (`scenario_migration.lua`), every M5 option through the panel and the slash commands with persistence across `/reload` and a second login (`scenario_options.lua`, also with no Settings API and with `OpenToCategory` needing the category object), a generated 250-jornada diary checking that the index creates a bounded number of frames (`scenario_bigdiary.lua`, also with no ScrollBox functions and with no ScrollBox templates), and for M4b `/diario importar` against a synthetic `AJProbeDB` (`scenario_import.lua`: an empty diary, a diary whose jornadas overlap the log, no AJProbe, a client where `time{...}` does not work) and the live conversation log (`scenario_conversations.lua`, also with no `C_FriendList` / `C_BattleNet`). `tools/import-dryrun.js` rehearses the import on copies of real SavedVariables files, in memory, printing counts only. The stubs cannot reproduce everything about real secrets, layout or the real Settings and ScrollBox behaviour; see the limits in [tools/README.md](../tools/README.md).

Test checklist before calling a change done:

- [ ] Loads with no Lua errors on **Classic Era** and on **Forever** (`/console scriptErrors 1`).
- [ ] Not shown as "out of date" on either client.
- [ ] On each client: turn in a quest, open an NPC gossip window, change subzone, die, and loot a blue item. Each one produces an entry.
- [ ] On Forever, **inside a dungeon**: talk to an NPC, receive a whisper, see loot messages, and kill a boss. No errors, and no `nil` entries after `/reload`.
- [ ] On Classic Era, with `/diario debug secrets`: talk to an NPC, whisper yourself or have a friend whisper you, loot something, kill something. No errors, fallback text in the entries, nothing saved as `nil`. Then `/diario debug off`.
- [ ] The book UI opens, scrolls and pages on both clients. Textures and arrows render.
- [ ] M5, on each client: `/diario opciones` opens the panel; each option changes behaviour and survives `/reload`; `/diario debug demo` shows 250 jornadas that scroll smoothly (the index is a ScrollBox, `/diario diag` says so). On Forever, also the addon-menu entry (minimap button) opens the book.
- [ ] M4b, on each client (steps in the roadmap's hand-over and, for Forever, [M3_RUNBOOK.md](M3_RUNBOOK.md) section 3c): back up `AJProbe.lua` and `AdventureJournal.lua`; `/diario importar prueba` counts, `/diario importar` imports, the second run adds nothing; the imported entries and jornadas show in the book; with `/diario conversaciones on`, a whisper appears in the book's conversations view, and with it off nothing is captured or shown. On Forever, also a dungeon: secret chat is skipped with no error.
- [ ] The exporter reads SavedVariables from both `WTF` folders.

## Exporter

`ExportarDiario.bat` runs `py -3 ExportarDiario.py`, which opens a file picker. Select the character's `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\AdventureJournal.lua` from either client. It writes `Diario_<Character>.txt` next to that file. Close the game first, because WoW only writes SavedVariables on logout or `/reload`. The parser is a minimal Lua-table reader. It handles what WoW's serialiser writes, but it is not a full Lua parser.

## Roadmap

The milestone plan (M0 Classic Era baseline → M7 release 1.2.0), the backlog, the bug-fix process and the bug log are in [ROADMAP.md](ROADMAP.md).
