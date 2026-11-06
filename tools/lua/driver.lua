-- Loads an addon's Lua files (as listed in its TOC) into the stubbed world,
-- runs a scenario, and renders a deterministic report into the OUTPUT global.
-- Globals set by run.js: ADDON_NAME, ADDON_DIR, ADDON_FILES, SCENARIO, MODE, RELOAD, PRESET_DB,
-- STUB_OPTIONS (read by stubs.lua), VARIANT ("" when none), TOC_COMPARTMENT_FUNC ("" when the TOC has no such field).

local leaked = 0
local function Serialize(value, indent)
    indent = indent or ""
    -- Stub secrets and the addon's simulated secrets are tables with a metatable
    -- (or report as secret). Neither may ever reach SavedVariables.
    if issecretvalue(value) or (type(value) == "table" and getmetatable(value) ~= nil) then
        leaked = leaked + 1
        return '"<<SECRET LEAKED INTO SAVEDVARIABLES>>"'
    end
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    if #keys == 0 then return "{}" end
    local inner = indent .. "  "
    local lines = { "{" }
    for _, k in ipairs(keys) do
        local key = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]"
        table.insert(lines, inner .. key .. " = " .. Serialize(value[k], inner) .. ",")
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local before = {}
for k in pairs(_G) do before[k] = true end

if PRESET_DB and PRESET_DB ~= "" then
    AdventureJournalDB = assert(load("return " .. PRESET_DB))()
end

local ns = {}
for file in string.gmatch(ADDON_FILES, "[^\n]+") do
    local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
    chunk(ADDON_NAME, ns)
end

local addonGlobals = {}
for k in pairs(_G) do
    if not before[k] and k ~= "AdventureJournalDB" then table.insert(addonGlobals, k) end
end
table.sort(addonGlobals)

local report = {}
local function Section(title) table.insert(report, "== " .. title) end
local function Line(text) table.insert(report, text) end

-- The scenario gets a few helpers and appends its own observations.
local H = {
    S = STUB,
    fire = STUB.Fire,
    advance = function(seconds) STUB.clock = STUB.clock + seconds end,
    ns = ns,
    slash = function(msg) SlashCmdList[string.upper(ADDON_NAME)](msg) end,
    note = function(text) Line("-- " .. text) end,
    reload = RELOAD,
    mode = MODE,   -- "login" | "reload" | "relogin"
    variant = VARIANT ~= "" and VARIANT or nil,   -- the scenario entry's `variant`, if any
    compartmentFunc = TOC_COMPARTMENT_FUNC ~= "" and TOC_COMPARTMENT_FUNC or nil,
    noDump = false,   -- a scenario with a huge diary sets this to keep the report readable
}
local scenario = assert(loadfile(SCENARIO))
Section("scenario log")
scenario(H)

Section("events registered")
local registered = {}
for _, w in ipairs(STUB.frames) do
    for e in pairs(w.events) do table.insert(registered, e) end
end
table.sort(registered)
Line(table.concat(registered, ", "))

Section("globals created by the addon")
Line(table.concat(addonGlobals, ", "))

Section("chat output")
for _, p in ipairs(STUB.prints) do Line(p) end

Section("AdventureJournalDB")
-- Always serialised (the secret scan runs inside Serialize), printed unless the
-- scenario opted out.
local dump = Serialize(AdventureJournalDB)
if H.noDump then
    local days = 0
    for _ in pairs(AdventureJournalDB.days) do days = days + 1 end
    Line(string.format("(dump omitted by the scenario: version %s, %d jornadas, currentDay %s)",
        tostring(AdventureJournalDB.version), days, tostring(AdventureJournalDB.currentDay)))
else
    Line(dump)
end

if leaked > 0 then error(leaked .. " secret value(s) reached AdventureJournalDB") end
OUTPUT = table.concat(report, "\n") .. "\n"
DB_DUMP = dump
