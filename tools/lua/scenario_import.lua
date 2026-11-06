-- M4b: /diario importar against a synthetic AJProbeDB (shape: fixture_ajprobe.lua).
-- Variants (H.variant):
--   empty    a diary with no jornadas: partial session, logins, reloads, duplicates, secret records,
--            records of another character, other players' loot, malformed records, chat.
--            Dry run, import, run twice, uncached loot cached later, conversations off then on.
--   overlap  a diary whose jornadas overlap the log (live entries for the same events, a
--            pre-M4 reload-split pair, a session with no jornada, the current jornada). Existing
--            entries must not change; duplicates are skipped; types switched off are not imported.
--   notimetable  a client where time{...} does not work: dates cannot be read back from the strings,
--            so imported jornadas rely on the epochs they store (startTs/endTs); still idempotent.
--   noprobe  AJProbe missing, empty, garbage, another character only, and an unreadable player name.
-- Every variant checks that AJProbeDB itself is never modified (the import only reads it).
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local F = dofile(string.match(SCENARIO, "^(.*)/[^/]*$") .. "/fixture_ajprobe.lua")
local Snap = F.Snapshot

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = false, link = Link("|cffa335ee", 5555, "Espada épica") }
S.items[7098] = { name = "Colmillo astillado", quality = 0, cached = true, link = Link("|cff9d9d9d", 7098, "Colmillo astillado") }

