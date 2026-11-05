# AdventureJournal: roadmap

Milestone plan to finish the dual-client port (WoW Forever + Classic Era), then handle bug fixes and improvements. Background and design rules: [README.md](README.md).

Last updated: 2026-11-04 (M0–M2, M4 and M5 tested on Classic Era and tagged; M4b tested on Classic Era and tagged, its import also run on real Forever data; M3 (the rest of the Forever checks) is in progress).

## Constraints that shape the plan

- **Forever cannot be tested until it launches** (2026-11-04 15:00 PST, which is 2026-11-05 local). **Classic Era can be tested now.**
- So we do everything Classic Era can verify first. Forever-only code (secret guards, Mainline item links, the Forever TOC) is written "blind" before launch, using defensive coding and diagnostics. It gets verified in M3, the first session after launch.
- Classic Era cannot produce secret values. Secret-handling code paths are checked on Classic Era with a **simulated-secret debug mode** (M2), and on Forever inside a dungeon (M3).
- Raids on Forever open on 2026-12-09. Until then, use 5-player dungeons to test boss behaviour during encounters.
- **The game runs whatever is in the working folder.** The junctions point at it, and the user plays every day. Work directly on `main` in small commits, but **before the user plays, the folder must be in a smoke-tested state**: either the milestone is finished and tested, or check out the last tag (`m0-done`, `m1-done`, ...) first. Tag each milestone when its smoke test passes.
- **Never lose AJProbe data.** `AJProbeDB.log` and `AJProbeDB.chat` hold the only complete record of the first Forever days (see M4b). Changes to AJProbe must keep existing records readable.

Legend: 🟢 testable on Classic Era now · 🔵 needs Forever · Size S/M/L = relative effort.

---

## M0: Classic Era baseline 🟢 (S)

Goal: know how the current code really behaves before changing it.

