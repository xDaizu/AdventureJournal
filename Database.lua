-- Database.lua: the SavedVariables table (AdventureJournalDB), schema version,
-- migrations and the settings helpers. Schema: README.md, "SavedVariables schema".
local addonName, ns = ...

-- v3 (T1): profiles, `lootQuality`, and the import of diaries written by Chema's Forever line
-- (1.1.0-Forever). That line also saves `version = 2` (and rewrites it to 2 on every load), so a
-- diary is recognised by its keys, never by this number alone. See ChemaDiaryKeys below.
ns.SCHEMA_VERSION = 3

-- The entry types the diary can log, in the order the options panel lists them.
--   key      the `type` stored in each entry
--   label    shown in the options panel and /diario tipos
--   words    what /diario tipos <word> accepts (lower case)
--   default  logged unless the player changes it (default true). A type added later with
--            default = false (T4: REVISIT) stays off for diaries that never chose a value.
-- Achievements are switched off (decision 2026-11-05: Forever has no achievements, as far as the
-- player knows; the one ID tried, 6, is not one there). The code, the prose, the import and the harness
-- are kept: set this to true to switch them back on, and then check on Forever what
-- GetAchievementInfo returns and what ACHIEVEMENT_EARNED sends (README, "APIs used"). While it is
-- false the type is hidden from the panel and the commands and is never logged or imported.
ns.ACHIEVEMENTS_SUPPORTED = false

ns.TYPE_INFO = {
    { key = "QUEST",     label = "Misiones completadas", words = { "misiones", "mision", "misión", "quest" } },
    { key = "BOSS",      label = "Jefes derrotados",     words = { "jefes", "jefe", "boss" } },
    { key = "DEATH",     label = "Muertes",              words = { "muertes", "muerte", "death" } },
    { key = "LOOT",      label = "Botín raro o mejor",   words = { "botin", "botín", "loot" } },
    { key = "DISCOVERY", label = "Lugares descubiertos", words = { "lugares", "lugar", "descubrimientos", "discovery" } },
    { key = "NPC",       label = "Charlas con PNJ",      words = { "pnj", "npc" } },
    { key = "CHAT",      label = "Susurros recibidos",   words = { "susurros", "susurro", "chat" } },
    -- M6. All on by default (a type missing from settings.types counts as on).
    { key = "LEVEL",     label = "Subidas de nivel",     words = { "nivel", "niveles", "level" } },
    -- Names of other players, like the conversations: switch it off if you do not want them kept.
    { key = "GROUP",     label = "Grupo: quién entra y sale",   words = { "grupo", "grupos", "group", "party" } },
    { key = "REPUTATION", label = "Reputación con facciones", words = { "reputacion", "reputación", "facciones", "reputation" } },
    { key = "SKILL",     label = "Habilidades nuevas o mejoradas", words = { "habilidades", "habilidad", "skill", "skills" } },
    { key = "SPELL",     label = "Hechizos aprendidos",   words = { "hechizos", "hechizo", "spell", "spells" } },
    -- T4a: the types of Chema's line that work on both clients. REVISIT is noisy (every place seen
    -- before), so it is off unless the "clasico" profile or the player turns it on.
    { key = "QUEST_ACCEPT", label = "Misiones aceptadas",  words = { "aceptadas", "aceptada", "aceptar", "quest_accept", "questaccept" } },
    { key = "REVISIT",   label = "Lugares que vuelves a visitar", words = { "revisitas", "revisita", "volver", "revisit" }, default = false },
    { key = "GUILD",     label = "Hermandad: entrar y salir", words = { "hermandad", "hermandades", "guild" } },
    -- T4b: only where the client has the API (Forever); `available` hides the type from the panel and
    -- /diario tipos elsewhere, and a type that is not available is never logged.
    { key = "MOUNT",     label = "Monturas nuevas",       words = { "monturas", "montura", "mount", "mounts" },
      available = function() return ns.HasMountJournal() end },
    { key = "ACHIEVEMENT", label = "Logros conseguidos",  words = { "logros", "logro", "achievement", "achievements" },
      available = function() return ns.ACHIEVEMENTS_SUPPORTED == true and ns.HasAchievements() end },
}

-- Whether this client can produce a type at all (T4b). Types with no `available` function always can.
function ns.IsTypeAvailable(entryType)
    for _, info in ipairs(ns.TYPE_INFO) do
        if info.key == entryType then return info.available == nil or info.available() == true end
    end
    return true   -- a type this version does not know (saved by another version)
end

