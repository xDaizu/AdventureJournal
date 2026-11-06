-- Synthetic AJProbeDB tables for the M4b import scenarios.
--
-- The records are built from what AJProbe.lua writes (LogActivity, LOG_BUILDERS, LogChat, Snap),
-- NOT copied from a real SavedVariables file:
--   activity record  { e = event, t = epoch, d = "YYYY-MM-DD HH:MM:SS", c = "Name-GetRealmName()",
--                      z = zone, s = subzone, i = instanceType, ...fields of the event's builder }
--   Snap() turns nil into "<nil>", a secret into "[SECRET]", a table into "<table>".
--   chat record      { ch = "SAY", t, d, c, msg, who, lang, rel, btag, z, s, i }
-- What this cannot show: the real file, real chat events, real timestamps (tools/README.md).
local F = {}

F.KEY = "Volgajin-Zandalar Tribe"     -- UnitName("player") .. "-" .. GetRealmName() in the stubs
F.OTHER = "Otropj-Zandalar Tribe"

local function Stamp(t) return date("%Y-%m-%d %H:%M:%S", t) end

function F.New()
    local self = { db = { samples = {}, counts = {}, registration = {}, log = {}, chat = {} } }
    self.z, self.s = "Durotar", "Valle de los Retos"

    -- Sets the zone and subzone the following records carry.
    function self.At(zone, sub) self.z, self.s = zone, sub end

    function self.Log(t, event, fields, key)
        local record = { e = event, t = t, d = Stamp(t), c = key or F.KEY, z = self.z, s = self.s, i = "none" }
        for field, value in pairs(fields or {}) do record[field] = value end
        table.insert(self.db.log, record)
        return record
    end

    function self.Chat(t, channel, fields, key)
        local record = { ch = channel, t = t, d = Stamp(t), c = key or F.KEY, msg = "...", who = "Thrall-ZandalarTribe",
            lang = "Orco", z = self.z, s = self.s, i = "none" }
        for field, value in pairs(fields or {}) do record[field] = value end
        table.insert(self.db.chat, record)
        return record
    end

    return self
end

-- A string for comparing two states of a table: sorted keys, nested tables, no cycles.
function F.Snapshot(value)
    if type(value) ~= "table" then return type(value) == "string" and string.format("%q", value) or tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = F.Snapshot(key) .. "=" .. F.Snapshot(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

return F
