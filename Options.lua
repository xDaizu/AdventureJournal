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

-- The loot button's text per quality (string.upper cannot capitalise "é": Lua works on bytes).
local LOOT_BUTTON_TEXT = { [2] = "Poco común", [3] = "Raro", [4] = "Épico", [5] = "Legendario" }

-- The text of a profile button: its name, or the second-click prompt while it is armed (the
-- confirmation used when this client has no StaticPopup; see AskProfile).
local function ProfileButtonText(name)
    if controls.armedProfile == name then return "¿Seguro? Otra vez" end
    return ns.PROFILE_NAMES[name]
end

function ns.RefreshOptionsPanel()
    if not panel then return end
    ns.EnsureDatabase()
    controls.profileStatus:SetText("Perfil actual: " .. ns.ProfileStatus())
    for name, button in pairs(controls.profileButtons) do button:SetText(ProfileButtonText(name)) end
    controls.chat:SetText(ns.CHAT_MODE_NAMES[ns.GetSetting("chat")] or "?")
    for _, info in ipairs(ns.VisibleTypes()) do
        -- A type that became visible after the panel was built has no checkbox (until the next /reload).
        local control = controls.types[info.key]
        if control then
            control:SetChecked(ns.IsTypeEnabled(info.key))
            control.label:SetText(ns.TypeLabel(info))   -- LOOT follows the loot threshold (T5)
        end
    end
    controls.loot:SetText(LOOT_BUTTON_TEXT[ns.GetLootQuality()] or "?")
    controls.deathKiller:SetChecked(ns.GetSetting("deathKiller") == true)
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
local function AddCheck(parent, y, text, onToggle, x)
    local check = CreateCheckButton(parent)
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", x or 20, y)
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

-- Profiles (T5) ----------------------------------------------------------------------------
local POPUP = "ADVENTUREJOURNAL_APPLY_PROFILE"

local function ApplyFromPanel(name)
    controls.armedProfile = nil
    ns.ApplyProfileAndReport(name)   -- says in the chat what changed; refreshes the panel
    ns.RefreshOptionsPanel()
end

