-- UI.lua: the book window.
--
-- T3: the look is Chema's (his AdventureJournal.lua at fa20e9f), for everyone: a dark frame with a
-- gold title, an index of jornadas on the left, and a page with Textures\tiled.tga on the right
-- (day title, date line, entries in QuestFont with red place headers). Sizes, positions, colours and
-- fonts below are his. This line's engine stays underneath: the ScrollBox index with its button
-- fallback, the conversations view, the demo diary, Escape to close.
-- Controls his design does not have (decision D4, flagged for his review):
--   previous / next jornada and the page number   in the title bar, left of the close button
--   conversations toggle and its paging           on the day title row of the page (only while on)
--   time (and the mood, with showProfile)          a muted prefix on each entry
local addonName, ns = ...

local journalFrame
ns.selectedDay = 1

-- M4b: the book shows either the events of a jornada or its conversations. The conversations
-- view exists only while the option is on (ConversationsEnabled); with it off the book is the
-- events view whatever was left selected, and no conversation text is ever put on screen.
ns.bookView = "events"        -- "events" | "conversations"
ns.conversationPage = 1

local function CurrentView()
    if ns.bookView == "conversations" and ns.ConversationsEnabled() then return "conversations" end
    return "events"
end

-- The diary the book shows: the real one, unless `/diario debug demo` swapped in a generated
-- one (ns.demoDB). The demo exists only in memory and is never written to SavedVariables;
-- entries still go into the real diary. It lets the index be tried with 250 jornadas.
local function ViewDB()
    return ns.demoDB or ns.EnsureDatabase()
end

-- Chema's colours.
local FONT_COLOR = {
    title = { 0.95, 0.82, 0.52 },
    heading = { 0.25, 0.14, 0.02 },
    metadata = { 0.40, 0.30, 0.20 },
    body = { 0.18, 0.12, 0.06 },
    secondary = { 0.75, 0.75, 0.75 },
}
local HEADER_COLOR = "|cFFFF3333"      -- red place headers
local TIME_COLOR = "|cFF8A5A24"        -- muted prefix (time, mood)

local function SetColor(fontString, color)
    if fontString and color then fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