- [x] `git init` the repo, then commit the current state as the baseline (commit `0fac3d3`, tag `m0-baseline`).
- [x] Junction-link the folder into `_classic_era_\Interface\AddOns\` (see README, "Development and testing"). The dev probe [AJProbe](../AJProbe/README.md) is linked too.
- [x] `/console scriptErrors 1`. (BugSack/BugGrabber skipped: optional.)
- [ ] Run the README test checklist on Classic Era. Smoke test done 2026-11-04 (Volgajin, Zandalar Tribe):
  - [x] quest, gossip, subzone change, death, `/reload`, `/diario`.
  - [ ] **Deferred, check while playing normally** (AJProbe stays installed and keeps recording): blue loot, whisper, `/diario hoy` / `anterior`, the key binding.
  - [ ] **Deferred, needs a group or dungeon:** group loot, boss kill.
- [x] Capture reference samples: see [REFERENCE_SAMPLES.md](REFERENCE_SAMPLES.md). Group loot and boss payloads are still missing (deferred, as above).
  - [x] the raw `CHAT_MSG_LOOT` message (own loot): `|cffRRGGBB` links, the current pattern matches;
  - [ ] `BOSS_KILL` / `ENCOUNTER_END` payloads (deferred);
  - [x] `C_QuestLog.GetTitleForQuestID` is **missing** on Classic Era. The quest-log scan works only at the event itself;
  - [x] `C_Item.GetItemInfo`, `Settings` and `ITEM_DATA_LOAD_RESULT` all exist. So does `issecretvalue`, which always returns false.
- [x] Run the exporter on the resulting SavedVariables: parses correctly, UTF-8 output.
- [x] Record every bug found in the [Bug log](#bug-log).

**Done when:** we have a list of actual Classic Era bugs, the reference samples, and an export generated from real data.

**Status (2026-11-04):** done for open-world solo play. The deferred checks above get filled in during normal play, and they don't block M1.

### Forever day-one safety net (added 2026-11-04, before launch)

So no events are lost on Forever while M1–M3 are in progress:
- `AdventureJournal_Forever.toc` (`16001`, version `1.1.0-forever-preview`) added, so the unported diary loads on Forever. Expect Lua errors from secret values inside dungeons (bug #2).
- The loot link pattern now accepts any colour prefix (`|c[^|]*`), covering `|cnIQ<n>:` (bug #3). No change on Classic Era.
- Both addons are linked into `_forever_\Interface\AddOns\`.
- AJProbe keeps a long-lived activity log of everything diary-worthy, plus an RP conversation log (see [AJProbe](../AJProbe/README.md)). [M4b](#m4b-backfill-from-ajprobe-and-rp-conversations--m) turns both into diary content.

## M1: Restructure for two clients, no behaviour change 🟢 (M)

Goal: a code layout that can hold client-specific code cleanly. Same behaviour as M0.

- [x] **Test harness first** (`tools/`): a `package.json` with `luaparse` (Lua 5.1 syntax check of every `.lua` file) and `fengari` (runs the addon against stubbed WoW globals). Add a script that loads the addon, fires a scripted event sequence (login, zone changes, gossip, quest, loot, death, reload) and prints the resulting `AdventureJournalDB`. The baseline was taken from the pre-M1 code (commit `1e052e4`). Time and `math.random` are stubbed deterministically, so the comparison is exact. `node_modules/` stays out of git.
- [x] Replace the current `AdventureJournal.toc` (Classic Era) and the provisional `AdventureJournal_Forever.toc` with:
  - `AdventureJournal_Vanilla.toc`: `## Interface: 11509`
  - `AdventureJournal_Forever.toc`: `## Interface: 16001`, plus `IconTexture`, `Category`
  - Both: same file list, `## SavedVariablesPerCharacter: AdventureJournalDB`, `## Version: 1.2.0-dev`
  - Do **not** list `Bindings.xml` (the client loads it by itself; bug #10). Check that the key binding still works afterwards.
- [x] Split `AdventureJournal.lua` into:
  - `Compat.lua`: client detection (`ns.IS_FOREVER`, `ns.IS_CLASSIC_ERA`), `ns.IsSecret`, and the API wrappers (`ns.GetItemInfoSafe`, `ns.GetQuestTitle`, `ns.GetPlace`, `ns.UnitNameSafe`)
  - `Database.lua`: `EnsureDatabase`, schema version, migrations
  - `Narrative.lua`: `MOODS`, `ChooseMood`, `ComposeEntry`
  - `Events.lua`: event registration and handlers, `AddEntry`, session start/end
  - `UI.lua`: the book frame, `RefreshUI`, `SelectDay`
  - `Commands.lua`: slash commands, binding globals, `AdventureJournal_ToggleUI`
- [x] Use `local addonName, ns = ...` in every file. Keep only the intended globals: `AdventureJournalDB`, `AdventureJournal_ToggleUI`, `SLASH_ADVENTUREJOURNAL*`, `BINDING_*`.
- [x] Move every direct Classic or Mainline API call into `Compat.lua`. Keep what M0 observed ([REFERENCE_SAMPLES.md](REFERENCE_SAMPLES.md)): `ns.GetQuestTitle` must stay synchronous (the quest leaves the log within 1 s), and `GetRealZoneText()` can be nil at `PLAYER_LOGIN`.
- [x] Register `MINIMAP_ZONE_CHANGED` only when `C_EventUtils.IsEventValid` confirms it exists (`ns.RegisterEventSafe`, bug #14).

- [x] **In-game smoke test on Classic Era** (2026-11-04, Volgajin): the `_Vanilla` TOC is picked up, jornadas 1–5 from before M1 load and display, a new jornada and entry are created and saved, the key binding works without `Bindings.xml` in the TOC, and the `Unrecognized XML` warning is gone. NPC entries and `/reload` were not re-checked in game (the harness covers them); they get exercised in normal play.

**Status (2026-11-04):** done, tagged `m1-done`.

**Done when:** the harness output matches the pre-M1 baseline, the M0 smoke test passes on Classic Era with identical results, diaries from M0 still open in the UI, and the Forever TOC still loads.

## M2: Prepare for Forever before launch 🟢 + 🔵-blind (M)

Goal: code that should run on Forever on day one, with tools to diagnose it quickly when it doesn't.

- [x] **Secret guards.** `ns.IsSecret` is checked before any comparison, match, `tonumber`, `#` or table-key use in `ns.SafeString` and in the `GOSSIP_SHOW`, `CHAT_MSG_WHISPER`, `CHAT_MSG_LOOT`, `ENCOUNTER_END`, `BOSS_KILL`, `QUEST_TURNED_IN`, `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` and zone handlers. Fallbacks: NPC "un habitante de la zona", whisper sender "alguien", boss "una criatura temible", quest "una misión cuyo nombre no he podido recuperar". Skipped entirely: a secret loot message (the item cannot be read), an `ENCOUNTER_END` with a secret `success` flag (`BOSS_KILL` covers the kill), a zone change with secret zone text. `ns.AddEntry` also drops any secret field as a last line of defence. Same-kind secrets share one fallback, so the 20 s NPC and 5 s boss dedupe merges them (acceptable, noted).
- [x] **Item links.** Game code accepts any colour prefix (day-one safety net). The exporter's `clean()` now also strips `|cnIQ<n>:` (checked with a sample string).
- [x] **Item data.** `C_Item.GetItemInfo` is tried first, then the global `GetItemInfo`. `ITEM_DATA_LOAD_RESULT` is registered next to `GET_ITEM_INFO_RECEIVED` through `RegisterEventSafe` and shares its handler. Items not cached yet are also requested with `C_Item.RequestLoadItemDataByID`. *Verify in M3:* which of the two events Forever actually fires.
- [x] **Diagnostics command `/diario diag`.** Prints the client (version, build, interface, project ID, detection result), instance state, zone, DB version and counts, which API branch each `Compat` wrapper takes, whether `issecretvalue` exists, which events registered (and why one did not), handler errors, and the debug state. First thing to run on Forever.
- [x] **Debug mode `/diario debug on|off`.** Prints the payload of each handled event with `[SECRET]` markers, plus a line whenever a fallback is taken. Session only (never saved).
- [x] **Simulated secrets `/diario debug secrets [off]`.** Event payload strings and `UnitName` results become proxies that error on everything a real secret forbids; `ns.IsSecret` recognises them. It also turns debug on; `/diario debug off` or `/reload` turns it off.
- [x] **Error isolation.** Every handler runs under `pcall`. The first error per event name goes to the game's error handler (so `scriptErrors` / BugSack show it, tagged with the event name); repeats are only counted. `/diario diag` lists them.
- [x] **Harness.** Third scenario `scenario_secrets.lua` (secret NPC name, whisper sender, loot message, boss names, quest ID, zone text, in an instance), a stub secret that errors like a real one, a DB scan that fails the run if a secret reaches SavedVariables. Limits are in [tools/README.md](../tools/README.md).

**Done when:** on Classic Era the M0 checklist passes in normal mode, and also with simulated secrets: no errors, and fallback text appears in the entries. The Forever TOC is in place, ready for launch.

**Status (2026-11-04):** done on Classic Era: the in-game smoke test passed (user, 2026-11-04), tagged `m2-done`. The Forever behaviour of all of this is **unverified until M3**. Open questions for M3: are `ENCOUNTER_END` / `BOSS_KILL` payloads really secret, what does `UnitName("npc")` return in a dungeon, is `CHAT_MSG_LOOT` / `CHAT_MSG_WHISPER` text secret there, is the zone text ever secret, which item-cache event fires, and does a secret really pass `type()` as `"string"`.

## M3: First Forever session 🔵 (M) (from 2026-11-05)

Goal: make it work on Forever and replace assumptions with what the game actually does.

**Prepared offline (2026-11-04):** the step-by-step is in [M3_RUNBOOK.md](M3_RUNBOOK.md), and `tools/ajprobe_summary.py` turns AJProbe's Forever data into a draft of the REFERENCE_SAMPLES Forever section (tested on the Classic Era file). Nothing below is ticked: every item needs the live Forever client.

- [x] Junction-link into `_forever_\Interface\AddOns\` (done 2026-11-04). Check that the addon is listed and not "out of date".
- [ ] Read AJProbe's Forever data (`_forever_\WTF\Account\<ACCOUNT>\SavedVariables\AJProbe.lua`) and fill the Forever section of [REFERENCE_SAMPLES.md](REFERENCE_SAMPLES.md): `env`, loot link format, quest titles, which values are `[SECRET]` and where.
- [ ] Check that `/chatlog` works on Forever (writes `_forever_\Logs\WoWChatLog.txt`).
- [ ] Run `/diario diag` and save the output in the README.
- [ ] README checklist in the open world: quest, gossip, subzone change, death, blue loot, whisper, `/reload`, UI, binding.
- [ ] README checklist **inside a dungeon**, with `/diario debug on`: NPC gossip, whisper received, group loot messages, boss kill. Check for errors and for `nil` or empty entries after `/reload`.
- [ ] Check that the textures and arrow glyphs render (`QuestBG`, `◀`/`▶`). Swap them out if not.
- [ ] Resolve every "verify" entry in the README's API table, and update the table. Update shared `docs/` when Forever behaviour differs from what they say (in-game behaviour wins).
- [ ] Run the exporter on a Forever SavedVariables file.
- [ ] Fix the bugs found. Re-run the Classic Era checklist after each fix.

**Done when:** both checklists pass on both clients, and the README has no "verify" entries left for the APIs in use.

## M4: Logic bug fixes 🟢 (M)

Can start in parallel with M3. Everything here can be tested on Classic Era. Re-check on Forever afterwards.

Test split (user, 2026-11-04): **everything is tested on Classic Era now (harness, then in game); the Forever side waits for M3.** Status below: `[x]` = written and passing the harness; the in-game Classic Era smoke test is still pending (see the status line); items marked *Forever: verify in M3* depend on what Forever really sends.

- [x] **One jornada per login, not per `/reload`.** The session now starts at `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`, no longer at `PLAYER_LOGIN`. A real login starts a new jornada. A reload continues the current one (clears the `endedAt` that the reload's `PLAYER_LOGOUT` set) and prints "Continúas la jornada N". A loading screen inside the game does nothing. If no jornada exists yet, one is created. *Forever: verify in M3* that the two flags arrive as on Classic Era.
- [x] **Real discoveries.** `visited` (per character, keyed by the place text) in the DB. A `DISCOVERY` is logged only the first time. Not logged while the zone text is nil (right after a fresh login) or secret. On reload the current place is marked visited silently. The optional lighter "travel" entry is **not** done (backlog).
- [x] **Own loot only.** Patterns built in `Compat.lua` from `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_PUSHED_SELF` and `LOOT_ITEM_PUSHED_SELF_MULTIPLE` (handles `%s`, `%d` and positional `%1$s`), so the locale doesn't matter. If a client has none of the strings, all loot is accepted as before. Checked against the real esES samples from AJProbe (9 of 9 own messages match). *Forever: verify in M3* with `tools/ajprobe_summary.py`, which reports how many real loot messages match; `/diario diag` shows the pattern count, and `/diario debug on` prints "botín de otro jugador" for every message ignored. A mismatch would silently drop own loot.
- [x] **Close with Escape:** `UISpecialFrames` (once). Checked in the harness by hiding the registered frames, as the game does. *Verify in game.*
- [x] **Less chat spam.** `settings.chat`: `important` (default: boss kills, deaths, epic or better loot), `all`, `off`. Command `/diario chat [todo|importante|nada]`. The "Comienza / Continúas la jornada" line stays.
- [x] **Schema v2.** `Database.lua` migrates v1 diaries: adds `visited` (seeded from the DISCOVERY entries already in the diary, so upgrading does not log them again) and `settings`; jornadas are never touched. Idempotent. Tested on a hand-written v1 diary (`scenario_migration.lua`). *Test on your real diary: it is the in-game smoke test.*
- [x] **Also fixed here (bug log):** the first `/diario` did nothing (#8), `◀`/`▶` rendered as squares (#9, now `< Anterior` / `Siguiente >`), `pendingLoot` grew without bound (#11), sentences started in lower case after a full stop (#13; only new entries, stored prose is not rewritten).

**Done when:** `/reload` doesn't create a new jornada, walking back and forth produces no repeated entries, group loot is ignored, and old diaries still load.

**Status (2026-11-04):** done on Classic Era: code passes `npm test` on both flavors and the in-game smoke test passed (user, 2026-11-04; it also covered M2), tagged `m4-done`. The user's real diary (v1 → v2 migration, jornadas 1–8) loaded and a first-time discovery ("Poblado Sen'jin, Durotar") was logged. **Pending:** after M3, the same checks on Forever ([runbook](M3_RUNBOOK.md)).

## M4b: Backfill from AJProbe, and RP conversations 🟢 (M)

New requirements (user, 2026-11-04): no event from the first Forever days may be lost, and on the RP server the diary should keep conversations, not only events. Depends on schema v2 (M4).

Status key (same as M5): **H** = covered by the stubbed harness (`npm test`), **R** = also rehearsed offline on a copy of the real Classic Era files (`tools/import-dryrun.js`, in memory, nothing written), **G** = needs the in-game Classic Era smoke test, **F** = needs Forever (verify in M3 / the next Forever session).

**Backfill.** AJProbe has been recording since Forever launch (`AJProbeDB.log`, `AJProbeDB.chat`). Turn that into diary content:
- [x] `/diario importar` (H; R; **G**; **F**). Reads the `AJProbeDB` global at command time; says so and does nothing if AJProbe is not installed or enabled. Imports only this character's records (`c` = `Name-GetRealmName()`, built by `ns.GetPlayerKey()`). `/diario importar prueba` is a dry run: prints the same summary and saves nothing.
- [x] Rebuild jornadas from the log's `PLAYER_ENTERING_WORLD` records (H; R; **G**; **F**). `login = true` starts a session, reloads and loading screens do not (the M4 rule); records before the first login form a partial session. A session whose time range overlaps an existing jornada is merged into it **record by record** (the narrowest jornada whose range holds the record, 3 s tolerance), so the pre-M4 pairs of jornadas split by a reload get the right records; a record in no jornada, and every session with no jornada, gets a new one (`source = "ajprobe"`, `startedAt` / `endedAt` / `dateLabel` from the log, plus the epochs `startTs` / `endTs`). New jornadas are inserted in time order, so jornadas after them move up one number; **the current jornada stays last**. Existing jornadas and entries are never modified or deleted (harness: verified byte for byte).
- [x] Map records to entry types (H; R; **G**; **F**): `QUEST_TURNED_IN` → `QUEST`, `GOSSIP_SHOW` → `NPC`, `PLAYER_DEAD` → `DEATH`, `CHAT_MSG_LOOT` (own loot by the locale's `LOOT_ITEM_SELF*` patterns, quality ≥ 3) → `LOOT`, `BOSS_KILL` / `ENCOUNTER_END` with `success` 1 or true → `BOSS`, zone records → `DISCOVERY`, and `CHAT_MSG_WHISPER` → the existing `CHAT` entry (sender name only; the live diary makes one too). The types switched off in the options are not imported, and `visited` is left alone for them (so switching one on and importing again brings them in). Entries use the place, zone and time of the record, not the current ones. Loot whose quality AJProbe did not know is looked up now; if the item is not cached yet it is requested and the summary says to repeat the command in a few seconds.
- [x] **Discovery rule (bug #16).** A place is a `DISCOVERY` only the first time (`visited`, including places seen earlier in the same run). A zone-only place ("Durotar", empty subzone) is **not** logged when any "subzone, Durotar" is already visited. Applied in the import only; the live handler still has bug #16.
- [x] Skip duplicates (H): same type and subject within a few seconds of an existing entry or of one imported earlier in the run. Subject = item ID for loot, quest ID for quests, else the text. Windows: NPC 20 s (the live rule), quest / boss / death / loot 5 s, whisper 1 s. This is also what makes a second run add nothing.
- [x] Secrets (H; **F**): `[SECRET]` becomes the same neutral texts the live handlers use (`ns.NEUTRAL_TEXT`: NPC, boss, quest, whisper sender) or the record is skipped (secret loot, secret `ENCOUNTER_END` success, secret place). Never an error.
- [x] Idempotent (H; R): the second run adds nothing and leaves the diary byte-identical, also when `time{...}` does not work on the client (the `notimetable` scenario: imported jornadas keep their epochs). AJProbeDB is compared before and after every run in every scenario.
- [ ] `PLAYER_LEVEL_UP` → a `LEVEL` type: **not done** (it needs a type in the options, a live handler and prose, which would change default behaviour). The records keep `level`; see the backlog.

**RP conversations.**
- [x] Per-jornada `conversations` list (H): `{ time, timestamp, channel, who, rel, lang, text, place }` (+ `source = "ajprobe"` when imported). `channel` is the event name without `CHAT_MSG_` (`WHISPER`, `WHISPER_INFORM`, `BN_WHISPER`, `PARTY`, `RAID`, `SAY`, `YELL`, `EMOTE`, `TEXT_EMOTE`, ...). **No schema bump**: the list and the new `source` / `startTs` / `endTs` fields are optional and additive; `version` stays 2. M5 diaries and v1 diaries load unchanged (harness: migration, big-diary and overlap scenarios), and an older addon reading a newer diary just ignores them.
- [x] Live capture (H; **G**; **F**): `Conversations.lua`, a port of AJProbe's filter: whispers (in / out, Battle.net), party and raid chat for everybody; `/say`, `/yell` and emotes only from me, group members and friends (`ns.GetRelationship`). The events are registered only while the option is on, and the handler checks the option again.
- [x] **Opt-in, off by default** (H; **G**): `settings.conversations`, the options panel check box (no longer disabled) and `/diario conversaciones on|off`. Turning it off stops capture and hides everything; what was stored stays in the file. The CHAT entry (sender only) is unchanged. A runaway guard stops capture for a jornada at 5000 lines.
- [x] Shown in the book (H; **G** for layout): a toggle button between the events view and the conversations view (only while the option is on), 100 lines per page with `< Antes` / `Después >` buttons. The ScrollBox index and its fallback are untouched apart from the row count. Not shown at all while the option is off. **Chosen over interleaving** because a busy RP day has far more lines than events.
- [x] `/diario importar` also imports `AJProbeDB.chat` (H; R) **only when the conversations option is on**; with it off the summary says how many lines it left alone. A line already captured live is a duplicate (same channel, author and text within 2 s). Chat records outside every jornada and session are counted ("sin jornada") and left out.
- [x] Known limit (workspace rule 5) (H; **F**): inside instances on Forever chat is secret. A line with a secret text or author is skipped, shows nothing and never errors (harness: stub secrets, simulated secrets, an "instance"). Whether Forever really sends secret chat there is still **verify in M3**.
- [ ] Included in the M6 export: **not part of M4b**. The shape is ready (`days[n].conversations`, optional); the exporter must learn it in M6.

**Done when:** a real AJProbe log from the first Forever days imports into the right jornadas with no duplicates and no errors; running it again changes nothing; conversations appear in the book and in the export only when the option is on.

**Status (2026-11-04):** code done and passing `npm test` (6 new scenario runs per client plus the changed reports). Rehearsed offline, in memory, on a copy of the real Classic Era files (94 activity records, 4 chat lines, a diary with 11 jornadas): no error, 1 NPC entry the diary lacked (probably logged while NPC was switched off during the M5 test), 4 duplicates skipped, second run byte-identical, AJProbeDB untouched. **Done on Classic Era:** the in-game smoke test passed (user, 2026-11-05) and `m4b-done` is tagged. The real import added exactly the predicted NPC entry, no duplicates; with conversations off nothing was captured (a line said while off is in AJProbe and not in the diary), with it on SAY, emote and party lines were. **Seen on Forever (2026-11-05, character Necroroth, real data):** `/diario importar prueba` and `/diario importar` worked: +18 conversation lines (party, party leader, say, emotes), 4 already captured live skipped as duplicates, 0 new jornadas, 0 errors, AJProbe only read (its record count grew only from the next login). Live party capture after a `/reload` stored 4 of 4 lines. **Still unverified on Forever:** whether switching the option on without a `/reload` registers the chat events (the party lines before the reload were missed; most likely the option was still off, not proven), chat inside instances (secret or not), the friend / Battle.net lookups, and the layout of the new buttons. The backup before the first Forever import was taken late (after the import, from the game's own `.bak` files); the runbook now says to copy the files first. The remaining Forever checks are in [M3_RUNBOOK.md](M3_RUNBOOK.md) section 3c.

## M5: Options and convenience 🟢 then 🔵 (M)

Status key: **H** = covered by the stubbed harness (`npm test`), **G** = needs the in-game Classic Era smoke test, **F** = needs Forever (verify in M3 / the next Forever session).

- [x] **Options panel** (code done; H; **G**; **F**). `Options.lua`: Settings API, canvas layout (own frame and plain widgets), guarded at every step; if it cannot be built, `/diario opciones` explains why and lists the commands, and every option still works by command. Observed on Classic Era (2026-11-04, `/run` check): `RegisterAddOnCategory`, `OpenToCategory`, `RegisterAddOnSetting`, `RegisterProxySetting`, `CreateCheckbox`, `CreateDropdown`, `VarType` and `SettingsPanel` exist; the check boxes and buttons use templates that exist. **Not verifiable offline:** the call signatures (so the vertical layout was not used), whether `OpenToCategory(categoryID)` is the right call on 1.15.9 (the code tries the ID, then the category object, and checks that the settings window is up), and how the panel looks. Options: chat echo (`settings.chat`), the seven entry types (`settings.types`, default all on), mood in the book (`settings.showProfile`, default off so the default book is unchanged). Slash commands: `/diario opciones`, `chat`, `tipos`, `animo`. Disabled types are dropped in `AddEntry` after the handlers update dedupe and `visited` (harness: counts per type, dedupe across an off/on switch, secret payloads with types off and on). No schema bump: `settings` gains keys that `EnsureDatabase` fills from `ns.DEFAULT_SETTINGS`; v1 and pre-M5 v2 diaries load (harness).
- [x] **Placeholder for the M4b conversations toggle** (H): a disabled checkbox in the panel and `settings.conversations = false`. Wired up in M4b: the check box is usable now and `/diario conversaciones on|off` does the same.
- [x] **Mood in the entry header** (code done; H; **G**). `Hora  ·  Ánimo`, only when `showProfile` is on. Entries without `characterProfile` render as before (harness: an entry injected without one, and 125 of 250 generated jornadas without moods).
- [x] **Forever addon-menu entry** (code done; H for the TOC field and the function; **F**). `## AddonCompartmentFunc: AdventureJournal_OnAddonCompartmentClick` in the Forever TOC only; the global toggles the book (harness: the TOC field is read, the function called, the book toggles; the Vanilla TOC has no such line). Whether the minimap menu shows the entry and the click works on Forever: **verify in M3/M5**.
- [x] **ScrollBox index** (code done; H; **G**; **F**). Used only if the functions, the templates (`WowScrollBoxList`, `MinimalScrollBar`) and a full build all work; otherwise the old buttons. Observed on Classic Era: all present and a test build succeeded (`/diario diag`). Harness: 251 jornadas create 35 frames in total with 15 rows; adding entries while open creates 0; three stub variants (functions missing, templates missing, forced with `/diario debug buttons`) all end on the button index and render. **Not verifiable offline:** row width and look, real scroll behaviour, the parchment background around the bar.
- [x] **`/diario debug demo`**: shows 250 generated jornadas in the book only (memory, never saved), so the index can be scrolled in game without touching the real diary (H).

**Done when:** options persist across sessions on both clients, and the UI stays responsive with 200+ jornadas (test with generated data).

**Status (2026-11-04):** done on Classic Era: code passes `npm test` (6 new scenario runs per client) and the in-game smoke test passed (user, 2026-11-04), tagged `m5-done`. **Pending:** the Forever checks (panel, `OpenToCategory`, ScrollBox, minimap entry) wait for the next Forever session ([M3_RUNBOOK.md](M3_RUNBOOK.md) section 3b).

## M6: Export 🟢 (S–M)

- [ ] In-game export window: a read-only multi-line `EditBox` with the selected jornada (or all of them) as plain text, ready to select all and copy. Players then don't need Python.
- [ ] Python exporter fixes: decode `\ddd` escapes as UTF-8 bytes, strip `|cnIQ` tags, and read schema v1 and v2 (including `conversations`, M4b).
- [ ] Optional: export one jornada at a time; a Markdown output option.

## M7: Release 1.2.0 (S)

- [ ] Version `1.2.0` in both TOCs. Drop the `-Era` suffix.
- [ ] Update `LEEME.txt` (Spanish): install for both clients (`_forever_` and `_classic_era_`), the new commands, options, in-game export.
- [ ] `CHANGELOG.md`.
- [ ] Final checklist on both clients from a clean SavedVariables, and from an M0-era v1 diary (migration test).
- [ ] Package: zip the **folder**; exclude `README.md`, `ROADMAP.md` and dev files. Tag game versions **1.60.1** (Forever) and **1.15.9** (Classic Era) on CurseForge/Wago.

---

## Future improvements (backlog, after 1.2.0)

Each item must work on both clients or be cleanly guarded. Mark ideas that only apply to one client.

**More story content**
- More prose variants for every entry type, not just quests. Avoid repeating the same template within a jornada.
- New entry types: level up (`PLAYER_LEVEL_UP`; AJProbe's log already has `level`, so the backfill can import it the day the type exists), new profession skill tiers, flight paths learned, first visit to a capital or dungeon, reputation level changes, PvP honour or battleground results (outside the match only).
- End-of-jornada summary paragraph (quests, places, deaths), written at logout or when the jornada is opened.
- Forever only: Hardcore deaths (`C_GameRules.IsHardcoreActive()`) get a special epitaph entry. Skyborne/Legacy/Camping events once their APIs are known (`/api`).

**Conversations**
- A way to delete stored conversations (`/diario conversaciones borrar`, with a confirmation) and per-channel choices. Search inside the conversations view.
- Import the other AJProbe records (XP, reputation, skills, system messages, achievements, spells learned, flights) once their entry types exist.

**UI**
- Search and filter by entry type or zone. Bookmarks.
- Page-turn animation (cosmetic).
- Chapter view grouping jornadas by level range or zone.

**Platform**
- English localization (`Locales/enUS.lua`, `esES.lua`) with Spanish as the default.
- DB size management: archive or compress old jornadas, with an optional cap.
- Optional: local Lua 5.1 unit tests for `Narrative.lua` and `Database.lua` migrations with stubbed WoW globals; pytest for the exporter.

**Out of scope** (workspace rules): anything that reads or infers combat data through workarounds for secret values; anything that relies on addon messaging inside instances.

---

## Bug fixes and maintenance (ongoing)

**Reporting:** capture the full error (BugSack or `/console scriptErrors 1`), the client (`/diario diag`), and whether it happened in an instance or encounter. Add it to the bug log below.

**Triage:**
- **P1:** a Lua error, data loss, or the addon not loading on either client. Fix immediately and publish a patch release (`1.2.x`).
- **P2:** wrong or missing entries, UI glitches. Fix in the next patch.
- **P3:** text or cosmetic issues. Fix when convenient.

**Every fix:** reproduce it on the client where it was reported, fix it, then run the README checklist on **both** clients. If the fix touches Forever-only code, also run the simulated-secrets mode on Classic Era.

**When a client is patched** (either one):
1. Read the new interface number in game: `/dump select(4, GetBuildInfo())`.
2. Bump only that client's TOC.
3. Read the `Patch_x.y.z/API_changes` page on Warcraft Wiki. Update the README API table and `docs/`.
4. Run `/diario diag` and the checklist on that client.

## Bug log

| # | Found | Client | Priority | Description | Status |
|---|---|---|---|---|---|
| 1 | 2026-11-04 | Forever | P1 | No Forever TOC (interface 11509 only) | Workaround: provisional `AdventureJournal_Forever.toc`. Proper TOCs in M1 |
| 2 | 2026-11-04 | Forever | P1 | Secret values cause errors in `GOSSIP_SHOW` / `CHAT_MSG_WHISPER` / `CHAT_MSG_LOOT` inside instances (from code analysis) | Guards and per-handler error isolation written in M2, tested with stub and simulated secrets on both flavors. **Verify in M3** inside a dungeon |
| 3 | 2026-11-04 | Forever | P2 | Loot link pattern may miss `\|cnIQ` item links (unverified) | Pattern fixed 2026-11-04; exporter `clean()` fixed in M2; verify in M3 with a real Forever link |
| 4 | 2026-11-04 | Both | P2 | `/reload` creates a new jornada. **Confirmed on Classic Era.** `PLAYER_ENTERING_WORLD` gives `true,false` on login and `false,true` on reload. | Fixed in M4 (harness); in-game check pending. Forever: verify in M3 |
| 5 | 2026-11-04 | Both | P2 | Subzone changes spam `DISCOVERY` entries and chat. **Confirmed on Classic Era:** "Valle de los Retos" was logged twice in one jornada. Every fresh login also logs a `DISCOVERY` for the starting spot, because `GetRealZoneText()` is nil at `PLAYER_LOGIN`. | Fixed in M4 (harness); in-game check pending |
| 6 | 2026-11-04 | Both | P2 | Group members' loot is logged as the player's | Fixed in M4 (own-loot patterns). Group loot never seen in game yet; Forever: verify in M3 |
| 7 | 2026-11-04 | Both | P3 | Escape does not close the book | Fixed in M4; in-game check pending |
| 8 | 2026-11-04 | Both | P2 | The first `/diario` (or key binding press) after login shows nothing. `BuildUI` creates the frame already shown, then `AdventureJournal_ToggleUI` sees `IsShown()` and hides it (`AdventureJournal.lua:342`, `:497-499`). **Confirmed on Classic Era** (second press works). | Fixed in M4 (the frame is hidden after creation); in-game check pending |
| 9 | 2026-11-04 | Both | P3 | `◀`/`▶` in the page buttons are probably not in the default font (Friz Quadrata), so they render as boxes or not at all. **Confirmed on Classic Era: empty squares.** Expect the same on Forever. | Fixed in M4: buttons read `< Anterior` / `Siguiente >`. The `QuestBG` texture still needs an in-game look on both clients |
| 10 | 2026-11-04 | Both | P3 | `Bindings.xml` is listed in the TOC. The client loads `Bindings.xml` by itself; listing it may log an XML error to `Logs\FrameXML.log`. **Confirmed:** `Bindings.xml:2 Unrecognized XML: Binding` warning on load. Fix: drop it from the TOC file list. | **Fixed** in M1: warning gone, key binding still works (confirmed in game) |
| 11 | 2026-11-04 | Both | P3 | `pendingLoot` keeps every looted item that is cached but below rare quality, and never clears it (`AdventureJournal.lua:251`). Small, unbounded growth per session. From code analysis. | Fixed in M4 (settled items are dropped) |
| 12 | 2026-11-04 | Classic Era | P2 | If `C_QuestLog.GetTitleForQuestID` is missing on 1.15.9, quest entries fall back to "una misión (ID n)", because the quest has already left the log at `QUEST_TURNED_IN`. **Rejected:** the API is missing, but the quest is still in the log during the event, so the scan finds the title. It is gone 1 s later. Keep the lookup synchronous. | Not a bug |
| 13 | 2026-11-04 | Both | P3 | Prose sentences start in lower case after a full stop: "«Tu lugar en el mundo». pensando en el largo camino...". This happens in `QUEST` (all three variants) and `LOOT`, because the mood phrases start in lower case. | Fixed in M4 for new entries (old stored prose is unchanged) |
| 14 | 2026-11-04 | Classic Era | P3 | `MINIMAP_ZONE_CHANGED` does not exist on Classic Era. Registering it fails silently inside `pcall`. Harmless; drop it in M1, or register it only if `C_EventUtils.IsEventValid` says it exists. | Fixed in M1 |
| 15 | 2026-11-04 | Classic Era | P3 | `/chatlog` produced no `WoWChatLog.txt` anywhere under the WoW folder, not even after closing the game. M3's runbook step "check that `/chatlog` works on Forever" may fail the same way; chat text cannot be selected in the default UI either, so diagnostics are copied by screenshot. | Observation; check on Forever in M3 |
| 16 | 2026-11-04 | Both | P3 | A zone-only place is a separate place from its subzones: the diary logged "Durotar" (empty subzone) as a first-time DISCOVERY at 20:06:16 in jornada 8, although other "subzone, Durotar" places were already in the diary. Cause not checked in game (probably a moment when the subzone text was empty). Consequence of keying `visited` by the full place text. Candidate fix: do not log a zone-only place when any "subzone, zone" of that zone is already visited. | Open for live play (not an M5 item). The same rule is already used by the AJProbe import (M4b) |
| 17 | 2026-11-04 | Both | P3 | Discoveries are never echoed to chat in the default `importante` mode (by design). The tester first read this as "not logged". Consider a clearer first-run hint or a `/diario chat` line in the login message. | Open (cosmetic) |
