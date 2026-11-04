# AdventureJournal: roadmap

Milestone plan to finish the dual-client port (WoW Forever + Classic Era), then handle bug fixes and improvements. Background and design rules: [README.md](README.md).

Last updated: 2026-11-04.

## Constraints that shape the plan

- **Forever cannot be tested until it launches** (2026-11-04 15:00 PST, which is 2026-11-05 local). **Classic Era can be tested now.**
- So we do everything Classic Era can verify first. Forever-only code (secret guards, Mainline item links, the Forever TOC) is written "blind" before launch, using defensive coding and diagnostics. It gets verified in M3, the first session after launch.
- Classic Era cannot produce secret values. Secret-handling code paths are checked on Classic Era with a **simulated-secret debug mode** (M2), and on Forever inside a dungeon (M3).
- Raids on Forever open on 2026-12-09. Until then, use 5-player dungeons to test boss behaviour during encounters.

Legend: 🟢 testable on Classic Era now · 🔵 needs Forever · Size S/M/L = relative effort.

---

## M0: Classic Era baseline 🟢 (S)

Goal: know how the current code really behaves before changing it.

- [x] `git init` the repo, then commit the current state as the baseline (commit `0fac3d3`, tag `m0-baseline`).
- [x] Junction-link the folder into `_classic_era_\Interface\AddOns\` (see README, "Development and testing"). The dev probe [AJProbe](../AJProbe/README.md) is linked too.
- [ ] `/console scriptErrors 1`. Install BugSack/BugGrabber if available.
- [ ] Run the README test checklist on Classic Era: quest, gossip, subzone change, death, blue loot, whisper, boss kill (an easy dungeon boss), `/reload`, every slash command, the key binding.
- [ ] Capture reference samples for later comparison. **AJProbe records all of these automatically** into `WTF\Account\<ACCOUNT>\SavedVariables\AJProbe.lua` (written on `/reload` or logout):
  - [ ] the raw `CHAT_MSG_LOOT` message (own loot and group loot), with the link's colour prefix and whether the current pattern matches;
  - [ ] the `BOSS_KILL` and `ENCOUNTER_END` payloads;
  - [ ] whether `C_QuestLog.GetTitleForQuestID` exists and returns a title at `QUEST_TURNED_IN` (checked at the event and 1 s later);
  - [ ] whether `C_Item.GetItemInfo`, `Settings` and `ITEM_DATA_LOAD_RESULT` exist (the probe's `env.api` and `env.events` tables).
- [ ] Run the exporter on the resulting SavedVariables.
- [ ] Record every bug found in the [Bug log](#bug-log). Bugs 8 to 12 were found by reading the code: confirm or reject each one in game.

**Done when:** we have a list of actual Classic Era bugs, the reference samples, and an export generated from real data.

## M1: Restructure for two clients, no behaviour change 🟢 (M)

Goal: a code layout that can hold client-specific code cleanly. Same behaviour as M0.

- [ ] Replace `AdventureJournal.toc` with:
  - `AdventureJournal_Vanilla.toc`: `## Interface: 11509`
  - `AdventureJournal_Forever.toc`: `## Interface: 16001`, plus `IconTexture`, `Category`
  - Both: same file list, `## SavedVariablesPerCharacter: AdventureJournalDB`, `## Version: 1.2.0-dev`
- [ ] Split `AdventureJournal.lua` into:
  - `Compat.lua`: client detection (`ns.IS_FOREVER`, `ns.IS_CLASSIC_ERA`), `ns.IsSecret`, and the API wrappers (`ns.GetItemInfoSafe`, `ns.GetQuestTitle`, `ns.GetPlace`, `ns.UnitNameSafe`)
  - `Database.lua`: `EnsureDatabase`, schema version, migrations
  - `Narrative.lua`: `MOODS`, `ChooseMood`, `ComposeEntry`
  - `Events.lua`: event registration and handlers, `AddEntry`, session start/end
  - `UI.lua`: the book frame, `RefreshUI`, `SelectDay`
  - `Commands.lua`: slash commands, binding globals, `AdventureJournal_ToggleUI`
- [ ] Use `local addonName, ns = ...` in every file. Keep only the intended globals: `AdventureJournalDB`, `AdventureJournal_ToggleUI`, `SLASH_ADVENTUREJOURNAL*`, `BINDING_*`.
- [ ] Move every direct Classic or Mainline API call into `Compat.lua`.

**Done when:** the full M0 checklist passes on Classic Era with identical results, and diaries from M0 still open in the UI.

## M2: Prepare for Forever before launch 🟢 + 🔵-blind (M)

Goal: code that should run on Forever on day one, with tools to diagnose it quickly when it doesn't.

