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

-- "Subzone, Zone" (or just the zone) from two texts that may be nil or secret. Also used by
-- the AJProbe import, which has the texts of a past moment instead of the current ones.
function ns.PlaceFrom(zoneText, subZoneText)
    local zone = ns.SafeString(zoneText, "tierras desconocidas")
    local sub = ns.SafeString(subZoneText, "")
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end

function ns.GetPlace()
    return ns.PlaceFrom(ns.GetZoneText(), ns.GetSubZoneText())
end

-- The text an entry gets when the real name is unreadable (secret) or unknown. One
-- table, so the live handlers and the AJProbe import say the same thing.
ns.NEUTRAL_TEXT = {
    NPC = "un habitante de la zona",
    BOSS = "una criatura temible",
    QUEST = "una misión cuyo nombre no he podido recuperar",
    SENDER = "alguien",
    LEVEL = "He subido de nivel",
}

-- "Name-Realm" -> "Name" (chat authors carry the realm, observed in M0).
function ns.StripRealm(name)
    if type(name) ~= "string" then return name end
    return string.match(name, "^([^%-]+)") or name
end

-- The key AJProbe writes into every record's `c` field: "Name-GetRealmName()" (with the
-- realm's spaces). Returns nil when the player's name is unreadable.
function ns.GetPlayerKey()
    if not (UnitName and GetRealmName) then return nil end
    local ok, name = pcall(UnitName, "player")
    local okRealm, realm = pcall(GetRealmName)
    if not (ok and okRealm) or ns.IsSecret(name) or ns.IsSecret(realm)
        or type(name) ~= "string" or type(realm) ~= "string" then
        return nil
    end
    return name .. "-" .. realm
end

-- "2026-11-04 19:12:18" (a local time written by date()) -> epoch, or nil. time{...} is
-- checked by converting back, so a client where it ignores the table is never trusted.
function ns.ParseDateTime(text)
    if type(text) ~= "string" then return nil end
    local year, month, day, hour, minute, second =
        string.match(text, "^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)$")
    if not year then return nil end
    local ok, result = pcall(time, { year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(minute), sec = tonumber(second) })
    if not ok or type(result) ~= "number" then return nil end
    if date("%Y-%m-%d %H:%M:%S", result) ~= text then return nil end
    return result
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
    return ns.NEUTRAL_TEXT.QUEST
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

-- Game messages from the client's own strings (M6) -------------------------------------
-- The client's global format strings ("%s se une al grupo.") turned into Lua patterns, so
-- nothing here depends on the locale. Unlike FormatToPattern above (loot, one kind of text), this
-- keeps track of positional arguments ("%2$s ... %1$s"), so a captured value can be asked for by
-- the argument it stands for, not by where it sits in the sentence.