local function Describe()
    local db = AdventureJournalDB
    note(string.format("diary: currentDay = %d, jornadas in days = %d", db.currentDay, #db.days))
    for index = 1, db.currentDay do
        local day = db.days[index]
        local conversations = day.conversations and #day.conversations or 0
        local types = {}
        for _, entry in ipairs(day.events) do types[#types + 1] = entry.type:sub(1, 2) .. (entry.source and "*" or "") end
        note(string.format("  jornada %d: %s -> %s, %d entradas [%s], %d conversaciones%s", index, tostring(day.startedAt),
            tostring(day.endedAt), #day.events, table.concat(types, " "), conversations, day.source and ", source=" .. day.source or ""))
    end
end

-- Every conversation line and entry must have the fields the book and the exporter read.
local function CheckShapes()
    for index = 1, AdventureJournalDB.currentDay do
        local day = AdventureJournalDB.days[index]
        local lastStamp
        for _, entry in ipairs(day.events) do
            assert(type(entry.type) == "string" and type(entry.text) == "string" and type(entry.prose) == "string"
                and type(entry.time) == "string" and type(entry.timestamp) == "number" and type(entry.place) == "string",
                "malformed entry in jornada " .. index)
            assert(not lastStamp or entry.timestamp >= lastStamp, "entries out of time order in jornada " .. index)
            lastStamp = entry.timestamp
        end
        for _, line in ipairs(day.conversations or {}) do
            assert(type(line.text) == "string" and type(line.channel) == "string" and type(line.timestamp) == "number"
                and type(line.time) == "string" and type(line.place) == "string", "malformed conversation in jornada " .. index)
        end
    end
end

local function Prints(from)
    local out = {}
    for index = from + 1, #S.prints do out[#out + 1] = S.prints[index] end
    return out
end

-- Runs /diario importar [prueba] and checks what must hold for every run.
local function RunImport(label, argument, expectChange)
    local diaryBefore, probeBefore = Snap(AdventureJournalDB), Snap(AJProbeDB)
    local mark = #S.prints
    note("== " .. label)
    slash("importar" .. (argument and (" " .. argument) or ""))
    assert(Snap(AJProbeDB) == probeBefore, "the import modified AJProbeDB")
    if argument == "prueba" then
        assert(Snap(AdventureJournalDB) == diaryBefore, "a dry run modified the diary")
        note("dry run: the diary is byte-identical afterwards")
    elseif expectChange == false then
        assert(Snap(AdventureJournalDB) == diaryBefore, "a repeated import changed the diary")
        note("repeat: the diary is byte-identical afterwards")
    end
    CheckShapes()
    return Prints(mark)
end

local function SetUp()
    fire("ADDON_LOADED", "AdventureJournal")
    fire("PLAYER_LOGIN")
end

-- ===================================================================================
if H.variant == "noprobe" then
    SetUp()
    fire("PLAYER_ENTERING_WORLD", true, false)
    local diary = Snap(AdventureJournalDB)
    local function Check(label, probe)
        AJProbeDB = probe
        slash("importar")
        slash("importar prueba")
        assert(Snap(AdventureJournalDB) == diary, label .. " changed the diary")
        note(label .. ": diary unchanged")
    end
    Check("AJProbeDB missing", nil)
    Check("AJProbeDB is a string", "garbage")
    Check("AJProbeDB empty table", {})
    Check("AJProbeDB with empty lists", { log = {}, chat = {} })

    -- Another character's records only: reads them, imports nothing, no error.
    local other = F.New()
    other.Log(S.clock - 500, "PLAYER_ENTERING_WORLD", { login = true, reload = false }, F.OTHER)
    other.Log(S.clock - 490, "PLAYER_DEAD", nil, F.OTHER)
    table.insert(other.db.log, false)
    table.insert(other.db.log, { e = "PLAYER_DEAD" })   -- no timestamp, no character
    Check("only another character", other.db)

    -- A player name that cannot be read (a secret) gives a message, not an error.
    S.playerName = S.SECRET
    Check("unreadable player name", other.db)
    S.playerName = "Volgajin"
    local errors = 0
    for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
    note("handler errors: " .. errors .. "; errors reaching the error handler: " .. #S.errors)
    slash("importar xyz")
    slash("importar prueba extra")
    return
end

-- ===================================================================================
if H.variant == "notimetable" then
    local B = S.clock - 50000
    local function Stamp(t) return date("%Y-%m-%d %H:%M:%S", t) end
    AdventureJournalDB = { version = 2, currentDay = 1, visited = {},
        days = { [1] = { startedAt = Stamp(B), endedAt = Stamp(B + 300), dateLabel = "x", events = {} } } }
    local fixture = F.New()
    fixture.Log(B, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.Log(B + 10, "QUEST_TURNED_IN", { quest = 100, xp = 5, money = 0, title = "Misión sin fecha" })
    fixture.Log(B + 300, "PLAYER_LOGOUT")
    fixture.Log(B + 5000, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.Log(B + 5010, "PLAYER_DEAD")
    fixture.Log(B + 5100, "PLAYER_LOGOUT")
    AJProbeDB = fixture.db
    SetUp()
    note("date parsing works here = " .. tostring(ns.ParseDateTime(Stamp(B)) ~= nil))
    slash("diag")
    RunImport("first import (the empty jornada cannot be dated, so its session gets a jornada of its own)")
    Describe()
    RunImport("second import: nothing new, byte-identical", nil, false)
    RunImport("third import", nil, false)
    local ranged = 0
    for index = 1, AdventureJournalDB.currentDay do
        if AdventureJournalDB.days[index].startTs then ranged = ranged + 1 end
    end
    note("imported jornadas keep their epochs: " .. ranged)
    return
end

-- ===================================================================================
if H.variant == "empty" then
    local fixture = F.New()
    local T0 = S.clock - 200000
    local T1, T2, T3 = T0 + 3600, T0 + 3600 + 7200, T0 + 3600 + 7200 + 10000
    local epic = S.items[5555].link
    local blue, grey = S.items[1234].link, S.items[7098].link

    -- A partial session: the log starts in the middle of one (a reload, no login record).
    fixture.At("Durotar", "Poblado Sen'jin")
    fixture.Log(T0, "ZONE_CHANGED")
    fixture.Log(T0 + 30, "PLAYER_DEAD")
    fixture.Log(T0 + 60, "PLAYER_LOGOUT")
    fixture.Log(T0 + 61, "PLAYER_ENTERING_WORLD", { login = false, reload = true })
    fixture.Log(T0 + 70, "GOSSIP_SHOW", { npc = "Gornek" })
    fixture.Log(T0 + 90, "PLAYER_LOGOUT")

    -- Session 1: a real login. The zone is nil at login (observed in M0).
    fixture.At("<nil>", "")
    fixture.Log(T1, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(T1 + 1, "ZONE_CHANGED_NEW_AREA")
    fixture.Log(T1 + 1, "PLAYER_ALIVE", { a = { "<nil>" } })
    fixture.Log(T1, "PLAYER_ENTERING_WORLD", { login = false, reload = false })   -- a loading screen: no new jornada
    fixture.Log(T1 + 10, "GOSSIP_SHOW", { npc = "Gornek" })
    fixture.Log(T1 + 15, "GOSSIP_SHOW", { npc = "Gornek" })             -- same NPC within 20 s: one entry
    fixture.Log(T1 + 45, "GOSSIP_SHOW", { npc = "Gornek" })
    fixture.Log(T1 + 50, "GOSSIP_SHOW", { npc = "[SECRET]" })           -- neutral text
    fixture.Log(T1 + 20, "CHAT_MSG_WHISPER", { from = "Amigo-ZandalarTribe" })     -- the CHAT entry: sender only
    fixture.Log(T1 + 21, "CHAT_MSG_WHISPER", { from = "[SECRET]" })                 -- neutral sender
    fixture.Log(T1 + 22, "CHAT_MSG_WHISPER", { from = "<nil>" })                    -- nothing to write
    fixture.Log(T1 + 60, "QUEST_TURNED_IN", { quest = 4641, xp = 40, money = 0, title = "Tu lugar en el mundo" })
    fixture.Log(T1 + 61, "QUEST_TURNED_IN", { quest = 4641, xp = 40, money = 0, title = "Tu lugar en el mundo" })   -- duplicate
    fixture.Log(T1 + 70, "QUEST_TURNED_IN", { quest = "[SECRET]", xp = "[SECRET]", money = "[SECRET]", title = "[SECRET]" })
    fixture.Log(T1 + 80, "QUEST_TURNED_IN", { quest = 9999, xp = 0, money = 0, title = "<unknown>" })
    fixture.Log(T1 + 90, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. blue .. ".", item = 1234, quality = 3, who = "Volgajin" })
    fixture.Log(T1 + 91, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. grey .. ".", item = 7098, quality = 0, who = "Volgajin" })
    fixture.Log(T1 + 92, "CHAT_MSG_LOOT", { msg = "Thrall recibe el botín: " .. blue .. ".", item = 1234, quality = 3, who = "Thrall" })
    fixture.Log(T1 + 93, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. epic .. ".", item = 5555, who = "Volgajin" })   -- quality unknown then
    fixture.Log(T1 + 94, "CHAT_MSG_LOOT", { secret = true })
    fixture.Log(T1 + 100, "BOSS_KILL", { id = 1144, name = "Jefe de prueba" })
    fixture.Log(T1 + 101, "ENCOUNTER_END", { id = 1144, name = "Jefe de prueba", difficulty = 1, size = 5, success = 1 })   -- same kill
    fixture.Log(T1 + 120, "ENCOUNTER_END", { id = 1145, name = "Otro jefe", difficulty = 1, size = 5, success = 0 })       -- wipe
    fixture.Log(T1 + 130, "ENCOUNTER_END", { id = 1145, name = "Otro jefe", difficulty = 1, size = 5, success = 1 })
    fixture.Log(T1 + 131, "ENCOUNTER_END", { id = "[SECRET]", name = "[SECRET]", difficulty = "[SECRET]", size = "[SECRET]", success = "[SECRET]" })
    fixture.Log(T1 + 132, "BOSS_KILL", { id = "[SECRET]", name = "[SECRET]" })
    fixture.Log(T1 + 140, "PLAYER_DEAD")
    fixture.Log(T1 + 150, "PLAYER_LEVEL_UP", { level = 2 })              -- backlog: no entry type for it yet
    fixture.Log(T1 + 151, "CHAT_MSG_SYSTEM", { a = { "Algo ocurrió" } })
    fixture.At("Durotar", "El Cubil")
    fixture.Log(T1 + 160, "ZONE_CHANGED")
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(T1 + 170, "ZONE_CHANGED")                                 -- already visited
    fixture.At("Durotar", "")
    fixture.Log(T1 + 171, "ZONE_CHANGED")                                 -- zone-only after a subzone: bug #16 rule, skipped
    fixture.At("[SECRET]", "[SECRET]")
    fixture.Log(T1 + 180, "ZONE_CHANGED")                                 -- secret place: skipped
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(T1 + 200, "PLAYER_LOGOUT")                                -- /reload
    fixture.Log(T1 + 201, "PLAYER_ENTERING_WORLD", { login = false, reload = true })
    fixture.Log(T1 + 210, "QUEST_TURNED_IN", { quest = 7000, xp = 10, money = 0, title = "Otra misión" })
    fixture.Log(T1 + 300, "PLAYER_LOGOUT")
    -- Another character on the same account, interleaved, plus records that are not records.
    fixture.Log(T1 + 20, "PLAYER_ENTERING_WORLD", { login = true, reload = false }, F.OTHER)
    fixture.Log(T1 + 25, "QUEST_TURNED_IN", { quest = 1, title = "Misión ajena" }, F.OTHER)
    table.insert(fixture.db.log, false)
    table.insert(fixture.db.log, { e = "PLAYER_DEAD", c = F.KEY })         -- no timestamp
    -- Session 2.
    fixture.At("<nil>", "")
    fixture.Log(T2, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Orgrimmar", "")
    fixture.Log(T2 + 1, "ZONE_CHANGED_NEW_AREA")
    fixture.At("Orgrimmar", "Valle de la Fuerza")
    fixture.Log(T2 + 20, "ZONE_CHANGED")
    fixture.At("Orgrimmar", "")
    fixture.Log(T2 + 40, "ZONE_CHANGED")
    fixture.Log(T2 + 60, "PLAYER_LOGOUT")
    -- Session 3: nothing but a login and a logout. It still gets its jornada.
    fixture.At("Orgrimmar", "")
    fixture.Log(T3, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.Log(T3 + 5, "PLAYER_LOGOUT")

    -- Conversations (AJProbeDB.chat).
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Chat(T1 + 20, "WHISPER", { who = "Amigo-ZandalarTribe", msg = "Hola, ¿vienes a Orgrimmar?" })
    fixture.Chat(T1 + 22, "WHISPER_INFORM", { who = "Amigo-ZandalarTribe", msg = "Claro, voy ya", rel = "friend" })
    fixture.Chat(T1 + 23, "WHISPER_INFORM", { who = "Amigo-ZandalarTribe", msg = "Claro, voy ya", rel = "friend" })   -- duplicate
    fixture.Chat(T1 + 30, "BN_WHISPER", { who = false, btag = "Compi#1234", msg = "¿Vienes a jugar?", rel = "bnfriend", lang = false })
    fixture.Chat(T1 + 35, "PARTY", { who = "Jaina-ZandalarTribe", msg = "Listos", rel = "group" })
    fixture.Chat(T1 + 36, "RAID_LEADER", { who = "Jaina-ZandalarTribe", msg = "A la carga", rel = "group" })
    fixture.Chat(T1 + 40, "SAY", { who = "Volgajin-ZandalarTribe", msg = "¡Por la Horda!", rel = "me" })
    fixture.Chat(T1 + 41, "SAY", { who = "Extraño-ZandalarTribe", msg = "Compro oro", rel = false })    -- a stranger: not kept
    fixture.Chat(T1 + 42, "YELL", { who = "Baine-ZandalarTribe", msg = "¡Atentos!", rel = "friend" })
    fixture.Chat(T1 + 43, "EMOTE", { who = "Volgajin-ZandalarTribe", msg = "saluda con la cabeza.", rel = "me", lang = false })
    fixture.Chat(T1 + 44, "TEXT_EMOTE", { who = "Volgajin-ZandalarTribe", msg = "Volgajin saluda a Gornek.", rel = "me", lang = false })
    fixture.Chat(T1 + 46, "WHISPER", { who = "[SECRET]", msg = "[SECRET]", lang = "[SECRET]" })              -- instance chat
    fixture.Chat(T1 + 47, "GUILD", { who = "Cheff-ZandalarTribe", msg = "Buenas", rel = "friend" })           -- not a channel we keep
    fixture.Chat(T1 + 48, "SAY", { who = "Otro-ZandalarTribe", msg = "No es mi personaje", rel = "friend" }, F.OTHER)
    fixture.Chat(T2 + 10, "WHISPER", { who = "Amigo-ZandalarTribe", msg = "Ya estoy en la ciudad", z = "Orgrimmar", s = "Valle de la Fuerza" })
    fixture.Chat(T0 - 99999, "WHISPER", { who = "Viejo-ZandalarTribe", msg = "Esto es de antes de todo" })    -- no jornada to hold it

    AJProbeDB = fixture.db
    local probeAtStart = Snap(AJProbeDB)
    SetUp()
    note("start: currentDay = " .. AdventureJournalDB.currentDay .. " (no jornada yet); conversations option = "
        .. tostring(AdventureJournalDB.settings.conversations))

    RunImport("dry run", "prueba")
    RunImport("first import")
    Describe()
    RunImport("second import: nothing new, byte-identical", nil, false)

    S.items[5555].cached = true
    RunImport("the epic is cached now: one more LOOT")
    RunImport("and again", nil, false)

    local withConversations = 0
    for index = 1, AdventureJournalDB.currentDay do
        if AdventureJournalDB.days[index].conversations then withConversations = withConversations + 1 end
    end
    note("conversations option off: jornadas holding conversations = " .. withConversations)
    assert(withConversations == 0, "conversations were imported while the option was off")

    slash("conversaciones on")
    RunImport("conversations on: dry run", "prueba")
    RunImport("conversations on: import")
    Describe()
    RunImport("conversations on: second import", nil, false)

    -- The book: events view and conversations view of the first jornada with conversations.
    for index = 1, AdventureJournalDB.currentDay do
        if AdventureJournalDB.days[index].conversations then
            ns.OpenAtDay(index)
            note("book, events view, jornada " .. index .. ":\n" .. tostring(_G.AdventureJournalBookFrame.body.text))
            ns.SetBookView("conversations")
            note("book, conversations view, jornada " .. index .. ":\n" .. tostring(_G.AdventureJournalBookFrame.body.text))
            ns.SetBookView("events")
            break
        end
    end
    -- Option off again: the stored lines stay in the file but nothing shows.
    slash("conversaciones off")
    ns.SetBookView("conversations")
    note("conversations off, view asked for 'conversations': body shows events again = "
        .. tostring(not string.find(tostring(_G.AdventureJournalBookFrame.body.text), "Amigo", 1, true)))
    RunImport("conversations off again: import skips the chat", nil, false)
    ns.SetBookView("events")

    assert(Snap(AJProbeDB) == probeAtStart, "AJProbeDB changed during the scenario")
    note("AJProbeDB is byte-identical after every import")

    -- The next real login starts a new jornada after the imported ones.
    local before = AdventureJournalDB.currentDay
    fire("PLAYER_ENTERING_WORLD", true, false)
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    advance(5); fire("GOSSIP_SHOW")
    note(string.format("next login: currentDay %d -> %d, the new jornada has %d entries", before, AdventureJournalDB.currentDay,
        #AdventureJournalDB.days[AdventureJournalDB.currentDay].events))
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
if H.variant == "overlap" then
    local B = S.clock - 100000
    local function Stamp(t) return date("%Y-%m-%d %H:%M:%S", t) end
    local function Clock(t) return date("%H:%M:%S", t) end
    local function Entry(kind, text, t, extra)
        local entry = { type = kind, text = text, place = "Valle de los Retos, Durotar", zone = "Durotar", subZone = "Valle de los Retos",
            time = Clock(t), timestamp = t, characterProfile = "Heroico", contextualTone = "con el ánimo firme", seed = 1,
            prose = "Prosa guardada de " .. text }
        for key, value in pairs(extra or {}) do entry[key] = value end
        return entry
    end
    local epic, blue = S.items[5555].link, S.items[1234].link
    S.items[5555].cached = true

    -- A diary as M5 saved it: schema v2, settings without anything new, no conversations anywhere.
    AdventureJournalDB = {
        version = 2, currentDay = 3,
        visited = { ["Valle de los Retos, Durotar"] = true },
        settings = { chat = "important", showProfile = false, conversations = false,
            types = { QUEST = true, BOSS = true, DEATH = true, LOOT = true, DISCOVERY = true, NPC = true, CHAT = true } },
        days = {
            [1] = { startedAt = Stamp(B), endedAt = Stamp(B + 600), dateLabel = "01/01/2000", events = {
                Entry("DISCOVERY", "Valle de los Retos, Durotar", B + 2),
                Entry("NPC", "Gornek", B + 100),
                Entry("QUEST", "Tu lugar en el mundo", B + 200, { questID = 4641 }),
            } },
            -- A pre-M4 reload split one play session into two jornadas, seconds apart.
            [2] = { startedAt = Stamp(B + 3600), endedAt = Stamp(B + 3700), dateLabel = "01/01/2000", events = {
                Entry("LOOT", epic, B + 3650, { itemID = 5555, itemQuality = 4, itemLink = epic }),
            } },
            [3] = { startedAt = Stamp(B + 3702), endedAt = Stamp(B + 3900), dateLabel = "01/01/2000", events = {
                Entry("DEATH", "He caído en combate", B + 3800),
            } },
        },
    }
    local originals = {}
    for index = 1, 3 do
        local day = AdventureJournalDB.days[index]
        local copy = {}
        for key, value in pairs(day) do if key ~= "events" then copy[key] = value end end
        originals[#originals + 1] = { day = day, fields = Snap(copy), entries = {} }
        for _, entry in ipairs(day.events) do
            table.insert(originals[#originals].entries, { entry = entry, snapshot = Snap(entry) })
        end
    end
    local visitedBefore = Snap(AdventureJournalDB.visited)

    SetUp()
    slash("conversaciones on")
    S.zone, S.subZone = nil, ""
    fire("PLAYER_ENTERING_WORLD", true, false)           -- the live jornada: number 4
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    advance(10); fire("GOSSIP_SHOW")                     -- a live NPC entry at clock + 10
    advance(2); fire("CHAT_MSG_WHISPER", "Hola desde el juego", "Amigo-ZandalarTribe", "", "", "", "", "", "", "", "", "", "Player-1-AMIGO")
    fire("CHAT_MSG_WHISPER_INFORM", "Respuesta en vivo", "Amigo-ZandalarTribe", "", "", "", "", "", "", "", "", "", "Player-1-AMIGO")
    local liveStart = S.clock
    advance(48)
    note("setup: jornada 4 is the live one, " .. #AdventureJournalDB.days[4].events .. " live entries, "
        .. #AdventureJournalDB.days[4].conversations .. " live conversation lines")

    local fixture = F.New()
    local now0 = liveStart - 12   -- the login second of the live jornada
    -- Session 1 overlaps jornada 1.
    fixture.At("<nil>", "")
    fixture.Log(B, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(B + 2, "ZONE_CHANGED_NEW_AREA")                                       -- visited
    fixture.Log(B + 101, "GOSSIP_SHOW", { npc = "Gornek" })                           -- same as the live entry at B + 100
    fixture.Log(B + 201, "QUEST_TURNED_IN", { quest = 4641, xp = 40, money = 0, title = "Tu lugar en el mundo" })   -- same
    fixture.Log(B + 300, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. blue .. ".", item = 1234, quality = 3, who = "Volgajin" })   -- new
    fixture.Log(B + 400, "PLAYER_DEAD")                                               -- new
    fixture.Log(B + 600, "PLAYER_LOGOUT")
    fixture.Chat(B + 150, "WHISPER", { who = "Amigo-ZandalarTribe", msg = "Un susurro de aquel día" })
    -- Session 2 spans the pre-M4 pair (jornadas 2 and 3) and the reload between them.
    fixture.Log(B + 3600, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.Log(B + 3651, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. epic .. ".", item = 5555, quality = 4, who = "Volgajin" })   -- same item
    fixture.At("Durotar", "El Cubil")
    fixture.Log(B + 3660, "ZONE_CHANGED")                                             -- new place, inside jornada 2
    fixture.Log(B + 3700, "PLAYER_LOGOUT")
    fixture.Log(B + 3701, "PLAYER_ENTERING_WORLD", { login = false, reload = true })
    fixture.Log(B + 3801, "PLAYER_DEAD")                                              -- same as jornada 3's death
    fixture.Log(B + 3850, "BOSS_KILL", { id = 1144, name = "Jefe de prueba" })        -- new, inside jornada 3
    fixture.Log(B + 3900, "PLAYER_LOGOUT")
    -- Session 3 has no jornada: it becomes a new one between jornada 3 and the live one.
    fixture.At("<nil>", "")
    fixture.Log(B + 7200, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.Log(B + 7210, "QUEST_TURNED_IN", { quest = 100, xp = 5, money = 0, title = "Misión nueva" })
    fixture.At("Orgrimmar", "")
    fixture.Log(B + 7220, "ZONE_CHANGED")
    fixture.Log(B + 7500, "PLAYER_LOGOUT")
    fixture.Chat(B + 7230, "SAY", { who = "Volgajin-ZandalarTribe", msg = "Ya estoy en Orgrimmar", rel = "me", z = "Orgrimmar", s = "" })
    -- Session 4 is the live one (login at the same second as the live jornada).
    fixture.At("<nil>", "")
    fixture.Log(now0, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(liveStart - 2, "GOSSIP_SHOW", { npc = "Gornek" })                     -- same as the live entry
    fixture.Log(liveStart, "CHAT_MSG_WHISPER", { from = "Amigo-ZandalarTribe" })      -- same as the live CHAT entry
    fixture.Log(liveStart + 20, "PLAYER_DEAD")                                        -- not live: gets added to the live jornada
    fixture.Chat(liveStart - 1, "WHISPER", { who = "Amigo-ZandalarTribe", msg = "Hola desde el juego" })                       -- live duplicate
    fixture.Chat(liveStart + 1, "WHISPER_INFORM", { who = "Amigo-ZandalarTribe", msg = "Respuesta en vivo", rel = "friend" })    -- live duplicate
    fixture.Chat(liveStart + 25, "WHISPER", { who = "Amigo-ZandalarTribe", msg = "Esto solo lo vio AJProbe" })
    AJProbeDB = fixture.db
    local probeAtStart = Snap(AJProbeDB)

    RunImport("dry run", "prueba")
    -- A type switched off is not imported, and its places are not marked visited.
    slash("tipos lugares off")
    RunImport("DISCOVERY switched off")
    note("visited is untouched while DISCOVERY is off = " .. tostring(Snap(AdventureJournalDB.visited) == visitedBefore))
    Describe()
    slash("tipos lugares on")
    RunImport("DISCOVERY back on: the places arrive now")
    Describe()
    RunImport("repeat: nothing new", nil, false)

    -- Existing entries and jornadas are exactly what they were.
    local kept = 0
    for _, original in ipairs(originals) do
        local found
        for index = 1, AdventureJournalDB.currentDay do
            if AdventureJournalDB.days[index] == original.day then found = AdventureJournalDB.days[index] end
        end
        assert(found, "an existing jornada disappeared")
        local copy = {}
        for key, value in pairs(found) do if key ~= "events" and key ~= "conversations" then copy[key] = value end end
        assert(Snap(copy) == original.fields, "an existing jornada's own fields changed")
        for _, saved in ipairs(original.entries) do
            local present = false
            for _, entry in ipairs(found.events) do if entry == saved.entry then present = true end end
            assert(present, "an existing entry disappeared")
            assert(Snap(saved.entry) == saved.snapshot, "an existing entry was modified")
            kept = kept + 1
        end
    end
    note("existing jornadas and their " .. kept .. " entries: all present and byte-identical")
    note("the live jornada is still the last one: currentDay = " .. AdventureJournalDB.currentDay
        .. ", its startedAt = " .. AdventureJournalDB.days[AdventureJournalDB.currentDay].startedAt)
    assert(AdventureJournalDB.days[AdventureJournalDB.currentDay].startedAt == Stamp(liveStart - 12), "the live jornada is not last")
    assert(Snap(AJProbeDB) == probeAtStart, "AJProbeDB changed during the scenario")
    note("AJProbeDB is byte-identical after every import")

    -- Live play goes on in the right jornada.
    advance(30); fire("PLAYER_DEAD")
    note("a live death after the import goes into jornada " .. AdventureJournalDB.currentDay .. ": "
        .. #AdventureJournalDB.days[AdventureJournalDB.currentDay].events .. " entries")
    fire("PLAYER_LOGOUT")
    return
end

error("unknown variant: " .. tostring(H.variant))