local function CreateText(parent, template, value, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(value or "")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if width then fs:SetWidth(width) end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function CreateBookButton(parent, label, width, height, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    return button
end

-- A backdrop can fail on a client without BackdropTemplate; the book is still usable without it.
local function SafeBackdrop(frame, settings, r, g, b, a)
    if not frame or not frame.SetBackdrop then return end
    pcall(function()
        frame:SetBackdrop(settings)
        if r then frame:SetBackdropColor(r, g, b, a or 1) end
    end)
end

local function CreatePanel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    SafeBackdrop(frame, {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    }, 0.08, 0.05, 0.04, 0.95)
    return frame
end

-- Jornada index (left panel) -----------------------------------------------------------
-- Preferred: a ScrollBox, which only creates frames for the rows on screen, so 250+
-- jornadas cost the same as 10. Fallback: the original ScrollFrame with one Button per
-- jornada. The ScrollBox is used only if the functions AND the templates exist and the
-- whole build succeeds (M5: "the function exists" does not mean "the template exists").
-- A row is Chema's: a 195 x 24 button "Jornada N" and, under it, "lugar · fecha"; 48 px per row.
local BUTTON_WIDTH, BUTTON_HEIGHT, ROW_STEP = 195, 24, 48

-- Chema's index line: the main place of the jornada (his diaries store it), else the place of the
-- first entry, else "Aventura"; then the date.
local function DaySubtitle(dayNumber)
    local day = ViewDB().days[dayNumber]
    day = type(day) == "table" and day or {}
    local events = type(day.events) == "table" and day.events or {}
    local place = day.mainZone
    if type(place) ~= "string" or place == "" then
        place = type(events[1]) == "table" and events[1].place or nil
    end
    if type(place) ~= "string" or place == "" then place = "Aventura" end
    return string.format("%s  ·  %s", place, tostring(day.dateLabel or "Fecha desconocida"))
end

-- Fills one index row (a ScrollBox element or a fallback button). The subtitle FontString is
-- added the first time the row is used and hangs under the button, in the space the view leaves.
local function FillIndexRow(button, dayNumber)
    button:SetText(string.format("Jornada %d", dayNumber))
    if not button.subtitle then
        local subtitle = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 4, -3)
        subtitle:SetWidth(BUTTON_WIDTH - 5)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetJustifyV("TOP")
        SetColor(subtitle, FONT_COLOR.secondary)
        button.subtitle = subtitle
    end
    button.subtitle:SetText(DaySubtitle(dayNumber))
    button:SetScript("OnClick", function() ns.SelectDay(dayNumber) end)
end

-- Raises if anything is missing; the half-built frames are hidden first.
local function BuildScrollBoxIndex(f, leftPanel)
    if not (CreateScrollBoxListLinearView and CreateDataProvider and ScrollUtil
            and ScrollUtil.InitScrollBoxListWithScrollBar) then
        error("faltan las funciones de ScrollBox", 0)
    end
    local holder = CreateFrame("Frame", nil, leftPanel)
    holder:SetPoint("TOPLEFT", 8, -8)
    holder:SetPoint("BOTTOMRIGHT", -8, 8)
    local box
    local ok, err = pcall(function()
        box = CreateFrame("Frame", nil, holder, "WowScrollBoxList")
        box:SetPoint("TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", -18, 0)
        local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
        -- Rows are 24 px buttons with 24 px of spacing: 48 px per row, the subtitle in the gap.
        -- (UNVERIFIED on the clients: the spacing argument; see README, "Book".)
        local view = CreateScrollBoxListLinearView(0, 0, 0, 0, ROW_STEP - BUTTON_HEIGHT)
        if view.SetPadding then view:SetPadding(0, 0, 0, 0, ROW_STEP - BUTTON_HEIGHT) end
        view:SetElementExtent(BUTTON_HEIGHT)
        view:SetElementInitializer("UIPanelButtonTemplate", FillIndexRow)
        ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    end)
    if not ok then
        holder:Hide()
        error(err, 0)
    end
    f.indexBox, f.indexMode = box, "scrollbox"
end

-- The original index: a ScrollFrame whose child holds one Button per jornada.
local function BuildButtonIndex(f, leftPanel)
    local indexScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    indexScroll:SetPoint("TOPLEFT", 8, -8)
    indexScroll:SetPoint("BOTTOMRIGHT", -26, 8)
    local indexChild = CreateFrame("Frame", nil, indexScroll)
    indexChild:SetSize(BUTTON_WIDTH, 1)
    indexScroll:SetScrollChild(indexChild)
    f.indexChild, f.indexScroll, f.indexMode = indexChild, indexScroll, "buttons"
end

local function BuildIndex(f, leftPanel)
    if ns.debug.buttons then
        f.indexFallbackReason = "forzado con /diario debug buttons"
    else
        local ok, err = pcall(BuildScrollBoxIndex, f, leftPanel)
        if ok then return end
        f.indexFallbackReason = string.sub(ns.StripPosition(err), 1, 120)
        ns.Debug("índice: sin ScrollBox (%s), se usan botones", f.indexFallbackReason)
    end
    BuildButtonIndex(f, leftPanel)
end

local function RefreshScrollBoxIndex(f, total)
    local list = {}
    for dayNumber = total, 1, -1 do list[#list + 1] = dayNumber end
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    f.indexBox:SetDataProvider(CreateDataProvider(list), retain)
end

local function RefreshButtonIndex(f, total)
    local buttons = f.dayButtons or {}
    for _, button in pairs(buttons) do
        button:Hide()
        if button.subtitle then button.subtitle:Hide() end
    end
    local y = 0
    for dayNumber = total, 1, -1 do
        local button = buttons[dayNumber]
        if not button then
            button = CreateFrame("Button", nil, f.indexChild, "UIPanelButtonTemplate")
            button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
            buttons[dayNumber] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, y)
        FillIndexRow(button, dayNumber)
        button:Show()
        button.subtitle:Show()
        y = y - ROW_STEP
    end
    f.dayButtons = buttons
    f.indexChild:SetHeight(math.max(1, -y + 5))
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

    -- Main frame: dark background, dialog border.
    local f = CreateFrame("Frame", "AdventureJournalBookFrame", UIParent, "BackdropTemplate")
    journalFrame = f
    f:SetSize(820, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    if f.SetFrameLevel then f:SetFrameLevel(20) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    local background = f:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetAllPoints(f)
    background:SetVertexColor(0.12, 0.08, 0.06, 0.98)
    f.mainBackground = background
    SafeBackdrop(f, {
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })

    -- Title and close button.
    local title = CreateText(f, "GameFontNormalLarge",
        "Diario de Aventura - " .. ns.SafeString(ns.UnitNameSafe("player"), "Aventurero"), 400)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -15)
    SetColor(title, FONT_COLOR.title)
    f.title = title

    local close = CreateFrame("Button", nil, f)
    close:SetSize(32, 32)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    close:SetScript("OnClick", function() f:Hide() end)

    -- Previous / next jornada and the page number (not in Chema's design; D4): the title bar.
    local nextButton = CreateBookButton(f, "Siguiente >", 84, 24, function() ns.SelectDay(ns.selectedDay + 1) end)
    nextButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -46, -11)
    f.nextButton = nextButton
    local pageNumber = CreateText(f, "GameFontHighlightSmall", "", 56)
    pageNumber:SetPoint("RIGHT", nextButton, "LEFT", -6, 0)
    pageNumber:SetJustifyH("CENTER")
    SetColor(pageNumber, FONT_COLOR.title)
    f.pageNumber = pageNumber
    local previous = CreateBookButton(f, "< Anterior", 84, 24, function() ns.SelectDay(ns.selectedDay - 1) end)
    previous:SetPoint("RIGHT", pageNumber, "LEFT", -6, 0)
    f.prevButton = previous

    -- Left panel: the index of jornadas.
    local leftPanel = CreatePanel(f, 240, 495)
    leftPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -45)
    f.leftPanel = leftPanel
    BuildIndex(f, leftPanel)

    -- Right page: tiled.tga with a tooltip border.
    local rightPage = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPage:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPage:SetSize(538, 495)
    SafeBackdrop(rightPage, {
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local paper = rightPage:CreateTexture(nil, "BACKGROUND")
    paper:SetTexture("Interface\\AddOns\\AdventureJournal\\Textures\\tiled.tga")
    paper:SetAllPoints(rightPage)
    rightPage.pageBackground = paper
    f.rightPage = rightPage

    local dayTitle = CreateText(rightPage, "QuestTitleFont", "Jornada", 250)
    dayTitle:SetPoint("TOPLEFT", rightPage, "TOPLEFT", 20, -15)
    SetColor(dayTitle, FONT_COLOR.heading)
    f.dayTitle = dayTitle

    local dayMeta = CreateText(rightPage, "GameFontHighlightSmall", "", 490)
    dayMeta:SetPoint("TOPLEFT", dayTitle, "BOTTOMLEFT", 0, -4)
    SetColor(dayMeta, FONT_COLOR.metadata)
    f.dayMeta = dayMeta

    -- M4b: events <-> conversations, and the pages of a long conversation list, on the title row.
    -- Shown only while the conversations option is on (RefreshUI).
    local viewButton = CreateBookButton(rightPage, "Conversaciones", 100, 22, function()
        ns.SetBookView(CurrentView() == "conversations" and "events" or "conversations")
    end)
    viewButton:SetPoint("TOPRIGHT", rightPage, "TOPRIGHT", -14, -14)
    viewButton:Hide()
    f.viewButton = viewButton
    local conversationNext = CreateBookButton(rightPage, "Después >", 62, 22, function() ns.SetConversationPage(ns.conversationPage + 1) end)
    conversationNext:SetPoint("RIGHT", viewButton, "LEFT", -4, 0)
    conversationNext:Hide()
    f.conversationNext = conversationNext
    local conversationPageText = CreateText(rightPage, "GameFontHighlightSmall", "", 36)
    conversationPageText:SetPoint("RIGHT", conversationNext, "LEFT", -2, 0)
    conversationPageText:SetJustifyH("CENTER")
    SetColor(conversationPageText, FONT_COLOR.metadata)
    conversationPageText:Hide()
    f.conversationPageText = conversationPageText
    local conversationPrev = CreateBookButton(rightPage, "< Antes", 56, 22, function() ns.SetConversationPage(ns.conversationPage - 1) end)
    conversationPrev:SetPoint("RIGHT", conversationPageText, "LEFT", -2, 0)
    conversationPrev:Hide()
    f.conversationPrev = conversationPrev

    -- The entries.
    local contentScroll = CreateFrame("ScrollFrame", nil, rightPage, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT", rightPage, "TOPLEFT", 20, -55)
    contentScroll:SetPoint("BOTTOMRIGHT", rightPage, "BOTTOMRIGHT", -28, 15)
    local contentChild = CreateFrame("Frame", nil, contentScroll)
    contentChild:SetSize(470, 1)
    contentScroll:SetScrollChild(contentChild)
    local body = CreateText(contentChild, "QuestFont", "", 450)
    body:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 10, -10)
    body:SetPoint("TOPRIGHT", contentChild, "TOPRIGHT", -10, -10)
    SetColor(body, FONT_COLOR.body)
    if body.SetShadowColor then body:SetShadowColor(0, 0, 0, 0.3) end
    if body.SetShadowOffset then body:SetShadowOffset(1, -1) end
    if body.SetSpacing then body:SetSpacing(4) end
    f.contentChild, f.contentScroll, f.body = contentChild, contentScroll, body

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
    local chosen = math.max(1, math.min(total, tonumber(dayNumber) or total))
    if chosen ~= ns.selectedDay then ns.conversationPage = 1 end
    ns.selectedDay = chosen
    if journalFrame then ns.RefreshUI() end
end

function ns.SetBookView(view)
    ns.bookView = view == "conversations" and "conversations" or "events"
    ns.conversationPage = 1
    if journalFrame then ns.RefreshUI() end
end

function ns.SetConversationPage(page)
    ns.conversationPage = math.max(1, tonumber(page) or 1)
    if journalFrame then ns.RefreshUI() end
end

-- One entry as Chema writes it: a red header for entries that have one (places), "En <lugar>" on a
-- first entry without one, no header otherwise. The time (and the mood with showProfile) is a muted
-- prefix of the text: his design has none, this line keeps them (decision D4).
local function EntryParagraph(day, index, entry, showProfile)
    local prose, header = entry.prose, entry.header
    if type(prose) ~= "string" or prose == "" then
        local composed, composedHeader = ns.ComposeEntry(entry)
        prose, header = composed, header or composedHeader
    end
    if type(header) ~= "string" or header == "" then header = nil end
    if index == 1 and not header then
        local place = type(entry.place) == "string" and entry.place ~= "" and entry.place
            or type(day.mainZone) == "string" and day.mainZone ~= "" and day.mainZone or "Azeroth"
        header = "En " .. place
    end
    local meta = type(entry.time) == "string" and entry.time or ""
    if showProfile and type(entry.characterProfile) == "string" and entry.characterProfile ~= "" then
        meta = meta == "" and entry.characterProfile or (meta .. "  ·  " .. entry.characterProfile)
    end
    if meta ~= "" then prose = TIME_COLOR .. meta .. "|r  " .. prose end
    if header then return string.format("%s%s|r\n%s", HEADER_COLOR, header, prose) end
    return prose
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
        journalFrame.contentChild:SetHeight(150)
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

    local view = CurrentView()
    local paragraphs = {}
    local pages = 1
    if view == "conversations" then
        local page
        paragraphs, pages, page = ns.ConversationParagraphs(day, ns.conversationPage)
        ns.conversationPage = page
        journalFrame.dayMeta:SetText(string.format("%s     ·     %d conversaciones%s", day.dateLabel or "Fecha desconocida",
            ns.CountConversations(day), ns.demoDB and "     ·     DATOS DE PRUEBA (no se guardan)" or ""))
        journalFrame.conversationPageText:SetText(string.format("%d / %d", page, pages))
        if #paragraphs == 0 then
            paragraphs[1] = "No hay conversaciones guardadas en esta jornada."
        end
    elseif #events == 0 then
        paragraphs[1] = "No dejé constancia de grandes gestas durante esta jornada. Quizá fue un día de descanso, preparativos o caminos tranquilos. Incluso las pausas forman parte de una aventura."
    else
        local showProfile = ns.GetSetting("showProfile") == true
        for index, entry in ipairs(events) do
            table.insert(paragraphs, EntryParagraph(day, index, entry, showProfile))
        end
    end
    -- The conversations view and its buttons exist only while the option is on.
    if ns.ConversationsEnabled() then
        journalFrame.viewButton:Show()
        journalFrame.viewButton:SetText(view == "conversations" and "Acontecimientos" or "Conversaciones")
    else
        journalFrame.viewButton:Hide()
    end
    if view == "conversations" and pages > 1 then
        journalFrame.conversationPrev:Show()
        journalFrame.conversationNext:Show()
        journalFrame.conversationPageText:Show()
        if ns.conversationPage <= 1 then journalFrame.conversationPrev:Disable() else journalFrame.conversationPrev:Enable() end
        if ns.conversationPage >= pages then journalFrame.conversationNext:Disable() else journalFrame.conversationNext:Enable() end
    else
        journalFrame.conversationPrev:Hide()
        journalFrame.conversationNext:Hide()
        journalFrame.conversationPageText:Hide()
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
