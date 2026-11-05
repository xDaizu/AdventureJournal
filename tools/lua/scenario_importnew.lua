-- M6: /diario importar for the entry types added after M5 (LEVEL, GROUP, REPUTATION, SKILL, SPELL),
-- against a synthetic AJProbeDB (shape: fixture_ajprobe.lua; the message texts are the shapes seen in
-- the real AJProbe files, with invented names).
-- Variants (H.variant):
--   types      one fixture with records of every new type and of the old ones: dry run, import, a second
--              run that must change nothing, records already in the diary (live entries), unreadable
--              records, then each new type switched off in turn (not imported) on a fresh diary.
--   off_with / off_without
--              all the new types switched off; `off_with` has the new records in the log, `off_without`
--              does not. run.js checks that the two saved diaries are byte-identical: the import with
--              every new type off equals the M4b import.
-- Every run asserts that AJProbeDB is never modified.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local F = dofile(string.match(SCENARIO, "^(.*)/[^/]*$") .. "/fixture_ajprobe.lua")
local Snap = F.Snapshot
-- T4a adds QUEST_ACCEPT and GUILD (REVISIT and the death killer are not in AJProbe's records: nothing to import).
local NEW_TYPES = { "LEVEL", "GROUP", "REPUTATION", "SKILL", "SPELL", "QUEST_ACCEPT", "GUILD" }
-- The fields, besides type and text, that each new type stores in an entry (compared live vs imported).
local EXTRA_FIELDS = { "level", "groupEvent", "repEvent", "standing", "skillEvent", "rank", "spellID", "learnKind", "questID", "guildEvent" }

S.questTitles[4641] = "Tu lugar en el mundo"
S.questTitles[4642] = "Cuernos rotos"
S.questLog = { { title = "Tu lugar en el mundo", questID = 4641 }, { title = "Cuernos rotos", questID = 4642 } }
-- QUEST_ACCEPTED as AJProbe records it: a = { questID } on Forever (observed), { questLogIndex, questID } on Classic.
local function AcceptedArgs(id, index)
    if FLAVOR == "classic" then return { index or 1, id } end
    return { id }
end

-- Messages as each client words them (see scenario_newtypes.lua).
local function Gain(faction, amount) return (string.format(FACTION_STANDING_INCREASED, faction, amount)) end
local function Standing(faction, standing)
    if FLAVOR == "classic" then return "Ahora eres " .. standing .. " con " .. faction .. "." end
    return "Con " .. faction .. " ahora eres " .. standing .. "."
end
local function Spell(id, name) return "|cff71d5ff|Hspell:" .. id .. ":0|h[" .. name .. "]|h|r" end

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }

local function Counts()
    local counts, total = {}, 0
    for index = 1, AdventureJournalDB.currentDay do
        for _, entry in ipairs(AdventureJournalDB.days[index].events) do
            counts[entry.type] = (counts[entry.type] or 0) + 1
            total = total + 1
        end
    end
    local parts = {}
    for _, info in ipairs(ns.TYPE_INFO) do parts[#parts + 1] = info.key .. "=" .. (counts[info.key] or 0) end
    return table.concat(parts, " "), counts, total
end

local function Describe(label)
    local text = Counts()
    note(label .. ": " .. AdventureJournalDB.currentDay .. " jornadas; " .. text)
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
    for index = 1, AdventureJournalDB.currentDay do
        local lastStamp
        for _, entry in ipairs(AdventureJournalDB.days[index].events) do
            assert(type(entry.type) == "string" and type(entry.text) == "string" and type(entry.prose) == "string"
                and type(entry.timestamp) == "number", "malformed entry in jornada " .. index)
            assert(not lastStamp or entry.timestamp >= lastStamp, "entries out of time order in jornada " .. index)
            lastStamp = entry.timestamp
        end
    end
    for index = mark + 1, #S.prints do
        local line = S.prints[index]
        if string.find(line, "Resumen") or string.find(line, "Añadidos") or string.find(line, "Se añadirían") then note("   " .. line) end
    end
end

local function SetUp()
    fire("ADDON_LOADED", "AdventureJournal")
    fire("PLAYER_LOGIN")
end

-- Records of the old types: the same in every variant.
local function BaseRecords(fixture, T)
    fixture.At("<nil>", "")
    fixture.Log(T, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(T + 1, "ZONE_CHANGED_NEW_AREA")
    fixture.Log(T + 30, "GOSSIP_SHOW", { npc = "Gornek" })
    fixture.Log(T + 60, "QUEST_TURNED_IN", { quest = 4641, xp = 40, money = 0, title = "Tu lugar en el mundo" })
    fixture.Log(T + 90, "CHAT_MSG_LOOT", { msg = "Recibes botín: " .. S.items[1234].link .. ".", item = 1234, quality = 3, who = "Volgajin" })
    fixture.Log(T + 500, "PLAYER_DEAD")
    fixture.Log(T + 900, "PLAYER_LOGOUT")
    -- A second session (the next login): the first-gain rule of REPUTATION needs it.
    fixture.At("<nil>", "")
    fixture.Log(T + 5000, "PLAYER_ENTERING_WORLD", { login = true, reload = false })
    fixture.At("Durotar", "Valle de los Retos")
    fixture.Log(T + 5100, "PLAYER_DEAD")
    fixture.Log(T + 5200, "PLAYER_LOGOUT")
end

-- Records of the new types, inside the session that starts at T.
local function NewRecords(fixture, T)
    fixture.At("Durotar", "Valle de los Retos")
    -- LEVEL
    fixture.Log(T + 100, "PLAYER_LEVEL_UP", { level = 2 })
    fixture.Log(T + 102, "PLAYER_LEVEL_UP", { level = 2 })            -- the same event twice: one entry
    fixture.Log(T + 400, "PLAYER_LEVEL_UP", { level = 3 })
    fixture.Log(T + 410, "PLAYER_LEVEL_UP", { level = "[SECRET]" })   -- neutral text
    fixture.Log(T + 600, "PLAYER_LEVEL_UP", { level = "<nil>" })      -- nothing readable: no entry
    -- GROUP: the shapes AJProbe recorded (system messages with the names; GROUP_JOINED with no names)
    fixture.Log(T + 200, "CHAT_MSG_SYSTEM", { a = { "Has invitado a Dips Jawshatter a unirse a tu grupo." } })   -- an invitation: no entry
    fixture.Log(T + 201, "GROUP_JOINED", { a = { 1, "Party-6951-1-00000007247F" } })       -- a home group forming: no entry
    fixture.Log(T + 202, "CHAT_MSG_SYSTEM", { a = { "Dips Jawshatter se une al grupo." } })
    fixture.Log(T + 203, "CHAT_MSG_SYSTEM", { a = { "Dips Jawshatter se une al grupo." } })    -- the same event twice
    fixture.Log(T + 230, "CHAT_MSG_SYSTEM", { a = { "Bizare Deathplay se une al grupo." } })
    fixture.Log(T + 260, "CHAT_MSG_SYSTEM", { a = { "Dips Jawshatter deja el grupo." } })
    fixture.Log(T + 280, "CHAT_MSG_SYSTEM", { a = { "Dejas el grupo." } })
    fixture.Log(T + 290, "CHAT_MSG_SYSTEM", { a = { "Tu grupo se ha disuelto." } })
    fixture.Log(T + 295, "CHAT_MSG_SYSTEM", { a = { "[SECRET]" } })                       -- unreadable: skipped
    fixture.Log(T + 296, "CHAT_MSG_SYSTEM", { a = { "Botín fijado en el modo libre." } })  -- not a group message
    fixture.Log(T + 297, "CHAT_MSG_SYSTEM", { a = { "<nil>" } })
    fixture.Log(T + 310, "GROUP_JOINED", { a = { 2, "Party-6951-2-00000007247F" } })       -- a dungeon group: "un grupo"
    fixture.Log(T + 311, "GROUP_JOINED", { a = { 2, "Party-6951-2-00000007247F" } })       -- twice: one entry
    fixture.Log(T + 320, "GROUP_JOINED", { a = { "[SECRET]", "[SECRET]" } })
    -- REPUTATION: the first gain with each faction in each jornada, and every change of standing
    fixture.Log(T + 120, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Entrañas", 12) } })
    fixture.Log(T + 121, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Entrañas", 9) } })      -- same faction, same jornada
    fixture.Log(T + 125, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Orgrimmar", 8) } })
    fixture.Log(T + 130, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Standing("Entrañas", "Amistoso") } })
    fixture.Log(T + 131, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Standing("Entrañas", "Amistoso") } })   -- twice
    fixture.Log(T + 140, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { "[SECRET]" } })
    fixture.Log(T + 141, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { "<nil>" } })
    fixture.Log(T + 142, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { "Tu reputación con Entrañas ha disminuido en 3." } })   -- a loss: not logged
    fixture.Log(T + 700, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Entrañas", 5) } })      -- much later, same jornada: none
    fixture.Log(T + 5050, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Entrañas", 6) } })     -- the next jornada: an entry again
    fixture.Log(T + 5051, "CHAT_MSG_COMBAT_FACTION_CHANGE", { a = { Gain("Entrañas", 6) } })
    -- SKILL: new skills and multiples of 25
    fixture.Log(T + 150, "CHAT_MSG_SKILL", { a = { "Tu habilidad en Dagas ha subido a 24." } })
    fixture.Log(T + 151, "CHAT_MSG_SKILL", { a = { "Tu habilidad en Dagas ha subido a 25." } })
    fixture.Log(T + 152, "CHAT_MSG_SKILL", { a = { "Tu habilidad en Dagas ha subido a 25." } })    -- twice
    fixture.Log(T + 180, "CHAT_MSG_SKILL", { a = { "Tu habilidad en Dagas ha subido a 50." } })
    fixture.Log(T + 181, "CHAT_MSG_SKILL", { a = { "Tu habilidad en Defensa ha subido a 75." } })
    fixture.Log(T + 182, "CHAT_MSG_SKILL", { a = { "Has ganado la siguiente habilidad: Herboristería" } })
    fixture.Log(T + 183, "CHAT_MSG_SKILL", { a = { "[SECRET]" } })
    fixture.Log(T + 184, "CHAT_MSG_SKILL", { a = { "algo que no es una habilidad" } })
    -- SPELL
    fixture.Log(T + 190, "CHAT_MSG_SYSTEM", { a = { "Has aprendido un nuevo hechizo: " .. Spell(348, "Inmolar") .. "." } })
    fixture.Log(T + 191, "CHAT_MSG_SYSTEM", { a = { "Has aprendido un nuevo hechizo: " .. Spell(348, "Inmolar") .. "." } })   -- twice
    fixture.Log(T + 192, "CHAT_MSG_SYSTEM", { a = { "Has aprendido un nuevo hechizo: " .. Spell(707, "Inmolar (Rango 2)") .. "." } })
    fixture.Log(T + 193, "CHAT_MSG_SYSTEM", { a = { "Has aprendido un nuevo hechizo: Bola de fuego." } })
    fixture.Log(T + 194, "CHAT_MSG_SYSTEM", { a = { "Has aprendido una nueva facultad: " .. Spell(2383, "Buscar hierbas") .. "." } })   -- the esES word, seen on Forever
    -- QUEST_ACCEPT (no giver: AJProbe does not record QUEST_DETAIL)
    fixture.Log(T + 160, "QUEST_ACCEPTED", { a = AcceptedArgs(4641), title = "Tu lugar en el mundo" })
    fixture.Log(T + 161, "QUEST_ACCEPTED", { a = AcceptedArgs(4641), title = "Tu lugar en el mundo" })   -- twice: one entry
    fixture.Log(T + 350, "QUEST_ACCEPTED", { a = AcceptedArgs(4642, 2), title = "Cuernos rotos" })
    fixture.Log(T + 351, "QUEST_ACCEPTED", { a = AcceptedArgs(99999, 3), title = "<nil>" })             -- no title: "una misión (ID n)"
    fixture.Log(T + 352, "QUEST_ACCEPTED", { a = AcceptedArgs(98765, 3), title = "[SECRET]" })          -- secret title: neutral text
    fixture.Log(T + 353, "QUEST_ACCEPTED", { a = { "[SECRET]" }, title = "<nil>" })                    -- nothing readable: neutral text
    -- GUILD: system messages about the player (invented wording, see stubs.lua), none about others
    fixture.Log(T + 370, "CHAT_MSG_SYSTEM", { a = { "Volgajin se ha unido a la hermandad." } })
    fixture.Log(T + 371, "CHAT_MSG_SYSTEM", { a = { "Volgajin se ha unido a la hermandad." } })        -- twice: one entry
    fixture.Log(T + 380, "CHAT_MSG_SYSTEM", { a = { "Garona se ha unido a la hermandad." } })          -- someone else: none
    fixture.Log(T + 385, "CHAT_MSG_SYSTEM", { a = { "Has invitado a Garona a unirse a tu hermandad." } })   -- an invitation: none
    fixture.Log(T + 390, "CHAT_MSG_SYSTEM", { a = { "Has dejado la hermandad." } })
    fixture.Log(T + 395, "CHAT_MSG_SYSTEM", { a = { "[SECRET]" } })
end

-- ===================================================================================
if H.variant == "off_with" or H.variant == "off_without" then
    local T = S.clock - 100000
    local fixture = F.New()
    BaseRecords(fixture, T)
    if H.variant == "off_with" then NewRecords(fixture, T) end
    AJProbeDB = fixture.db
    SetUp()
    for _, key in ipairs(NEW_TYPES) do slash("tipos " .. key .. " off") end
    RunImport("import with every new type off")
    RunImport("repeat", nil, false)
    Describe("result")
    return
end

-- ===================================================================================
if H.variant == "types" then
    local T1 = S.clock - 100000
    local T2 = T1 + 5000
    local fixture = F.New()
    BaseRecords(fixture, T1)
    NewRecords(fixture, T1)
    AJProbeDB = fixture.db
    local probeAtStart = Snap(AJProbeDB)
    SetUp()
    Describe("start")
    RunImport("dry run", "prueba")
    RunImport("first import")
    Describe("after the first import")
    local importedDB = AdventureJournalDB
    RunImport("second import: nothing new, byte-identical", nil, false)

    -- Each type switched off on its own, on a fresh diary: that type is not imported, the others are.
    for _, key in ipairs(NEW_TYPES) do
        AdventureJournalDB = nil
        ns.EnsureDatabase()
        slash("tipos " .. key .. " off")
        RunImport(key .. " switched off")
        local _, counts = Counts()
        assert((counts[key] or 0) == 0, key .. " was imported while switched off")
        Describe(key .. " off")
        RunImport(key .. " off: repeat", nil, false)
        slash("tipos " .. key .. " on")
        RunImport(key .. " back on: it arrives now")
        local _, countsOn = Counts()
        assert((countsOn[key] or 0) > 0, key .. " was not imported once switched on")
        RunImport(key .. " on: repeat", nil, false)
    end

    -- Entries already in the diary (made live): the same events in the log are duplicates, the existing
    -- entries stay exactly as they were.
    do
        AdventureJournalDB = nil
        ns.EnsureDatabase()
        local function Stamp(t) return date("%Y-%m-%d %H:%M:%S", t) end
        local function Entry(kind, text, t, extra)
            local entry = { type = kind, text = text, place = "Valle de los Retos, Durotar", zone = "Durotar", subZone = "Valle de los Retos",
                time = date("%H:%M:%S", t), timestamp = t, characterProfile = "Heroico", contextualTone = "con el ánimo firme", seed = 1,
                prose = "Prosa guardada de " .. text }
            for key, value in pairs(extra or {}) do entry[key] = value end
            return entry
        end
        local live = {
            Entry("LEVEL", "He alcanzado el nivel 3", T1 + 401, { level = 3 }),
            Entry("GROUP", "Dips Jawshatter", T1 + 203, { groupEvent = "join" }),
            Entry("REPUTATION", "Entrañas", T1 + 118, { repEvent = "gain" }),
            Entry("SKILL", "Dagas", T1 + 151, { skillEvent = "rank", rank = 25 }),
            Entry("SPELL", "Inmolar", T1 + 190, { spellID = 348, learnKind = "spell" }),
            Entry("QUEST_ACCEPT", "Tu lugar en el mundo", T1 + 162, { questID = 4641, npc = "Gornek" }),
            Entry("GUILD", "una hermandad", T1 + 372, { guildEvent = "join" }),
        }
        AdventureJournalDB.currentDay = 1
        AdventureJournalDB.days[1] = { startedAt = Stamp(T1 - 5), endedAt = Stamp(T1 + 905), dateLabel = "x", events = {} }
        for _, entry in ipairs(live) do table.insert(AdventureJournalDB.days[1].events, entry) end
        table.sort(AdventureJournalDB.days[1].events, function(a, b) return a.timestamp < b.timestamp end)
        local before = {}
        for index, entry in ipairs(live) do before[index] = Snap(entry) end
        RunImport("the diary already holds a LEVEL 3 and a GROUP join made live")
        for index, entry in ipairs(live) do assert(Snap(entry) == before[index], "an existing entry was modified") end
        local _, counts = Counts()
        local joins, gains, daggers, immolates, accepts, guildJoins = 0, 0, 0, 0, 0, 0
        for index = 1, AdventureJournalDB.currentDay do
            for _, entry in ipairs(AdventureJournalDB.days[index].events) do
                if entry.type == "GROUP" and entry.groupEvent == "join" and entry.text == "Dips Jawshatter" then joins = joins + 1 end
                if entry.type == "REPUTATION" and entry.repEvent == "gain" and entry.text == "Entrañas" then gains = gains + 1 end
                if entry.type == "SKILL" and entry.text == "Dagas" and entry.rank == 25 then daggers = daggers + 1 end
                if entry.type == "SPELL" and entry.spellID == 348 then immolates = immolates + 1 end
                if entry.type == "QUEST_ACCEPT" and entry.questID == 4641 then accepts = accepts + 1 end
                if entry.type == "GUILD" and entry.guildEvent == "join" then guildJoins = guildJoins + 1 end
            end
        end
        note("existing entries kept; LEVEL entries = " .. (counts.LEVEL or 0) .. " (3 expected: one was there), Dips joins = " .. joins
            .. ", Entrañas first gains = " .. gains .. " (2 expected: the first jornada's was there, the next jornada gets its own), Dagas 25 = "
            .. daggers .. ", Inmolar = " .. immolates .. ", quest 4641 accepted = " .. accepts .. ", guild joins = " .. guildJoins)
        assert(counts.LEVEL == 3 and joins == 1 and gains == 2 and daggers == 1 and immolates == 1 and accepts == 1 and guildJoins == 1,
            "live entries were not recognised as duplicates")
        RunImport("repeat", nil, false)
    end

    -- Live and imported entries read the same: fire the same events live in a fresh diary, then look
    -- each live entry up among the imported ones (same type and text) and compare the stored fields
    -- and the prose (composed with the imported entry's own seed, tone and place).
    AdventureJournalDB = nil
    ns.EnsureDatabase()
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    fire("PLAYER_ENTERING_WORLD", true, false)
    advance(100); fire("PLAYER_LEVEL_UP", 2)
    advance(300); fire("PLAYER_LEVEL_UP", 3)
    advance(20); fire("PLAYER_LEVEL_UP", S.SECRET_NUMBER)
    advance(20); fire("CHAT_MSG_SYSTEM", "Dips Jawshatter se une al grupo.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Bizare Deathplay se une al grupo.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Dips Jawshatter deja el grupo.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Dejas el grupo.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Tu grupo se ha disuelto.")
    advance(20); fire("GROUP_JOINED", 2, "Party-6951-2-00000007247F")
    advance(20); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 12))
    advance(20); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Orgrimmar", 8))
    advance(20); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Standing("Entrañas", "Amistoso"))
    advance(20); fire("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 25.")
    advance(40); fire("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 50.")
    advance(40); fire("CHAT_MSG_SKILL", "Tu habilidad en Defensa ha subido a 75.")
    advance(40); fire("CHAT_MSG_SKILL", "Has ganado la siguiente habilidad: Herboristería")
    advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(348, "Inmolar") .. ".")
    advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(707, "Inmolar (Rango 2)") .. ".")
    advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: Bola de fuego.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido una nueva facultad: " .. Spell(2383, "Buscar hierbas") .. ".")
    -- QUEST_ACCEPT and GUILD live. No QUEST_DETAIL, so no giver (the import has none either), and no guild known.
    S.guildName = nil
    advance(20); if FLAVOR == "classic" then fire("QUEST_ACCEPTED", 1, 4641) else fire("QUEST_ACCEPTED", 4641) end
    advance(20); if FLAVOR == "classic" then fire("QUEST_ACCEPTED", 2, 4642) else fire("QUEST_ACCEPTED", 4642) end
    advance(20); fire("CHAT_MSG_SYSTEM", "Volgajin se ha unido a la hermandad.")
    advance(20); fire("CHAT_MSG_SYSTEM", "Has dejado la hermandad.")
    local compared = 0
    for _, live in ipairs(AdventureJournalDB.days[AdventureJournalDB.currentDay].events) do
        if live.type ~= "DISCOVERY" then
            local imported
            for index = 1, importedDB.currentDay do
                for _, candidate in ipairs(importedDB.days[index].events) do
                    local same = candidate.type == live.type and candidate.text == live.text
                    for _, field in ipairs(EXTRA_FIELDS) do
                        if candidate[field] ~= live[field] then same = false end
                    end
                    if same then imported = candidate end
                end
            end
            assert(imported, "no imported entry reads like the live " .. live.type .. " entry: " .. live.text)
            local copy = {}
            for key, value in pairs(live) do copy[key] = value end
            copy.seed, copy.contextualTone, copy.place = imported.seed, imported.contextualTone, imported.place
            assert(ns.ComposeEntry(copy) == imported.prose, live.type .. " prose differs live vs imported")
            compared = compared + 1
        end
    end
    note("live and imported entries compared (same fields, same prose): " .. compared)
    AdventureJournalDB = nil
    ns.EnsureDatabase()
    assert(Snap(AJProbeDB) == probeAtStart, "AJProbeDB changed during the scenario")
    note("AJProbeDB is byte-identical after every import")
    return
end

error("unknown variant: " .. tostring(H.variant))
