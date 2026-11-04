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

-- Debug state. Session only: never saved, so a /reload resets it.
--   on      print the payload of every handled event and every fallback taken
--   secrets simulate secret values on Classic Era (see ns.Taint)
--   buttons force the old one-Button-per-jornada index (the ScrollBox fallback path);
--           only read when the book is first built, so set it before the first /diario
ns.debug = { on = false, secrets = false, buttons = false }

-- Simulated secrets ----------------------------------------------------------------
-- Classic Era never produces secrets, so `/diario debug secrets` wraps event
-- payload strings (and UnitName results) in a proxy that errors on everything a
-- real secret forbids. A proxy is a table, so type() on it says "table" where a
-- real secret string says "string": always call ns.IsSecret before type().
local simulated = setmetatable({}, { __mode = "k" })
local simMeta = {}
for _, metaEvent in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm",
        "__lt", "__le", "__len", "__index", "__newindex", "__call", "__concat",
        "__eq", "__tostring" }) do
    simMeta[metaEvent] = function()
        error("AdventureJournal: operation on a simulated secret value (" .. metaEvent .. ")", 2)
    end
end

function ns.Taint(value)
    if ns.debug.secrets and not ns.IsSecret(value) and type(value) == "string" then
        local proxy = setmetatable({}, simMeta)
        simulated[proxy] = true
        return proxy
    end
    return value
end

-- issecretvalue exists on Forever and on Classic Era 1.15.9 (where it is always
-- false). The nil check keeps this safe on any client that lacks it. The real
-- check comes first: indexing `simulated` with a real secret would raise an error.
function ns.IsSecret(value)
    if issecretvalue ~= nil and issecretvalue(value) == true then return true end
    return ns.debug.secrets and simulated[value] == true
end

-- Text for debug output. Never touches the content of a secret.
function ns.Describe(value)
    if ns.IsSecret(value) then return "[SECRET]" end
    local kind = type(value)
    if kind == "string" then
        if #value > 60 then value = string.sub(value, 1, 57) .. "..." end
        return string.format("%q", value)
    elseif kind == "number" or kind == "boolean" or kind == "nil" then
        return tostring(value)
    end
    return "<" .. kind .. ">"
end

function ns.Debug(message, ...)
    if ns.debug.on then
        print("|cFF888888[Diario debug]|r " .. string.format(message, ...))
    end
end

local DEFAULT_TEXT = "algo que no supe identificar"

-- Returns value when it is a non-empty string, else the fallback. A secret never
-- passes: its content cannot be read, compared or saved.
function ns.SafeString(value, fallback)
    if ns.IsSecret(value) then return fallback or DEFAULT_TEXT end
    if type(value) == "string" and value ~= "" then return value end
    return fallback or DEFAULT_TEXT
end

-- An error message without its "path\File.lua:123: " prefix, for diagnostics.
function ns.StripPosition(err)
    return (string.gsub(tostring(err), "^.-:%d+: ", ""))
end

-- A TOC field of this addon ("Version", "AddonCompartmentFunc", ...), or nil.
function ns.GetAddonField(field)
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then return nil end
    local ok, value = pcall(getMetadata, addonName, field)
    if ok then return value end
    return nil
end

function ns.GetAddonVersion()
    return ns.GetAddonField("Version")
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
    if ok then return ns.Taint(name) end
    return nil
end

-- Quests -------------------------------------------------------------------------
-- Forever: C_QuestLog.GetTitleForQuestID. Classic Era lacks it (observed), so scan
-- the quest log. Call this synchronously inside QUEST_TURNED_IN: the quest is
-- still in the log during the event and gone about a second later (observed).
function ns.GetQuestTitle(questID)
    if ns.IsSecret(questID) then questID = nil end
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
-- Classic Era has both APIs (they agree, observed). Forever may lack the global,
-- so the C_Item version goes first.
function ns.GetItemInfoSafe(item)
    if not item or ns.IsSecret(item) then return nil end
    if C_Item and C_Item.GetItemInfo then
        local ok, name, link, quality = pcall(C_Item.GetItemInfo, item)
        if ok and quality then return name, link, quality end
    end
    if GetItemInfo then
        local name, link, quality = GetItemInfo(item)
        if quality then return name, link, quality end
    end
    return nil
