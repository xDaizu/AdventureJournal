-- Events.lua: event registration and handlers, entry creation, session start/end.
local addonName, ns = ...
local SafeString = ns.SafeString

local eventFrame = CreateFrame("Frame")
local currentPlace = ""
local sessionStarted = false
local lastQuestID, lastQuestAt
local lastBossName, lastBossAt
local lastNPCName, lastNPCTime
local pendingLoot = {}   -- [itemID] = itemLink, waiting for GET_ITEM_INFO_RECEIVED

function ns.AddEntry(eventType, description, extra)
    local DB = ns.DB
    if not DB then return end
    local day = DB.days[DB.currentDay]
    if not day then return end

    local profile, tone = ns.ChooseMood(eventType)
    local entry = {
        type = eventType,
        text = SafeString(description, "Acontecimiento sin descripción"),
        place = ns.GetPlace(),
        zone = SafeString(ns.GetZoneText(), "Desconocido"),
        subZone = SafeString(ns.GetSubZoneText(), ""),
        time = date("%H:%M:%S"),
        timestamp = time(),
        characterProfile = profile,
        contextualTone = tone,
        seed = #(day.events or {}) + 1,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            -- Secrets cannot be saved (they would become nil); drop them.
            if ns.IsSecret(value) then
                ns.Debug("AddEntry: campo %s descartado por ser secreto", tostring(key))
            else
                entry[key] = value
            end
        end
    end
    entry.prose = ns.ComposeEntry(entry)
    day.events = day.events or {}
    table.insert(day.events, entry)
    ns.RefreshIfVisible()
    print(string.format("|cFF00FF00[Diario]|r %s", entry.text))
end

local function StartSession()
    if sessionStarted then return end
    sessionStarted = true
    local DB = ns.EnsureDatabase()

    -- Se conserva deliberadamente el criterio solicitado: cada inicio de sesión crea una jornada.
    DB.currentDay = DB.currentDay + 1
    local n = DB.currentDay
    DB.days[n] = {
        startedAt = date("%Y-%m-%d %H:%M:%S"),
        dateLabel = date("%d/%m/%Y"),
        events = {},
    }
    ns.selectedDay = n
    currentPlace = ns.GetPlace()
    print(string.format("|cFFFFD700[Diario]|r Comienza la jornada %d. Tu historia continúa.", n))
end

local function TryLogLoot(itemLink, itemID)
    local _, _, quality = ns.GetItemInfoSafe(itemLink or itemID)
    if quality and quality >= 3 then
        local displayLink = itemLink
        if not displayLink then
            local _, link = ns.GetItemInfoSafe(itemID)
            displayLink = link
        end
        ns.AddEntry("LOOT", displayLink or ("un objeto (ID " .. tostring(itemID) .. ")"), {
            itemQuality = quality,
            itemLink = displayLink,
            itemID = itemID,
        })
        return true
    end
    return false
end

local handlers = {}

handlers.ADDON_LOADED = function(loadedName)
    if loadedName == addonName then ns.EnsureDatabase() end
end

handlers.PLAYER_LOGIN = function()
    StartSession()
end

handlers.PLAYER_LOGOUT = function()
    local DB = ns.DB
    if DB and DB.days and DB.days[DB.currentDay] then
        DB.days[DB.currentDay].endedAt = date("%Y-%m-%d %H:%M:%S")
    end
end

handlers.QUEST_TURNED_IN = function(questID)
    if ns.IsSecret(questID) then
        ns.Debug("QUEST_TURNED_IN: questID secreto, se usa el texto neutro")
        questID = nil
    end
    if not questID or questID ~= lastQuestID or not lastQuestAt or time() - lastQuestAt > 3 then
        lastQuestID, lastQuestAt = questID, time()
        ns.AddEntry("QUEST", ns.GetQuestTitle(questID), { questID = questID })
    end
end

local UNKNOWN_BOSS = "una criatura temible"

handlers.BOSS_KILL = function(_, bossName)
    if ns.IsSecret(bossName) then ns.Debug("BOSS_KILL: nombre secreto, se usa el texto neutro") end
    bossName = SafeString(bossName, UNKNOWN_BOSS)
    if bossName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
        lastBossName, lastBossAt = bossName, time()
        ns.AddEntry("BOSS", bossName)
    end
end

handlers.ENCOUNTER_END = function(_, encounterName, _, _, success)
    -- Without a readable success flag we cannot tell a kill from a wipe. BOSS_KILL
    -- covers the kill, so skip.
    if ns.IsSecret(success) then
        ns.Debug("ENCOUNTER_END: success secreto, se ignora")
        return
    end
    if success == 1 and encounterName then
        if ns.IsSecret(encounterName) then
            ns.Debug("ENCOUNTER_END: nombre secreto, se usa el texto neutro")
            encounterName = UNKNOWN_BOSS
        end
        if encounterName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
            lastBossName, lastBossAt = encounterName, time()
            ns.AddEntry("BOSS", encounterName)
        end
    end
end

handlers.PLAYER_DEAD = function()
    ns.AddEntry("DEATH", "He caído en combate")
end

handlers.CHAT_MSG_LOOT = function(message)
    if ns.IsSecret(message) then
        -- The item cannot be read, so there is nothing to log.
        ns.Debug("CHAT_MSG_LOOT: mensaje secreto, se omite")
        return
    end
    if type(message) == "string" then
        -- Any colour prefix: |cffRRGGBB (Classic Era) or |cnIQ<n>: (possibly Forever).
        local itemLink = string.match(message, "|c[^|]*|Hitem:.-|h%[.-%]|h|r")
        if itemLink then
            local itemID = tonumber(string.match(itemLink, "|Hitem:(%d+)"))
            if not TryLogLoot(itemLink, itemID) and itemID then
                pendingLoot[itemID] = itemLink
                ns.RequestItemData(itemID)
            end
        end
    end
end

-- Also handles ITEM_DATA_LOAD_RESULT (same arguments: itemID, success).
handlers.GET_ITEM_INFO_RECEIVED = function(itemID, success)
    if ns.IsSecret(itemID) or ns.IsSecret(success) then return end
    local link = itemID and pendingLoot[itemID]
    if link then
        pendingLoot[itemID] = nil
        if success then TryLogLoot(link, itemID) end
    end
end
handlers.ITEM_DATA_LOAD_RESULT = handlers.GET_ITEM_INFO_RECEIVED

local function OnZoneChanged()
    -- An unreadable zone is not a discovery: skip it instead of logging "unknown lands".
    if ns.IsSecret(ns.GetZoneText()) or ns.IsSecret(ns.GetSubZoneText()) then
        ns.Debug("ZONE_CHANGED: nombre de zona secreto, se omite")
        return
    end
    local newPlace = ns.GetPlace()
    if newPlace ~= currentPlace then
        currentPlace = newPlace
        ns.AddEntry("DISCOVERY", newPlace)
    end
end
handlers.ZONE_CHANGED_NEW_AREA = OnZoneChanged
handlers.ZONE_CHANGED = OnZoneChanged
handlers.ZONE_CHANGED_INDOORS = OnZoneChanged
handlers.MINIMAP_ZONE_CHANGED = OnZoneChanged

handlers.GOSSIP_SHOW = function()
    local rawName = ns.UnitNameSafe("npc")
    if ns.IsSecret(rawName) then ns.Debug("GOSSIP_SHOW: nombre del PNJ secreto, se usa el texto neutro") end
    local npcName = SafeString(rawName, "un habitante de la zona")
    if npcName ~= lastNPCName or not lastNPCTime or time() - lastNPCTime > 20 then
        lastNPCName, lastNPCTime = npcName, time()
        ns.AddEntry("NPC", npcName)
    end
end

-- Stores the sender name only, never the message text (privacy; see README).
handlers.CHAT_MSG_WHISPER = function(_, sender)
    if ns.IsSecret(sender) then
        ns.Debug("CHAT_MSG_WHISPER: remitente secreto, se usa el texto neutro")
        ns.AddEntry("CHAT", "alguien")
    elseif type(sender) == "string" and sender ~= "" then
        sender = string.match(sender, "^([^%-]+)") or sender
        ns.AddEntry("CHAT", sender)
    end
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
    "QUEST_TURNED_IN", "BOSS_KILL", "ENCOUNTER_END", "PLAYER_DEAD",
    "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED",
    "GOSSIP_SHOW", "CHAT_MSG_WHISPER",
}
ns.EVENTS = EVENTS
for _, eventName in ipairs(EVENTS) do ns.RegisterEventSafe(eventFrame, eventName) end

