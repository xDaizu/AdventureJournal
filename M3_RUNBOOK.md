# M3 runbook: first Forever session

Step-by-step for the first session on WoW Forever (launch 2026-11-05). It follows the [M3 checklist in the roadmap](ROADMAP.md#m3-first-forever-session--m-from-2026-11-05). The folder you will play on is the **M4b state (includes M2, M4 and M5)**: M2, M4 and M5 passed the Classic Era smoke test (tags `m2-done`, `m4-done`, `m5-done`); M4b passed the Classic Era smoke test too (tag `m4b-done`). Of all this, only the diary itself, the first M4b import and live party capture have been seen on Forever so far (2026-11-05); the options panel, ScrollBox index and addon-menu entry have not been confirmed there. M4b changes nothing by default: the conversation log is off and the import only runs when you type it.

**Rules for this session**
- Don't edit addon files while the game is running. Play, note what happens, fix afterwards.
- AJProbe keeps recording everything whatever AdventureJournal does. If AdventureJournal misbehaves, you lose nothing.
- Emergency brake: at the character select screen, open **AddOns** and untick *AdventureJournal* (leave *AJProbe* ticked).

## 1. Log in and look for errors
1. Log in. Type `/console scriptErrors 1` and press Enter. Lua errors now pop up in a box instead of staying hidden.
2. Check the **AddOns** button on the character select screen: both *Diario de Aventuras* and *AJProbe* should be listed and not marked "out of date".
3. In the chat you should see `[Diario] Comienza la jornada N.` If a red error box appears, take a screenshot or copy the text, and keep going.

## 2. Diagnostics (first thing)
1. Type `/diario diag`. The block is about 70 lines. Chat text cannot be selected and `/chatlog` wrote no file on Classic Era (bug #15), so send **screenshots**: scroll the chat up with the mouse wheel and capture it in two or three pieces. The new "Interfaz (M5)" lines at the end matter most. (For a single yes/no question, a one-line `/run print(...)` is easier than the whole block.)
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

## 3b. M5 checks on Forever (options panel, ScrollBox index, addon menu)
None of this has run on Forever. In `/diario diag`, "Interfaz (M5)" tells you what the client has; then:

| Step | What to do | You should see |
|---|---|---|
| Panel registered | `/diario diag`, look at "Panel de opciones" | `panel registrado (categoría N)`. If it says `NO disponible: ...`, send that text |
| Open the panel | `/diario opciones` | The Settings window opens on **Diario de Aventuras** with a chat button, 7 check boxes, a mood check box and a greyed-out conversations box. If nothing opens, the command prints why; the panel should still be under Esc > Opciones > AddOns |
| Options work | Press the chat button until it reads `nada`; untick *Muertes*; tick the mood box; `/reload`; reopen | The three changes are still there. Die once: no entry and no chat line. Open `/diario`: entry headers read `Hora · Ánimo` |
| Commands | `/diario tipos`, `/diario tipos muertes on`, `/diario animo off`, `/diario chat importante` | Each answers and the panel (if open) follows |
| Index | `/diario diag`, look at "Índice del libro" (after opening the book once); then `/diario debug demo` | `ScrollBox`; the demo shows 250 jornadas, the index scrolls with the wheel and the scroll bar, clicking a jornada opens it. `/diario debug demo off` goes back to your diary. If it says `botones (...)`, send the reason |
| Addon menu | Click the addon-menu button at the minimap (the one that lists addons) | **Diario de Aventuras** is listed with the book icon and clicking it toggles the book. If it is not listed, run `/diario diag`: "Menú de addons" shows what the TOC field and the function look like |

Send back what each step showed. These answer the "verify in M3/M5" items: whether `Settings.OpenToCategory` takes the category ID on Forever, whether the ScrollBox templates exist and look right, and whether `AddonCompartmentFunc` works with this TOC.

## 3c. M4b checks on Forever (the AJProbe backfill, opt-in conversations)
Do this **after** a first stretch of play, so that AJProbe has data. AdventureJournal has been running meanwhile, so many events are already in the diary: the import fills only the gaps and skips duplicates.

**Before you import anything, back up the two files** (the game must be closed or have just run `/reload`, so they are current). In PowerShell, replace `<ACCOUNT>`, `<Realm>` and `<Character>` with your own folder names:
```
$wtf = "D:\Games\Battle.net\World of Warcraft\_forever_\WTF\Account\<ACCOUNT>"
$backup = "D:\Projects\wow-addons-backup-m4b\forever"
New-Item -ItemType Directory -Force $backup
Copy-Item "$wtf\SavedVariables\AJProbe.lua" $backup
Copy-Item "$wtf\<Realm>\<Character>\SavedVariables\AdventureJournal.lua" $backup
Get-ChildItem $backup
```
Both files must be listed (AJProbe.lua is the only complete record of the first days). The backup folder is outside the repository and outside the game folder.
Optional, outside the game: rehearse on those files (from the `AdventureJournal` folder) with `node tools\import-dryrun.js --probe <AJProbe.lua> --diary <AdventureJournal.lua> --flavor forever`. It writes nothing and prints counts; send me the output.

| Step | What to do | You should see |
|---|---|---|
| Diag | `/diario diag`, look at "Lectura de fechas", "Conversaciones" and "AJProbe" | `Lectura de fechas ...: OK`; `Conversaciones: no. Eventos de chat registrados: 0 de 12`; `AJProbe: presente, N registros de actividad y M mensajes` |
| Dry run | `/diario importar prueba` | A summary ending in `PRUEBA: no se ha guardado nada`. Nothing in the book changes |
| Import | `/diario importar`, then open `/diario` | The summary says how many entries and new jornadas were added. Imported entries read like normal ones; new jornadas may appear between old ones (the one you are playing stays last) |
| Again | `/diario importar` | `+0 acontecimientos`, `No había nada nuevo que importar` |
| Loot | If the summary mentions loot whose quality is not cached | Wait a few seconds, run `/diario importar` again |
| Conversations off | Whisper yourself or have a friend whisper you | A `[Diario]` CHAT entry as before. `/diario conversaciones` says `no`; the book has no conversations button |
| Conversations on | `/diario conversaciones on`, have a friend whisper you, say something | The book shows a **Conversaciones** button; the whisper and your /say are in it. `/diario conversaciones off` hides it and stops capture |
| Import chat | With it on, `/diario importar` | `Conversaciones: ...` line; the earlier chat appears in the right jornadas, nothing repeated |
| Dungeon | Conversations on, party chat and /say inside a 5-player dungeon, then `/diario diag` | Whether the lines were stored, skipped or `[SECRET]`; `Errores en manejadores: ninguno`. This answers "is chat secret in instances" |

Send back: the summary lines of the dry run and the import, the `/diario diag` lines above, a screenshot of the book with the conversations button and of the conversations view, and anything that overlaps in the book's layout (the new buttons are at the bottom of the book).

## 3d. M6 checks on Forever (level, party, reputation, skills, spells; their import)
Five new entry types, all on by default (`/diario tipos` lists them). Everything below is **F** (needs Forever): the harness and Classic Era cannot say what Forever really sends.

| Step | What to do | You should see |
|---|---|---|
| Strings | `/diario diag mensajes` (take a screenshot) | Five lines, none saying `ninguna`, then a round-trip test (one invented sentence per string, `OK` or `NO`) whose **last line** is `RESULTADO: todos los textos se reconocen.`. The five lines: group (6 names), reputation increases (`FACTION_STANDING_INCREASED...`) and changes (`FACTION_STANDING_CHANGED...`), skills (`ERR_SKILL_UP_SI [rank]`, `ERR_SKILL_GAINED_S [new]`), spells (3 names). A `ninguna` means the global has another name on Forever: then type `/run print(ERR_JOINED_GROUP_S)` (and the other names) and send what it prints |
| The texts | `/run print(ERR_JOINED_GROUP_S, ERR_LEFT_GROUP_S, ERR_LEFT_GROUP_YOU, ERR_GROUP_DISBANDED)` and `/run print(FACTION_STANDING_INCREASED, FACTION_STANDING_CHANGED)` and `/run print(ERR_SKILL_UP_SI, ERR_SKILL_GAINED_S, ERR_LEARN_SPELL_S, ERR_LEARN_ABILITY_S)` | The sentences with `%s` / `%d` where the name or number goes. Send them (screenshot). The Spanish ones for group, skills and spells were already seen in AJProbe's Forever file; `FACTION_STANDING_CHANGED` never was |
| Level | Level up once | An entry "He alcanzado el nivel N" with the **new** level (if it shows the old level, tell me) |
| Party | Invite a player, let them join, then they leave, then you leave | One entry per event with the name: `<Name>` joined, `<Name>` left, "He dejado el grupo" or "Mi grupo se ha disuelto". If the names are missing, `/diario debug on` and repeat: send the grey `CHAT_MSG_SYSTEM(...)` line |
| Dungeon group | `/diario debug on`, join a dungeon through the group finder (or a normal 5-player group), then `/diario debug off` and `/diario hoy` | Whether `CHAT_MSG_SYSTEM` payloads print `[SECRET]` there (then no entry from them: expected) and whether `GROUP_JOINED(2, ...)` made "me uní a un grupo ... instancia" with no names. Send the grey lines |
| Reputation | Kill a mob of a faction you have not hit today | One entry the **first** time with that faction ("... ganarme la confianza de X"), none for the next kills, again after a new login. Send a screenshot of the chat line when your standing changes (for example Neutral to Friendly) so the standing entry can be checked: that sentence was never captured |
| Skills | Raise a weapon skill to a multiple of 25, or learn a profession | An entry at 25, 50, 75... and one for "Has ganado la siguiente habilidad" |
| Spells | Learn a spell at a trainer or by levelling | "Aprendí un nuevo hechizo: X" (one per rank) |
| Off | `/diario tipos grupo off`, repeat a join | Nothing is logged; `/diario tipos grupo on` brings it back |

**Import.** Back up first (section 3c has the PowerShell block; for this milestone use `D:\Projects\wow-addons-backup-m6orever`, and copy **both** `AJProbe.lua` and `AdventureJournal.lua`). Rehearsal on a copy of your Forever files (2026-11-05, character Necroroth): the dry run says `Se añadirían: 25 acontecimientos (LEVEL 5, GROUP 8, REPUTATION 1, SKILL 1, SPELL 10)`; the import adds them with 0 new jornadas; the second run adds nothing. If your numbers differ, send the summary lines. The imported group entries carry the names AJProbe saw in the system messages; if you do not want them, `/diario tipos grupo off` before importing.

Send back: the screenshot of `/diario diag mensajes`, the `/run print(...)` lines, the grey debug lines of the dungeon, the standing-change sentence, and the import summaries.

## 4. Inside a dungeon (5-player)
1. Before entering, type `/diario debug on`. From now on grey `[Diario debug]` lines print every event's payload, with `[SECRET]` where the game hides the value.
2. Inside: talk to an NPC, get a whisper (or a message in party chat), loot something, and kill a boss.
3. After the boss, type `/diario diag` and look at `Errores en manejadores`.
4. Copy the grey debug lines for the NPC, the loot, the whisper and the boss. They tell us exactly which values are secret.
5. Type `/diario debug off`, then `/reload`, then `/diario hoy`. Check that entries inside the dungeon read normally (fallback text such as "un habitante de la zona" or "una criatura temible" is expected if values were secret).

## 5. Extras
- `/chatlog` (type it again to stop). Check that `D:\Games\Battle.net\World of Warcraft\_forever_\Logs\WoWChatLog.txt` appears, also after closing the game. On Classic Era it never appeared (bug #15), so do not plan on it for copying diagnostics.
- `/dump select(4, GetBuildInfo())` should print `16001`.

## 6. After you log out
Close the game first: WoW writes SavedVariables on `/reload` or logout.

1. Summarise AJProbe's Forever data (read-only; run from the `AdventureJournal` folder):
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
- The M4b results from section 3c (summaries, diag lines, screenshots).
- The M6 results from section 3d (message strings, dungeon group, the standing-change sentence, import summaries).
- Anything that looked wrong in the UI (missing background texture, wrong button text).
- Whether `/reload` continued the jornada (it should) and a real login started a new one.

Open questions this session answers (all "verify in M3" in the README and ROADMAP): the `PLAYER_ENTERING_WORLD` flags (reload vs login), whether the own-loot patterns match Forever's loot messages (`toolsjprobe_summary.py` counts them), which payloads are really secret in a dungeon, whether `ENCOUNTER_END` / `BOSS_KILL` arguments are secret, which item-cache event fires (`GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT`), what Forever's item links look like, whether zone text is ever secret, whether `C_QuestLog.GetTitleForQuestID` returns titles at `QUEST_TURNED_IN`, and (M4b) whether chat is secret in instances, whether `C_FriendList.IsFriend` / `C_BattleNet.GetGameAccountInfoByGUID` identify friends by GUID, whether `time{...}` converts dates back, and whether `ENCOUNTER_END`'s `success` is the number 1 or a boolean.