end

-- Asks the client to load an item that is not cached yet; the answer arrives as
-- GET_ITEM_INFO_RECEIVED or ITEM_DATA_LOAD_RESULT.
function ns.RequestItemData(itemID)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

-- Own loot ------------------------------------------------------------------------
-- The game's own loot strings, which differ per locale (esES: "Recibes botín: %s.").
-- Only the "you receive" forms are used, so other players' loot is ignored (bug #6).
local OWN_LOOT_GLOBALS = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }
local ownLootPatterns

-- "Recibes botín: %s." -> "^Recibes botín: (.+)%.$". Also handles positional
-- formats such as "%1$s" and "%2$d".
local function FormatToPattern(format)
    local pattern = string.gsub(format, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    pattern = string.gsub(pattern, "%%%%%d%$s", "(.+)")
    pattern = string.gsub(pattern, "%%%%%d%$d", "(%%d+)")
    pattern = string.gsub(pattern, "%%%%s", "(.+)")
    pattern = string.gsub(pattern, "%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

function ns.GetOwnLootPatterns()
    if not ownLootPatterns then
        ownLootPatterns = {}
        for _, name in ipairs(OWN_LOOT_GLOBALS) do
            local format = _G[name]
            if type(format) == "string" and format ~= "" then
                table.insert(ownLootPatterns, FormatToPattern(format))
            end
        end
    end
    return ownLootPatterns
end

-- True when a CHAT_MSG_LOOT message (never secret here) is the player's own loot.
-- If this client has none of the strings, everything counts as own loot (the
-- behaviour before M4) so loot is never lost to a missing string.
function ns.IsOwnLootMessage(message)
    local patterns = ns.GetOwnLootPatterns()
    if #patterns == 0 then return true end
    for _, pattern in ipairs(patterns) do
        if string.find(message, pattern) then return true end
    end
    return false
end

-- Events -------------------------------------------------------------------------
-- Registers an event only if this client knows it. MINIMAP_ZONE_CHANGED, for
-- example, does not exist on Classic Era (observed).
-- ns.eventStatus[event] = true (registered), or the reason it was not.
ns.eventStatus = {}
function ns.RegisterEventSafe(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        ns.eventStatus[event] = "el cliente no conoce este evento"
        return false
    end
    local ok = pcall(frame.RegisterEvent, frame, event)
    ns.eventStatus[event] = ok or "RegisterEvent falló"
    return ok
end

-- UI feature detection (M5) ---------------------------------------------------------
-- "The function exists" does not mean "the template exists", so templates are tested
-- by creating a throwaway hidden frame under pcall. Results are cached: a frame
-- cannot be deleted, so each probe creates at most one.

-- Looks up a dotted global path ("Settings.OpenToCategory") without erroring.
function ns.Resolve(path)
    local value = _G
    for part in string.gmatch(path, "[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local templateResults = {}
function ns.TemplateWorks(frameType, template)
    local key = frameType .. ":" .. template
    local cached = templateResults[key]
    if cached then return cached.ok, cached.err end
    local ok, result = pcall(CreateFrame, frameType, nil, UIParent, template)
    if ok and type(result) == "table" and result.Hide then result:Hide() end
    templateResults[key] = { ok = ok, err = not ok and tostring(result) or nil }
    return ok, templateResults[key].err
end

-- Builds a real ScrollBox list (view, scroll bar, data provider) on a hidden frame,
-- the way UI.lua will, and reports the step that failed. Cached.
local scrollBoxProbe
function ns.ProbeScrollBox()
    if scrollBoxProbe then return scrollBoxProbe end
    local step = "funciones"
    local ok, err = pcall(function()
        if not (CreateScrollBoxListLinearView and CreateDataProvider and ScrollUtil
                and ScrollUtil.InitScrollBoxListWithScrollBar) then
            error("faltan CreateScrollBoxListLinearView, CreateDataProvider o ScrollUtil.InitScrollBoxListWithScrollBar", 0)
        end
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(10, 10)
        holder:Hide()
        step = "plantilla WowScrollBoxList"
        local box = CreateFrame("Frame", nil, holder, "WowScrollBoxList")
        step = "plantilla MinimalScrollBar"
        local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
        step = "CreateScrollBoxListLinearView"
        local view = CreateScrollBoxListLinearView()
        step = "view:SetElementExtent"
        view:SetElementExtent(24)
        step = "view:SetElementInitializer"
        view:SetElementInitializer("UIPanelButtonTemplate", function(button, data) button:SetText(tostring(data)) end)
        step = "ScrollUtil.InitScrollBoxListWithScrollBar"
        ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
        step = "box:SetDataProvider"
        box:SetDataProvider(CreateDataProvider({ 1, 2, 3 }))
    end)
    scrollBoxProbe = { ok = ok, step = step, err = not ok and tostring(err) or nil }
    return scrollBoxProbe
end

-- Rows { label, value } for /diario diag: what the options panel, the ScrollBox
-- index and the addon compartment can rely on in this client.
function ns.GetUiFeatures()
    local rows = {}
    local function add(label, value) table.insert(rows, { label, value }) end
    local function has(path) return ns.Resolve(path) ~= nil and "sí" or "NO" end
    for _, path in ipairs({
        "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterVerticalLayoutCategory",
        "Settings.RegisterAddOnCategory", "Settings.OpenToCategory",
        "Settings.RegisterAddOnSetting", "Settings.RegisterProxySetting",
        "Settings.CreateCheckbox", "Settings.CreateDropdown", "Settings.VarType",
        "SettingsPanel", "InterfaceOptions_AddCategory",
        "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil.InitScrollBoxListWithScrollBar",
        "AddonCompartmentFrame",
    }) do add(path, has(path)) end
    for _, spec in ipairs({
        { "CheckButton", "UICheckButtonTemplate" }, { "CheckButton", "InterfaceOptionsCheckButtonTemplate" },
        { "Button", "UIPanelButtonTemplate" }, { "Frame", "WowScrollBoxList" },
        { "EventFrame", "MinimalScrollBar" },
    }) do
        local ok, err = ns.TemplateWorks(spec[1], spec[2])
        add("plantilla " .. spec[2], ok and "sí" or ("NO (" .. string.sub(tostring(err), 1, 80) .. ")"))
    end
    local probe = ns.ProbeScrollBox()
    add("prueba de ScrollBox", probe.ok and "OK" or ("FALLA en " .. probe.step .. ": " .. string.sub(probe.err or "?", 1, 160)))
    return rows
end

-- Diagnostics -----------------------------------------------------------------------
-- Which API branch each wrapper above takes on this client. Used by /diario diag.
function ns.GetApiBranches()
    local function has(value) return value ~= nil and "sí" or "NO" end
    local secretProbe = "NO"
    if issecretvalue ~= nil then
        local ok, result = pcall(issecretvalue, "x")
        secretProbe = ok and ("sí (issecretvalue('x') = " .. tostring(result) .. ")") or "sí (pero falla)"
    end
    return {
        { "issecretvalue", secretProbe },
        { "C_Secrets / C_RestrictedActions", has(C_Secrets) .. " / " .. has(C_RestrictedActions) },
        { "Info de objetos", (C_Item and C_Item.GetItemInfo) and "C_Item.GetItemInfo (primero)" or "sin C_Item.GetItemInfo" },
        { "GetItemInfo global", has(GetItemInfo) },
        { "C_Item.RequestLoadItemDataByID", has(C_Item and C_Item.RequestLoadItemDataByID) },
        { "Título de misión", (C_QuestLog and C_QuestLog.GetTitleForQuestID) and "C_QuestLog.GetTitleForQuestID"
            or ((GetNumQuestLogEntries and GetQuestLogTitle) and "recorrer el registro de misiones" or "solo el ID") },
        { "C_EventUtils.IsEventValid", has(C_EventUtils and C_EventUtils.IsEventValid) },
        { "C_AddOns.GetAddOnMetadata / GetAddOnMetadata", has(C_AddOns and C_AddOns.GetAddOnMetadata) .. " / " .. has(GetAddOnMetadata) },
        { "GetRealZoneText / GetSubZoneText", has(GetRealZoneText) .. " / " .. has(GetSubZoneText) },
    }
end
