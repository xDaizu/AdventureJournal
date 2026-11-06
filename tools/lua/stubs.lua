-- Minimal, deterministic WoW API for running addon code under fengari.
-- Globals set by run.js before this file: FLAVOR ("classic" | "forever").
-- Everything the scenario controls lives in the STUB table.

-- Stub options (comma separated, set by run.js per scenario run in STUB_OPTIONS):
--   nosettings          the Settings API does not exist
--   opentoobject        Settings.OpenToCategory silently ignores a numeric ID (needs the category object)
--   noscrollbox         CreateScrollBoxListLinearView, CreateDataProvider and ScrollUtil do not exist
--   noscrolltemplates   those functions exist, but the WowScrollBoxList / MinimalScrollBar templates do not
--   nosocial            C_FriendList and C_BattleNet do not exist (M4b: relationship lookups degrade)
--   notimetable         time{year=...} ignores its table and returns the clock (M4b: date parsing falls back)
--   nomessages          none of the game's message strings of M6 exist (group, reputation, skill, spell):
--                       the handlers must find no pattern and do nothing, without errors
local FLAGS = {}
for flag in string.gmatch(STUB_OPTIONS or "", "[^,]+") do FLAGS[flag] = true end

local S = {
    flags = FLAGS,
    clock = 1793815000,       -- fixed epoch; the scenario advances it explicitly
    zone = nil,               -- GetRealZoneText() is nil at PLAYER_LOGIN (observed in M0)
    subZone = "",
    npcName = "Gornek",
    playerName = "Volgajin",
    questLog = {},            -- { { title = "...", questID = n } } (Classic quest log)
    questTitles = {},         -- [questID] = title (C_QuestLog.GetTitleForQuestID, Forever)
    items = {},               -- [itemID] = { name, link, quality, cached = bool }
    unknownEvents = { MINIMAP_ZONE_CHANGED = true },  -- observed on Classic Era
    prints = {},
    frames = {},
}
STUB = S
local IS_CLASSIC = FLAVOR == "classic"

