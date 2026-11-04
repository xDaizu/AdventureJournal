-- Database.lua: the SavedVariables table (AdventureJournalDB), schema version
-- and migrations. Schema: README.md, "SavedVariables schema".
local addonName, ns = ...

ns.SCHEMA_VERSION = 2

-- Settings every character gets unless the player changed them.
--   chat: what is echoed to the chat window: "all", "important" or "off"
ns.DEFAULT_SETTINGS = { chat = "important" }

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
    for key, value in pairs(ns.DEFAULT_SETTINGS) do
        if db.settings[key] == nil then db.settings[key] = value end
    end
    if oldVersion < 2 then MigrateToV2(db) end
    if oldVersion < ns.SCHEMA_VERSION then db.version = ns.SCHEMA_VERSION end
    ns.DB = db
    return db
end
