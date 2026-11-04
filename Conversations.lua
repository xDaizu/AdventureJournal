-- Conversations.lua (M4b): the opt-in RP conversation log. OFF by default, because it stores
-- other players' words (settings.conversations, /diario conversaciones on|off, options panel).
--
-- While the option is off nothing is registered, captured or shown. While it is on, the lines
-- are stored per jornada in `day.conversations`:
--   { time = "HH:MM:SS", timestamp = <epoch>, channel = "WHISPER", who = "Name", rel = "friend",
--     lang = "Orco", text = "...", place = "Subzone, Zone", source = "ajprobe" (imported only) }
-- It is a port of AJProbe's filter ("all" / "people"), which has recorded the same lines since
-- the first Forever day. The existing CHAT entry (sender name only, never the text) is
-- untouched and works with or without this option.
--
-- Workspace rule 5: inside instances on Forever, chat arrives as secret values and cannot be
-- stored. A line whose text or author is secret is skipped; nothing is shown and nothing errors.
local addonName, ns = ...
local SafeString = ns.SafeString

-- "all": stored whoever wrote it. "people": stored only when written by me, a group member
-- or a friend (/say, /yell and emotes would otherwise record every stranger in a capital).
ns.CONVERSATION_FILTER = {
    CHAT_MSG_WHISPER = "all", CHAT_MSG_WHISPER_INFORM = "all",
    CHAT_MSG_BN_WHISPER = "all", CHAT_MSG_BN_WHISPER_INFORM = "all",
    CHAT_MSG_PARTY = "all", CHAT_MSG_PARTY_LEADER = "all",
    CHAT_MSG_RAID = "all", CHAT_MSG_RAID_LEADER = "all",
    CHAT_MSG_SAY = "people", CHAT_MSG_YELL = "people",
    CHAT_MSG_EMOTE = "people", CHAT_MSG_TEXT_EMOTE = "people",
}
ns.CONVERSATION_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
}

-- A runaway guard for SavedVariables: past this many lines in one jornada, live capture stops
-- for that jornada (the import ignores the limit, it only reads what AJProbe already kept).
ns.MAX_CONVERSATIONS_PER_DAY = 5000
-- Lines per page in the book.
ns.CONVERSATIONS_PER_PAGE = 100

function ns.ConversationsEnabled()
    return ns.GetSetting("conversations") == true
end

local conversationFrame = CreateFrame("Frame")
local handlers = {}
local registered = false
local limitReportedFor
local status = {}   -- [event] = true, or why it did not register (separate from ns.eventStatus)

-- Builds the stored line for one chat event, or nil and the reason it was skipped.
-- Never touches the content of a secret.
function ns.BuildConversation(event, ...)
    local mode = ns.CONVERSATION_FILTER[event]
    if not mode then return nil, "canal desconocido" end
    local text, author, language = ...
    local guid, bnSenderID = select(12, ...), select(13, ...)
    local isBattleNet = event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM"

    if ns.IsSecret(text) then return nil, "texto secreto" end
    if type(text) ~= "string" or text == "" then return nil, "sin texto" end

    local who
    if isBattleNet then
        who = ns.GetBattleTag(bnSenderID)   -- the author is a protected string; the BattleTag is not
    else
        if ns.IsSecret(author) then return nil, "autor secreto" end
        if type(author) ~= "string" or author == "" then return nil, "sin autor" end
        who = ns.StripRealm(author)
    end

    local rel = ns.GetRelationship(guid)   -- nil for a secret or missing GUID
    if mode == "people" and not rel then return nil, "no es del grupo ni un amigo" end

    local lang
    if not ns.IsSecret(language) and type(language) == "string" and language ~= "" then lang = language end

    return {
        time = date("%H:%M:%S"),
        timestamp = time(),
        channel = (string.gsub(event, "^CHAT_MSG_", "")),
        who = who,
        rel = rel,
        lang = lang,
        text = text,
        place = ns.GetPlace(),
    }
end

local function Capture(event, ...)
    -- The events are only registered while the option is on; this is the second lock.
    if not ns.ConversationsEnabled() then return end
    local DB = ns.DB
    local day = DB and DB.days and DB.days[DB.currentDay]
    if not day then return end
    local conversation, reason = ns.BuildConversation(event, ...)
    if not conversation then
        ns.Debug("%s: conversación omitida (%s)", event, tostring(reason))
        return
    end
    day.conversations = day.conversations or {}
    if #day.conversations >= ns.MAX_CONVERSATIONS_PER_DAY then
        if limitReportedFor ~= DB.currentDay then
            limitReportedFor = DB.currentDay
            print(string.format("|cFFFFD700[Diario]|r Esta jornada ya guarda %d conversaciones: no se anotan más hasta la próxima.",
                ns.MAX_CONVERSATIONS_PER_DAY))
        end
        return
    end
    table.insert(day.conversations, conversation)
    ns.RefreshIfVisible()
