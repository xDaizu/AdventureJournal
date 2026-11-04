-- Database.lua: the SavedVariables table (AdventureJournalDB), schema version
-- and migrations. Schema: README.md, "SavedVariables schema".
local addonName, ns = ...

ns.SCHEMA_VERSION = 1

-- Creates or normalises AdventureJournalDB and caches it as ns.DB.
-- Migrations from older schema versions go here (schema v2 is planned in M4).
function ns.EnsureDatabase()
    if type(AdventureJournalDB) ~= "table" then
        AdventureJournalDB = { version = ns.SCHEMA_VERSION, currentDay = 0, days = {} }
    end
    local db = AdventureJournalDB
    db.version = ns.SCHEMA_VERSION
    db.currentDay = tonumber(db.currentDay) or 0
    if type(db.days) ~= "table" then db.days = {} end
    ns.DB = db
    return db
end
