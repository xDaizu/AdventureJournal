-- Options.lua: the options panel (Esc > Opciones > AddOns > Diario de Aventuras).
--
-- Built with the Settings API's CANVAS layout: our own frame with plain widgets,
-- registered through Settings.RegisterCanvasLayoutCategory + RegisterAddOnCategory.
-- That needs far less of the API than the vertical layout (RegisterAddOnSetting,
-- CreateCheckbox, CreateDropdown), whose signatures are not known on either client.
-- Observed on Classic Era 1.15.9: all of those functions exist, but their call
-- signatures cannot be read from the game. Forever: verify in M3.
--
-- Every option is also reachable by slash command (Commands.lua), so a client where
-- this file cannot build the panel loses nothing: ns.optionsError says why, and
-- /diario diag shows it. Settings are read and written through ns.GetSetting /
-- ns.SetSetting / ns.SetTypeEnabled (Database.lua).
local addonName, ns = ...

local PANEL_TITLE = "Diario de Aventuras"

local panel                     -- the canvas frame, nil when it could not be built
local controls = { types = {} } -- the widgets, so RefreshOptionsPanel can sync them

-- Called by every setting write: keep the panel and the open book in step.
function ns.OnSettingsChanged()
    -- M4b: the chat events of the conversation log are registered only while it is on.
    if ns.UpdateConversationEvents then ns.UpdateConversationEvents() end
    ns.RefreshOptionsPanel()
    ns.RefreshIfVisible()
end

function ns.RefreshOptionsPanel()
    if not panel then return end
    ns.EnsureDatabase()
    controls.chat:SetText(ns.CHAT_MODE_NAMES[ns.GetSetting("chat")] or "?")
    for _, info in ipairs(ns.TYPE_INFO) do
        controls.types[info.key]:SetChecked(ns.IsTypeEnabled(info.key))
    end
    controls.profile:SetChecked(ns.GetSetting("showProfile") == true)
    controls.conversations:SetChecked(ns.ConversationsEnabled())
end

-- Widgets ---------------------------------------------------------------------------
local CHECK_TEMPLATES = { "UICheckButtonTemplate", "InterfaceOptionsCheckButtonTemplate" }

local function CreateCheckButton(parent)
    local lastError
    for _, template in ipairs(CHECK_TEMPLATES) do
        local ok, result = pcall(CreateFrame, "CheckButton", nil, parent, template)
        if ok then return result end
        lastError = result
    end
    error("ninguna plantilla de casilla funciona: " .. tostring(lastError), 0)
end

local function AddText(parent, template, x, y, text, width)
    local fontString = parent:CreateFontString(nil, "OVERLAY", template)
    fontString:SetPoint("TOPLEFT", x, y)
    if width then fontString:SetWidth(width) end
    fontString:SetJustifyH("LEFT")
    fontString:SetText(text)
    return fontString
end

-- onToggle receives true/false. GetChecked() returns 1/nil on some clients, so only
-- its truthiness is used.
local function AddCheck(parent, y, text, onToggle)
    local check = CreateCheckButton(parent)
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 20, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 1)
    label:SetText(text)
    check.label = label
    if onToggle then
        check:SetScript("OnClick", function(self) onToggle(self:GetChecked() and true or false) end)
    end
    return check
end

local CHAT_CYCLE = { all = "important", important = "off", off = "all" }

