-- Compat.lua: client detection, the secret-value guard, and every game-API call
-- that differs between WoW Classic Era (11509) and WoW Forever (16001, Mainline).
-- Other files must go through these wrappers instead of calling the APIs directly.
-- Observed behaviour behind these choices: REFERENCE_SAMPLES.md.
local addonName, ns = ...

local _, _, _, tocVersion = GetBuildInfo()
ns.TOC_VERSION = tocVersion
ns.IS_CLASSIC_ERA = WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
ns.IS_FOREVER = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
    or (type(tocVersion) == "number" and tocVersion > 16000 and tocVersion < 20000)

-- issecretvalue exists on Forever and on Classic Era 1.15.9 (where it is always
-- false). The nil check keeps this safe on any client that lacks it.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

function ns.SafeString(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback or "algo que no supe identificar"
end

-- Zone ---------------------------------------------------------------------------
-- GetRealZoneText() can be nil at PLAYER_LOGIN on a fresh login (observed).
function ns.GetZoneText()
    return GetRealZoneText and GetRealZoneText()
end

function ns.GetSubZoneText()
    return GetSubZoneText and GetSubZoneText()
end

function ns.GetPlace()
    local zone = ns.SafeString(ns.GetZoneText(), "tierras desconocidas")
    local sub = ns.SafeString(ns.GetSubZoneText(), "")
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end

-- Units --------------------------------------------------------------------------
function ns.UnitNameSafe(unit)
    if not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if ok then return name end
    return nil
end

-- Quests -------------------------------------------------------------------------
-- Forever: C_QuestLog.GetTitleForQuestID. Classic Era lacks it (observed), so scan
-- the quest log. Call this synchronously inside QUEST_TURNED_IN: the quest is
-- still in the log during the event and gone about a second later (observed).
function ns.GetQuestTitle(questID)
    if questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then return title end
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, _, foundID = GetQuestLogTitle(index)
            if not isHeader and foundID == questID and title then return title end
        end
    end
    if questID then return "una misión (ID " .. tostring(questID) .. ")" end
    return "una misión cuyo nombre no he podido recuperar"
end

-- Items --------------------------------------------------------------------------
-- Returns name, link, quality; or nil while the item is not cached yet.
-- Classic Era has both APIs (they agree, observed). Forever may lack the global.
function ns.GetItemInfoSafe(item)
    if not item then return nil end
    if GetItemInfo then
        local name, link, quality = GetItemInfo(item)
        if quality then return name, link, quality end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, name, link, quality = pcall(C_Item.GetItemInfo, item)
        if ok and quality then return name, link, quality end
    end
    return nil
end

-- Events -------------------------------------------------------------------------
-- Registers an event only if this client knows it. MINIMAP_ZONE_CHANGED, for
-- example, does not exist on Classic Era (observed).
function ns.RegisterEventSafe(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return false
    end
    return (pcall(frame.RegisterEvent, frame, event))
end
