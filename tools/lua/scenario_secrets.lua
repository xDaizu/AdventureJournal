-- Scripted play session with secret values, inside an instance (M2).
-- Part 1 uses the stub's real secret sentinels (STUB.SECRET and STUB.SECRET_NUMBER:
--   they error on arithmetic, #, indexing, concatenation, ordering, tostring, and
--   issecretvalue() recognises them). Part 2 uses `/diario debug secrets`, which
--   is how Classic Era simulates secrets in game.
-- The driver fails the run if any secret reaches AdventureJournalDB.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local SECRET, SECRET_NUMBER = S.SECRET, S.SECRET_NUMBER

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = false, link = Link("|cffa335ee", 5555, "Espada épica") }

local function Events()
    local DB = AdventureJournalDB
    return DB.days[DB.currentDay].events
end

-- Runs fn and notes how many entries it added and what the last one says.
local function Step(label, fn)
    local before = #Events()
    local errorsBefore = #S.errors
    fn()
    local events = Events()
    local added = #events - before
    local last = events[#events]
    for index = before + 1, #events do
        assert(type(events[index].text) == "string" and events[index].text ~= "", label .. ": entry without text")
        assert(type(events[index].prose) == "string" and events[index].prose ~= "", label .. ": entry without prose")
    end
    note(string.format("%s: +%d entries%s%s", label, added,
        added > 0 and string.format(" (last: %s %q)", last.type, last.text) or "",
        #S.errors > errorsBefore and (", " .. (#S.errors - errorsBefore) .. " error(s) reached the error handler") or ""))
end

-- Starts a session like the real game does.
fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")
S.zone, S.subZone = "Cavernas de Lamento", "Entrada"
fire("PLAYER_ENTERING_WORLD", not H.reload, H.reload and true or false)
S.inInstance = true

if H.reload then
    -- Second run: the saved diary must open and read cleanly.
    slash("")
    slash("anterior")
    local f = _G.AdventureJournalBookFrame
    note("reload: viewing jornada 1, body:\n" .. tostring(f.body.text))
    assert(not string.find(f.body.text, "table:", 1, true), "a table leaked into the prose")
    local bad = 0
    for _, day in pairs(AdventureJournalDB.days) do
        for _, entry in ipairs(day.events) do
            if type(entry.text) ~= "string" or type(entry.prose) ~= "string" then bad = bad + 1 end
        end
    end
    note("reload: entries with a missing text or prose: " .. bad)
    slash("diag")
    fire("PLAYER_LOGOUT")
    return
end

-- 0. The stub secret behaves like a real one -----------------------------------------
local function Errors(fn) return not (pcall(fn)) end
note("self-check: issecretvalue(SECRET) = " .. tostring(issecretvalue(SECRET)) .. ", type() = " .. type(SECRET))
note("self-check: concat errors = " .. tostring(Errors(function() return SECRET .. "x" end)))
note("self-check: # errors = " .. tostring(Errors(function() return #SECRET end)))
note("self-check: index errors = " .. tostring(Errors(function() return SECRET.x end)))
note("self-check: method call errors = " .. tostring(Errors(function() return SECRET:match("x") end)))
note("self-check: string.match errors = " .. tostring(Errors(function() return string.match(SECRET, "x") end)))
note("self-check: string.format %s errors = " .. tostring(Errors(function() return string.format("%s", SECRET) end)))
note("self-check: < errors = " .. tostring(Errors(function() return SECRET_NUMBER < 1 end)))
note("self-check: arithmetic errors = " .. tostring(Errors(function() return SECRET_NUMBER + 1 end)))
note("self-check: tonumber errors = " .. tostring(Errors(function() return tonumber(SECRET) end)))
note("self-check: tostring errors = " .. tostring(Errors(function() return tostring(SECRET) end)))
note("self-check: nil test works = " .. tostring(SECRET ~= nil))

slash("diag")

-- 1. Real secret values, debug off ---------------------------------------------------
Step("secret NPC name", function() S.npcName = SECRET; fire("GOSSIP_SHOW") end)
Step("secret NPC again within 20 s (same fallback: deduped)", function() advance(5); fire("GOSSIP_SHOW") end)
S.npcName = "Gornek"

advance(30)
Step("secret whisper sender and text", function() fire("CHAT_MSG_WHISPER", SECRET, SECRET) end)
Step("plain sender, secret text", function() fire("CHAT_MSG_WHISPER", SECRET, "Amigo-OtroReino") end)

Step("secret loot message", function()
    fire("CHAT_MSG_LOOT", SECRET, SECRET, SECRET, SECRET, SECRET, SECRET_NUMBER)
end)
Step("plain loot message (a blue item)", function()
    advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
end)
Step("uncached epic, secret item ID callback, then ITEM_DATA_LOAD_RESULT", function()
    fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5555].link .. ".", "", "", "", "Volgajin")
    fire("GET_ITEM_INFO_RECEIVED", SECRET_NUMBER, true)      -- must be ignored
    fire("ITEM_DATA_LOAD_RESULT", SECRET_NUMBER, SECRET)     -- must be ignored
    S.items[5555].cached = true
    fire("ITEM_DATA_LOAD_RESULT", 5555, true)                -- logs the item
    fire("GET_ITEM_INFO_RECEIVED", 5555, true)               -- already logged: no duplicate
end)

advance(30)
Step("BOSS_KILL, secret name", function() fire("BOSS_KILL", SECRET_NUMBER, SECRET) end)
Step("ENCOUNTER_END kill, secret name, same kill within 5 s (deduped)", function()
    fire("ENCOUNTER_END", SECRET_NUMBER, SECRET, SECRET_NUMBER, SECRET_NUMBER, 1)
end)
Step("ENCOUNTER_END, secret success flag (skipped)", function()
    advance(10); fire("ENCOUNTER_END", SECRET_NUMBER, SECRET, SECRET_NUMBER, SECRET_NUMBER, SECRET_NUMBER)
end)
Step("ENCOUNTER_END kill, readable name, secret difficulty and size", function()
    advance(10); fire("ENCOUNTER_END", 1145, "Jefe visible", SECRET_NUMBER, SECRET_NUMBER, 1)
end)
Step("ENCOUNTER_END wipe, secret name (skipped)", function()
    advance(10); fire("ENCOUNTER_END", 1145, SECRET, 1, 5, 0)
end)

Step("QUEST_TURNED_IN, secret quest ID", function()
    advance(5); fire("QUEST_TURNED_IN", SECRET_NUMBER, SECRET_NUMBER, SECRET_NUMBER)
end)

Step("zone text secret: no DISCOVERY entry", function()
    S.zone, S.subZone = SECRET, SECRET; fire("ZONE_CHANGED")
end)
Step("death while the zone is secret (place falls back)", function()
    advance(5); fire("PLAYER_DEAD")
end)
note("place of that entry: " .. tostring(Events()[#Events()].place))
S.zone, S.subZone = "Cavernas de Lamento", "Cámara del jefe"
Step("zone readable again: DISCOVERY", function() fire("ZONE_CHANGED") end)

-- 2. Error isolation ----------------------------------------------------------------
local realCompose = ns.ComposeEntry
ns.ComposeEntry = function() error("boom (test)", 0) end
Step("a handler that fails (first time)", function() advance(5); fire("PLAYER_DEAD") end)
Step("the same handler fails again (counted, not reported again)", function() fire("PLAYER_DEAD") end)
ns.ComposeEntry = realCompose
Step("other handlers keep working afterwards", function() advance(5); fire("PLAYER_DEAD") end)
for _, message in ipairs(S.errors) do note("error handler received: " .. message) end
for event, record in pairs(ns.handlerErrors) do note(string.format("handlerErrors[%s] = count %d", event, record.count)) end

-- 3. /diario debug on, with real secrets --------------------------------------------
slash("debug")                    -- no argument: usage
slash("debug on")
advance(30)
S.npcName = SECRET; fire("GOSSIP_SHOW"); S.npcName = "Gornek"
fire("CHAT_MSG_WHISPER", SECRET, SECRET)
fire("CHAT_MSG_LOOT", SECRET, SECRET, SECRET, SECRET, SECRET, SECRET_NUMBER)
advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
advance(10); fire("ENCOUNTER_END", 1146, "Jefe de prueba", 8, 5, 1)
fire("ENCOUNTER_END", SECRET_NUMBER, SECRET, SECRET_NUMBER, SECRET_NUMBER, SECRET_NUMBER)
fire("QUEST_TURNED_IN", SECRET_NUMBER, SECRET_NUMBER, SECRET_NUMBER)
slash("diag")
slash("debug off")
advance(30); fire("CHAT_MSG_WHISPER", "texto", "Amigo-OtroReino")   -- debug off: no debug lines

-- 4. /diario debug secrets: plain strings are turned into simulated secrets ------------
note("simulated secrets: Taint('x') is secret before = " .. tostring(ns.IsSecret(ns.Taint("x"))))
slash("debug secrets")
local tainted = ns.Taint("x")
note("simulated secrets: Taint('x') is secret = " .. tostring(ns.IsSecret(tainted)) ..
     ", concat errors = " .. tostring(Errors(function() return tainted .. "x" end)) ..
     ", string.match errors = " .. tostring(Errors(function() return string.match(tainted, "x") end)))
advance(30)
Step("simulated: NPC name", function() fire("GOSSIP_SHOW") end)
Step("simulated: whisper from a friend", function() advance(1); fire("CHAT_MSG_WHISPER", "texto", "Amigo-OtroReino") end)
Step("simulated: loot message (skipped)", function()
    advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
end)
Step("simulated: BOSS_KILL", function() advance(10); fire("BOSS_KILL", 1147, "Jefe de prueba") end)
Step("simulated: ENCOUNTER_END kill", function() advance(10); fire("ENCOUNTER_END", 1148, "Otro jefe", 1, 5, 1) end)
slash("diag")
slash("debug secrets off")
Step("simulation off: loot works again", function()
    advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
end)
slash("debug secrets")
slash("debug off")                -- turns both off
Step("after /diario debug off: whisper plain again", function() advance(1); fire("CHAT_MSG_WHISPER", "texto", "Amigo-OtroReino") end)

fire("PLAYER_LOGOUT")
