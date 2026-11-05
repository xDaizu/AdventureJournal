-- T4b: the two types that exist only on Forever, live: MOUNT (NEW_MOUNT_ADDED, the journal's name) and
-- ACHIEVEMENT (ACHIEVEMENT_EARNED, GetAchievementInfo). On Classic Era neither API exists: the types are
-- hidden from /diario tipos and the panel, refused by the command, never logged, and their events are not
-- registered (the same scenario runs on both flavors and the report shows the difference).
-- Variants (H.variant):
--   live       every feature through its events, in login, /reload and second login.
--   secrets    the same events with secret values (stub secrets), then the addon's simulated secrets.
--   off_with / off_without
--              both types off. `off_with` also fires the new events; `off_without` fires only the old
--              ones. run.js checks that the two saved diaries are byte-identical (the M6 off-equality rule).
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
local FOREVER = FLAVOR ~= "classic"

local function Day() return AdventureJournalDB.days[AdventureJournalDB.currentDay] end

local function Counts()
    local counts = {}
    for _, entry in ipairs(Day().events) do counts[entry.type] = (counts[entry.type] or 0) + 1 end
    return string.format("MOUNT=%d ACHIEVEMENT=%d", counts.MOUNT or 0, counts.ACHIEVEMENT or 0)
end

local function Show(label) note(label .. ": " .. #Day().events .. " entries; " .. Counts()) end

local function Dump(kind)
    local out = {}
    for _, entry in ipairs(Day().events) do
        if entry.type == kind then
            out[#out + 1] = string.format("  %s | %s | mountID=%s achievementID=%s\n    %s", entry.type, tostring(entry.text),
                tostring(entry.mountID), tostring(entry.achievementID), tostring(entry.prose))
        end
    end
    note(kind .. " entries (" .. #out .. "):\n" .. (#out > 0 and table.concat(out, "\n") or "  (none)"))
end

local function Keys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
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

local function SetUpJournal()
    S.mounts = {
        [21] = { name = "Carnero gris", collected = true },
        [35] = { name = "Lobo atroz", collected = true },
        [40] = { name = "Corcel espectral", collected = false },
        [55] = { name = "Mamut de viaje", collected = false },
    }
    S.achievements = { [7] = "Explorador", [8] = "Aventurero" }
end

local function OldEvents()
    advance(10); fire("PLAYER_DEAD")
    advance(5); fire("GOSSIP_SHOW")
end

local BLOCKS = {}
BLOCKS.MOUNT = {
    normal = function(ev)
        advance(20); if FOREVER then S.mounts[40].collected = true end; ev("NEW_MOUNT_ADDED", 40)   -- a new mount
        advance(2); ev("NEW_MOUNT_ADDED", 40)                                                       -- the same event again: none
        advance(20); ev("NEW_MOUNT_ADDED", 21)                                                      -- one the player had: none (seeded)
        advance(20); ev("NEW_MOUNT_ADDED", 777)                                                     -- not in the journal: neutral text
        advance(20); ev("NEW_MOUNT_ADDED", nil)
        advance(20); ev("NEW_MOUNT_ADDED", "55")                                                    -- not a number
    end,
    secrets = function(ev)
        advance(20); ev("NEW_MOUNT_ADDED", S.SECRET_NUMBER)
        advance(20); ev("NEW_MOUNT_ADDED", S.SECRET)
    end,
    simulated = function(ev) advance(20); ev("NEW_MOUNT_ADDED", 55) end,
}
BLOCKS.ACHIEVEMENT = {
    normal = function(ev)
        advance(20); ev("ACHIEVEMENT_EARNED", 7, false)       -- a new achievement
        advance(2); ev("ACHIEVEMENT_EARNED", 7, false)        -- again: none
        advance(20); ev("ACHIEVEMENT_EARNED", 8, true)        -- earned before (an alt): none
        advance(20); ev("ACHIEVEMENT_EARNED", 8, false)       -- ... and known from now on: none
        advance(20); ev("ACHIEVEMENT_EARNED", 4242, false)    -- no name: neutral text
        advance(20); ev("ACHIEVEMENT_EARNED", nil, false)
        advance(20); ev("ACHIEVEMENT_EARNED", "9", false)     -- not a number
    end,
    secrets = function(ev)
        advance(20); ev("ACHIEVEMENT_EARNED", S.SECRET_NUMBER, false)
        advance(20); ev("ACHIEVEMENT_EARNED", 9, S.SECRET)    -- a readable ID, a secret flag: the flag is ignored
        advance(20); ev("ACHIEVEMENT_EARNED", S.SECRET, S.SECRET)
    end,
    simulated = function(ev) advance(20); ev("ACHIEVEMENT_EARNED", 7, false) end,
}

local ORDER = { "MOUNT", "ACHIEVEMENT" }
local function Run(part, live)
    local function ev(...) if live then fire(...) end end
    for _, key in ipairs(ORDER) do BLOCKS[key][part](ev) end
end

-- ===================================================================================
if H.variant == "off_with" or H.variant == "off_without" then
    SetUpJournal()
    StartSession()
    slash("tipos MOUNT off"); slash("tipos ACHIEVEMENT off")
    OldEvents()
    Run("normal", H.variant == "off_with")
    Run("secrets", H.variant == "off_with")
    Show("both types off")
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
if H.variant == "secrets" then
    SetUpJournal()
    StartSession()
    S.inInstance = true
    note("in an instance, stub secrets")
    Run("secrets", true)
    Show("after the secret events")
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
-- The journal has not loaded yet at the first login: nothing is seeded (and nothing is logged).
StartSession()
note("availability: MOUNT = " .. tostring(ns.IsTypeAvailable("MOUNT")) .. ", ACHIEVEMENT = " .. tostring(ns.IsTypeAvailable("ACHIEVEMENT"))
    .. "; visible types = " .. #ns.VisibleTypes() .. " of " .. #ns.TYPE_INFO)
note("events registered: NEW_MOUNT_ADDED = " .. tostring(ns.eventStatus.NEW_MOUNT_ADDED) .. ", ACHIEVEMENT_EARNED = " .. tostring(ns.eventStatus.ACHIEVEMENT_EARNED))
note("at the start of the session: mountsSeeded = " .. tostring(AdventureJournalDB.mountsSeeded) .. ", knownMounts = " .. Keys(AdventureJournalDB.knownMounts))

if H.mode == "reload" then
    SetUpJournal()
    Show("after /reload")
    advance(30); Run("normal", true)
    Show("reload: live events go on in the same jornada")
    fire("PLAYER_LOGOUT")
    return
end
if H.mode == "relogin" then
    SetUpJournal()
    fire("PLAYER_ENTERING_WORLD", false, false)   -- a loading screen: the journal is read now
    Show("second login: a new jornada")
    note("known mounts after the seed: " .. Keys(AdventureJournalDB.knownMounts) .. ", seeded = " .. tostring(AdventureJournalDB.mountsSeeded))
    fire("PLAYER_LOGOUT")
    return
end

-- The journal loads: the next loading screen seeds the mounts the player already has, without entries.
SetUpJournal()
-- A diary from Chema's line: his table has a key this journal does not (a mount he logged), and not the others.
AdventureJournalDB.knownMounts = { ["999"] = true }
fire("PLAYER_ENTERING_WORLD", false, false)
note("after the first read of the journal: seeded = " .. tostring(AdventureJournalDB.mountsSeeded) .. ", knownMounts = " .. Keys(AdventureJournalDB.knownMounts)
    .. " (his 999 kept, the collected mounts added, none logged)")
Show("seed makes no entries")
fire("PLAYER_ENTERING_WORLD", false, false)
note("a second loading screen changes nothing: knownMounts = " .. Keys(AdventureJournalDB.knownMounts))

OldEvents()
Run("normal", true)
Show("live events")
Dump("MOUNT"); Dump("ACHIEVEMENT")
note("known after the events: mounts " .. Keys(AdventureJournalDB.knownMounts) .. ", achievements " .. Keys(AdventureJournalDB.knownAchievements))

-- A type switched off is ignored and leaves the known tables alone; switched on again it works at once.
slash("tipos montura off")
advance(30); if FOREVER then S.mounts[55].collected = true end; fire("NEW_MOUNT_ADDED", 55)
Show("MOUNT off")
slash("tipos montura on")
note("knownMounts has 55 while it was off: " .. tostring(AdventureJournalDB.knownMounts and AdventureJournalDB.knownMounts["55"] == true))
advance(30); fire("NEW_MOUNT_ADDED", 55)
Show("MOUNT on again (the mount learned while off is logged now)")
slash("tipos logros off")
advance(30); fire("ACHIEVEMENT_EARNED", 9, false)
Show("ACHIEVEMENT off")
slash("tipos logros on")
slash("tipos")
slash("tipos montura on")
note("book body:\n" .. (function() ns.OpenAtDay(AdventureJournalDB.currentDay) return tostring(_G.AdventureJournalBookFrame.body.text) end)())
local errors = 0
for _ in pairs(ns.handlerErrors) do errors = errors + 1 end
assert(errors == 0 and #S.errors == 0, "a handler failed: " .. tostring(S.errors[1]))
fire("PLAYER_LOGOUT")