- [ ] **Secret guards.** Check `ns.IsSecret` before any comparison, match or `tonumber` in `SafeString` and in the `GOSSIP_SHOW`, `CHAT_MSG_WHISPER`, `CHAT_MSG_LOOT` and `ENCOUNTER_END`/`BOSS_KILL` handlers. When a value is secret, use a neutral fallback ("un habitante de la zona", "alguien") or skip the entry. Never pass a secret to `AddEntry`.
- [ ] **Item links.** Match `|Hitem:.-|h%[.-%]|h` with no colour prefix. Update the exporter's `clean()` to also strip `|cnIQ<n>:`.
- [ ] **Item data.** Prefer `C_Item.GetItemInfo`. Keep `GET_ITEM_INFO_RECEIVED`, and also listen to `ITEM_DATA_LOAD_RESULT` when it exists.
- [ ] **Diagnostics command `/diario diag`.** Prints the client (project ID, interface), the DB version, which API branches `Compat` chose, whether `issecretvalue` exists, and which events registered successfully. This is the first thing to run on Forever.
- [ ] **Debug mode `/diario debug [on|off]`.** Prints the raw payload of each handled event, with `[SECRET]` markers, to help confirm what Forever sends.
- [ ] **Simulated secrets `/diario debug secrets`.** On Classic Era, makes `ns.IsSecret` return true for event payload strings, so every fallback branch can be run and checked without Forever.
- [ ] **Error isolation.** Wrap each handler so one failing handler doesn't stop the others, and so the error is reported once with the event name (in debug mode).

**Done when:** on Classic Era the M0 checklist passes in normal mode, and also with simulated secrets: no errors, and fallback text appears in the entries. The Forever TOC is in place, ready for launch.

## M3: First Forever session 🔵 (M) (from 2026-11-05)

Goal: make it work on Forever and replace assumptions with what the game actually does.

- [ ] Junction-link into `_forever_\Interface\AddOns\`. Check that the addon is listed and not "out of date".
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

## M5: Options and convenience 🟢 then 🔵 (M)

- [ ] `Settings` panel, guarded by a check that the API exists. If Classic Era lacks it, fall back to slash commands: chat output, the event types to log, whether to show the mood/profile.
- [ ] Show `characterProfile` (the mood) in the entry header in the UI.
- [ ] Forever only, guarded: `AddonCompartmentFunc` entry (minimap addon menu).
- [ ] Use a `ScrollBox` for the index if available, otherwise keep the current buttons. This fixes the one-Button-per-jornada growth.

**Done when:** options persist across sessions on both clients, and the UI stays responsive with 200+ jornadas (test with generated data).

## M6: Export 🟢 (S–M)

- [ ] In-game export window: a read-only multi-line `EditBox` with the selected jornada (or all of them) as plain text, ready to select all and copy. Players then don't need Python.
- [ ] Python exporter fixes: decode `\ddd` escapes as UTF-8 bytes, strip `|cnIQ` tags, and read schema v1 and v2.
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
| 1 | 2026-11-04 | Forever | P1 | No Forever TOC (interface 11509 only) | Planned: M1 |
| 2 | 2026-11-04 | Forever | P1 | Secret values cause errors in `GOSSIP_SHOW` / `CHAT_MSG_WHISPER` / `CHAT_MSG_LOOT` inside instances (from code analysis) | Planned: M2 |
| 3 | 2026-11-04 | Forever | P2 | Loot link pattern may miss `|cnIQ` item links (unverified) | Planned: M2, verify in M3 |
| 4 | 2026-11-04 | Both | P2 | `/reload` creates a new jornada | Planned: M4 |
| 5 | 2026-11-04 | Both | P2 | Subzone changes spam `DISCOVERY` entries and chat | Planned: M4 |
| 6 | 2026-11-04 | Both | P2 | Group members' loot is logged as the player's | Planned: M4 |
| 7 | 2026-11-04 | Both | P3 | Escape does not close the book | Planned: M4 |
| 8 | 2026-11-04 | Both | P2 | The first `/diario` (or key binding press) after login shows nothing. `BuildUI` creates the frame already shown, then `AdventureJournal_ToggleUI` sees `IsShown()` and hides it (`AdventureJournal.lua:342`, `:497-499`). From code analysis. | Confirm in M0 |
| 9 | 2026-11-04 | Both | P3 | `◀`/`▶` in the page buttons are probably not in the default font (Friz Quadrata), so they render as boxes or not at all. This applies to Classic Era too, not only Forever. | Confirm in M0 |
| 10 | 2026-11-04 | Both | P3 | `Bindings.xml` is listed in the TOC. The client loads `Bindings.xml` by itself; listing it may log an XML error to `Logs\FrameXML.log`. Unverified. | Confirm in M0 |
| 11 | 2026-11-04 | Both | P3 | `pendingLoot` keeps every looted item that is cached but below rare quality, and never clears it (`AdventureJournal.lua:251`). Small, unbounded growth per session. From code analysis. | Planned: M4 |
| 12 | 2026-11-04 | Classic Era | P2 | If `C_QuestLog.GetTitleForQuestID` is missing on 1.15.9, quest entries fall back to "una misión (ID n)", because the quest has already left the log at `QUEST_TURNED_IN`. AJProbe answers this. | Confirm in M0 |