-- Error isolation: a failing handler never stops the others. Each event name is
-- reported once to the game's error handler (so scriptErrors / BugSack show it);
-- later failures are only counted. /diario diag lists them.
ns.handlerErrors = {}   -- [event] = { count = n, message = first error }

local function ReportHandlerError(event, err)
    local record = ns.handlerErrors[event]
    if record then
        record.count = record.count + 1
        return
    end
    ns.handlerErrors[event] = { count = 1, message = tostring(err) }
    local text = string.format("AdventureJournal: error en el manejador de %s: %s", event, tostring(err))
    ns.Debug("%s", text)
    local errorHandler = geterrorhandler and geterrorhandler()
    if errorHandler then errorHandler(text) end
end

local function LogPayload(event, ...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = ns.Describe((select(index, ...)))
    end
    ns.Debug("%s(%s)", event, table.concat(parts, ", "))
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if not handler then return end
    local ok, err
    if ns.debug.on or ns.debug.secrets then
        local args = { n = select("#", ...), ... }
        if ns.debug.secrets and event ~= "ADDON_LOADED" then
            for index = 1, args.n do args[index] = ns.Taint(args[index]) end
        end
        if ns.debug.on then LogPayload(event, unpack(args, 1, args.n)) end
        ok, err = pcall(handler, unpack(args, 1, args.n))
    else
        ok, err = pcall(handler, ...)
    end
    if not ok then ReportHandlerError(event, err) end
end)
