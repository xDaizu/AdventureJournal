-- M6: the entry types added after M5 (LEVEL, GROUP, REPUTATION, SKILL, SPELL), live.
-- Variants (H.variant):
--   live       every type through its game event: the normal case, dedupe windows, threshold rules,
--              unreadable values, a type switched off and on again. Runs as login, /reload, second login.
--   secrets    the same events with secret values (stub secrets) in an instance, and again with the
--              addon's simulated secrets (/diario debug secrets). Nothing may error or reach the file.
--   off_with / off_without
--              all the new types switched off. `off_with` also fires the new events; `off_without` fires
--              only the old ones. run.js checks that the two saved diaries are byte-identical: with every
--              new type off the diary behaves exactly as in M4b.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local NEW_TYPES = { "LEVEL", "GROUP", "REPUTATION", "SKILL", "SPELL" }

-- Reputation messages as each client words them (AJProbe recorded the two forms; the stub's globals
-- are those strings). The standing-changed wording is invented (never seen), only its shape is tested.
local function Gain(faction, amount)
    return (string.format(FACTION_STANDING_INCREASED or "Tu reputación con %s ha aumentado en %d.", faction, amount))   -- the global is missing in the nomessages run
end
local function Standing(faction, standing)
    if FLAVOR == "classic" then return "Ahora eres " .. standing .. " con " .. faction .. "." end
    return "Con " .. faction .. " ahora eres " .. standing .. "."   -- positional in the stub: the standing is argument 1
end
local function Spell(id, name) return "|cff71d5ff|Hspell:" .. id .. ":0|h[" .. name .. "]|h|r" end

