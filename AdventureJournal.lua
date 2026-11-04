-- Diario de Aventuras - World of Warcraft Classic Era (1.15.9)
-- SavedVariablesPerCharacter: cada personaje conserva su propio diario.
local addonName, addon = ...
addon = addon or {}

local DB
local eventFrame = CreateFrame("Frame")
local journalFrame
local selectedDay = 1
local currentPlace = ""
local sessionStarted = false
local lastQuestID, lastQuestAt
local lastBossName, lastBossAt
local lastNPCName, lastNPCTime
local pendingLoot = {}
local SelectDay

BINDING_HEADER_ADVENTUREJOURNAL = "Diario de Aventuras"
BINDING_NAME_ADVENTUREJOURNAL_TOGGLE = "Abrir / cerrar el diario"

local MOODS = {
    { "Heroico", "con el ánimo firme y la sensación de que aún queda mucho por hacer" },
    { "Cínico", "con más ironía que paciencia y la esperanza puesta en la recompensa" },
    { "Salvaje", "con los nervios despiertos y ganas de resolverlo todo por la fuerza" },
    { "Erudito", "atento a los detalles y tratando de comprender lo ocurrido" },
    { "Cauteloso", "sin bajar la guardia y procurando no confiarme" },
    { "Melancólico", "pensando en el largo camino recorrido y en quienes quedaron atrás" },
}

