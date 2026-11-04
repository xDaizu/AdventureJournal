-- UI.lua: the book window (index on the left page, the jornada's prose on the right).
local addonName, ns = ...

local journalFrame
ns.selectedDay = 1

-- The diary the book shows: the real one, unless `/diario debug demo` swapped in a generated
-- one (ns.demoDB). The demo exists only in memory and is never written to SavedVariables;
-- entries still go into the real diary. It lets the index be tried with 250 jornadas.
local function ViewDB()
    return ns.demoDB or ns.EnsureDatabase()
end

local function CreateText(parent, template, value, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(value or "")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function CreateBookButton(parent, label, width, height, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    return button
end

local function SetPageBackdrop(frame, backgroundColor)
    -- Conserva el borde de la página
    frame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })

    -- Crea el fondo una sola vez
    if not frame.pageBackground then
        frame.pageBackground = frame:CreateTexture(nil, "BACKGROUND")
        frame.pageBackground:SetTexture("Interface\\QuestFrame\\QuestBG")

        -- Recorta la parte transparente de la derecha de QuestBG.
        -- El pergamino visible pasa a ocupar todo el ancho de la página.
        frame.pageBackground:SetTexCoord(0, 0.60, 0, 0.6)

        -- Hace que la textura se adapte a todo el marco
        frame.pageBackground:SetAllPoints(frame)
    end

    frame.pageBackground:SetVertexColor(
        backgroundColor[1],
        backgroundColor[2],
        backgroundColor[3],
        1
    )
end

-- Jornada index (left page) ----------------------------------------------------------
-- Preferred: a ScrollBox, which only creates frames for the rows on screen, so 250+
-- jornadas cost the same as 10. Fallback: the original ScrollFrame with one Button per
-- jornada. The ScrollBox is used only if the functions AND the templates exist and the
-- whole build succeeds (M5: "the function exists" does not mean "the template exists").
local ROW_HEIGHT = 27

local function DayLabel(dayNumber)
    local day = ViewDB().days[dayNumber]
    local count = day and type(day.events) == "table" and #day.events or 0
    return string.format("Jornada %d  ·  %d", dayNumber, count)
end

-- Raises if anything is missing; the half-built frames are hidden first.
local function BuildScrollBoxIndex(f, leftPage)
    if not (CreateScrollBoxListLinearView and CreateDataProvider and ScrollUtil
            and ScrollUtil.InitScrollBoxListWithScrollBar) then
        error("faltan las funciones de ScrollBox", 0)
    end
    local holder = CreateFrame("Frame", nil, leftPage)
    holder:SetPoint("TOPLEFT", 10, -45)
    holder:SetPoint("BOTTOMRIGHT", -10, 12)
    local box
    local ok, err = pcall(function()
        box = CreateFrame("Frame", nil, holder, "WowScrollBoxList")
        box:SetPoint("TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", -18, 0)
        local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
        local view = CreateScrollBoxListLinearView()
        view:SetElementExtent(ROW_HEIGHT)
        view:SetElementInitializer("UIPanelButtonTemplate", function(button, dayNumber)
            button:SetText(DayLabel(dayNumber))
            button:SetScript("OnClick", function() ns.SelectDay(dayNumber) end)
        end)
        ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    end)
    if not ok then
        holder:Hide()
        error(err, 0)
    end
    f.indexBox, f.indexMode = box, "scrollbox"
end

-- The original index: a ScrollFrame whose child holds one Button per jornada.
local function BuildButtonIndex(f, leftPage)
    local indexScroll = CreateFrame("ScrollFrame", nil, leftPage, "UIPanelScrollFrameTemplate")
    indexScroll:SetPoint("TOPLEFT", 10, -45)
    indexScroll:SetPoint("BOTTOMRIGHT", -27, 12)
    local indexChild = CreateFrame("Frame", nil, indexScroll)
    indexChild:SetSize(165, 1)
    indexScroll:SetScrollChild(indexChild)
    f.indexChild, f.indexScroll, f.indexMode = indexChild, indexScroll, "buttons"
end

local function BuildIndex(f, leftPage)
    if ns.debug.buttons then
        f.indexFallbackReason = "forzado con /diario debug buttons"
    else
        local ok, err = pcall(BuildScrollBoxIndex, f, leftPage)
        if ok then return end
        f.indexFallbackReason = string.sub(ns.StripPosition(err), 1, 120)
        ns.Debug("índice: sin ScrollBox (%s), se usan botones", f.indexFallbackReason)
    end
    BuildButtonIndex(f, leftPage)
end

local function RefreshScrollBoxIndex(f, total)
    local list = {}
    for dayNumber = total, 1, -1 do list[#list + 1] = dayNumber end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    f.indexBox:SetDataProvider(CreateDataProvider(list), retain)
end

local function RefreshButtonIndex(f, total)
    local buttons = f.dayButtons or {}
    for _, button in pairs(buttons) do button:Hide() end
    local y = -2
    for dayNumber = total, 1, -1 do
        local button = buttons[dayNumber]
        if not button then
            button = CreateFrame("Button", nil, f.indexChild, "UIPanelButtonTemplate")
            button:SetSize(160, 24)
            buttons[dayNumber] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, y)
        button:SetText(DayLabel(dayNumber))
        local chosenDay = dayNumber
        button:SetScript("OnClick", function() ns.SelectDay(chosenDay) end)
        button:Show()
        y = y - 27
    end
    f.dayButtons = buttons
    f.indexChild:SetHeight(math.max(1, -y + 4))
end

-- A broken index must not take the right page with it: report the first error to
-- the game's error handler and carry on.
local indexErrorReported
local function RefreshIndex(f, total)
    local ok, err
    if f.indexMode == "scrollbox" then
        ok, err = pcall(RefreshScrollBoxIndex, f, total)
    else
        ok, err = pcall(RefreshButtonIndex, f, total)
    end
    if ok then return end
    ns.Debug("índice: %s", tostring(err))
    if indexErrorReported then return end
    indexErrorReported = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler("AdventureJournal: error al actualizar el índice: " .. tostring(err)) end
end

-- "ScrollBox" or "botones (reason)", for /diario diag.
function ns.GetIndexMode()
    if not journalFrame then return "el libro aún no se ha abierto" end
    if journalFrame.indexMode == "scrollbox" then return "ScrollBox" end
    return "botones (" .. tostring(journalFrame.indexFallbackReason) .. ")"
end

local function BuildUI()
    if journalFrame then return end

    local f = CreateFrame("Frame", "AdventureJournalBookFrame", UIParent, "BackdropTemplate")
    journalFrame = f
    f:SetSize(780, 545)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.78, 0.68, 0.48, 1)

    local title = CreateText(f, "GameFontNormalLarge", "Diario de aventuras", 600)
    title:SetPoint("TOP", 0, -20)
    title:SetTextColor(0.95, 0.82, 0.52)
    local character = CreateText(f, "GameFontHighlightSmall", ns.UnitNameSafe("player") or "Aventurero", 300)
    character:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)

    -- Libro abierto: índice en la hoja izquierda y relato en la hoja derecha.
    local leftPage = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftPage:SetPoint("TOPLEFT", 22, -72)
    leftPage:SetSize(205, 420)
    SetPageBackdrop(leftPage, { 0.94, 0.87, 0.68 })

    local rightPage = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPage:SetPoint("TOPLEFT", leftPage, "TOPRIGHT", 5, 0)
    rightPage:SetSize(525, 420)
    SetPageBackdrop(rightPage, { 0.94, 0.87, 0.68 })

    local indexTitle = CreateText(leftPage, "GameFontNormalLarge", "Índice", 175)
    indexTitle:SetPoint("TOPLEFT", 13, -14)
    indexTitle:SetTextColor(0.25, 0.16, 0.08)

    BuildIndex(f, leftPage)

    local dayTitle = CreateText(rightPage, "GameFontNormalLarge", "Jornada", 470)
    dayTitle:SetPoint("TOPLEFT", 20, -17)
    dayTitle:SetTextColor(0.25, 0.16, 0.08)
    f.dayTitle = dayTitle
    local dayMeta = CreateText(rightPage, "GameFontHighlightSmall", "", 470)
    dayMeta:SetPoint("TOPLEFT", dayTitle, "BOTTOMLEFT", 0, -6)
    dayMeta:SetTextColor(0.35, 0.27, 0.17)
    f.dayMeta = dayMeta

    local contentScroll = CreateFrame("ScrollFrame", nil, rightPage, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT", 19, -65)
    contentScroll:SetPoint("BOTTOMRIGHT", -30, 15)
    local contentChild = CreateFrame("Frame", nil, contentScroll)
    contentChild:SetSize(455, 1)
    contentScroll:SetScrollChild(contentChild)
    local body = CreateText(contentChild, "GameFontNormal", "", 445)
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetTextColor(0.20, 0.15, 0.10)
    if body.SetSpacing then body:SetSpacing(5) end
    f.contentChild, f.contentScroll, f.body = contentChild, contentScroll, body

    local previous = CreateBookButton(f, "< Anterior", 120, 24, function() ns.SelectDay(ns.selectedDay - 1) end)
    previous:SetPoint("BOTTOMLEFT", 35, 20)
    f.prevButton = previous
    local nextButton = CreateBookButton(f, "Siguiente >", 120, 24, function() ns.SelectDay(ns.selectedDay + 1) end)
    nextButton:SetPoint("BOTTOMRIGHT", -35, 20)
    f.nextButton = nextButton
    local pageNumber = CreateText(f, "GameFontHighlightSmall", "", 180)
    pageNumber:SetPoint("BOTTOM", 0, 25)
    pageNumber:SetJustifyH("CENTER")
    pageNumber:SetTextColor(0.95, 0.82, 0.52)
    f.pageNumber = pageNumber

    f:SetScript("OnShow", function() ns.RefreshUI() end)

    -- Escape closes the book (bug #7).
    local alreadyRegistered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "AdventureJournalBookFrame" then alreadyRegistered = true end
    end
    if not alreadyRegistered then tinsert(UISpecialFrames, "AdventureJournalBookFrame") end

    -- CreateFrame returns a shown frame. Hide it so that ToggleUI's first call shows
    -- it instead of hiding it again (bug #8). OnShow refreshes the content.
    f:Hide()
end

function ns.SelectDay(dayNumber)
    local total = ViewDB().currentDay or 0
    if total < 1 then return end
    ns.selectedDay = math.max(1, math.min(total, tonumber(dayNumber) or total))
    if journalFrame then ns.RefreshUI() end
end

function ns.RefreshUI()
    if not journalFrame then return end
    local DB = ViewDB()
    local total = DB.currentDay or 0
    RefreshIndex(journalFrame, total)

    if total < 1 then
        journalFrame.dayTitle:SetText("Aún no hay jornadas")
        journalFrame.dayMeta:SetText("")
        journalFrame.body:SetText("Tu historia comienza cuando salgas a explorar.")
        journalFrame.contentChild:SetHeight(80)
        journalFrame.pageNumber:SetText("Sin páginas")
        journalFrame.prevButton:Disable()
        journalFrame.nextButton:Disable()
        return
    end

    ns.selectedDay = math.max(1, math.min(total, ns.selectedDay))
    local day = DB.days[ns.selectedDay] or { events = {} }
    local events = day.events or {}
    journalFrame.dayTitle:SetText(string.format("Jornada %d", ns.selectedDay))
    journalFrame.dayMeta:SetText(string.format("%s     ·     %d acontecimientos%s", day.dateLabel or "Fecha desconocida", #events,
        ns.demoDB and "     ·     DATOS DE PRUEBA (no se guardan)" or ""))

    local paragraphs = {}
    if #events == 0 then
        paragraphs[1] = "No dejé constancia de grandes gestas durante esta jornada. Quizá fue un día de descanso, preparativos o caminos tranquilos. Incluso las pausas forman parte de una aventura."
    else
        -- The header is the time, plus the mood when the player turned that option on.
        -- Entries saved before the mood existed simply have no profile: header unchanged.
        local showProfile = ns.GetSetting("showProfile") == true
        for _, entry in ipairs(events) do
            local header = entry.time or ""
            if showProfile and type(entry.characterProfile) == "string" and entry.characterProfile ~= "" then
                header = header == "" and entry.characterProfile or (header .. "  ·  " .. entry.characterProfile)
            end
            table.insert(paragraphs, string.format("|cFF8A5A24%s|r\n%s", header, entry.prose or ns.ComposeEntry(entry)))
        end
    end
    journalFrame.body:SetText(table.concat(paragraphs, "\n\n"))
    journalFrame.contentChild:SetHeight(math.max(100, journalFrame.body:GetStringHeight() + 20))
    journalFrame.contentScroll:SetVerticalScroll(0)
    journalFrame.pageNumber:SetText(string.format("%d / %d", ns.selectedDay, total))
    if ns.selectedDay <= 1 then journalFrame.prevButton:Disable() else journalFrame.prevButton:Enable() end
    if ns.selectedDay >= total then journalFrame.nextButton:Disable() else journalFrame.nextButton:Enable() end
end

function ns.RefreshIfVisible()
    if journalFrame and journalFrame:IsShown() then ns.RefreshUI() end
end

function ns.ToggleUI()
    if not journalFrame then BuildUI() end
    if journalFrame:IsShown() then journalFrame:Hide() else journalFrame:Show() end
end

-- Opens the book at a given jornada (used by /diario hoy and /diario anterior).
function ns.OpenAtDay(dayNumber)
    if not journalFrame then BuildUI() end
    ns.SelectDay(dayNumber)
    journalFrame:Show()
end