local function Counts()
    local day = AdventureJournalDB.days[AdventureJournalDB.currentDay]
    local counts = {}
    for _, entry in ipairs(day.events) do counts[entry.type] = (counts[entry.type] or 0) + 1 end
    local parts = {}
    for _, info in ipairs(ns.TYPE_INFO) do parts[#parts + 1] = info.key .. "=" .. (counts[info.key] or 0) end
    return table.concat(parts, " ")
end

local function Show(label)
    local day = AdventureJournalDB.days[AdventureJournalDB.currentDay]
    note(label .. ": " .. #day.events .. " entries; " .. Counts())
end

-- The entries of the current jornada of one type, as "text" lines.
local function Texts(kind)
    local out = {}
    for _, entry in ipairs(AdventureJournalDB.days[AdventureJournalDB.currentDay].events) do
        if entry.type == kind then out[#out + 1] = entry.text end
    end
    return table.concat(out, " | ")
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

-- The old types' events: the same in off_with and off_without.
local function OldEvents()
    advance(10); fire("GOSSIP_SHOW")
    advance(5); fire("QUEST_TURNED_IN", 4641, 40, 0)
    advance(5); fire("PLAYER_DEAD")
    advance(5); S.subZone = "El Cubil"; fire("ZONE_CHANGED")
    advance(5); fire("CHAT_MSG_WHISPER", "texto privado", "Amigo-OtroReino")
    advance(5); fire("BOSS_KILL", 1144, "Jefe de prueba")
end

-- One block per new type. Each takes `ev`, which is `fire` for a normal run and a function that fires
-- nothing in `off_without`; the clock advances the same either way, so the two diaries can be compared.
local BLOCKS = {}

-- LEVEL
BLOCKS.LEVEL = {
    normal = function(ev)
        advance(3); ev("PLAYER_LEVEL_UP", 2)
        advance(2); ev("PLAYER_LEVEL_UP", 2)           -- the same level within 10 s: one event
        advance(400); ev("PLAYER_LEVEL_UP", 3, 12, 5)  -- the game sends more arguments (health, mana...): ignored
    end,
    secrets = function(ev)
        advance(5); ev("PLAYER_LEVEL_UP", S.SECRET_NUMBER)
        advance(5); ev("PLAYER_LEVEL_UP", S.SECRET)          -- a secret that is not even a number
        advance(15); ev("PLAYER_LEVEL_UP", nil)
        advance(15); ev("PLAYER_LEVEL_UP", "5")              -- not a number
        advance(15); ev("PLAYER_LEVEL_UP", 0)
    end,
    simulated = function(ev) advance(15); ev("PLAYER_LEVEL_UP", 7) end,
}

-- GROUP: names from the system messages (the shapes seen in AJProbe's records, invented names)
BLOCKS.GROUP = {
    normal = function(ev)
        advance(20); ev("CHAT_MSG_SYSTEM", "Has invitado a Dips Jawshatter a unirse a tu grupo.")   -- an invitation: no entry
        advance(1); ev("GROUP_JOINED", 1, "Party-6951-1-00000007247F")                                -- a home group forming: no entry
        advance(1); ev("CHAT_MSG_SYSTEM", "Dips Jawshatter se une al grupo.")
        advance(1); ev("CHAT_MSG_SYSTEM", "Dips Jawshatter se une al grupo.")                         -- repeated within 3 s: one event
        advance(10); ev("CHAT_MSG_SYSTEM", "Bizare Deathplay se une al grupo.")
        advance(10); ev("CHAT_MSG_SYSTEM", "|Hplayer:Pedro-Zandalar:12:CHAT_MSG_SYSTEM:0|h[Pedro]|h se une al grupo.")   -- a player link
        advance(10); ev("CHAT_MSG_SYSTEM", "Lucía-Zandalar se une al grupo.")                         -- the realm is dropped
        advance(10); ev("CHAT_MSG_SYSTEM", "Dips Jawshatter deja el grupo.")
        advance(10); ev("CHAT_MSG_SYSTEM", "Mara se une a la banda.")                                  -- the raid string
        advance(10); ev("CHAT_MSG_SYSTEM", "Dejas el grupo.")
        advance(10); ev("CHAT_MSG_SYSTEM", "Tu grupo se ha disuelto.")
        advance(10); ev("CHAT_MSG_SYSTEM", "Botín fijado en el modo libre.")                          -- not a group message
        advance(10); ev("CHAT_MSG_SYSTEM", "Experiencia obtenida: 40.")
        advance(10); ev("CHAT_MSG_SYSTEM", nil)
        advance(10); ev("GROUP_JOINED", 2, "Party-6951-2-00000007247F")                               -- a dungeon group: no names
        advance(1); ev("GROUP_JOINED", 2, "Party-6951-2-00000007247F")                                -- twice: one entry
    end,
    secrets = function(ev)
        advance(5); ev("CHAT_MSG_SYSTEM", S.SECRET)             -- unreadable: nothing can be said, nothing is guessed
        advance(5); ev("GROUP_JOINED", S.SECRET_NUMBER, S.SECRET)
        advance(5); ev("GROUP_JOINED", 2, S.SECRET)             -- the category is readable: "un grupo"
        advance(5); ev("GROUP_JOINED", "2")
        advance(5); ev("CHAT_MSG_SYSTEM", "")
    end,
    simulated = function(ev) advance(15); ev("CHAT_MSG_SYSTEM", "Dips Jawshatter se une al grupo.") end,
}

-- REPUTATION: the first gain with each faction in each jornada, and every change of standing
BLOCKS.REPUTATION = {
    normal = function(ev)
        advance(20); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 12))                -- first gain: an entry
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 9))                  -- same faction, same jornada: none
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Orgrimmar", 8))                 -- another faction: an entry
        advance(60); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 5))                 -- much later, still none
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Standing("Entrañas", "Amistoso"))     -- a change of standing: an entry
        advance(2); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Standing("Entrañas", "Amistoso"))     -- twice: one entry
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", "Tu reputación con Entrañas ha disminuido en 3.")   -- a loss: not logged
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", "algo que no es reputación")
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", nil)
    end,
    secrets = function(ev)
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", S.SECRET)
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", nil)
        advance(5); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", "")
    end,
    simulated = function(ev) advance(15); ev("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 4)) end,
}

-- SKILL: a new skill, and every multiple of 25
BLOCKS.SKILL = {
    normal = function(ev)
        advance(10); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 24.")            -- not on the threshold
        advance(2); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 25.")             -- an entry
        advance(2); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 25.")             -- twice: one entry
        advance(2); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 26.")
        advance(60); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 50.")            -- an entry
        advance(5); ev("CHAT_MSG_SKILL", "Tu habilidad en Defensa ha subido a 75.")           -- another skill: an entry
        advance(5); ev("CHAT_MSG_SKILL", "Tu habilidad en Defensa ha subido a 5.")            -- below the first step
        advance(5); ev("CHAT_MSG_SKILL", "Has ganado la siguiente habilidad: Herboristería")  -- a new skill
        advance(40); ev("CHAT_MSG_SKILL", "Has ganado la siguiente habilidad: Herboristería") -- again later: logged again (a re-learned skill)
        advance(5); ev("CHAT_MSG_SKILL", "algo que no es una habilidad")
        advance(5); ev("CHAT_MSG_SKILL", nil)
    end,
    secrets = function(ev)
        advance(5); ev("CHAT_MSG_SKILL", S.SECRET)
        advance(5); ev("CHAT_MSG_SKILL", nil)
        advance(5); ev("CHAT_MSG_SKILL", "")
    end,
    simulated = function(ev) advance(15); ev("CHAT_MSG_SKILL", "Tu habilidad en Dagas ha subido a 100.") end,
}

