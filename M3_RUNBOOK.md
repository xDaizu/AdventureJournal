# M3 runbook: first Forever session

Step-by-step for the first session on WoW Forever (launch 2026-11-05). It follows the [M3 checklist in the roadmap](ROADMAP.md#m3-first-forever-session--m-from-2026-11-05). The folder you will play on is the **M4 state (includes M2), tested only against stubs** (and on Classic Era if you ran the smoke tests). Nothing here needs code changes before you play.

**Rules for this session**
- Don't edit addon files while the game is running. Play, note what happens, fix afterwards.
- AJProbe keeps recording everything whatever AdventureJournal does. If AdventureJournal misbehaves, you lose nothing.
- Emergency brake: at the character select screen, open **AddOns** and untick *AdventureJournal* (leave *AJProbe* ticked).

## 1. Log in and look for errors
1. Log in. Type `/console scriptErrors 1` and press Enter. Lua errors now pop up in a box instead of staying hidden.
2. Check the **AddOns** button on the character select screen: both *Diario de Aventuras* and *AJProbe* should be listed and not marked "out of date".
3. In the chat you should see `[Diario] Comienza la jornada N.` If a red error box appears, take a screenshot or copy the text, and keep going.

## 2. Diagnostics (first thing)
1. Type `/diario diag`. Copy the whole block (screenshot, or select the chat text) and send it to Claude.
2. What to look for: `Cliente` says `1.60.1` and interface `16001`; `IS_FOREVER=true`; `issecretvalue: sí`; the *events* lines say which events registered and why one did not; `Errores en manejadores: ninguno`.
3. Type `/ajprobe`. It prints event counts, which proves AJProbe is recording.

## 3. Open world, one thing at a time
First type `/diario chat todo`. Since M4 the chat only echoes boss kills, deaths and epic loot by default; this makes it echo every entry, so you can see each step work. (Go back with `/diario chat importante`.)

After each step, type `/diario diag` only if something looked wrong. Otherwise just do the step and watch the chat for a green `[Diario]` line.

| Step | What to do | You should see |
|---|---|---|
| Quest | Turn in any quest | `[Diario]` line with the quest title (not "una misión (ID n)") |
| Gossip | Open an NPC's dialog window | `[Diario]` with the NPC name |
| Place | Walk into a **new** subzone | `[Diario]` with the place. Walking back into a place you already saw gives nothing (M4) |
| Death | Die once, if it happens | `[Diario] He caído en combate` |
| Loot | Loot a blue (rare) item | `[Diario]` with the item link, shown as a clickable link. If nothing appears, run `/diario diag` ("Patrones de botín propio" should say 4) and `/diario debug on`, then loot again: a line saying "botín de otro jugador" means the loot message did not match your client's own-loot strings |
| Group loot | In a group, let someone else loot | Nothing (M4: only your own loot counts) |
| Whisper | Have a friend whisper you | `[Diario]` with the sender name |
| UI | Type `/diario` | The book opens on the first press (M4). Buttons read `< Anterior` / `Siguiente >`. Press Escape: the book closes. Does the paper background render? |
| Binding | Press the key bound to the diary, if you set one | The book toggles |
| Reload | `/reload`, then `/diario hoy` | Chat says `Continúas la jornada N` (same N as before, M4). Entries read as text, no `nil`. Log out and in again: now a **new** jornada starts |

## 4. Inside a dungeon (5-player)
1. Before entering, type `/diario debug on`. From now on grey `[Diario debug]` lines print every event's payload, with `[SECRET]` where the game hides the value.
2. Inside: talk to an NPC, get a whisper (or a message in party chat), loot something, and kill a boss.
3. After the boss, type `/diario diag` and look at `Errores en manejadores`.
4. Copy the grey debug lines for the NPC, the loot, the whisper and the boss. They tell us exactly which values are secret.
5. Type `/diario debug off`, then `/reload`, then `/diario hoy`. Check that entries inside the dungeon read normally (fallback text such as "un habitante de la zona" or "una criatura temible" is expected if values were secret).

## 5. Extras
- `/chatlog` (type it again to stop). Check that `D:\Games\Battle.net\World of Warcraft\_forever_\Logs\WoWChatLog.txt` appears.
- `/dump select(4, GetBuildInfo())` should print `16001`.

## 6. After you log out
Close the game first: WoW writes SavedVariables on `/reload` or logout.

1. Summarise AJProbe's Forever data (read-only):
   ```
   py -3 tools\ajprobe_summary.py > forever_summary.md
   ```
   Send `forever_summary.md` to Claude. It becomes the Forever section of [REFERENCE_SAMPLES.md](REFERENCE_SAMPLES.md). It lists secret fields by event, the loot link format and whether the current pattern matches it, quest titles, and events that failed to register. Conversation text from `AJProbeDB.chat` is **not** printed. (Test it on Classic Era data with `--flavor classic`.)
2. Run the exporter on `_forever_\WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\AdventureJournal.lua` (see README, "Exporter") and check that the `.txt` has no `|cn` codes and no raw `|H` links.

## 7. What to send Claude
- The `/diario diag` output.
- Any Lua error text (full message).
- The grey debug lines from the dungeon.
- `forever_summary.md`.
- Anything that looked wrong in the UI (missing background texture, wrong button text).
- Whether `/reload` continued the jornada (it should) and a real login started a new one.

Open questions this session answers (all "verify in M3" in the README and ROADMAP): the `PLAYER_ENTERING_WORLD` flags (reload vs login), whether the own-loot patterns match Forever's loot messages (`toolsjprobe_summary.py` counts them), which payloads are really secret in a dungeon, whether `ENCOUNTER_END` / `BOSS_KILL` arguments are secret, which item-cache event fires (`GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT`), what Forever's item links look like, whether zone text is ever secret, and whether `C_QuestLog.GetTitleForQuestID` returns titles at `QUEST_TURNED_IN`.
