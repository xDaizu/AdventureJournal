-- Database.lua: the SavedVariables table (AdventureJournalDB), schema version,
-- migrations and the settings helpers. Schema: README.md, "SavedVariables schema".
local addonName, ns = ...

ns.SCHEMA_VERSION = 2

-- The entry types the diary can log, in the order the options panel lists them.
--   key    the `type` stored in each entry
--   label  shown in the options panel and /diario tipos
--   words  what /diario tipos <word> accepts (lower case)
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
}

-- Names of the chat echo modes, for messages and the options panel.
ns.CHAT_MODE_NAMES = { all = "todo", important = "importante", off = "nada" }

-- Settings every character gets unless the player changed them. Missing keys are
-- filled in on every load, so adding an option here needs no schema bump and
-- diaries saved by older versions keep their own values.
--   chat           what is echoed to the chat window: "all", "important" or "off"
--   types          which entry types are logged (a type missing here counts as on)
--   showProfile    show the mood (characterProfile) in each entry's header in the book
--   conversations  M4b placeholder (record RP conversations); off by default. Nothing
--                  reads it yet: the options panel shows it disabled.
ns.DEFAULT_SETTINGS = {
    chat = "important",
    types = {},
    showProfile = false,
    conversations = false,
}
for _, info in ipairs(ns.TYPE_INFO) do ns.DEFAULT_SETTINGS.types[info.key] = true end

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

-- Fills in defaults without touching values the player set. A value of the wrong
-- type (a hand-edited file) is replaced by the default.
local function NormaliseSettings(settings)
    for key, default in pairs(ns.DEFAULT_SETTINGS) do
        if type(default) == "table" then
            if type(settings[key]) ~= "table" then settings[key] = {} end
            for subKey, subDefault in pairs(default) do
                if type(settings[key][subKey]) ~= type(subDefault) then settings[key][subKey] = subDefault end
            end
        elseif settings[key] == nil or (type(default) == "boolean" and type(settings[key]) ~= "boolean") then
            settings[key] = default
        end
    end
end

-- Creates or normalises AdventureJournalDB and caches it as ns.DB. Idempotent.
function ns.EnsureDatabase()
    if type(AdventureJournalDB) ~= "table" then
        AdventureJournalDB = { version = ns.SCHEMA_VERSION, currentDay = 0, days = {} }
    end
    local db = AdventureJournalDB
    local oldVersion = tonumber(db.version) or 1
    db.currentDay = tonumber(db.currentDay) or 0
    if type(db.days) ~= "table" then db.days = {} end
    if type(db.visited) ~= "table" then db.visited = {} end
    if type(db.settings) ~= "table" then db.settings = {} end
    NormaliseSettings(db.settings)
    if oldVersion < 2 then MigrateToV2(db) end
    if oldVersion < ns.SCHEMA_VERSION then db.version = ns.SCHEMA_VERSION end
    ns.DB = db
    return db
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

-- A type is logged unless it is explicitly switched off, so a type added in a later
-- version (or one the file does not know) defaults to on.
function ns.IsTypeEnabled(entryType)
    local settings = ns.DB and ns.DB.settings
    local types = settings and settings.types
    return not (type(types) == "table" and types[entryType] == false)
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