end

for _, event in ipairs(ns.CONVERSATION_EVENTS) do
    handlers[event] = function(...) Capture(event, ...) end
end
conversationFrame:SetScript("OnEvent", ns.MakeDispatcher(handlers))

-- Registers the chat events while the option is on and drops them when it is off. Called when
-- the diary loads and after every settings change.
function ns.UpdateConversationEvents()
    local wanted = ns.ConversationsEnabled()
    if wanted == registered then return end
    for _, event in ipairs(ns.CONVERSATION_EVENTS) do
        if wanted then
            ns.RegisterEventSafe(conversationFrame, event, status)
        else
            pcall(conversationFrame.UnregisterEvent, conversationFrame, event)
            status[event] = nil
        end
    end
    -- Without the option the book has no conversations view; do not reopen on it later.
    if not wanted then ns.bookView = "events"; ns.conversationPage = 1 end
    registered = wanted
end

-- For /diario diag: "n de 12 eventos de chat registrados" and the ones that failed.
function ns.GetConversationStatus()
    local ok, failed = 0, {}
    for _, event in ipairs(ns.CONVERSATION_EVENTS) do
        if status[event] == true then ok = ok + 1
        elseif status[event] ~= nil then table.insert(failed, event .. " (" .. tostring(status[event]) .. ")") end
    end
    return ok, failed
end

-- Reading ---------------------------------------------------------------------------------
function ns.CountConversations(day)
    return type(day) == "table" and type(day.conversations) == "table" and #day.conversations or 0
end

function ns.ConversationPageCount(day)
    return math.max(1, math.ceil(ns.CountConversations(day) / ns.CONVERSATIONS_PER_PAGE))
end

-- One line of the book. Works on whatever was stored, including lines from AJProbe's import.
function ns.FormatConversation(c)
    local who = SafeString(c.who, ns.NEUTRAL_TEXT.SENDER)
    local text = SafeString(c.text, "…")
    local lang = (type(c.lang) == "string" and c.lang ~= "") and (" (" .. c.lang .. ")") or ""
    local channel = c.channel
    if channel == "WHISPER" then
        return string.format("%s te susurra%s: «%s»", who, lang, text)
    elseif channel == "WHISPER_INFORM" then
        return string.format("Susurras a %s%s: «%s»", who, lang, text)
    elseif channel == "BN_WHISPER" then
        return string.format("%s te susurra por Battle.net: «%s»", who, text)
    elseif channel == "BN_WHISPER_INFORM" then
        return string.format("Susurras a %s por Battle.net: «%s»", who, text)
    elseif channel == "PARTY" or channel == "PARTY_LEADER" then
        return string.format("%s, en el grupo%s: «%s»", who, lang, text)
    elseif channel == "RAID" or channel == "RAID_LEADER" then
        return string.format("%s, en la banda%s: «%s»", who, lang, text)
    elseif channel == "SAY" then
        return string.format("%s dice%s: «%s»", who, lang, text)
    elseif channel == "YELL" then
        return string.format("%s grita%s: «%s»", who, lang, text)
    elseif channel == "EMOTE" then
        return string.format("%s %s", who, text)
    elseif channel == "TEXT_EMOTE" then
        return text
    end
    return string.format("%s: «%s»", who, text)
end

-- The paragraphs of one page of a jornada's conversations: "HH:MM:SS" in the book's brown, then
-- the line. Returns the paragraphs and the number of pages.
function ns.ConversationParagraphs(day, page)
    local list = type(day) == "table" and type(day.conversations) == "table" and day.conversations or {}
    local pages = ns.ConversationPageCount(day)
    page = math.max(1, math.min(pages, tonumber(page) or 1))
    local first = (page - 1) * ns.CONVERSATIONS_PER_PAGE + 1
    local last = math.min(#list, first + ns.CONVERSATIONS_PER_PAGE - 1)
    local paragraphs = {}
    for index = first, last do
        local c = list[index]
        if type(c) == "table" then
            table.insert(paragraphs, string.format("|cFF8A5A24%s|r  %s", c.time or "", ns.FormatConversation(c)))
        end
    end
    return paragraphs, pages, page
end
