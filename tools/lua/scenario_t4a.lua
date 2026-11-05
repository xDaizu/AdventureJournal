-- T4a: the entry types of Chema's line that work on both clients, live: QUEST_ACCEPT (with the giver),
-- REVISIT with the travel method (hearthstone, teleport, taxi), the enemy named in a death
-- (settings.deathKiller) and GUILD (the client's guild system messages).
-- Variants (H.variant):
--   live       every feature through its game events, in login, /reload and second login.
--   secrets    the same events with secret values (stub secrets) in an instance, then the addon's simulated
--              secrets. Nothing may error or reach the file.
--   off_with / off_without
--              QUEST_ACCEPT, REVISIT, GUILD and deathKiller off. `off_with` also fires the new events;
--              `off_without` fires only the old ones. run.js checks that the two saved diaries are
--              byte-identical (the M6 off-equality rule).
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local NEW_TYPES = { "QUEST_ACCEPT", "REVISIT", "GUILD" }
local CLASSIC = FLAVOR == "classic"

S.questTitles[4641] = "Tu lugar en el mundo"
S.questTitles[4642] = "Cuernos rotos"
S.questLog = { { title = "Tu lugar en el mundo", questID = 4641 }, { title = "Cuernos rotos", questID = 4642 } }

-- QUEST_ACCEPTED as each client sends it: (questID) on Forever (observed), (questLogIndex, questID) on Classic Era.
local function Accepted(ev, id, index)
    if CLASSIC then ev("QUEST_ACCEPTED", index or 1, id) else ev("QUEST_ACCEPTED", id) end
end

local function Day() return AdventureJournalDB.days[AdventureJournalDB.currentDay] end

local function Counts()
    local counts = {}
    for _, entry in ipairs(Day().events) do counts[entry.type] = (counts[entry.type] or 0) + 1 end
    local parts = {}
    for _, info in ipairs(ns.TYPE_INFO) do parts[#parts + 1] = info.key .. "=" .. (counts[info.key] or 0) end
    return table.concat(parts, " ")
end

local function Show(label)
    note(label .. ": " .. #Day().events .. " entries; " .. Counts())
end

-- The entries of one type in the current jornada: text, the T4a fields, and the prose.
local function Dump(kind)
    local out = {}
    for _, entry in ipairs(Day().events) do
        if entry.type == kind then
            local fields = {}
            for _, key in ipairs({ "questID", "npc", "travelMethod", "guildEvent", "killer" }) do
                if entry[key] ~= nil then fields[#fields + 1] = key .. "=" .. tostring(entry[key]) end
            end
            out[#out + 1] = string.format("  %s | %s | %s\n    %s%s", entry.type, tostring(entry.text), table.concat(fields, " "),
                tostring(entry.prose), entry.header and ("\n    [header] " .. entry.header) or "")
        end
    end
    note(kind .. " entries (" .. #out .. "):\n" .. (#out > 0 and table.concat(out, "\n") or "  (none)"))
end

local function StartSession()
    fire("ADDON_LOADED", "AdventureJournal")
    fire("PLAYER_LOGIN")
    if H.mode == "reload" then
        S.zone, S.subZone = "Durotar", "Valle de los Retos"
        fire("PLAYER_ENTERING_WORLD", false, true)
    else
        fire("PLAYER_ENTERING_WORLD", true, false)
        S.zone, S.subZone = "Durotar", "Valle de los Retos"
        fire("ZONE_CHANGED_NEW_AREA")
    end
end

-- The old types' events: the same in off_with and off_without. The two zone changes visit El Cubil
-- (a discovery) and come back to a place already seen.
local function OldEvents()
    advance(10); S.subZone = "El Cubil"; fire("ZONE_CHANGED")
    advance(5); fire("PLAYER_DEAD")
    advance(5); fire("GOSSIP_SHOW")
end

-- Blocks. Each takes `ev` (fire in a normal run, a function that fires nothing in `off_without`); the clock
-- and the zone changes happen either way, so the two diaries can be compared.
local BLOCKS = {}

BLOCKS.QUEST_ACCEPT = {
    normal = function(ev)
        S.npcName = "Gornek"
        advance(20); ev("QUEST_DETAIL"); advance(3); Accepted(ev, 4641)            -- offered by Gornek, accepted
        advance(1); Accepted(ev, 4641)                                              -- the same quest twice within 3 s: one entry
        S.npcName = nil
        advance(20); ev("QUEST_DETAIL"); advance(3); Accepted(ev, 4642, 2)          -- a quest with no NPC (from an item): no giver
        S.npcName = "Thrall"
        advance(20); ev("QUEST_DETAIL")                                             -- offered and declined...
        advance(200); Accepted(ev, 4641, 3)                                         -- ...accepted much later: the giver is stale, none
        advance(20); Accepted(ev, 99999)                                            -- not in the quest log: "una misión (ID n)"
        advance(20); ev("QUEST_ACCEPTED")                                           -- no arguments at all
        S.npcName = "Gornek"
    end,
    secrets = function(ev)
        S.npcName = S.SECRET
        advance(20); ev("QUEST_DETAIL"); advance(3); ev("QUEST_ACCEPTED", S.SECRET_NUMBER)
        advance(20); ev("QUEST_ACCEPTED", S.SECRET, S.SECRET_NUMBER)
        advance(20); ev("QUEST_ACCEPTED", "4641")                                   -- not a number
        S.npcName = "Gornek"
    end,
    simulated = function(ev)
        advance(20); ev("QUEST_DETAIL"); advance(3); if CLASSIC then ev("QUEST_ACCEPTED", 1, 4641) else ev("QUEST_ACCEPTED", 4641) end
    end,
}

-- Revisits: the player is at El Cubil. Moves are zone changes (old events); the casts and the taxi flag are new.
BLOCKS.REVISIT = {
    normal = function(ev)
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8690)       -- hearthstone...
        advance(8); S.subZone = "Valle de los Retos"; fire("ZONE_CHANGED")          -- ...and a place seen before: REVISIT by hearthstone
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 3567)       -- a mage teleport
        advance(5); S.subZone = "El Cubil"; fire("ZONE_CHANGED")                    -- REVISIT by teleport
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-3", 8690)       -- someone else's cast: ignored
        advance(5); S.subZone = "Valle de los Retos"; fire("ZONE_CHANGED")          -- on foot
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 8690)       -- a cast that expires...
        advance(70); S.subZone = "El Cubil"; fire("ZONE_CHANGED")                   -- ...(61+ s later): on foot
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 12345)      -- a spell that is no travel
        advance(5); S.subZone = "Valle de los Retos"; fire("ZONE_CHANGED")          -- on foot
        advance(20); S.onTaxi = H.live; S.subZone = "El Cubil"; fire("ZONE_CHANGED"); S.onTaxi = false   -- a flight: TAXI
    end,
    secrets = function(ev)
        advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", S.SECRET, "cast", 8690)
        advance(5); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", S.SECRET_NUMBER)
        advance(5); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", "8690")
    end,
    simulated = function(ev) advance(20); ev("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8690) end,
}

-- The enemy named in a death. deathKiller is switched by the scenario.
BLOCKS.DEATH = {
    normal = function(ev)
        S.target = { name = "Hogger", hostile = true, player = false }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")                   -- named
        S.target = { name = "Rival", hostile = true, player = true }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")                   -- a player: not named
        S.target = { name = "Hogger", hostile = true, player = false }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); ev("PLAYER_REGEN_ENABLED")            -- combat ends, alive
        advance(20); fire("PLAYER_DEAD")                                                             -- a later fall: not named
        advance(30); ev("PLAYER_REGEN_DISABLED"); S.dead = true; advance(5); ev("PLAYER_REGEN_ENABLED")   -- ends because the player died...
        advance(1); fire("PLAYER_DEAD"); S.dead = false                                              -- ...the enemy is still known
        S.target = { name = "Dummy", hostile = false, player = false }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")                   -- not hostile: not named
        S.target = nil
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")                   -- no target
    end,
    secrets = function(ev)
        S.target = { name = S.SECRET, hostile = true, player = false }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")
        S.target = nil
    end,
    simulated = function(ev)
        S.target = { name = "Hogger", hostile = true, player = false }
        advance(30); ev("PLAYER_REGEN_DISABLED"); advance(20); fire("PLAYER_DEAD")
        S.target = nil
    end,
}

-- Guild: the stub strings are invented (no guild message has been recorded yet), see stubs.lua.
BLOCKS.GUILD = {
    normal = function(ev)
        local me = S.playerName
        S.guildName = "Los Errantes"
        advance(30); ev("PLAYER_GUILD_UPDATE", "player")
        advance(1); ev("CHAT_MSG_SYSTEM", me .. " se ha unido a la hermandad.")                    -- me, joining
        advance(1); ev("CHAT_MSG_SYSTEM", me .. " se ha unido a la hermandad.")                    -- twice within 10 s: one entry
        advance(20); ev("CHAT_MSG_SYSTEM", "Garona se ha unido a la hermandad.")                   -- someone else: none
        advance(20); ev("CHAT_MSG_SYSTEM", "Garona ha dejado la hermandad.")                       -- someone else: none
        advance(20); S.guildName = nil; ev("CHAT_MSG_SYSTEM", "Has dejado la hermandad.")          -- me, leaving (the guild is already gone)
        advance(20); ev("CHAT_MSG_SYSTEM", me .. " ha dejado la hermandad.")                       -- leaving, in the third-person shape: the guild is no longer remembered
        advance(20); ev("CHAT_MSG_SYSTEM", "Has invitado a Garona a unirse a tu hermandad.")       -- an invitation: none
        advance(20); ev("CHAT_MSG_SYSTEM", "No tienes permiso para hacer eso.")                    -- an error: none
        advance(20); S.guildName = "Hijos del Alba"; ev("CHAT_MSG_SYSTEM", "|Hplayer:" .. me .. "-Zandalar:1|h[" .. me .. "]|h se ha unido a la hermandad.")   -- a link; another guild
    end,
    secrets = function(ev)
        advance(20); ev("CHAT_MSG_SYSTEM", S.SECRET)
    end,
    simulated = function(ev) advance(20); ev("CHAT_MSG_SYSTEM", S.playerName .. " se ha unido a la hermandad.") end,
}

local ORDER = { "QUEST_ACCEPT", "REVISIT", "DEATH", "GUILD" }

local function Run(part, live)
    local function ev(...) if live then fire(...) end end
    H.live = live
    for _, key in ipairs(ORDER) do BLOCKS[key][part](ev) end
end

-- ===================================================================================
if H.variant == "off_with" or H.variant == "off_without" then
    StartSession()
    for _, key in ipairs(NEW_TYPES) do slash("tipos " .. key .. " off") end
    OldEvents()
    Run("normal", H.variant == "off_with")
    Run("secrets", H.variant == "off_with")
    Show("all new types off, deathKiller off")
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
if H.variant == "secrets" then
    StartSession()
    ns.SetSetting("deathKiller", true)
    S.inInstance = true
    note("in an instance, stub secrets")
    Run("secrets", true)
    Show("after the secret events")
    for _, key in ipairs({ "QUEST_ACCEPT", "GUILD", "DEATH" }) do Dump(key) end
    slash("debug secrets")
    note("simulated secrets on")
    Run("simulated", true)
    slash("debug off")
    S.inInstance = false
    Show("after the simulated secrets")
    local errors = 0
    for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
    note("handler errors = " .. errors .. "; errors reaching the error handler: " .. #S.errors)
    assert(errors == 0 and #S.errors == 0, "a handler failed")
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
StartSession()
if H.mode == "reload" then
    Show("after /reload")
    slash("tipos revisit on")
    advance(30); S.subZone = "El Cubil"; fire("ZONE_CHANGED")
    advance(30); Run("normal", true)
    Show("reload: live events go on in the same jornada")
    fire("PLAYER_LOGOUT")
    return
end
if H.mode == "relogin" then
    Show("second login: a new jornada")
    note("the guild remembered from the first login: " .. tostring(S.guildName))
    advance(30); fire("CHAT_MSG_SYSTEM", S.playerName .. " se ha unido a la hermandad.")
    Dump("GUILD")
    fire("PLAYER_LOGOUT")
    return
end

note("deathKiller default = " .. tostring(ns.GetSetting("deathKiller")) .. ", REVISIT default = " .. tostring(ns.IsTypeEnabled("REVISIT"))
    .. ", profile = " .. tostring(ns.GetSetting("profile")))
OldEvents()
Show("old events (REVISIT off by default)")
Run("normal", true)
Show("with deathKiller off and REVISIT off")
Dump("QUEST_ACCEPT"); Dump("REVISIT"); Dump("GUILD")
note("deaths without deathKiller: " .. (function()
    local named = 0
    for _, entry in ipairs(Day().events) do if entry.type == "DEATH" and entry.killer then named = named + 1 end end
    return named
end)() .. " named")

-- REVISIT on: a place seen before is logged with its travel method.
slash("tipos revisit on")
note("REVISIT on")
advance(30); S.subZone = "Valle de los Retos"; fire("ZONE_CHANGED")   -- no cast: on foot
H.live = true
BLOCKS.REVISIT.normal(fire)
-- A place nobody saw, reached right after a cast: a DISCOVERY by hearthstone.
advance(20); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 8690)
advance(5); S.zone, S.subZone = "Orgrimmar", ""; fire("ZONE_CHANGED_NEW_AREA")
advance(10); S.zone, S.subZone = "Durotar", "El Cubil"; fire("ZONE_CHANGED_NEW_AREA")
Show("REVISIT on")
Dump("REVISIT")
note("DISCOVERY entries now carry their travel method: " .. (function()
    local out = {}
    for _, entry in ipairs(Day().events) do
        if entry.type == "DISCOVERY" then out[#out + 1] = entry.text .. "=" .. tostring(entry.travelMethod) end
    end
    return table.concat(out, "; ")
end)())

-- deathKiller on.
ns.SetSetting("deathKiller", true)
note("deathKiller on")
BLOCKS.DEATH.normal(fire)
Dump("DEATH")

-- A type switched off is ignored; switched on again it works at once.
slash("tipos aceptadas off")
advance(30); S.npcName = "Gornek"; fire("QUEST_DETAIL"); Accepted(fire, 4641)
Show("QUEST_ACCEPT off")
slash("tipos aceptadas on")
advance(30); fire("QUEST_DETAIL"); advance(2); Accepted(fire, 4642)
Show("QUEST_ACCEPT on again")
slash("tipos")
slash("diag mensajes")
note("book body:\n" .. (function() ns.OpenAtDay(AdventureJournalDB.currentDay) return tostring(_G.AdventureJournalBookFrame.body.text) end)())
local errors = 0
for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
assert(errors == 0 and #S.errors == 0, "a handler failed: " .. tostring(S.errors[1]))
fire("PLAYER_LOGOUT")