-- A profile rewrites several settings at once, so the panel asks first. StaticPopup exists on both
-- clients (the dialog's OnAccept receives the `data` given to StaticPopup_Show); where it is missing
-- or fails to show, the button asks for a second click instead.
local function AskProfile(name)
    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs[POPUP] then
            StaticPopupDialogs[POPUP] = {
                text = "%s",
                button1 = ACCEPT or "Aceptar",
                button2 = CANCEL or "Cancelar",
                OnAccept = function(_, data) ApplyFromPanel(data) end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
        end
        local question = "¿Aplicar el perfil " .. ns.PROFILE_NAMES[name] .. "?\n\n"
            .. ns.PROFILE_NAMES[name] .. ": " .. ns.PROFILE_DESCRIPTIONS[name] .. ".\n\n"
            .. "Cambia de una vez el chat, el botín, el enemigo en las muertes y lo que se anota; "
            .. "luego puedes cambiar cada cosa. Tus jornadas no se tocan."
        local ok, dialog = pcall(StaticPopup_Show, POPUP, question, nil, name)
        if ok and dialog then return end
    end
    if controls.armedProfile == name then
        ApplyFromPanel(name)
    else
        controls.armedProfile = name
        ns.RefreshOptionsPanel()
    end
end

-- The panel ---------------------------------------------------------------------------------
-- T5 made it taller than the settings window on some screens, so it sits in a ScrollFrame when
-- the template exists (both clients have it; the book's index falls back to it too), and directly
-- on the canvas otherwise.
local CONTENT_WIDTH = 580

local function CreateContent(frame)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    if not ok or not scroll then return frame end
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 10)
    scroll:SetScrollChild(content)
    controls.scroll = scroll
    return content
end

local function BuildPanel()
    local frame = CreateFrame("Frame")
    local content = CreateContent(frame)
    AddText(content, "GameFontNormalLarge", 16, -16, PANEL_TITLE)
    AddText(content, "GameFontHighlightSmall", 16, -42,
        "Los cambios se aplican al momento y se guardan para este personaje.", 540)

    -- T5: the profile (settings.profile and everything it writes). Each button asks before applying.
    AddText(content, "GameFontNormal", 16, -74, "Perfil")
    controls.profileStatus = AddText(content, "GameFontHighlight", 20, -102, "Perfil actual:", 250)
    controls.profileButtons = {}
    for index, name in ipairs(ns.PROFILE_ORDER) do
        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(140, 24)
        button:SetPoint("TOPLEFT", 270 + (index - 1) * 150, -98)
        button:SetScript("OnClick", function() AskProfile(name) end)
        controls.profileButtons[name] = button
    end
    AddText(content, "GameFontHighlightSmall", 20, -128,
        "Clásico: lo que anotaba la versión 1.1.0-Forever de Chema. Ampliado: todo lo que anota esta versión. "
        .. "Un perfil cambia de una vez los ajustes de abajo (te pide confirmación); después puedes cambiar cada uno.", 520)

    -- Chat echo (settings.chat): a button that cycles todo > importante > nada.
    AddText(content, "GameFontNormal", 16, -170, "Mensajes en el chat")
    AddText(content, "GameFontHighlight", 20, -198, "Mostrar en el chat:")
    local chatButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    chatButton:SetSize(140, 24)
    chatButton:SetPoint("TOPLEFT", 190, -194)
    chatButton:SetScript("OnClick", function()
        ns.SetSetting("chat", CHAT_CYCLE[ns.GetSetting("chat")] or "important")
    end)
    controls.chat = chatButton
    AddText(content, "GameFontHighlightSmall", 20, -224,
        "todo: cada anotación  ·  importante: jefes, muertes y botín épico  ·  nada: ninguna. Pulsa el botón para cambiar.", 520)

    -- Which entry types are logged (settings.types).
    AddText(content, "GameFontNormal", 16, -262, "Qué se anota en el diario")
    -- Two columns, so that the types (M6, T4) do not make the panel too long.
    local visibleTypes = ns.VisibleTypes()
    local rows = math.ceil(#visibleTypes / 2)
    local y = -286
    for index, info in ipairs(visibleTypes) do
        local key = info.key
        local column = index > rows and 1 or 0
        local row = (index - 1) % rows
        controls.types[key] = AddCheck(content, y - row * 24, ns.TypeLabel(info),
            function(enabled) ns.SetTypeEnabled(key, enabled) end, 20 + column * 270)
    end
    y = y - rows * 24 - 8

    -- T5: the loot threshold (settings.lootQuality), cycling poco común > raro > épico > legendario.
    AddText(content, "GameFontHighlight", 20, y - 4, "Botín: anotar desde la calidad")
    local lootButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    lootButton:SetSize(140, 24)
    lootButton:SetPoint("TOPLEFT", 290, y)
    lootButton:SetScript("OnClick", function()
        local order, current = ns.LOOT_QUALITY_ORDER, ns.GetLootQuality()
        local nextQuality = order[1]
        for index, quality in ipairs(order) do
            if quality == current then nextQuality = order[index + 1] or order[1] end
        end
        ns.SetSetting("lootQuality", nextQuality)
    end)
    controls.loot = lootButton
    y = y - 30

    -- T4a setting, given a control in T5 (settings.deathKiller).
    controls.deathKiller = AddCheck(content, y, "En una muerte, nombrar al último enemigo con el que luché",
        function(enabled) ns.SetSetting("deathKiller", enabled) end)
    y = y - 24
    AddText(content, "GameFontHighlightSmall", 50, y - 2,
        "Sin registro de combate no se sabe quién te mató: es el último enemigo al que te enfrentaste.", 490)
    y = y - 22

    -- The book (settings.showProfile).
    AddText(content, "GameFontNormal", 16, y - 14, "El libro")
    y = y - 38
    controls.profile = AddCheck(content, y, "Mostrar el ánimo del personaje en cada anotación",
        function(enabled) ns.SetSetting("showProfile", enabled) end)
    y = y - 40

    -- M4b: RP conversations (settings.conversations). Off by default, because it stores other
    -- players' words. /diario conversaciones on|off does the same.
    AddText(content, "GameFontNormal", 16, y, "Conversaciones de rol")
    y = y - 24
    controls.conversations = AddCheck(content, y, "Guardar las conversaciones de rol",
        function(enabled) ns.SetSetting("conversations", enabled) end)
    AddText(content, "GameFontHighlightSmall", 20, y - 28,
        "Guarda susurros, chat de grupo y banda, y lo que dicen tú, tu grupo y tus amigos. Son palabras de otros jugadores: "
        .. "por eso está desactivado por defecto. Desmarcada, no se guarda ni se muestra nada (lo guardado se conserva). "
        .. "En instancias el chat es secreto y no se guarda.", 520)
    y = y - 80
    if content ~= frame then content:SetHeight(-y) end
    controls.contentHeight = -y

    frame:SetScript("OnShow", function() ns.RefreshOptionsPanel() end)
    -- A profile button armed for a second click (no StaticPopup) is disarmed when the panel closes.
    frame:SetScript("OnHide", function()
        if controls.armedProfile then
            controls.armedProfile = nil
            ns.RefreshOptionsPanel()
        end
    end)
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
