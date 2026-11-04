# AdventureJournal: roadmap

Milestone plan to finish the dual-client port (WoW Forever + Classic Era), then handle bug fixes and improvements. Background and design rules: [README.md](README.md).

Last updated: 2026-11-04 (M2 code done, waiting for the Classic Era smoke test; M4b added earlier).

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

**Status (2026-11-04):** code done, `npm test` passes. Waiting for the in-game Classic Era smoke test; then tag `m2-done`. The Forever behaviour of all of this is **unverified until M3**. Open questions for M3: are `ENCOUNTER_END` / `BOSS_KILL` payloads really secret, what does `UnitName("npc")` return in a dungeon, is `CHAT_MSG_LOOT` / `CHAT_MSG_WHISPER` text secret there, is the zone text ever secret, which item-cache event fires, and does a secret really pass `type()` as `"string"`.

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

- [ ] **One jornada per login, not per `/reload`.** Use the `isReload` argument of `PLAYER_ENTERING_WORLD`. Keep starting a new jornada on a real login (the original design).
- [ ] **Real discoveries.** Keep a per-character `visited` set of zone/subzone keys in the DB. Log a `DISCOVERY` only the first time. Optionally, a lighter "travel" entry for moving between zones, without spam.
- [ ] **Own loot only.** Build a pattern from `LOOT_ITEM_SELF` / `LOOT_ITEM_SELF_MULTIPLE` (these differ by locale; check them on esES and enUS). Ignore other players' loot.
- [ ] **Close with Escape:** `tinsert(UISpecialFrames, "AdventureJournalBookFrame")`.
- [ ] **Less chat spam.** Turn the chat print off by default, or limit it to important events (boss, death, epic loot).
- [ ] **Schema v2.** Add a migration in `Database.lua` for `visited` and the settings table. Existing v1 diaries must load unchanged.

**Done when:** `/reload` doesn't create a new jornada, walking back and forth produces no repeated entries, group loot is ignored, and old diaries still load.

## M4b: Backfill from AJProbe, and RP conversations 🟢 (M)

New requirements (user, 2026-11-04): no event from the first Forever days may be lost, and on the RP server the diary should keep conversations, not only events. Depends on schema v2 (M4).

**Backfill.** AJProbe has been recording since Forever launch (`AJProbeDB.log`, `AJProbeDB.chat`). Turn that into diary content:
- [ ] `/diario importar`: in game, with both addons enabled (AdventureJournal can read the `AJProbeDB` global once AJProbe has loaded). Import only the current character's records (`c` field).
- [ ] Rebuild jornadas from the log's `PLAYER_ENTERING_WORLD` records (`login = true` starts a jornada; reloads don't, matching the M4 rule). Merge into existing jornadas when the timestamps overlap.
- [ ] Map records to entry types: `QUEST_TURNED_IN` → `QUEST`, `GOSSIP_SHOW` → `NPC`, zone records → `DISCOVERY` (first visit only, via `visited`), `PLAYER_DEAD` → `DEATH`, `CHAT_MSG_LOOT` with quality ≥ 3 from the player → `LOOT`, `BOSS_KILL` / successful `ENCOUNTER_END` → `BOSS`, `PLAYER_LEVEL_UP` → a new `LEVEL` type. Other records (XP, reputation, skills, system messages) are input for the backlog entry types.
- [ ] Skip duplicates: an entry of the same type and subject within a few seconds of an existing one is the same event.
- [ ] Records with `[SECRET]` values become neutral text or are skipped, and never fail.
- [ ] Mark imported entries (`source = "ajprobe"`), and make the import idempotent: running it twice adds nothing.

**RP conversations.**
- [ ] New per-jornada `conversations` list (schema v2): `{ time, channel, who, rel, lang, text, place }`.
- [ ] Live capture in AdventureJournal, ported from AJProbe's filter: whispers (in/out, Battle.net), party and raid chat, and `/say`, `/yell` and emotes from me, group members and friends only.
- [ ] **Opt-in, off by default** in the released addon, because it stores other players' words. The setting lives in the M5 options panel; until then, `/diario conversaciones on|off`.
- [ ] Shown in the book (a toggle between "events" and "conversations", or interleaved by time) and included in the M6 export.
- [ ] `/diario importar` also imports `AJProbeDB.chat`.
- [ ] Known limit (workspace rule 5): inside instances on Forever, chat arrives as secrets and cannot be stored. Show nothing for those, don't error.