-- Returns { pattern, order } or nil. order[i] = { arg = n, number = bool } for capture i.
function ns.CompileFormat(format)
    if type(format) ~= "string" or format == "" then return nil end
    local parts, order = { "^" }, {}
    local nextArg, position, length = 1, 1, #format
    while position <= length do
        local char = string.sub(format, position, position)
        local consumed = 1
        if char == "%" then
            local _, finish, argument, conversion = string.find(format, "^%%(%d+)%$([sdifg])", position)
            if not finish then
                _, finish, conversion = string.find(format, "^%%[%-%+ #0]*%d*%.?%d*([sdifg%%])", position)
                argument = nil
            end
            if not finish then return nil end       -- a conversion we do not understand: no pattern
            consumed = finish - position + 1
            if conversion == "%" then
                parts[#parts + 1] = "%%"
            else
                local arg = tonumber(argument)
                if not arg then arg = nextArg; nextArg = nextArg + 1 end
                local isNumber = conversion ~= "s"
                order[#order + 1] = { arg = arg, number = isNumber }
                if not isNumber then
                    parts[#parts + 1] = "(.-)"
                elseif conversion == "d" or conversion == "i" then
                    parts[#parts + 1] = "(%-?%d+)"
                else
                    parts[#parts + 1] = "([%d%.]+)"
                end
            end
        elseif string.find(char, "^%p$") then
            parts[#parts + 1] = "%" .. char
        else
            parts[#parts + 1] = char
        end
        position = position + consumed
    end
    parts[#parts + 1] = "$"
    return { pattern = table.concat(parts), order = order }
end

-- The values of a message matching `compiled`, indexed by argument number (numbers converted),
-- or nil when it does not match. A format without arguments gives an empty table.
function ns.MatchFormat(compiled, text)
    if type(text) ~= "string" then return nil end
    if #compiled.order == 0 then
        if string.find(text, compiled.pattern) then return {} end
        return nil
    end
    local captures = { string.match(text, compiled.pattern) }
    if #captures == 0 then return nil end
    local values = {}
    for index, spec in ipairs(compiled.order) do
        local value = captures[index]
        values[spec.arg] = spec.number and tonumber(value) or value
    end
    return values
end

-- The client's formats for one kind of message: the given global names (those that exist), then
-- every string global that starts with `prefix`, sorted. Cached. Each item:
-- { name = "ERR_JOINED_GROUP_S", format = "...", compiled = {...} }.
local formatCache = {}
function ns.GlobalFormats(key, names, prefix)
    local cached = formatCache[key]
    if cached then return cached end
    local list, seen = {}, {}
    local function add(name)
        if seen[name] then return end
        local value = _G[name]
        if type(value) == "string" and value ~= "" then
            local compiled = ns.CompileFormat(value)
            if compiled then
                seen[name] = true
                list[#list + 1] = { name = name, format = value, compiled = compiled }
            end
        end
    end
    for _, name in ipairs(names or {}) do add(name) end
    if prefix then
        local found = {}
        for name, value in pairs(_G) do
            if type(name) == "string" and string.sub(name, 1, #prefix) == prefix and type(value) == "string" then
                found[#found + 1] = name
            end
        end
        table.sort(found)
        for _, name in ipairs(found) do add(name) end
    end
    formatCache[key] = list
    return list
end

-- The first of `formats` (from GlobalFormats) that `text` matches: item, values; or nil.
function ns.MatchFormats(formats, text)
    for _, item in ipairs(formats) do
        local values = ns.MatchFormat(item.compiled, text)
        if values then return item, values end
    end
    return nil
end

-- A player name out of a system message: unwraps a |Hplayer:...|h[Name]|h link and colour codes,
-- and drops "-Realm". Returns nil when nothing readable is left.
function ns.PlayerNameFromText(text)
    if type(text) ~= "string" then return nil end
    local linked = string.match(text, "|Hplayer:[^|]*|h%[?([^|%]]+)%]?|h")
    if linked then text = linked end
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = ns.StripRealm(text)
    if text == "" then return nil end
    return text
end

-- Who wrote a chat line (M4b) ----------------------------------------------------------
-- Ported from AJProbe's relationship filter. Returns "me", "group", "friend", "bnfriend" or
-- nil. Every lookup is optional and runs under pcall: a client without C_FriendList or
-- C_BattleNet (or one that returns secrets inside an instance) just yields nil.
function ns.GetRelationship(guid)
    if ns.IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    if UnitGUID then
        local own = UnitGUID("player")
        if not ns.IsSecret(own) and own == guid then return "me" end
    end
    if GetNumGroupMembers and UnitGUID and GetNumGroupMembers() > 0 then
        local prefix, count = "party", 4
        if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
        for index = 1, count do
            local unitGUID = UnitGUID(prefix .. index)
            if unitGUID and not ns.IsSecret(unitGUID) and unitGUID == guid then return "group" end
        end
    end
    if C_FriendList and C_FriendList.IsFriend then
        local ok, isFriend = pcall(C_FriendList.IsFriend, guid)
        if ok and isFriend == true then return "friend" end
    end
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
        local ok, info = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
        if ok and type(info) == "table" then return "bnfriend" end
    end
    return nil
end

-- The BattleTag behind a Battle.net whisper (the author of those is a protected string).
function ns.GetBattleTag(bnSenderID)
    if ns.IsSecret(bnSenderID) or type(bnSenderID) ~= "number" then return nil end
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnSenderID)
        if ok and type(info) == "table" and not ns.IsSecret(info.battleTag) and type(info.battleTag) == "string" then
            return info.battleTag
        end
    end
    return nil
end

-- Events -------------------------------------------------------------------------
-- Registers an event only if this client knows it. MINIMAP_ZONE_CHANGED, for
-- example, does not exist on Classic Era (observed).
-- ns.eventStatus[event] = true (registered), or the reason it was not.
-- A frame with its own list of events (the conversation log) passes its own `status` table, so
-- that an event both frames use, such as CHAT_MSG_WHISPER, keeps one status per frame.
ns.eventStatus = {}
function ns.RegisterEventSafe(frame, event, status)
    status = status or ns.eventStatus
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        status[event] = "el cliente no conoce este evento"
        return false
    end
    local ok = pcall(frame.RegisterEvent, frame, event)
    status[event] = ok or "RegisterEvent falló"
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
