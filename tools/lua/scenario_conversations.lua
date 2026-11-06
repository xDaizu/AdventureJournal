-- M4b: the opt-in RP conversation log, live. Runs in three modes on top of each other's
-- SavedVariables (login, reload, relogin), and with a client that has no C_FriendList /
-- C_BattleNet (stub flag nosocial).
--   login    off by default (nothing registered, captured or shown), turned on through the options
--            panel, every channel and relationship, strangers, secrets, instances, simulated
--            secrets, the per-day limit, paging in the book, turned off again and on again.
--   reload   the option survives, the events register again, the continued jornada keeps its lines.
--   relogin  a new jornada, the option is switched off by the panel: nothing captured or shown,
--            what was stored stays in the file.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns

local function Registered(event)
    local count = 0
    for _, widget in ipairs(S.frames) do if widget.events[event] then count = count + 1 end end
    return count
end

local function ChannelEvents()
    local parts = {}
    for _, event in ipairs(ns.CONVERSATION_EVENTS) do parts[#parts + 1] = Registered(event) end
    return table.concat(parts, "")
end

local function Day() return AdventureJournalDB.days[AdventureJournalDB.currentDay] end
local function Lines() return Day().conversations and #Day().conversations or 0 end
local function Entries(kind)
    local count = 0
    for _, entry in ipairs(Day().events) do if entry.type == kind then count = count + 1 end end
    return count
end
local function Errors()
    local count = 0
    for _ in pairs(ns.handlerErrors) do count = count + 1 end
    return count
end

-- CHAT_MSG_* arguments: 1 text, 2 author, 3 language, ... 12 GUID, 13 Battle.net sender ID.
local function Chat(event, text, author, language, guid, bnSenderID)
    fire(event, text, author, language, "", "", "", "", "", "", "", "", guid, bnSenderID)
end

local function ControlLine()
    local control = ns.optionsControls and ns.optionsControls.conversations
    if not control then return "(no options panel)" end
    return string.format("conversations check box: %s, %s", control:GetChecked() and "checked" or "unchecked",
        control.enabled == false and "disabled" or "usable")
end

local function SetOption(enabled)
    local control = ns.optionsControls and ns.optionsControls.conversations
    if control then
        control:SetChecked(enabled)            -- a click toggles the box before OnClick
        control.scripts.OnClick(control)
    else
        slash("conversaciones " .. (enabled and "on" or "off"))
    end
end

local function BookBody()
    return tostring(_G.AdventureJournalBookFrame.body.text)
end

local function Has(text, needle) return string.find(text, needle, 1, true) ~= nil end

fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")

-- ===================================================================================
if H.mode == "login" then
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    fire("PLAYER_ENTERING_WORLD", true, false)
    S.group = { "Player-1-JAINA" }
    S.friends["Player-1-BAINE"] = true
    S.bnGameAccounts["Player-1-COMPI"] = {}
    S.bnAccounts[777] = { battleTag = "Compi#1234" }

    note("default: conversations = " .. tostring(AdventureJournalDB.settings.conversations)
        .. "; channel events registered (12 digits, one per event) = " .. ChannelEvents())
    note("CHAT_MSG_WHISPER is still registered once, for the CHAT entry: " .. Registered("CHAT_MSG_WHISPER"))
    note("diag status while off: " .. select(1, ns.GetConversationStatus()) .. " registered")

    -- Off: nothing is captured. The CHAT entry (sender only) works as before.
    advance(5); Chat("CHAT_MSG_WHISPER", "Un secreto de rol", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    advance(1); Chat("CHAT_MSG_SAY", "Buenas", "Volgajin-ZandalarTribe", "Orco", S.guid)
    advance(1); Chat("CHAT_MSG_PARTY", "Listos", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    note(string.format("off: %d conversation lines, %d CHAT entries (sender name only)", Lines(), Entries("CHAT")))
    assert(Lines() == 0 and not Day().conversations, "a conversation was stored while the option was off")
    ns.OpenAtDay(AdventureJournalDB.currentDay)
    local f = _G.AdventureJournalBookFrame
    ns.SetBookView("conversations")
    note("off: asked for the conversations view: view button shown = " .. tostring(f.viewButton.shown)
        .. ", body contains conversation text = " .. tostring(Has(BookBody(), "secreto de rol") or Has(BookBody(), "Buenas")))
    ns.SetBookView("events")
    note("off: " .. ControlLine())

    -- On, through the panel (or the command when there is no panel).
    SetOption(true)
    note("on: setting = " .. tostring(AdventureJournalDB.settings.conversations) .. "; channel events registered = "
        .. ChannelEvents() .. "; " .. ControlLine())
    note("diag status on: " .. select(1, ns.GetConversationStatus()) .. " registered")

    advance(5); Chat("CHAT_MSG_WHISPER", "Hola, ¿qué tal?", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    advance(1); Chat("CHAT_MSG_WHISPER_INFORM", "Bien, gracias", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    advance(1); Chat("CHAT_MSG_BN_WHISPER", "Eh, ¿juegas?", "|Kq1|k", "", "Player-1-COMPI", 777)
    advance(1); Chat("CHAT_MSG_BN_WHISPER_INFORM", "Ahora no", "|Kq1|k", "", "Player-1-COMPI", 777)
    advance(1); Chat("CHAT_MSG_PARTY", "Listos", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    advance(1); Chat("CHAT_MSG_PARTY_LEADER", "Adelante", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    advance(1); S.raid = true; S.group = { "Player-1-JAINA", "Player-1-THRALL" }
    Chat("CHAT_MSG_RAID", "Cuidado con la ola", "Thrall-ZandalarTribe", "Orco", "Player-1-THRALL")
    Chat("CHAT_MSG_RAID_LEADER", "Todos juntos", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    S.raid = false; S.group = { "Player-1-JAINA" }
    advance(1); Chat("CHAT_MSG_SAY", "¡Por la Horda!", "Volgajin-ZandalarTribe", "Orco", S.guid)
    advance(1); Chat("CHAT_MSG_SAY", "Compro oro barato", "Extraño-ZandalarTribe", "Orco", "Player-1-EXTRANO")      -- stranger: not kept
    advance(1); Chat("CHAT_MSG_YELL", "¡Atentos!", "Baine-ZandalarTribe", "Orco", "Player-1-BAINE")                  -- friend
    advance(1); Chat("CHAT_MSG_SAY", "Hola de un amigo de Battle.net", "Compi-ZandalarTribe", "Orco", "Player-1-COMPI")
    advance(1); Chat("CHAT_MSG_YELL", "¡Cuidado!", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")                 -- group
    advance(1); Chat("CHAT_MSG_EMOTE", "saluda con la cabeza.", "Volgajin-ZandalarTribe", "", S.guid)
    advance(1); Chat("CHAT_MSG_TEXT_EMOTE", "Volgajin saluda a Gornek.", "Volgajin-ZandalarTribe", "", S.guid)
    advance(1); Chat("CHAT_MSG_SAY", "Un guiño", "Volgajin-ZandalarTribe", "", nil)                                 -- no GUID: not kept
    note(string.format("on: %d conversation lines, %d CHAT entries, %d handler errors", Lines(), Entries("CHAT"), Errors()))
    for _, line in ipairs(Day().conversations) do
        note(string.format("   %s %s who=%s rel=%s lang=%s place=%q text=%q", line.time, line.channel, tostring(line.who),
            tostring(line.rel), tostring(line.lang), line.place, line.text))
    end

    -- Secrets: skipped, never an error. The real guard is ns.IsSecret before anything else.
    local lines = Lines()
    advance(1); Chat("CHAT_MSG_WHISPER", S.SECRET, "Amigo-ZandalarTribe", "", "Player-1-AMIGO")          -- secret text
    Chat("CHAT_MSG_WHISPER", "Texto claro", S.SECRET, "", "Player-1-AMIGO")                              -- secret author
    Chat("CHAT_MSG_WHISPER", "Texto claro 2", "Amigo-ZandalarTribe", S.SECRET, S.SECRET)                 -- secret language and GUID: kept, without them
    Chat("CHAT_MSG_SAY", "Texto claro 3", "Volgajin-ZandalarTribe", "Orco", S.SECRET)                    -- secret GUID on a /say: cannot tell who: skipped
    Chat("CHAT_MSG_BN_WHISPER", S.SECRET, S.SECRET, "", S.SECRET, S.SECRET_NUMBER)
    note(string.format("secrets: %d new line (secret language and GUID only), %d handler errors", Lines() - lines, Errors()))
    assert(Lines() - lines == 1, "secret chat was stored")
    S.inInstance = true
    lines = Lines()
    Chat("CHAT_MSG_PARTY", S.SECRET, S.SECRET, S.SECRET, S.SECRET)
    Chat("CHAT_MSG_SAY", S.SECRET, S.SECRET, S.SECRET, S.SECRET)
    note(string.format("in an instance, all secret: %d new lines, %d handler errors", Lines() - lines, Errors()))
    assert(Lines() == lines, "instance chat was stored")
    S.inInstance = false
    -- The addon's own simulated secrets (Classic Era has no real ones).
    slash("debug secrets")
    lines = Lines()
    Chat("CHAT_MSG_WHISPER", "Texto simulado", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    Chat("CHAT_MSG_PARTY", "Grupo simulado", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    slash("debug off")
    note(string.format("simulated secrets: %d new lines, %d handler errors", Lines() - lines, Errors()))
    assert(Lines() == lines, "simulated secret chat was stored")

    -- The book: both views, then pages.
    ns.OpenAtDay(AdventureJournalDB.currentDay)
    note("on: view button shown = " .. tostring(f.viewButton.shown) .. ", reads '" .. tostring(f.viewButton.text) .. "'")
    local eventsBody = BookBody()
    ns.SetBookView("conversations")
    local conversationsBody = BookBody()
    note("conversations view: button reads '" .. tostring(f.viewButton.text) .. "'; " .. tostring(f.dayMeta.text))
    note("body:\n" .. conversationsBody)
    assert(Has(conversationsBody, "Hola, ¿qué tal?") and not Has(conversationsBody, "Compro oro"), "wrong conversation text in the book")
    assert(not Has(eventsBody, "Hola, ¿qué tal?"), "conversation text in the events view")
    ns.CONVERSATIONS_PER_PAGE = 4
    ns.SetBookView("conversations")
    note(string.format("paging, 4 per page: %s | prev %s next %s (prev/next shown: %s/%s)", tostring(f.dayMeta.text) .. " [label " .. tostring(f.conversationPageText.text) .. "]",
        tostring(f.conversationPrev.enabled), tostring(f.conversationNext.enabled),
        tostring(f.conversationPrev.shown), tostring(f.conversationNext.shown)))
    f.conversationNext.scripts.OnClick()
    note("page 2: " .. tostring(f.dayMeta.text) .. " [label " .. tostring(f.conversationPageText.text) .. "]"  .. " | first line: " .. string.match(BookBody(), "|r  ([^\n]*)"))
    f.conversationNext.scripts.OnClick(); f.conversationNext.scripts.OnClick(); f.conversationNext.scripts.OnClick()
    note("last page: " .. tostring(f.dayMeta.text) .. " [label " .. tostring(f.conversationPageText.text) .. "]"  .. " | next enabled = " .. tostring(f.conversationNext.enabled))
    ns.CONVERSATIONS_PER_PAGE = 100
    f.viewButton.scripts.OnClick()
    note("view button toggles back: " .. tostring(f.viewButton.text) .. "; body has conversations = " .. tostring(Has(BookBody(), "Hola, ¿qué tal?")))

    -- The per-day limit: capture stops for the jornada, one notice.
    local normalMax = ns.MAX_CONVERSATIONS_PER_DAY
    ns.MAX_CONVERSATIONS_PER_DAY = Lines() + 2
    local printsBefore = #S.prints
    for index = 1, 5 do advance(1); Chat("CHAT_MSG_WHISPER", "Mensaje " .. index, "Amigo-ZandalarTribe", "", "Player-1-AMIGO") end
    note(string.format("limit: %d lines (limit %d), %d notices printed", Lines(), ns.MAX_CONVERSATIONS_PER_DAY, #S.prints - printsBefore))
    ns.MAX_CONVERSATIONS_PER_DAY = normalMax

    -- Off by command: nothing captured, nothing shown, what was stored stays.
    local stored = Lines()
    slash("conversaciones off")
    note("off again: channel events registered = " .. ChannelEvents() .. "; " .. ControlLine() .. "; CHAT_MSG_WHISPER still registered once = " .. Registered("CHAT_MSG_WHISPER"))
    advance(5); Chat("CHAT_MSG_WHISPER", "Con la opción apagada", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    Chat("CHAT_MSG_SAY", "Apagado", "Volgajin-ZandalarTribe", "Orco", S.guid)
    assert(Lines() == stored, "captured while off")
    note(string.format("off again: %d lines stored (unchanged), book view = %s, body shows conversation text = %s, view button shown = %s",
        Lines(), tostring(ns.bookView), tostring(Has(BookBody(), "Hola, ¿qué tal?")), tostring(f.viewButton.shown)))
    slash("conversaciones")
    slash("conversaciones quizá")

    -- On again, by command; the diary keeps going.
    slash("conversaciones on")
    advance(5); Chat("CHAT_MSG_WHISPER", "Otra vez encendido", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
    note("on again: " .. Lines() .. " lines; channel events registered = " .. ChannelEvents())
    slash("diag")
    fire("PLAYER_LOGOUT")
    return
end

-- ===================================================================================
if H.mode == "reload" then
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    S.group = { "Player-1-JAINA" }
    local before = Lines()
    note("after /reload (before the world loads): conversations = " .. tostring(AdventureJournalDB.settings.conversations)
        .. "; channel events registered = " .. ChannelEvents() .. "; stored lines = " .. before)
    fire("PLAYER_ENTERING_WORLD", false, true)
    advance(5); Chat("CHAT_MSG_PARTY", "Tras el reload", "Jaina-ZandalarTribe", "Orco", "Player-1-JAINA")
    note("the continued jornada " .. AdventureJournalDB.currentDay .. " keeps its lines and gets the new one: " .. before .. " -> " .. Lines())
    ns.OpenAtDay(AdventureJournalDB.currentDay)
    ns.SetBookView("conversations")
    note("the book shows them: " .. tostring(Has(BookBody(), "Tras el reload")))
    fire("PLAYER_LOGOUT")
    return
end

-- relogin ===========================================================================
S.zone, S.subZone = nil, ""
fire("PLAYER_ENTERING_WORLD", true, false)
S.zone, S.subZone = "Durotar", "Valle de los Retos"
S.group = { "Player-1-JAINA" }
local first = AdventureJournalDB.days[1]
note("second login: jornada " .. AdventureJournalDB.currentDay .. "; the first jornada holds " .. #first.conversations .. " stored lines; option = "
    .. tostring(AdventureJournalDB.settings.conversations) .. "; channel events registered = " .. ChannelEvents())
advance(5); Chat("CHAT_MSG_WHISPER", "En la jornada nueva", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
note("new jornada: " .. Lines() .. " line(s)")
ns.OpenAtDay(1)
ns.SetBookView("conversations")
note("jornada 1, conversations view: " .. tostring(_G.AdventureJournalBookFrame.dayMeta.text))
-- Off through the panel: nothing captured, the stored lines are hidden.
SetOption(false)
advance(5); Chat("CHAT_MSG_WHISPER", "No debería guardarse", "Amigo-ZandalarTribe", "", "Player-1-AMIGO")
note(string.format("off by the panel: %s; channel events registered = %s; new jornada holds %d line(s); %s",
    tostring(AdventureJournalDB.settings.conversations), ChannelEvents(), Lines(), ControlLine()))
ns.OpenAtDay(1)
note("jornada 1 with the option off shows conversation text = " .. tostring(Has(BookBody(), "Hola, ¿qué tal?"))
    .. "; stored lines still in the file = " .. #first.conversations)
fire("PLAYER_LOGOUT")