-- TYPE_INFO without the types this client cannot produce: what the panel and the commands list.
function ns.VisibleTypes()
    local out = {}
    for _, info in ipairs(ns.TYPE_INFO) do
        if info.available == nil or info.available() == true then out[#out + 1] = info end
    end
    return out
end

-- Names of the chat echo modes, for messages and the options panel.
ns.CHAT_MODE_NAMES = { all = "todo", important = "importante", off = "nada" }

-- Settings every character gets unless the player changed them. Missing keys are
-- filled in on every load, so adding an option here needs no schema bump and
-- diaries saved by older versions keep their own values.
--   chat           what is echoed to the chat window: "all", "important" or "off"
--   types          which entry types are logged (a type missing here gets its TYPE_INFO
--                  default; a type this version does not know counts as on)
--   showProfile    show the mood (characterProfile) in each entry's header in the book
--   conversations  M4b: record RP conversations; off by default
--   lootQuality    T1: lowest item quality logged as LOOT (3 = rare, 4 = epic)
--   profile        T1: the profile last applied ("ampliado" or "clasico"); a record, see PROFILES
--   deathKiller    T4a: name, in a death entry, the last enemy fought (the target when combat began;
--                  there is no combat log to know the real killer)
ns.DEFAULT_SETTINGS = {
    chat = "important",
    types = {},
    showProfile = false,
    conversations = false,
    lootQuality = 3,
    profile = "ampliado",
    deathKiller = false,
}
ns.TYPE_DEFAULT = {}   -- [key] = true/false, from TYPE_INFO
for _, info in ipairs(ns.TYPE_INFO) do
    ns.TYPE_DEFAULT[info.key] = info.default ~= false
    ns.DEFAULT_SETTINGS.types[info.key] = ns.TYPE_DEFAULT[info.key]
end

-- Profiles (T1). A profile is a set of setting values written once; afterwards every setting can
-- still be changed on its own. "clasico" reproduces what Chema's Forever diary (1.1.0-Forever)
-- logged and echoed: every entry echoed to chat, epic or better loot, and none of the types that
-- line never produced. "ampliado" is this line's own defaults. A diary written by Chema's line gets
-- "clasico" the first time it loads here; every other diary keeps its settings.
-- Chema's own types (QUEST_ACCEPT, REVISIT, MOUNT, ACHIEVEMENT, GUILD) arrive in T4. "clasico" sets
-- them now, so a later `default = false` (REVISIT) cannot switch them off for these players.
ns.PROFILES = {
    clasico = {
        chat = "all",
        lootQuality = 4,
        deathKiller = true,
        types = {
            QUEST = true, BOSS = true, DEATH = true, LOOT = true, DISCOVERY = true,
            NPC = false, CHAT = false, LEVEL = false, GROUP = false, REPUTATION = false, SKILL = false, SPELL = false,
            QUEST_ACCEPT = true, REVISIT = true, MOUNT = true, ACHIEVEMENT = true, GUILD = true,
        },
    },
    ampliado = {
        chat = "important",
        lootQuality = 3,
        deathKiller = false,
        -- types: every TYPE_INFO type at its default (filled in by ApplyProfileTo)
    },
}

-- Writes profile `name` into a settings table. Returns false for an unknown name.
local function ApplyProfileTo(settings, name)
    local profile = ns.PROFILES[name]
    if not profile then return false end
    settings.chat = profile.chat
    settings.lootQuality = profile.lootQuality
    settings.deathKiller = profile.deathKiller == true
    if type(settings.types) ~= "table" then settings.types = {} end
    if profile.types then
        for key, enabled in pairs(profile.types) do settings.types[key] = enabled end
    else
        for key, enabled in pairs(ns.TYPE_DEFAULT) do settings.types[key] = enabled end
    end
    settings.profile = name
    return true
end

-- Chema's Forever line (1.1.0-Forever) ------------------------------------------------------
-- Its EnsureDatabase always creates these three tables (and never `settings`), so their presence
-- in a diary without `settings` means "saved by that line, never loaded here".
local CHEMA_KEYS = { "visitedZones", "knownMounts", "knownAchievements" }

local function HasChemaKeys(db)
    for _, key in ipairs(CHEMA_KEYS) do
        if type(db[key]) == "table" then return true end
    end
    return false
end

-- Chema's `visitedZones` uses the same "Subzona, Zona" key as `visited` (both build it as
-- sub .. ", " .. zone), so its places are copied over: a place seen there is not discovered again
-- here. Done on every load, not only the first, because a player who goes back to Chema's version
-- for a while keeps adding places there (that version ignores `visited`). `visitedZones` itself,
-- `knownMounts`, `knownAchievements` and every jornada are left exactly as they are.
local function MergeChemaVisited(db)
    if type(db.visitedZones) ~= "table" then return end
    for place, seen in pairs(db.visitedZones) do
        if type(place) == "string" and place ~= "" and seen then db.visited[place] = true end
    end
end

-- v1 -> v2: `visited` (places already logged as a DISCOVERY) and `settings`.
-- Places that v1 diaries already logged as discoveries are seeded into
-- `visited`, so upgrading does not log them a second time. The jornadas
-- themselves are never touched.
local function MigrateToV2(db)
    for _, day in pairs(db.days) do
        if type(day) == "table" and type(day.events) == "table" then
            for _, entry in ipairs(day.events) do
                if type(entry) == "table" and entry.type == "DISCOVERY" and type(entry.text) == "string" then
                    db.visited[entry.text] = true
                end
            end
        end
    end