-- Output and time ------------------------------------------------------------
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(S.prints, table.concat(parts, " "))
end
-- time() is the fixed clock; with a table (like the game's time{year=...}) it converts local
-- time to an epoch. run.js pins TZ=UTC.
function time(fields)
    if fields and not FLAGS.notimetable then return os.time(fields) end
    return S.clock
end
function date(fmt, t) return os.date(fmt or "%c", t or S.clock) end   -- run.js pins TZ=UTC

-- Deterministic math.random: same call sequence, same results.
local randomCalls = 0
math.random = function(a, b)
    randomCalls = randomCalls + 1
    if a == nil then return (randomCalls % 100) / 100 end
    if b == nil then a, b = 1, a end
    return a + (randomCalls * 7) % (b - a + 1)
end

tinsert, tremove = table.insert, table.remove

-- fengari is Lua 5.3; make the library look like WoW's Lua 5.1 where it matters.
unpack = unpack or table.unpack
loadstring = loadstring or load
utf8 = nil

-- Widgets ----------------------------------------------------------------------
local Widget = {}
Widget.__index = Widget

local function NewWidget(kind, name, parent, template)
    local w = setmetatable({ kind = kind, name = name, parent = parent, template = template,
                             shown = true, scripts = {}, events = {} }, Widget)
    table.insert(S.frames, w)
    if name then _G[name] = w end
    return w
end

local noop = function() end
for _, method in ipairs({
    "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata", "SetMovable",
    "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetClampedToScreen",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetWidth", "SetJustifyH",
    "SetJustifyV", "SetTextColor", "SetTexture", "SetTexCoord", "SetVertexColor", "SetScrollChild",
    "SetSpacing", "SetVerticalScroll", "SetFontObject", "SetAlpha",
}) do Widget[method] = noop end

function Widget:SetHeight(h) self.height = h end
function Widget:GetHeight() return self.height or 0 end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:GetStringHeight()
    local _, lines = string.gsub(self.text or "", "\n", "")
    return (lines + 1) * 14
end
function Widget:SetChecked(value) self.checked = value and true or false end
-- Classic clients historically returned 1 / nil; the stub does the same there, so code
-- that compares the result with `true` is caught. Forever returns real booleans.
function Widget:GetChecked()
    if IS_CLASSIC then return self.checked and 1 or nil end
    return self.checked == true
end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled ~= false end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:CreateFontString(name) return NewWidget("FontString", name, self) end
function Widget:CreateTexture(name) return NewWidget("Texture", name, self) end
function Widget:RegisterEvent(event)
    if S.unknownEvents[event] then
        error('Frame:RegisterEvent(): Attempt to register unknown event "' .. event .. '"', 2)
    end
    self.events[event] = true
end
function Widget:RegisterUnitEvent(event) return self:RegisterEvent(event) end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:IsEventRegistered(event) return self.events[event] == true end

-- Templates the stub knows. The real game errors on an unknown one ("Couldn't find
-- inherited node"); so does the stub, so a wrong template name fails the harness.
local KNOWN_TEMPLATES = {
    BackdropTemplate = true, UIPanelButtonTemplate = true, UIPanelCloseButton = true,
    UIPanelScrollFrameTemplate = true, UICheckButtonTemplate = true,
    InterfaceOptionsCheckButtonTemplate = true,
}
if not FLAGS.noscrolltemplates and not FLAGS.noscrollbox then
    KNOWN_TEMPLATES.WowScrollBoxList = true
    KNOWN_TEMPLATES.MinimalScrollBar = true
end

local AttachScrollBox   -- defined at the end of this file

function CreateFrame(kind, name, parent, template)
    if template then
        for part in string.gmatch(template, "[^,%s]+") do
            if not KNOWN_TEMPLATES[part] then
                error('CreateFrame: Couldn\'t find inherited node "' .. part .. '"', 2)
            end
        end
    end
    local widget = NewWidget(kind, name, parent, template)
    if template == "WowScrollBoxList" then AttachScrollBox(widget) end
    return widget
end
UIParent = NewWidget("Frame", "UIParent")
UISpecialFrames = {}
SlashCmdList = {}

-- Fires an event at every frame that registered it, in creation order.
function S.Fire(event, ...)
    for _, w in ipairs(S.frames) do
        if w.events[event] and w.scripts.OnEvent then w.scripts.OnEvent(w, event, ...) end
    end
end

-- Game API -------------------------------------------------------------------
if IS_CLASSIC then
    function GetBuildInfo() return "1.15.9", "70576", "Oct 22 2026", 11509 end
    WOW_PROJECT_ID = 2
else
    function GetBuildInfo() return "1.60.1", "70755", "Nov 1 2026", 16001 end
    WOW_PROJECT_ID = 1
    WOW_PROJECT_MAINLINE = 1
end
WOW_PROJECT_CLASSIC = 2

-- Secret values. A stub secret is a table whose metatable errors on everything
-- the real game forbids (arithmetic, #, indexing, calling, concatenation,
-- ordering comparisons, tostring/format("%s")); the string library rejects it
-- because it is not a string. Limits (see tools/README.md): `==` / `~=` against
-- a plain value does NOT error here (Lua only calls __eq for two tables, and
-- the game errors for same-type operands), and a secret still works as a table
-- key. type() and tonumber() are replaced below to mimic the game.
local realType, realToNumber = type, tonumber
local secretKinds = setmetatable({}, { __mode = "k" })   -- [secret] = underlying type
local secretMeta = {}
for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm",
        "__idiv", "__lt", "__le", "__len", "__index", "__newindex", "__call",
        "__concat", "__eq", "__tostring" }) do
    secretMeta[event] = function() error("attempt to use a secret value (" .. event .. ")", 2) end
end
function S.MakeSecret(kind)
    local secret = setmetatable({}, secretMeta)
    secretKinds[secret] = kind or "string"
    return secret
end
S.SECRET = S.MakeSecret("string")
S.SECRET_NUMBER = S.MakeSecret("number")
function issecretvalue(v) return realType(v) == "table" and secretKinds[v] ~= nil end
-- The game's type() returns the real underlying type of a secret.
function type(v)
    local kind = realType(v) == "table" and secretKinds[v]
    return kind or realType(v)
end
-- tonumber() on a secret string errors in the game.
function tonumber(v, ...)
    if issecretvalue(v) then error("attempt to use a secret value (tonumber)", 2) end
    return realToNumber(v, ...)
end

