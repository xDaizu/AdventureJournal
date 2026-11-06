-- Used by import-dryrun.js: a rehearsal of /diario importar on copies of real SavedVariables,
-- in memory only. Prints counts, never entry text or chat text.
local H = ...
local S, fire, slash, note, ns = H.S, H.fire, H.slash, H.note, H.ns
H.noDump = true   -- never print the real diary

assert(load(REAL_PROBE_TEXT, "AJProbe.lua"))()
assert(load(REAL_DIARY_TEXT, "AdventureJournal.lua"))()
local probe = AJProbeDB
assert(type(probe) == "table", "the AJProbe file does not define AJProbeDB")
assert(type(AdventureJournalDB) == "table", "the diary file does not define AdventureJournalDB")

-- Whose records are these? The character key AJProbe writes is "Name-Realm". Taken from --player, or
-- else the key that appears most often in the log (a Forever file holds one character).
local key = REAL_PLAYER
if not key or key == "" then
    local counts, best, bestCount = {}, nil, 0
    for _, r in ipairs(probe.log or {}) do
        if type(r) == "table" and type(r.c) == "string" then
            counts[r.c] = (counts[r.c] or 0) + 1
            if counts[r.c] > bestCount then best, bestCount = r.c, counts[r.c] end
        end
    end
    key = best
end
if key then
    local name, realm = string.match(key, "^([^%-]+)%-(.+)$")
    if name then S.playerName, S.realmName = name, realm end
end
note("character: " .. tostring(S.playerName) .. "-" .. tostring(S.realmName))

local newest = 0
for _, list in ipairs({ probe.log or {}, probe.chat or {} }) do
    for _, r in ipairs(list) do
        if type(r) == "table" and type(r.t) == "number" and r.t > newest then newest = r.t end
    end
end
note(string.format("AJProbeDB: %d activity records, %d chat lines. Diary: version %s, currentDay %s.",
    #(probe.log or {}), #(probe.chat or {}), tostring(AdventureJournalDB.version), tostring(AdventureJournalDB.currentDay)))

-- The player imports during a later session: a login after everything the files hold.
S.clock = newest + 600
fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)

local function Snap(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end return type(a) == "number" end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = Snap(k) .. "=" .. Snap(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local probeBefore = Snap(probe)

local function Days(label)
    local db = AdventureJournalDB
    note(label .. " (currentDay = " .. db.currentDay .. ", the last one is the simulated login):")
    for index = 1, db.currentDay do
        local day = db.days[index]
        local imported, byType = 0, {}
        for _, e in ipairs(day.events) do
            byType[e.type] = (byType[e.type] or 0) + 1
            if e.source == "ajprobe" then imported = imported + 1 end
        end
        local kinds = {}
        for k, v in pairs(byType) do kinds[#kinds + 1] = k .. " " .. v end
        table.sort(kinds)
        note(string.format("  %3d  %s -> %s  %3d entradas (%d importadas) [%s]  conversaciones: %d%s", index, tostring(day.startedAt),
            tostring(day.endedAt), #day.events, imported, table.concat(kinds, ", "),
            day.conversations and #day.conversations or 0, day.source and "  (jornada nueva)" or ""))
    end
end

Days("Before")
local before = Snap(AdventureJournalDB)
slash("importar prueba")
assert(Snap(AdventureJournalDB) == before, "the dry run changed the diary")
slash("importar")
Days("After importing (conversations off)")
local afterFirst = Snap(AdventureJournalDB)
slash("importar")
assert(Snap(AdventureJournalDB) == afterFirst, "a second import changed the diary")
note("Second import: the diary is byte-identical.")
slash("conversaciones on")
slash("importar")
Days("After importing with conversations on")
local afterChat = Snap(AdventureJournalDB)
slash("importar")
assert(Snap(AdventureJournalDB) == afterChat, "a second import (conversations on) changed the diary")
note("Second import: the diary is byte-identical.")
assert(Snap(probe) == probeBefore, "AJProbeDB changed")
local errors = 0
for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
note("AJProbeDB is byte-identical. Handler errors: " .. errors .. ". Errors that reached the game's error handler: " .. #S.errors .. ".")
for _, message in ipairs(S.errors) do note("ERROR: " .. message) end