end

-- Item qualities `lootQuality` accepts (Enum.ItemQuality: 2 uncommon ... 5 legendary).
local LOOT_QUALITIES = { [2] = true, [3] = true, [4] = true, [5] = true }

-- Fills in defaults without touching values the player set. A value of the wrong
-- type (a hand-edited file) is replaced by the default.
local function NormaliseSettings(settings)
    -- A diary that took the "clasico" profile before deathKiller existed (T1..T3) gets what that profile says.
    if settings.deathKiller == nil and settings.profile == "clasico" then settings.deathKiller = true end
    for key, default in pairs(ns.DEFAULT_SETTINGS) do
        if type(default) == "table" then
            if type(settings[key]) ~= "table" then settings[key] = {} end
            for subKey, subDefault in pairs(default) do
                if type(settings[key][subKey]) ~= type(subDefault) then settings[key][subKey] = subDefault end
            end
        elseif type(settings[key]) ~= type(default) then
            settings[key] = default
        end
    end
    if not LOOT_QUALITIES[settings.lootQuality] then settings.lootQuality = ns.DEFAULT_SETTINGS.lootQuality end
    if not ns.PROFILES[settings.profile] then settings.profile = ns.DEFAULT_SETTINGS.profile end
end

-- Creates or normalises AdventureJournalDB and caches it as ns.DB. Idempotent.
function ns.EnsureDatabase()
    if type(AdventureJournalDB) ~= "table" then
        AdventureJournalDB = { version = ns.SCHEMA_VERSION, currentDay = 0, days = {} }
    end
    local db = AdventureJournalDB
    local oldVersion = tonumber(db.version) or 1
    -- Decided before `settings` is created below: once it exists, this diary has loaded here.
    local firstLoadOfChemaDiary = type(db.settings) ~= "table" and HasChemaKeys(db)
    db.currentDay = tonumber(db.currentDay) or 0
    if type(db.days) ~= "table" then db.days = {} end
    if type(db.visited) ~= "table" then db.visited = {} end
    if type(db.settings) ~= "table" then db.settings = {} end
    NormaliseSettings(db.settings)
    if oldVersion < 2 then MigrateToV2(db) end
    if firstLoadOfChemaDiary then
        db.origin = "chema"
        ApplyProfileTo(db.settings, "clasico")
    end
    MergeChemaVisited(db)
    if oldVersion < ns.SCHEMA_VERSION then db.version = ns.SCHEMA_VERSION end
    ns.DB = db
    return db
end

-- Applies a profile to this character's settings (T1; the panel and a command come in T5).
-- Returns true, or false for an unknown name.
function ns.ApplyProfile(name)
    local ok = ApplyProfileTo(ns.EnsureDatabase().settings, name)
    if ok then ns.OnSettingsChanged() end
    return ok
end

-- The lowest item quality logged as LOOT.
function ns.GetLootQuality()
    local value = ns.GetSetting("lootQuality")
    if LOOT_QUALITIES[value] then return value end
    return ns.DEFAULT_SETTINGS.lootQuality
end

-- Settings helpers ----------------------------------------------------------------
-- Reads work before the database exists (they fall back to the defaults); writes
-- create it. After a write, call ns.OnSettingsChanged() so the panel and the book
-- show the new value.

function ns.GetSetting(key)
    local settings = ns.DB and ns.DB.settings
    local value = settings and settings[key]
    if value == nil then return ns.DEFAULT_SETTINGS[key] end
    return value
end

function ns.SetSetting(key, value)
    ns.EnsureDatabase().settings[key] = value
    ns.OnSettingsChanged()
end

-- A type the player set is what they set. Otherwise its TYPE_INFO default, and a type this
-- version does not know (an entry saved by another version, such as Chema's MOUNT) counts as on.
function ns.IsTypeEnabled(entryType)
    if not ns.IsTypeAvailable(entryType) then return false end
    local settings = ns.DB and ns.DB.settings
    local types = settings and settings.types
    local value
    if type(types) == "table" then value = types[entryType] end
    if value == true or value == false then return value end
    return ns.TYPE_DEFAULT[entryType] ~= false
end

function ns.SetTypeEnabled(entryType, enabled)
    ns.EnsureDatabase().settings.types[entryType] = enabled and true or false
    ns.OnSettingsChanged()
end

-- Maps what the player typed ("botin", "LOOT") to an entry type key, or nil.
function ns.TypeFromWord(word)
    word = string.lower(word or "")
    for _, info in ipairs(ns.TYPE_INFO) do
        if string.lower(info.key) == word then return info.key end
        for _, candidate in ipairs(info.words) do
            if candidate == word then return info.key end
        end
    end
    return nil
end

-- UI.lua and Options.lua replace this to refresh themselves (they load later).
function ns.OnSettingsChanged() end