**Done when:** a real AJProbe log from the first Forever days imports into the right jornadas with no duplicates and no errors; running it again changes nothing; conversations appear in the book and in the export only when the option is on.

## M5: Options and convenience 🟢 then 🔵 (M)

- [ ] `Settings` panel, guarded by a check that the API exists. If Classic Era lacks it, fall back to slash commands: chat output, the event types to log, whether to show the mood/profile.
- [ ] Show `characterProfile` (the mood) in the entry header in the UI.
- [ ] Forever only, guarded: `AddonCompartmentFunc` entry (minimap addon menu).
- [ ] Use a `ScrollBox` for the index if available, otherwise keep the current buttons. This fixes the one-Button-per-jornada growth.

**Done when:** options persist across sessions on both clients, and the UI stays responsive with 200+ jornadas (test with generated data).

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
- New entry types: level up (`PLAYER_LEVEL_UP`), new profession skill tiers, flight paths learned, first visit to a capital or dungeon, reputation level changes, PvP honour or battleground results (outside the match only).
- End-of-jornada summary paragraph (quests, places, deaths), written at logout or when the jornada is opened.
- Forever only: Hardcore deaths (`C_GameRules.IsHardcoreActive()`) get a special epitaph entry. Skyborne/Legacy/Camping events once their APIs are known (`/api`).

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
| 4 | 2026-11-04 | Both | P2 | `/reload` creates a new jornada. **Confirmed on Classic Era.** `PLAYER_ENTERING_WORLD` gives `true,false` on login and `false,true` on reload. | Planned: M4 |
| 5 | 2026-11-04 | Both | P2 | Subzone changes spam `DISCOVERY` entries and chat. **Confirmed on Classic Era:** "Valle de los Retos" was logged twice in one jornada. Every fresh login also logs a `DISCOVERY` for the starting spot, because `GetRealZoneText()` is nil at `PLAYER_LOGIN`. | Planned: M4 |
| 6 | 2026-11-04 | Both | P2 | Group members' loot is logged as the player's | Planned: M4 |
| 7 | 2026-11-04 | Both | P3 | Escape does not close the book | Planned: M4 |
| 8 | 2026-11-04 | Both | P2 | The first `/diario` (or key binding press) after login shows nothing. `BuildUI` creates the frame already shown, then `AdventureJournal_ToggleUI` sees `IsShown()` and hides it (`AdventureJournal.lua:342`, `:497-499`). **Confirmed on Classic Era** (second press works). | Planned: M4 |
| 9 | 2026-11-04 | Both | P3 | `◀`/`▶` in the page buttons are probably not in the default font (Friz Quadrata), so they render as boxes or not at all. **Confirmed on Classic Era: empty squares.** Expect the same on Forever. | Planned: M4 |
| 10 | 2026-11-04 | Both | P3 | `Bindings.xml` is listed in the TOC. The client loads `Bindings.xml` by itself; listing it may log an XML error to `Logs\FrameXML.log`. **Confirmed:** `Bindings.xml:2 Unrecognized XML: Binding` warning on load. Fix: drop it from the TOC file list. | **Fixed** in M1: warning gone, key binding still works (confirmed in game) |
| 11 | 2026-11-04 | Both | P3 | `pendingLoot` keeps every looted item that is cached but below rare quality, and never clears it (`AdventureJournal.lua:251`). Small, unbounded growth per session. From code analysis. | Planned: M4 |
| 12 | 2026-11-04 | Classic Era | P2 | If `C_QuestLog.GetTitleForQuestID` is missing on 1.15.9, quest entries fall back to "una misión (ID n)", because the quest has already left the log at `QUEST_TURNED_IN`. **Rejected:** the API is missing, but the quest is still in the log during the event, so the scan finds the title. It is gone 1 s later. Keep the lookup synchronous. | Not a bug |
| 13 | 2026-11-04 | Both | P3 | Prose sentences start in lower case after a full stop: "«Tu lugar en el mundo». pensando en el largo camino...". This happens in `QUEST` (all three variants) and `LOOT`, because the mood phrases start in lower case. | Planned: M4 |
| 14 | 2026-11-04 | Classic Era | P3 | `MINIMAP_ZONE_CHANGED` does not exist on Classic Era. Registering it fails silently inside `pcall`. Harmless; drop it in M1, or register it only if `C_EventUtils.IsEventValid` says it exists. | Fixed in M1 |