function GetLocale() return "esES" end
-- Loot strings as observed on Classic Era esES in M0 (REFERENCE_SAMPLES.md).
LOOT_ITEM_SELF = "Recibes botín: %s."
LOOT_ITEM_SELF_MULTIPLE = "Recibes el botín: %sx%d."
LOOT_ITEM_PUSHED_SELF = "Recibes: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "Has recibido: %sx%d"
LOOT_ITEM = "%s recibe el botín: %s."
LOOT_ITEM_MULTIPLE = "%s recibe el botín: %sx%d."
-- Message strings of M6 (esES). Taken from the real AJProbe data where observed (the sentence the
-- game printed), NOT from a client: ERR_JOINED_GROUP_S, ERR_LEFT_GROUP_S, ERR_LEFT_GROUP_YOU,
-- ERR_GROUP_DISBANDED, ERR_LEARN_SPELL_S, ERR_LEARN_ABILITY_S ("facultad", seen in the Forever file), ERR_SKILL_UP_SI, ERR_SKILL_GAINED_S and the reputation
-- increase (Classic Era and Forever print different sentences, as AJProbe recorded). The raid,
-- passive and "standing changed" strings were never seen: their wording here is invented, only
-- their shape (which arguments, in which order) is used to test the pattern builder.
if not FLAGS.nomessages then
    ERR_JOINED_GROUP_S = "%s se une al grupo."
    ERR_LEFT_GROUP_S = "%s deja el grupo."
    ERR_LEFT_GROUP_YOU = "Dejas el grupo."
    ERR_GROUP_DISBANDED = "Tu grupo se ha disuelto."
    ERR_RAID_MEMBER_ADDED_S = "%s se une a la banda."
    ERR_RAID_MEMBER_REMOVED_S = "%s deja la banda."
    ERR_LEARN_SPELL_S = "Has aprendido un nuevo hechizo: %s."
    ERR_LEARN_ABILITY_S = "Has aprendido una nueva facultad: %s."
    ERR_LEARN_PASSIVE_S = "Has aprendido una nueva habilidad pasiva: %s."
    ERR_SKILL_UP_SI = "Tu habilidad en %s ha subido a %d."
    ERR_SKILL_GAINED_S = "Has ganado la siguiente habilidad: %s"
    if IS_CLASSIC then
        FACTION_STANDING_INCREASED = "Tu reputación con %s ha aumentado. (+%d)"
        FACTION_STANDING_CHANGED = "Ahora eres %s con %s."
    else
        FACTION_STANDING_INCREASED = "Tu reputación con %s ha aumentado en %d."
        FACTION_STANDING_CHANGED = "Con %2$s ahora eres %1$s."   -- positional: the standing is argument 1
    end
end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function GetRealZoneText() return S.zone end
function GetSubZoneText() return S.subZone end
S.realmName = "Zandalar Tribe"
function GetRealmName() return S.realmName end
-- Social APIs (M4b conversations). S.guid is the player's GUID; S.group is a list of the other
-- members' GUIDs (party1..partyN, or raid1..raidN when S.raid); S.friends[guid] = true;
-- S.bnGameAccounts[guid] = {} and S.bnAccounts[id] = { battleTag = "..." }.
S.guid = "Player-4421-0000AAAA"
S.group, S.raid, S.friends, S.bnGameAccounts, S.bnAccounts = {}, false, {}, {}, {}
function UnitGUID(unit)
    if unit == "player" then return S.guid end
    local index = tonumber(string.match(unit or "", "^party(%d+)$") or string.match(unit or "", "^raid(%d+)$"))
    return index and S.group[index] or nil
end
function GetNumGroupMembers() return #S.group > 0 and (#S.group + 1) or 0 end
function IsInRaid() return S.raid end
if not FLAGS.nosocial then
    C_FriendList = { IsFriend = function(guid) return S.friends[guid] == true end }
    C_BattleNet = {
        GetGameAccountInfoByGUID = function(guid) return S.bnGameAccounts[guid] end,
        GetAccountInfoByID = function(id) return S.bnAccounts[id] end,
    }
end
function UnitName(unit)
    if unit == "player" then return S.playerName end
    if unit == "npc" then return S.npcName end
    return nil
end
function InCombatLockdown() return false end
S.inInstance = false
function IsInInstance() return S.inInstance, S.inInstance and "party" or "none" end
S.errors = {}   -- messages that reached the global error handler
function geterrorhandler() return function(message) table.insert(S.errors, tostring(message)) end end
C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "Version" then return "1.2.0-dev" end
    if field == "AddonCompartmentFunc" and TOC_COMPARTMENT_FUNC and TOC_COMPARTMENT_FUNC ~= "" then
        return TOC_COMPARTMENT_FUNC
    end
    return nil
end }

C_EventUtils = { IsEventValid = function(event) return not S.unknownEvents[event] end }
C_Timer = { After = function(_, fn) fn() end }

local function ItemFrom(item)
    local id = type(item) == "number" and item or tonumber(string.match(tostring(item), "item:(%d+)"))
    local data = id and S.items[id]
    if not data or not data.cached then return nil end
    return data.name, data.link, data.quality
end
C_Item = { GetItemInfo = ItemFrom, RequestLoadItemDataByID = function() end }

if IS_CLASSIC then
    GetItemInfo = ItemFrom
    C_QuestLog = {}   -- GetTitleForQuestID is missing on Classic Era (observed)
    function GetNumQuestLogEntries() return #S.questLog end
    function GetQuestLogTitle(index)
        local q = S.questLog[index]
        if not q then return nil end
        return q.title, 1, nil, false, false, false, 0, q.questID
    end