-- SPELL: "Has aprendido un nuevo hechizo: [link]." in the system chat
BLOCKS.SPELL = {
    normal = function(ev)
        advance(30); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(348, "Inmolar") .. ".")
        advance(1); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(348, "Inmolar") .. ".")      -- twice: one entry
        advance(10); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(707, "Inmolar (Rango 2)") .. ".")   -- another rank: an entry
        advance(10); ev("CHAT_MSG_SYSTEM", "Has aprendido una nueva facultad: " .. Spell(1454, "Vida de conducto") .. ".")
        advance(10); ev("CHAT_MSG_SYSTEM", "Has aprendido una nueva habilidad pasiva: " .. Spell(5019, "Disparo con varita") .. ".")
        advance(10); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: Bola de fuego.")                        -- no link: the text is the name
        advance(10); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: .")
    end,
    secrets = function(ev)
        advance(5); ev("CHAT_MSG_SYSTEM", S.SECRET)
    end,
    simulated = function(ev) advance(15); ev("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(172, "Corrupción") .. ".") end,
}

local ORDER = NEW_TYPES

local function Run(part, live)
    local function ev(...) if live then fire(...) end end
    for _, key in ipairs(ORDER) do BLOCKS[key][part](ev) end
end

-- ===================================================================================
if H.variant == "off_with" or H.variant == "off_without" then
    StartSession()
    for _, key in ipairs(NEW_TYPES) do slash("tipos " .. key .. " off") end
    OldEvents()
    Run("normal", H.variant == "off_with")
    Run("secrets", H.variant == "off_with")
    Show("all new types off")
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
if H.variant == "secrets" then
    StartSession()
    S.inInstance = true
    note("in an instance, stub secrets")
    Run("secrets", true)
    Show("after the secret events")
    for _, key in ipairs(NEW_TYPES) do note(key .. " entries: " .. Texts(key)) end

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
    advance(30); Run("normal", true)
    Show("reload: live events go on in the same jornada")
    fire("PLAYER_LOGOUT")
    return
end
if H.mode == "relogin" then
    Show("second login: a new jornada")
    advance(30); fire("PLAYER_LEVEL_UP", 4)
    advance(10); fire("CHAT_MSG_SYSTEM", "Dips Jawshatter se une al grupo.")
    advance(10); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 7))   -- a new jornada: the first gain counts again
    advance(5); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Entrañas", 7))
    Show("relogin")
    fire("PLAYER_LOGOUT")
    return
end

OldEvents()
Show("old events")
Run("normal", true)
Show("new type events")
for _, key in ipairs(NEW_TYPES) do note(key .. " entries: " .. Texts(key)) end

-- A type switched off is ignored; switched on again it works at once.
for _, spec in ipairs({
    { "nivel", "LEVEL", function() advance(400); fire("PLAYER_LEVEL_UP", 5) end, function() advance(400); fire("PLAYER_LEVEL_UP", 6) end },
    { "grupo", "GROUP", function() advance(20); fire("CHAT_MSG_SYSTEM", "Zed se une al grupo.") end,
        function() advance(20); fire("CHAT_MSG_SYSTEM", "Yan se une al grupo.") end },
    { "reputacion", "REPUTATION", function() advance(20); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Facción Z", 3)) end,
        function() advance(20); fire("CHAT_MSG_COMBAT_FACTION_CHANGE", Gain("Facción Z", 3)) end },   -- off: nothing is remembered, on: the first gain counts
    { "habilidades", "SKILL", function() advance(40); fire("CHAT_MSG_SKILL", "Tu habilidad en Mazas ha subido a 100.") end,
        function() advance(40); fire("CHAT_MSG_SKILL", "Tu habilidad en Mazas ha subido a 125.") end },
    { "hechizos", "SPELL", function() advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(172, "Corrupción") .. ".") end,
        function() advance(20); fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. Spell(980, "Agonía") .. ".") end },
}) do
    local word, key, whileOff, whileOn = spec[1], spec[2], spec[3], spec[4]
    slash("tipos " .. word .. " off")
    whileOff()
    Show(key .. " off")
    slash("tipos " .. word .. " on")
    whileOn()
    Show(key .. " on again")
end
slash("tipos")
slash("diag mensajes")
note("book body:\n" .. (function() ns.OpenAtDay(AdventureJournalDB.currentDay) return tostring(_G.AdventureJournalBookFrame.body.text) end)())
local errors = 0
for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
assert(errors == 0 and #S.errors == 0, "a handler failed")
fire("PLAYER_LOGOUT")