local function BuildPanel()
    local frame = CreateFrame("Frame")
    AddText(frame, "GameFontNormalLarge", 16, -16, PANEL_TITLE)
    AddText(frame, "GameFontHighlightSmall", 16, -42,
        "Los cambios se aplican al momento y se guardan para este personaje.", 540)

    -- Chat echo (settings.chat): a button that cycles todo > importante > nada.
    AddText(frame, "GameFontNormal", 16, -74, "Mensajes en el chat")
    AddText(frame, "GameFontHighlight", 20, -102, "Mostrar en el chat:")
    local chatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chatButton:SetSize(140, 24)
    chatButton:SetPoint("TOPLEFT", 190, -98)
    chatButton:SetScript("OnClick", function()
        ns.SetSetting("chat", CHAT_CYCLE[ns.GetSetting("chat")] or "important")
    end)
    controls.chat = chatButton
    AddText(frame, "GameFontHighlightSmall", 20, -128,
        "todo: cada anotación  ·  importante: jefes, muertes y botín épico  ·  nada: ninguna. Pulsa el botón para cambiar.", 520)

    -- Which entry types are logged (settings.types).
    AddText(frame, "GameFontNormal", 16, -166, "Qué se anota en el diario")
    local y = -190
    for _, info in ipairs(ns.TYPE_INFO) do
        local key = info.key
        controls.types[key] = AddCheck(frame, y, info.label, function(enabled) ns.SetTypeEnabled(key, enabled) end)
        y = y - 24
    end

    -- The book (settings.showProfile).
    AddText(frame, "GameFontNormal", 16, y - 14, "El libro")
    y = y - 38
    controls.profile = AddCheck(frame, y, "Mostrar el ánimo del personaje en cada anotación",
        function(enabled) ns.SetSetting("showProfile", enabled) end)
    y = y - 40

    -- M4b: RP conversations (settings.conversations). Off by default, because it stores other
    -- players' words. /diario conversaciones on|off does the same.
    AddText(frame, "GameFontNormal", 16, y, "Conversaciones de rol")
    y = y - 24
    controls.conversations = AddCheck(frame, y, "Guardar las conversaciones de rol",
        function(enabled) ns.SetSetting("conversations", enabled) end)
    AddText(frame, "GameFontHighlightSmall", 20, y - 28,
        "Guarda susurros, chat de grupo y banda, y lo que dicen tú, tu grupo y tus amigos. Son palabras de otros jugadores: "
        .. "por eso está desactivado por defecto. Desmarcada, no se guarda ni se muestra nada (lo guardado se conserva). "
        .. "En instancias el chat es secreto y no se guarda.", 520)

    frame:SetScript("OnShow", function() ns.RefreshOptionsPanel() end)
    return frame
end

-- Registration ------------------------------------------------------------------------
-- Failure is reported once to the game's error handler and leaves the slash
-- commands as the only way to change options.
local function Register()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        ns.optionsError = "la API Settings no existe en este cliente"
        return
    end
    local ok, err = pcall(function()
        panel = BuildPanel()
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_TITLE)
        Settings.RegisterAddOnCategory(category)
        ns.optionsCategory = category
    end)
    if ok then
        ns.optionsPanel, ns.optionsControls = panel, controls
        return
    end
    if panel then panel:Hide() end
    panel, ns.optionsCategory = nil, nil
    ns.optionsError = ns.StripPosition(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler("AdventureJournal: no se pudo crear el panel de opciones: " .. tostring(err)) end
end
Register()

-- Opens the panel. Returns true, or false and a reason. Settings.OpenToCategory takes
-- a category ID on current clients; the category object is tried as well, in case this
-- client wants that (signature unverified: see the header).
function ns.OpenOptions()
    local category = ns.optionsCategory
    if not category then return false, ns.optionsError or "el panel de opciones no está disponible" end
    if not (Settings and Settings.OpenToCategory) then return false, "falta Settings.OpenToCategory" end
    ns.RefreshOptionsPanel()
    local attempts = {}
    local idOk, id = pcall(function() return category:GetID() end)
    if idOk and id ~= nil then attempts[#attempts + 1] = id end
    attempts[#attempts + 1] = category
    for _, argument in ipairs(attempts) do
        local ok = pcall(Settings.OpenToCategory, argument)
        -- A call that raised nothing may still have done nothing (wrong argument), so
        -- check that the settings window is up. A canvas frame without a parent says
        -- little about IsVisible, hence SettingsPanel rather than our own frame.
        local opened
        if SettingsPanel and SettingsPanel.IsShown then opened = SettingsPanel:IsShown() else opened = panel:IsVisible() end
        if ok and opened then return true end
    end
    return false, "no he podido abrir el panel"
end

-- For /diario diag.
function ns.GetOptionsStatus()
    if not ns.optionsCategory then return "panel NO disponible: " .. tostring(ns.optionsError) end
    local idOk, id = pcall(function() return ns.optionsCategory:GetID() end)
    return "panel registrado (categoría " .. tostring(idOk and id or "?") .. ")"
end
