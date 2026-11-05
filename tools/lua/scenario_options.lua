-- M5 options: every setting changes behaviour, through the options panel (clicking the
-- stub widgets exactly as the game would) and through the slash commands, and persists
-- across a /reload and a second login. Also covers the Forever AddonCompartment function.
-- Runs in three modes on top of each other's SavedVariables (login, reload, relogin), and
-- in stub variants: no Settings API (slash commands only), OpenToCategory needing the
-- category object. Where the panel does not exist the same steps go through slash commands.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = true, link = Link("|cffa335ee", 5555, "Espada épica") }
S.items[5556] = { name = "Daga épica", quality = 4, cached = false, link = Link("|cffa335ee", 5556, "Daga épica") }

local function Settings() return AdventureJournalDB.settings end

local function Counts()
    local day = AdventureJournalDB.days[AdventureJournalDB.currentDay]
    local counts, parts = {}, {}
    for _, entry in ipairs(day.events) do counts[entry.type] = (counts[entry.type] or 0) + 1 end
    for _, info in ipairs(ns.TYPE_INFO) do parts[#parts + 1] = info.key .. "=" .. (counts[info.key] or 0) end
    return table.concat(parts, " ")
end

local function SettingsLine()
    local off = {}
    for _, info in ipairs(ns.VisibleTypes()) do
        if Settings().types[info.key] == false then off[#off + 1] = info.key end
    end
    return string.format("chat=%s showProfile=%s conversations=%s typesOff=[%s]", tostring(Settings().chat),
        tostring(Settings().showProfile), tostring(Settings().conversations), table.concat(off, ","))
end

local function ControlsLine()
    local c = ns.optionsControls
    if not c then return "(no options panel)" end
    local parts = { "chat button = " .. tostring(c.chat.text) }
    for _, info in ipairs(ns.VisibleTypes()) do
        parts[#parts + 1] = info.key .. (c.types[info.key]:GetChecked() and "=on" or "=off")
    end
    parts[#parts + 1] = "mood" .. (c.profile:GetChecked() and "=on" or "=off")
    parts[#parts + 1] = "conversations" .. (c.conversations:GetChecked() and "=on" or "=off")
        .. (c.conversations.enabled == false and " (disabled)" or " (usable)")
    return table.concat(parts, ", ")
end

-- The player's actions, through the panel when there is one.
local function PanelClick(widget, checked)
    if checked ~= nil then widget:SetChecked(checked) end   -- a click toggles the box before OnClick
    widget.scripts.OnClick(widget)
end

local function SetChat(mode)
    local c = ns.optionsControls
    if not c then
        slash("chat " .. ({ all = "todo", important = "importante", off = "nada" })[mode])
        return
    end
    local clicks = 0
    while Settings().chat ~= mode and clicks < 4 do
        PanelClick(c.chat)
        clicks = clicks + 1
    end
    note(string.format("panel: chat -> %s after %d click(s), button reads %q", mode, clicks, tostring(c.chat.text)))
end

local function SetType(key, enabled)
    local c = ns.optionsControls
    if c then PanelClick(c.types[key], enabled)
    else slash("tipos " .. key .. (enabled and " on" or " off")) end
end

local function SetProfile(enabled)
    local c = ns.optionsControls
    if c then PanelClick(c.profile, enabled)
    else slash("animo " .. (enabled and "on" or "off")) end
end


local function BookBody(day)
    ns.OpenAtDay(day)
    return tostring(_G.AdventureJournalBookFrame.body.text)
end

-- Setup facts ------------------------------------------------------------------------
note("options panel: " .. ns.GetOptionsStatus())
for _, category in ipairs(S.settings.categories) do
    note(string.format("Settings category %q: kind=%s registered=%s", category.name, category.kind, tostring(category.registered)))
end
note("registered via Settings.RegisterAddOnCategory: " .. table.concat(S.settings.registered, ", "))
note("TOC AddonCompartmentFunc = " .. tostring(H.compartmentFunc)
    .. "; the global function exists = " .. tostring(type(_G.AdventureJournal_OnAddonCompartmentClick) == "function"))

fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")

-- A fresh login ----------------------------------------------------------------------------
if H.mode == "login" then
    fire("PLAYER_ENTERING_WORLD", true, false)
    note("defaults: " .. SettingsLine())
    -- With no Settings API, also exercise the forced button index (/diario debug buttons must
    -- come before the book is first built).
    if S.flags.nosettings then slash("debug buttons") end

    -- Open the panel, as the player would with /diario opciones.
    slash("opciones")
    note("Settings.OpenToCategory was called with: " .. table.concat(S.settings.opened, ", ")
        .. "; settings window shown = " .. tostring(SettingsPanel and SettingsPanel.shown))
    note("panel controls: " .. ControlsLine())

    -- Change options: chat off, three types off, mood on.
    SetChat("off")
    SetType("DISCOVERY", false)
    SetType("NPC", false)
    SetType("CHAT", false)
    SetProfile(true)
    note("after changes: " .. SettingsLine())
    note("panel controls: " .. ControlsLine())

    -- Events while those types are off. Chat is off, so nothing may be printed.
    local printedBefore = #S.prints
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    advance(5); fire("ZONE_CHANGED_NEW_AREA")
    advance(5); fire("GOSSIP_SHOW")
    advance(5); fire("GOSSIP_SHOW")
    advance(5); fire("CHAT_MSG_WHISPER", "texto", "Amigo-OtroReino")
    S.questTitles[4641] = "Tu lugar en el mundo"
    S.questLog = { { title = "Tu lugar en el mundo", questID = 4641 } }
    advance(5); fire("QUEST_TURNED_IN", 4641, 40, 0)
    fire("QUEST_TURNED_IN", 4641, 40, 0)                 -- dedupe still works: one entry
    advance(5); fire("PLAYER_DEAD")
    advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5555].link .. ".", "", "", "", "Volgajin")
    note("entries after events: " .. Counts())
    note("chat lines printed while chat = nada: " .. (#S.prints - printedBefore))
    note("the place was still marked visited while DISCOVERY was off: " .. tostring(AdventureJournalDB.visited["Valle de los Retos, Durotar"]))

    -- Back on, by slash command. The NPC dedupe state was updated while NPC was off, so the
    -- same NPC within 20 s is still ignored (and logged after that).
    advance(30); fire("GOSSIP_SHOW")                      -- handled while NPC is off: refreshes the dedupe window
    slash("tipos npc on")
    advance(5); fire("GOSSIP_SHOW")
    note("NPC on again, same NPC 5 s after the one seen while off (dedupe): " .. Counts())
    advance(30); fire("GOSSIP_SHOW")
    note("NPC on again, 30 s later: " .. Counts())
    slash("tipos")
    slash("tipos jefes")
    slash("tipos xyz off")
    note("panel controls follow the commands: " .. ControlsLine())

    -- Chat echo by slash command updates the panel and the behaviour.
    slash("chat todo")
    note("panel after /diario chat todo: " .. ControlsLine())
    advance(5); fire("PLAYER_DEAD")
    slash("chat importante")

    -- LOOT off: no entry and nothing pending, even for an item that is not cached yet.
    slash("tipos botin off")
    advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5556].link .. ".", "", "", "", "Volgajin")
    S.items[5556].cached = true
    fire("GET_ITEM_INFO_RECEIVED", 5556, true)
    note("LOOT off, uncached epic, then cached: " .. Counts())
    slash("tipos loot on")
    advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5556].link .. ".", "", "", "", "Volgajin")
    note("LOOT on again: " .. Counts())

    -- Secret values with types switched off and on: no errors, nothing secret saved.
    SetType("NPC", false)
    SetType("CHAT", false)
    S.npcName = S.SECRET
    advance(30); fire("GOSSIP_SHOW")
    fire("CHAT_MSG_WHISPER", "texto", S.SECRET)
    fire("CHAT_MSG_LOOT", S.SECRET)
    SetType("NPC", true)
    SetType("CHAT", true)
    advance(30); fire("GOSSIP_SHOW")
    fire("CHAT_MSG_WHISPER", "texto", S.SECRET)
    local errorCount = 0
    for _ in pairs(ns.handlerErrors) do errorCount = errorCount + 1 end
    note("secret payloads: " .. Counts() .. "; handler errors = " .. errorCount)
    S.npcName = "Gornek"

    -- The mood in the book.
    note("book with the mood shown:\n" .. BookBody(AdventureJournalDB.currentDay))
    slash("animo")
    slash("animo off")
    note("book with the mood hidden:\n" .. BookBody(AdventureJournalDB.currentDay))
    slash("animo quizá")
    slash("animo on")

    note("book index: " .. ns.GetIndexMode())
    slash("debug off")

    -- The AddonCompartment entry (Forever TOC only) toggles the book.
    local before = _G.AdventureJournalBookFrame.shown
    if H.compartmentFunc then
        _G[H.compartmentFunc]("AdventureJournal", "LeftButton")
        note("compartment click: book shown " .. tostring(before) .. " -> " .. tostring(_G.AdventureJournalBookFrame.shown))
        _G[H.compartmentFunc]("AdventureJournal", "LeftButton")
        note("compartment click again: book shown = " .. tostring(_G.AdventureJournalBookFrame.shown))
    else
        note("no compartment entry in this client's TOC: nothing to click")
    end

    -- /diario debug demo: a generated diary shown in the book only. The real diary must not
    -- change (the final DB dump of this run would show it), and entries still go to the real one.
    local day = AdventureJournalDB.currentDay
    local realEntries = #AdventureJournalDB.days[day].events
    local framesBefore = #S.frames
    slash("debug demo")
    local book = _G.AdventureJournalBookFrame
    note(string.format("demo: book shows %s, page %s, %s", tostring(book.dayTitle.text), tostring(book.pageNumber.text),
        tostring(book.dayMeta.text)))
    note("demo: new frames = " .. (#S.frames - framesBefore) .. ", index mode: " .. ns.GetIndexMode())
    advance(5); fire("PLAYER_DEAD")
    note(string.format("demo: an entry made meanwhile went to the real diary (%d -> %d entries); the real diary still has %d jornada(s)",
        realEntries, #AdventureJournalDB.days[day].events, AdventureJournalDB.currentDay))
    slash("debug demo off")
    note("demo off: book shows " .. tostring(book.dayTitle.text) .. ", page " .. tostring(book.pageNumber.text))

    -- The state that must survive the /reload and the second login.
    SetType("DISCOVERY", false)
    SetType("CHAT", false)
    slash("chat todo")
    note("end of login: " .. SettingsLine())
    fire("PLAYER_LOGOUT")
    return
end

-- A /reload: options persisted ------------------------------------------------------------
if H.mode == "reload" then
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    fire("PLAYER_ENTERING_WORLD", false, true)
    note("after /reload: " .. SettingsLine())
    slash("opciones")
    note("panel controls after /reload: " .. ControlsLine())
    local printedBefore = #S.prints
    S.zone, S.subZone = "Orgrimmar", ""
    advance(5); fire("ZONE_CHANGED_NEW_AREA")             -- DISCOVERY is still off
    advance(5); fire("CHAT_MSG_WHISPER", "texto", "Amigo-OtroReino")   -- CHAT is still off
    advance(5); fire("PLAYER_DEAD")                       -- chat = todo: echoed
    note("entries after /reload events: " .. Counts() .. "; chat lines printed: " .. (#S.prints - printedBefore))
    SetProfile(false)
    SetChat("off")
    note("end of reload: " .. SettingsLine())
    fire("PLAYER_LOGOUT")
    return
end

-- A second login: options persisted, and an old entry without a mood still renders --------------
fire("PLAYER_ENTERING_WORLD", true, false)
note("after the second login: " .. SettingsLine() .. "; currentDay = " .. AdventureJournalDB.currentDay)
slash("opciones")
note("panel controls after the second login: " .. ControlsLine())
table.insert(AdventureJournalDB.days[1].events, { type = "QUEST", text = "Misión antigua", time = "10:00:00",
    prose = "Una vieja historia, anotada antes de que existiera el ánimo." })
SetProfile(true)
note("jornada 1 with the mood shown (the last entry has no characterProfile):\n" .. BookBody(1))
SetProfile(false)
note("jornada 1 with the mood hidden:\n" .. BookBody(1))
fire("PLAYER_LOGOUT")