local function SafeString(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback or "algo que no supe identificar"
end

local function GetPlace()
    local zone = SafeString(GetRealZoneText and GetRealZoneText(), "tierras desconocidas")
    local sub = SafeString(GetSubZoneText and GetSubZoneText(), "")
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end

local function EnsureDatabase()
    if type(AdventureJournalDB) ~= "table" then
        AdventureJournalDB = { version = 1, currentDay = 0, days = {} }
    end
    DB = AdventureJournalDB
    DB.version = 1
    DB.currentDay = tonumber(DB.currentDay) or 0
    if type(DB.days) ~= "table" then DB.days = {} end
end

local function ChooseMood(eventType)
    if eventType == "DEATH" then
        return "Derrotado", "con la amarga certeza de que esta vez el enemigo fue más rápido"
    elseif eventType == "BOSS" then
        return "Aliviado", "con el pulso todavía acelerado y la satisfacción de seguir en pie"
    elseif eventType == "LOOT" then
        return "Entusiasmado", "con la agradable impresión de que el viaje empieza a dar sus frutos"
    elseif eventType == "DISCOVERY" then
        return "Explorador", "con la curiosidad de quien acaba de encontrar un lugar nuevo"
    end
    local mood = MOODS[math.random(1, #MOODS)]
    return mood[1], mood[2]
end

local function ComposeEntry(entry)
    local place = SafeString(entry.place, "algún lugar del mundo")
    local subject = SafeString(entry.text, "un acontecimiento inesperado")
    local tone = SafeString(entry.contextualTone, "con el ánimo sereno")
    local variant = (entry.seed or 1) % 3

    if entry.type == "QUEST" then
        if variant == 1 then
            return string.format("En %s terminé la tarea «%s». %s. No parece que las obligaciones vayan a darme tregua.", place, subject, tone)
        elseif variant == 2 then
            return string.format("La jornada me llevó a resolver «%s» en %s. %s. Al menos hoy he cumplido con mi parte.", subject, place, tone)
        end
        return string.format("Queda atrás una tarea más: «%s», completada en %s. %s.", subject, place, tone)
    elseif entry.type == "BOSS" then
        return string.format("En %s me enfrenté a %s. La lucha fue intensa y, cuando el polvo se asentó, seguía en pie: %s.", place, subject, tone)
    elseif entry.type == "DEATH" then
        return string.format("La aventura se detuvo en %s. Caí antes de poder continuar; %s. Tendré que regresar con más cuidado.", place, tone)
    elseif entry.type == "LOOT" then
        return string.format("La fortuna se dejó notar en %s: apareció %s. %s.", place, subject, tone)
    elseif entry.type == "DISCOVERY" then
        return string.format("Mis pasos me condujeron hasta %s. Me detuve un momento para observar el lugar; %s.", subject, tone)
    elseif entry.type == "NPC" then
        return string.format("En %s crucé unas palabras con %s. No sé si aquel encuentro tendrá importancia, pero merece quedar anotado.", place, subject)
    elseif entry.type == "CHAT" then
        return string.format("Recibí noticias de %s mientras me encontraba en %s. Incluso en los caminos más solitarios llegan voces de otros aventureros.", subject, place)
    end
    return subject
end

local function RefreshIfVisible()
    if journalFrame and journalFrame:IsShown() and addon.RefreshUI then addon:RefreshUI() end
end

local function AddEntry(eventType, description, extra)
    if not DB then return end
    local day = DB.days[DB.currentDay]
    if not day then return end

    local profile, tone = ChooseMood(eventType)
    local entry = {
        type = eventType,
        text = SafeString(description, "Acontecimiento sin descripción"),
        place = GetPlace(),
        zone = SafeString(GetRealZoneText and GetRealZoneText(), "Desconocido"),
        subZone = SafeString(GetSubZoneText and GetSubZoneText(), ""),
        time = date("%H:%M:%S"),
        timestamp = time(),
        characterProfile = profile,
        contextualTone = tone,
        seed = #(day.events or {}) + 1,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do entry[key] = value end
    end
    entry.prose = ComposeEntry(entry)
    day.events = day.events or {}
    table.insert(day.events, entry)
    RefreshIfVisible()
    print(string.format("|cFF00FF00[Diario]|r %s", entry.text))
end

local function StartSession()
    if sessionStarted then return end
    sessionStarted = true
    EnsureDatabase()

    -- Se conserva deliberadamente el criterio solicitado: cada inicio de sesión crea una jornada.
    DB.currentDay = DB.currentDay + 1
    local n = DB.currentDay
    DB.days[n] = {
        startedAt = date("%Y-%m-%d %H:%M:%S"),
        dateLabel = date("%d/%m/%Y"),
        events = {},
    }
    selectedDay = n
    currentPlace = GetPlace()
    print(string.format("|cFFFFD700[Diario]|r Comienza la jornada %d. Tu historia continúa.", n))
end

local function GetQuestTitle(questID)
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

local function GetItemQuality(itemLink)
    if not itemLink then return nil end
    if GetItemInfo then
        local _, _, quality = GetItemInfo(itemLink)
        if quality then return quality end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, quality = pcall(C_Item.GetItemInfo, itemLink)
        if ok and quality then return quality end
    end
    return nil
end

local function TryLogLoot(itemLink, itemID)
    local quality = GetItemQuality(itemLink or itemID)
    if quality and quality >= 3 then
        local displayLink = itemLink
        if not displayLink and GetItemInfo then
            local _, link = GetItemInfo(itemID)
            displayLink = link
        end
        AddEntry("LOOT", displayLink or ("un objeto (ID " .. tostring(itemID) .. ")"), {
            itemQuality = quality,
            itemLink = displayLink,
            itemID = itemID,
        })
        return true
    end
    return false
end

local function RegisterEventSafe(name)
    -- Algunas compilaciones Classic no exponen todos los eventos de encuentros.
    pcall(eventFrame.RegisterEvent, eventFrame, name)
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
    "QUEST_TURNED_IN", "BOSS_KILL", "ENCOUNTER_END", "PLAYER_DEAD",
    "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED",
    "GOSSIP_SHOW", "CHAT_MSG_WHISPER",
}
for _, eventName in ipairs(EVENTS) do RegisterEventSafe(eventName) end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then EnsureDatabase() end

    elseif event == "PLAYER_LOGIN" then
        StartSession()

    elseif event == "PLAYER_LOGOUT" then
        if DB and DB.days and DB.days[DB.currentDay] then
            DB.days[DB.currentDay].endedAt = date("%Y-%m-%d %H:%M:%S")
        end

    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if not questID or questID ~= lastQuestID or not lastQuestAt or time() - lastQuestAt > 3 then
            lastQuestID, lastQuestAt = questID, time()
            AddEntry("QUEST", GetQuestTitle(questID), { questID = questID })
        end

    elseif event == "BOSS_KILL" then
        local _, bossName = ...
        bossName = SafeString(bossName, "una criatura temible")
        if bossName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
            lastBossName, lastBossAt = bossName, time()
            AddEntry("BOSS", bossName)
        end

    elseif event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        if success == 1 and encounterName then
            if encounterName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
                lastBossName, lastBossAt = encounterName, time()
                AddEntry("BOSS", encounterName)
            end
        end

    elseif event == "PLAYER_DEAD" then
        AddEntry("DEATH", "He caído en combate")

    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        if type(message) == "string" then
            -- Any colour prefix: |cffRRGGBB (Classic Era) or |cnIQ<n>: (possibly Forever).
            local itemLink = string.match(message, "|c[^|]*|Hitem:.-|h%[.-%]|h|r")
            if itemLink then
                local itemID = tonumber(string.match(itemLink, "|Hitem:(%d+)"))
                if not TryLogLoot(itemLink, itemID) and itemID then
                    pendingLoot[itemID] = itemLink
                end
            end
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        local link = itemID and pendingLoot[itemID]
        if link then
            pendingLoot[itemID] = nil
            if success then TryLogLoot(link, itemID) end
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "MINIMAP_ZONE_CHANGED" then
        local newPlace = GetPlace()
        if newPlace ~= currentPlace then
            currentPlace = newPlace
            AddEntry("DISCOVERY", newPlace)
        end

    elseif event == "GOSSIP_SHOW" then
        local npcName
        if UnitName then
            local ok, name = pcall(UnitName, "npc")
            if ok then npcName = name end
        end
        npcName = SafeString(npcName, "un habitante de la zona")
        if npcName ~= lastNPCName or not lastNPCTime or time() - lastNPCTime > 20 then
            lastNPCName, lastNPCTime = npcName, time()
            AddEntry("NPC", npcName)
        end

    elseif event == "CHAT_MSG_WHISPER" then
        local _, sender = ...
        if sender and sender ~= "" then
            sender = string.match(sender, "^([^%-]+)") or sender
            AddEntry("CHAT", sender)
        end
    end
end)

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
    local character = CreateText(f, "GameFontHighlightSmall", UnitName("player") or "Aventurero", 300)
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

    local indexScroll = CreateFrame("ScrollFrame", nil, leftPage, "UIPanelScrollFrameTemplate")
    indexScroll:SetPoint("TOPLEFT", 10, -45)
    indexScroll:SetPoint("BOTTOMRIGHT", -27, 12)
    local indexChild = CreateFrame("Frame", nil, indexScroll)
    indexChild:SetSize(165, 1)
    indexScroll:SetScrollChild(indexChild)
    f.indexChild, f.indexScroll = indexChild, indexScroll

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

    local previous = CreateBookButton(f, "◀ Anterior", 120, 24, function() SelectDay(selectedDay - 1) end)
    previous:SetPoint("BOTTOMLEFT", 35, 20)
    f.prevButton = previous
    local nextButton = CreateBookButton(f, "Siguiente ▶", 120, 24, function() SelectDay(selectedDay + 1) end)
    nextButton:SetPoint("BOTTOMRIGHT", -35, 20)
    f.nextButton = nextButton
    local pageNumber = CreateText(f, "GameFontHighlightSmall", "", 180)
    pageNumber:SetPoint("BOTTOM", 0, 25)
    pageNumber:SetJustifyH("CENTER")
    pageNumber:SetTextColor(0.95, 0.82, 0.52)
    f.pageNumber = pageNumber

    f:SetScript("OnShow", function() addon:RefreshUI() end)
end

SelectDay = function(dayNumber)
    if not DB then EnsureDatabase() end
    local total = DB.currentDay or 0
    if total < 1 then return end
    selectedDay = math.max(1, math.min(total, tonumber(dayNumber) or total))
    if journalFrame then addon:RefreshUI() end
end

function addon:RefreshUI()
    if not journalFrame then return end
    EnsureDatabase()
    local total = DB.currentDay or 0
    local buttons = journalFrame.dayButtons or {}
    for _, button in pairs(buttons) do button:Hide() end
    local y = -2
    for dayNumber = total, 1, -1 do
        local day = DB.days[dayNumber] or { events = {} }
        local count = day.events and #day.events or 0
        local button = buttons[dayNumber]
        if not button then
            button = CreateFrame("Button", nil, journalFrame.indexChild, "UIPanelButtonTemplate")
            button:SetSize(160, 24)
            buttons[dayNumber] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, y)
        button:SetText(string.format("Jornada %d  ·  %d", dayNumber, count))
        local chosenDay = dayNumber
        button:SetScript("OnClick", function() SelectDay(chosenDay) end)
        button:Show()
        y = y - 27
    end
    journalFrame.dayButtons = buttons
    journalFrame.indexChild:SetHeight(math.max(1, -y + 4))

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

    selectedDay = math.max(1, math.min(total, selectedDay))
    local day = DB.days[selectedDay] or { events = {} }
    local events = day.events or {}
    journalFrame.dayTitle:SetText(string.format("Jornada %d", selectedDay))
    journalFrame.dayMeta:SetText(string.format("%s     ·     %d acontecimientos", day.dateLabel or "Fecha desconocida", #events))

    local paragraphs = {}
    if #events == 0 then
        paragraphs[1] = "No dejé constancia de grandes gestas durante esta jornada. Quizá fue un día de descanso, preparativos o caminos tranquilos. Incluso las pausas forman parte de una aventura."
    else
        for _, entry in ipairs(events) do
            table.insert(paragraphs, string.format("|cFF8A5A24%s|r\n%s", entry.time or "", entry.prose or ComposeEntry(entry)))
        end
    end
    journalFrame.body:SetText(table.concat(paragraphs, "\n\n"))
    journalFrame.contentChild:SetHeight(math.max(100, journalFrame.body:GetStringHeight() + 20))
    journalFrame.contentScroll:SetVerticalScroll(0)
    journalFrame.pageNumber:SetText(string.format("%d / %d", selectedDay, total))
    if selectedDay <= 1 then journalFrame.prevButton:Disable() else journalFrame.prevButton:Enable() end
    if selectedDay >= total then journalFrame.nextButton:Disable() else journalFrame.nextButton:Enable() end
end

function AdventureJournal_ToggleUI()
    if not journalFrame then BuildUI() end
    if journalFrame:IsShown() then journalFrame:Hide() else journalFrame:Show() end
end

SLASH_ADVENTUREJOURNAL1 = "/diario"
SLASH_ADVENTUREJOURNAL2 = "/journal"
SlashCmdList["ADVENTUREJOURNAL"] = function(message)
    local command = string.lower(message or "")
    if command == "" or command == "abrir" then
        AdventureJournal_ToggleUI()
    elseif command == "hoy" or command == "actual" then
        if not journalFrame then BuildUI() end
        SelectDay(DB and DB.currentDay or 1)
        journalFrame:Show()
    elseif command == "anterior" then
        if not journalFrame then BuildUI() end
        SelectDay((DB and DB.currentDay or 1) - 1)
        journalFrame:Show()
    else
        print("|cFFFFD700[Diario]|r Usa /diario, /diario hoy o /diario anterior.")
    end
end