else
    C_QuestLog = { GetTitleForQuestID = function(id) return S.questTitles[id] end }
end

-- Settings API (options panel) ---------------------------------------------------
-- Records what the addon registers. Only the canvas-layout path is implemented;
-- the other helpers exist (as on the real clients) but fail loudly if used, so a
-- later change that starts relying on them has to extend the stub on purpose.
S.settings = { categories = {}, registered = {}, opened = {} }
if not FLAGS.nosettings then
    local function NewCategory(kind, frame, name)
        local category = { kind = kind, frame = frame, name = name, id = 100 + #S.settings.categories }
        function category:GetID() return self.id end
        table.insert(S.settings.categories, category)
        return category
    end
    local function Unstubbed(name)
        return function() error("stub: Settings." .. name .. " is not stubbed; the addon must not use it", 2) end
    end
    SettingsPanel = NewWidget("Frame", "SettingsPanel")
    SettingsPanel.shown = false
    Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) return NewCategory("canvas", frame, name) end,
        RegisterVerticalLayoutCategory = function(name) return NewCategory("vertical", nil, name) end,
        RegisterAddOnCategory = function(category)
            category.registered = true
            table.insert(S.settings.registered, category.name)
        end,
        OpenToCategory = function(arg)
            table.insert(S.settings.opened, type(arg) == "table" and "category object" or ("ID " .. tostring(arg)))
            if FLAGS.opentoobject and type(arg) ~= "table" then return end
            for _, category in ipairs(S.settings.categories) do
                if (category == arg or category.id == arg) and category.registered and category.frame then
                    SettingsPanel:Show()
                    category.frame:Show()
                    return
                end
            end
            error("stub: Settings.OpenToCategory: unknown category", 2)
        end,
        RegisterAddOnSetting = Unstubbed("RegisterAddOnSetting"),
        RegisterProxySetting = Unstubbed("RegisterProxySetting"),
        CreateCheckbox = Unstubbed("CreateCheckbox"),
        CreateDropdown = Unstubbed("CreateDropdown"),
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
    }
end

-- ScrollBox (the jornada index) --------------------------------------------------
-- Models the part of the real ScrollBox that matters here: frames are created only
-- for the visible rows (plus one) and recycled when the data changes. Real row
-- height, layout and scroll physics are NOT modelled (see tools/README.md).
S.scrollBoxVisibleRows = 14

function AttachScrollBox(box)
    box.isScrollBox, box.offset, box.pool = true, 0, {}
    function box:LayoutStub()
        local view, provider = self.view, self.dataProvider
        assert(view and view.initializer, "ScrollBox used before ScrollUtil.InitScrollBoxListWithScrollBar")
        local size = provider and #provider.list or 0
        local maxOffset = math.max(0, size - S.scrollBoxVisibleRows)
        if self.offset > maxOffset then self.offset = maxOffset end
        local visible = math.min(size, S.scrollBoxVisibleRows + 1)
        for index = 1, visible do
            local frame = self.pool[index]
            if not frame then
                frame = CreateFrame("Button", nil, self, view.template)
                self.pool[index] = frame
            end
            frame.shown = true
            frame.elementData = provider.list[self.offset + index]
            view.initializer(frame, frame.elementData)
        end
        for index = visible + 1, #self.pool do self.pool[index].shown = false end
    end
    function box:SetDataProvider(provider, retainScrollPosition)
        self.dataProvider = provider
        if not retainScrollPosition then self.offset = 0 end
        self:LayoutStub()
    end
    function box:GetDataProvider() return self.dataProvider end
    function box:ForEachFrame(callback)
        for _, frame in ipairs(self.pool) do
            if frame.shown then callback(frame, frame.elementData) end
        end
    end
end

-- Test helper: pretend the user scrolled the index so that row `offset + 1` is on top.
function S.ScrollStubTo(box, offset)
    box.offset = offset
    box:LayoutStub()
end

if not FLAGS.noscrollbox then
    function CreateDataProvider(list)
        local provider = { list = {} }
        for index, value in ipairs(list or {}) do provider.list[index] = value end
        function provider:GetSize() return #self.list end
        return provider
    end
    function CreateScrollBoxListLinearView()
        local view = {}
        function view:SetElementExtent(extent) self.extent = extent end
        function view:SetElementInitializer(template, initializer)
            self.template, self.initializer = template, initializer
        end
        return view
    end
    ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, bar, view)
            assert(box and box.isScrollBox, "stub: not a WowScrollBoxList frame")
            assert(bar, "stub: no scroll bar")
            box.view = view
        end,
    }
    ScrollBoxConstants = { RetainScrollPosition = true, DiscardScrollPosition = false }
end
