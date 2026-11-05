-- Import.lua (M4b): backfill the diary from AJProbe's records. `/diario importar`.
--
-- READ ONLY on AJProbe: it reads the AJProbeDB global at command time (AJProbe may not be
-- installed or enabled) and never writes to it. AJProbeDB.log is the activity log, AJProbeDB.chat
-- the RP conversation log; every record carries the character in its `c` field ("Name-Realm").
--
-- Two steps, so that a dry run (`/diario importar prueba`) changes nothing and a planning error
-- leaves the diary untouched:
--   PlanImport   reads AJProbe and the diary, decides everything, mutates nothing.
--   ApplyImport  inserts what the plan decided.
--
-- Rules (ROADMAP M4b):
--  * Jornadas are rebuilt from the PLAYER_ENTERING_WORLD records: login = true starts one,
--    reloads and loading screens do not (the M4 rule). A session that overlaps an existing
--    jornada is merged into it, record by record (the narrowest jornada whose time range holds
--    the record); anything left over, and every session with no jornada, gets a new jornada.
--  * Existing entries and jornadas are never modified or deleted. New jornadas are inserted in
--    time order, so later jornadas can move up one number; the current jornada stays last.
--  * An entry of the same type and subject within a few seconds of an existing one is the same
--    event and is skipped. That is also what makes a second run add nothing.
--  * Types switched off in the options are not imported (and `visited` is left alone for them).
--  * Secret markers ("[SECRET]") become the neutral texts or are skipped; they never error.
--  * Imported entries carry source = "ajprobe". Conversations are imported only while the
--    conversations option is on.
local addonName, ns = ...

local PREFIX = "|cFFFFD700[Diario]|r "
local function Say(text) print(PREFIX .. text) end

local SLACK = 3          -- seconds of tolerance when matching records to jornadas
local CHAT_WINDOW = 2    -- seconds: same channel, author and text is the same line
-- Same windows as the live handlers (quest 3 s, boss 5 s, NPC 20 s), widened a little because
-- the diary and AJProbe read the clock in different frames.
-- A whisper has no live dedupe, so only clock skew counts as the same event.
local WINDOW = { QUEST = 5, BOSS = 5, NPC = 20, DEATH = 5, LOOT = 5, CHAT = 1 }

-- What AJProbe writes for values it could not or would not record (Snap in AJProbe.lua).
local NOT_A_VALUE = {
    [""] = true, ["<nil>"] = true, ["<unknown>"] = true, ["<error>"] = true, ["<missing>"] = true,
    ["<not in log>"] = true, ["<table>"] = true, ["<function>"] = true, ["<userdata>"] = true,
    ["<boolean>"] = true, ["<number>"] = true, ["<string>"] = true,
}

-- A usable text, or nil; the second result is true when the record held a secret marker.
local function Text(value)
    if ns.IsSecret(value) or value == "[SECRET]" then return nil, true end
    if type(value) == "string" and not NOT_A_VALUE[value] then return value, false end
    return nil, false
end

local function DateText(record)
    if type(record.d) == "string" and string.match(record.d, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
        return record.d
    end
    return date("%Y-%m-%d %H:%M:%S", record.t)
end

local function TimeText(record) return string.sub(DateText(record), 12, 19) end

local function DateLabel(record)
    local year, month, day = string.match(DateText(record), "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return string.format("%s/%s/%s", day, month, year)
end

-- The subject two entries must share to be the same event.
local function Subject(entryType, text, source)
    local newType = ns.NewTypeSubject(entryType, text, source)   -- the M6 types (Messages.lua)
    if newType then return newType end
    if entryType == "LOOT" and type(source.itemID) == "number" then return "item:" .. source.itemID end
    if entryType == "QUEST" and type(source.questID) == "number" then return "quest:" .. source.questID end
    return text
end

local function Remember(known, kind, subject, timestamp)
    known[kind] = known[kind] or {}
    local list = known[kind][subject]
    if not list then list = {}; known[kind][subject] = list end
    list[#list + 1] = timestamp
end

local function IsKnown(known, kind, subject, timestamp, window)
    local byKind = known[kind]
    local list = byKind and byKind[subject]
    if not list then return false end
    for index = 1, #list do
        local difference = list[index] - timestamp
        if difference <= window and difference >= -window then return true end
    end
    return false
end

-- Record handlers ----------------------------------------------------------------------
-- Each returns a candidate { type, text, extra, secret, ... }, or nil and the reason it makes
-- no entry: "secret" (a secret value left nothing to write), "foreign" (another player's loot),
-- "noquality", "ignored" (not diary material, wipes, junk loot...).

local function Where(record)
    local zone = Text(record.z)
    local sub = Text(record.s)
    return {
        place = ns.PlaceFrom(zone, sub),
        zone = ns.SafeString(zone, "Desconocido"),
        subZone = ns.SafeString(sub, ""),
    }
end

local function IsOwnLoot(message, record, playerName)
    if #ns.GetOwnLootPatterns() > 0 then return ns.IsOwnLootMessage(message) end
    -- This client has none of the loot strings: fall back on who looted (arg5).
    local who = Text(record.who)
    return who == nil or ns.StripRealm(who) == playerName
end

local HANDLERS = {}

HANDLERS.QUEST_TURNED_IN = function(record)
    local id = type(record.quest) == "number" and record.quest or nil
    local title, secretTitle = Text(record.title)
    local text
    if title then
        text = title
    elseif id then
        text = "una misión (ID " .. id .. ")"
    else
        text = ns.NEUTRAL_TEXT.QUEST
    end
    return { type = "QUEST", text = text, extra = { questID = id },
             secret = title == nil and (secretTitle or record.quest == "[SECRET]") }
end

HANDLERS.GOSSIP_SHOW = function(record)
    local name, secret = Text(record.npc)
    return { type = "NPC", text = name or ns.NEUTRAL_TEXT.NPC, secret = name == nil and secret }
end

-- The CHAT entry (sender name only, never the text), as CHAT_MSG_WHISPER makes it live.
HANDLERS.CHAT_MSG_WHISPER = function(record)
    local from, secret = Text(record.from)
    if from then return { type = "CHAT", text = ns.StripRealm(from) } end
    if secret then return { type = "CHAT", text = ns.NEUTRAL_TEXT.SENDER, secret = true } end
    return nil, "ignored"
end

-- The first argument of a generic AJProbe record (CHAT_MSG_*, GROUP_JOINED...): `a` holds the
-- first four event arguments.
local function FirstArg(record)
    local args = record.a
    return type(args) == "table" and args[1] or nil
end

-- M6: CHAT_MSG_SYSTEM carries the group joins and leaves (by name) in a[1].
HANDLERS.CHAT_MSG_SYSTEM = function(record)
    local message, secret = Text(FirstArg(record))
    if secret then return nil, "secret" end
    if not message then return nil, "ignored" end
    local candidate = ns.SystemMessageCandidate(message)
    if not candidate then return nil, "ignored" end
    return candidate
end

-- M6: reputation and skills: the message is a[1] of the record.
HANDLERS.CHAT_MSG_COMBAT_FACTION_CHANGE = function(record)
    local message, secret = Text(FirstArg(record))
    if secret then return nil, "secret" end
    if not message then return nil, "ignored" end
    local candidate = ns.ReputationCandidate(message)
    if not candidate then return nil, "ignored" end
    return candidate
end

HANDLERS.CHAT_MSG_SKILL = function(record)
    local message, secret = Text(FirstArg(record))
    if secret then return nil, "secret" end
    if not message then return nil, "ignored" end
    local candidate, reason = ns.SkillCandidate(message)
    if not candidate then return nil, reason or "ignored" end
    return candidate
end

-- M6: GROUP_JOINED a[1] = partyCategory. Only a dungeon group makes an entry (no names).
HANDLERS.GROUP_JOINED = function(record)
    local candidate = ns.GroupJoinedCandidate(FirstArg(record))
    if not candidate then return nil, "ignored" end
    return candidate
end

-- M6: PLAYER_LEVEL_UP carries the new level in `level`.
HANDLERS.PLAYER_LEVEL_UP = function(record)
    if type(record.level) == "number" or ns.IsSecret(record.level) or record.level == "[SECRET]" then
        return ns.LevelCandidate(record.level == "[SECRET]" and nil or record.level)
    end
    return nil, "ignored"
end

HANDLERS.PLAYER_DEAD = function()
    return { type = "DEATH", text = "He caído en combate" }
end

HANDLERS.BOSS_KILL = function(record)
    local name, secret = Text(record.name)
    return { type = "BOSS", text = name or ns.NEUTRAL_TEXT.BOSS, secret = name == nil and secret }
end

HANDLERS.ENCOUNTER_END = function(record)
    if ns.IsSecret(record.success) or record.success == "[SECRET]" then return nil, "secret" end
    -- A wipe is not a kill. BOSS_KILL covers kills too, the dedupe merges the two.
    if record.success ~= 1 and record.success ~= true then return nil, "ignored" end
    local name, secret = Text(record.name)
    return { type = "BOSS", text = name or ns.NEUTRAL_TEXT.BOSS, secret = name == nil and secret }
end

HANDLERS.CHAT_MSG_LOOT = function(record, context)
    if record.secret == true then return nil, "secret" end
    local message, secret = Text(record.msg)
    if secret then return nil, "secret" end
    if not message then return nil, "ignored" end
    if not IsOwnLoot(message, record, context.playerName) then return nil, "foreign" end
    local link = string.match(message, "|c[^|]*|Hitem:.-|h%[.-%]|h|r")
    if not link then return nil, "ignored" end
    local itemID = type(record.item) == "number" and record.item or tonumber(string.match(link, "|Hitem:(%d+)"))
    local quality = type(record.quality) == "number" and record.quality or nil
    if not quality then
        local _, _, cachedQuality = ns.GetItemInfoSafe(link)
        quality = cachedQuality
    end
    if not quality then
        ns.RequestItemData(itemID)   -- a second /diario importar a moment later will know it
        return nil, "noquality"
    end
    if quality < ns.GetLootQuality() then return nil, "ignored" end   -- the live rule (settings.lootQuality)
    return { type = "LOOT", text = link, extra = { itemQuality = quality, itemLink = link, itemID = itemID } }
end

local function ZoneHandler(record)
    local zone, zoneSecret = Text(record.z)
    local sub, subSecret = Text(record.s)
    if zoneSecret or subSecret then return nil, "secret" end   -- the live rule: no secret place
    if not zone then return nil, "ignored" end                 -- zone unreadable (nil at login)
    local place = ns.PlaceFrom(zone, sub)
    return { type = "DISCOVERY", text = place, zoneName = zone, zoneOnly = place == zone }
end
HANDLERS.ZONE_CHANGED_NEW_AREA = ZoneHandler
HANDLERS.ZONE_CHANGED = ZoneHandler
HANDLERS.ZONE_CHANGED_INDOORS = ZoneHandler

-- A chat record -> the stored conversation line, or nil and the reason.
local function ConversationFrom(record)
    local channel = type(record.ch) == "string" and record.ch or nil
    local mode = channel and ns.CONVERSATION_FILTER["CHAT_MSG_" .. channel]
    if not mode then return nil, "ignored" end
    local text, secret = Text(record.msg)
    if secret then return nil, "secret" end
    if not text then return nil, "ignored" end
    local rel = type(record.rel) == "string" and record.rel or nil
    if mode == "people" and not rel then return nil, "ignored" end
    local who
    if channel == "BN_WHISPER" or channel == "BN_WHISPER_INFORM" then
        who = Text(record.btag)
    else
        local author, authorSecret = Text(record.who)
        if authorSecret then return nil, "secret" end
        if not author then return nil, "ignored" end
        who = ns.StripRealm(author)
    end
    local where = Where(record)
    return {
        time = TimeText(record), timestamp = record.t, channel = channel, who = who, rel = rel,
        lang = Text(record.lang), text = text, place = where.place, source = "ajprobe",
    }
end

-- Planning -------------------------------------------------------------------------------
local function NewStats()
    return { logRead = 0, chatRead = 0, mine = 0, other = 0, malformed = 0, sessions = 0, newDays = 0,
        added = {}, addedTotal = 0, duplicates = 0, secretNeutral = 0, secretSkipped = 0, typeOff = 0,
        ignored = 0, revisits = 0, zoneOnly = 0, foreign = 0, noQuality = 0,
        chatMine = 0, convAdded = 0, convDuplicates = 0, convSecret = 0, convIgnored = 0,
        convOrphans = 0, convOff = 0 }
end

-- This character's records, oldest first (the log is normally in order already).
local function MyRecords(list, key, stats)
    local mine = {}
    for index = 1, #list do
        local record = list[index]
        if type(record) == "table" and type(record.t) == "number" then
            if record.c == key then mine[#mine + 1] = { r = record, i = index } else stats.other = stats.other + 1 end
        else
            stats.malformed = stats.malformed + 1
        end
    end
    local ordered = true
    for index = 2, #mine do
        if mine[index].r.t < mine[index - 1].r.t then ordered = false break end
    end
    if not ordered then
        table.sort(mine, function(a, b)
            if a.r.t ~= b.r.t then return a.r.t < b.r.t end
            return a.i < b.i
        end)
    end
    return mine
end

-- A jornada's time range: its startedAt/endedAt and the timestamps of what it holds. The
-- current jornada is still running, so it reaches up to now.
local function RangeOfDay(day, isCurrent)
    -- The strings are local times read back with time{...}; imported jornadas also keep the
    -- epochs (startTs, endTs) for a client where that conversion does not work.
    local low = ns.ParseDateTime(day.startedAt) or (type(day.startTs) == "number" and day.startTs or nil)
    local high = ns.ParseDateTime(day.endedAt) or (type(day.endTs) == "number" and day.endTs or nil)
    local function Widen(stamp)
        if type(stamp) ~= "number" then return end
        if not low or stamp < low then low = stamp end
        if not high or stamp > high then high = stamp end
    end
    if type(day.events) == "table" then
        for _, entry in ipairs(day.events) do
            if type(entry) == "table" then Widen(entry.timestamp) end
        end
    end
    if type(day.conversations) == "table" then
        for _, line in ipairs(day.conversations) do
            if type(line) == "table" then Widen(line.timestamp) end
        end
    end
    if isCurrent and not day.endedAt then high = math.max(high or 0, time()) end
    if low and not high then high = low end
    if high and not low then low = high end
    return low, high
end

-- The "once per jornada" keys (ns.OnceKey) a jornada range already holds, read lazily from its entries
-- and kept up to date with what the plan adds.
local function OnceSeen(range)
    if not range.onceSeen then
        range.onceSeen = {}
        for _, entry in ipairs(range.day.events or {}) do
            if type(entry) == "table" and type(entry.text) == "string" then
                local key = ns.OnceKey(entry.type, entry.text, entry)
                if key then range.onceSeen[key] = true end
            end
        end
    end
    return range.onceSeen
end

-- Returns a plan, or nil and a message for the player.
function ns.PlanImport()
    local probe = _G.AJProbeDB
    if type(probe) ~= "table" then
        return nil, "AJProbe no está instalado o no está activado en este cliente (no existe AJProbeDB). "
            .. "Actívalo en la lista de AddOns, vuelve a entrar al juego y repite /diario importar. No he cambiado nada."
    end
    local key = ns.GetPlayerKey()
    if not key then
        return nil, "No puedo leer el nombre de este personaje ahora mismo. Inténtalo de nuevo fuera de combate. No he cambiado nada."
    end
    local DB = ns.EnsureDatabase()
    local log = type(probe.log) == "table" and probe.log or {}
    local chat = type(probe.chat) == "table" and probe.chat or {}
    if #log == 0 and #chat == 0 then
        return nil, "AJProbe no tiene registros guardados (AJProbeDB.log y AJProbeDB.chat están vacíos). No he cambiado nada."
    end

    local stats = NewStats()
    stats.logRead, stats.chatRead = #log, #chat
    local plan = { key = key, stats = stats, ops = {}, convOps = {}, newDays = {} }
    local conversationsOn = ns.ConversationsEnabled()
    local playerName = ns.StripRealm(key)
    local context = { playerName = playerName }

    -- Sessions: a login starts one; records before the first login belong to a partial one.
    local mine = MyRecords(log, key, stats)
    stats.mine = #mine
    local sessions, current = {}, nil
    for _, item in ipairs(mine) do
        local record = item.r
        if record.e == "PLAYER_ENTERING_WORLD" and record.login == true then
            current = nil
        end
        if not current then
            current = { first = record.t, last = record.t, firstRecord = record, lastRecord = record, records = {} }
            sessions[#sessions + 1] = current
        end
        current.records[#current.records + 1] = item
        if record.t >= current.last then current.last, current.lastRecord = record.t, record end
    end
    stats.sessions = #sessions

    -- The existing jornadas, their time ranges, and what they already hold.
    local ranges = {}
    local known = {}
    for index = 1, DB.currentDay do
        local day = DB.days[index]
        if type(day) == "table" then
            local low, high = RangeOfDay(day, index == DB.currentDay)
            if low then ranges[#ranges + 1] = { day = day, lo = low, hi = high, order = #ranges + 1 } end
            if type(day.events) == "table" then
                for _, entry in ipairs(day.events) do
                    if type(entry) == "table" and type(entry.type) == "string" and type(entry.timestamp) == "number"
                        and type(entry.text) == "string" then
                        Remember(known, entry.type, Subject(entry.type, entry.text, entry), entry.timestamp)
                    end
                end
            end
            if type(day.conversations) == "table" then
                for _, line in ipairs(day.conversations) do
                    if type(line) == "table" and type(line.timestamp) == "number" and type(line.text) == "string" then
                        Remember(known, "CHAT", (line.channel or "") .. "\1" .. (line.who or "") .. "\1" .. line.text, line.timestamp)
                    end
                end
            end
        end
    end
    local existingCount = #ranges

    -- Places already visited, and which zones already have a visited subzone (bug #16: a
    -- zone-only place such as "Durotar" is not a discovery once "Valle de los Retos, Durotar" is).
    local visited = setmetatable({}, { __index = DB.visited })
    local zoneHasSubzone = {}
    for place in pairs(DB.visited) do
        local zone = type(place) == "string" and string.match(place, "^.+, (.+)$")
        if zone then zoneHasSubzone[zone] = true end
    end

    -- The narrowest jornada range that holds time t. A new range belongs to its own session only.
    local function Containing(stamp, session)
        local best, bestSpan
        for index = 1, #ranges do
            local range = ranges[index]
            if (not range.new or range.session == session) and stamp >= range.lo - SLACK and stamp <= range.hi + SLACK then
                local span = range.hi - range.lo
                if not best or span < bestSpan or (span == bestSpan and range.order > best.order) then
                    best, bestSpan = range, span
                end
            end
        end
        return best
    end

    local function NewDay(session)
        local day = {
            startedAt = DateText(session.firstRecord), endedAt = DateText(session.lastRecord),
            dateLabel = DateLabel(session.firstRecord), events = {}, source = "ajprobe",
            startTs = session.first, endTs = session.last,
        }
        local range = { day = day, lo = session.first, hi = session.last, new = true, session = session, order = #ranges + 1 }
        ranges[#ranges + 1] = range
        plan.newDays[#plan.newDays + 1] = range
        stats.newDays = stats.newDays + 1
        return range
    end

    for _, session in ipairs(sessions) do
        -- A session with no existing jornada gets its own, even when it ends up empty: one
        -- jornada per login, as when the addon runs live.
        local overlaps = false
        for index = 1, existingCount do
            local range = ranges[index]
            if session.first - SLACK <= range.hi and session.last + SLACK >= range.lo then overlaps = true break end
        end
        if not overlaps then NewDay(session) end

        for _, item in ipairs(session.records) do
            local record = item.r
            local handler = HANDLERS[record.e]
            if not handler then
                stats.ignored = stats.ignored + 1
            else
                local candidate, reason = handler(record, context)
                if not candidate then
                    if reason == "secret" then stats.secretSkipped = stats.secretSkipped + 1
                    elseif reason == "foreign" then stats.foreign = stats.foreign + 1
                    elseif reason == "noquality" then stats.noQuality = stats.noQuality + 1
                    else stats.ignored = stats.ignored + 1 end
                elseif not ns.IsTypeEnabled(candidate.type) then
                    stats.typeOff = stats.typeOff + 1
                else
                    local kind, text = candidate.type, candidate.text
                    local keep = true
                    if kind == "DISCOVERY" then
                        if visited[text] then
                            stats.revisits = stats.revisits + 1
                            keep = false
                        elseif candidate.zoneOnly and zoneHasSubzone[candidate.zoneName] then
                            stats.zoneOnly = stats.zoneOnly + 1
                            keep = false
                        end
                    elseif candidate.once then
                        -- Once per jornada (the first reputation gain with a faction): a duplicate when
                        -- the jornada this record belongs to already has one. A record that falls in no
                        -- jornada yet starts a new one, which has none.
                        local existing = Containing(record.t, session)
                        local seen = existing and OnceSeen(existing)
                        if seen and seen[candidate.once] then
                            stats.duplicates = stats.duplicates + 1
                            keep = false
                        end
                    else
                        local subject = Subject(kind, text, candidate.extra or {})
                        if IsKnown(known, kind, subject, record.t, WINDOW[kind] or ns.DEDUPE_WINDOW[kind] or 5) then
                            stats.duplicates = stats.duplicates + 1
                            keep = false
                        else
                            Remember(known, kind, subject, record.t)
                        end
                    end
                    if keep then
                        local target = Containing(record.t, session)
                        if not target then target = NewDay(session) end
                        if candidate.once then OnceSeen(target)[candidate.once] = true end
                        if kind == "DISCOVERY" then
                            visited[text] = true
                            if not candidate.zoneOnly then zoneHasSubzone[candidate.zoneName] = true end
                        end
                        if candidate.secret then stats.secretNeutral = stats.secretNeutral + 1 end
                        local where = Where(record)
                        local entry = {
                            type = kind, text = text, place = where.place, zone = where.zone, subZone = where.subZone,
                            time = TimeText(record), timestamp = record.t, source = "ajprobe",
                        }
                        for field, value in pairs(candidate.extra or {}) do entry[field] = value end
                        plan.ops[#plan.ops + 1] = { range = target, entry = entry }
                        stats.added[kind] = (stats.added[kind] or 0) + 1
                        stats.addedTotal = stats.addedTotal + 1
                    end
                end
            end
        end
    end

    -- Conversations: only while the option is on (they are other players' words).
    local chatMine = MyRecords(chat, key, { other = 0, malformed = 0 })
    stats.chatMine = #chatMine
    if not conversationsOn then
        stats.convOff = #chatMine
    else
        local nextSession = 1
        for _, item in ipairs(chatMine) do
            local record = item.r
            local line, reason = ConversationFrom(record)
            if not line then
                if reason == "secret" then stats.convSecret = stats.convSecret + 1 else stats.convIgnored = stats.convIgnored + 1 end
            else
                local subject = (line.channel or "") .. "\1" .. (line.who or "") .. "\1" .. line.text
                if IsKnown(known, "CHAT", subject, line.timestamp, CHAT_WINDOW) then
                    stats.convDuplicates = stats.convDuplicates + 1
                else
                    -- The session this line falls in (sessions and chat are both oldest first).
                    while sessions[nextSession] and sessions[nextSession].last + SLACK < line.timestamp do
                        nextSession = nextSession + 1
                    end
                    local session = sessions[nextSession]
                    if session and line.timestamp < session.first - SLACK then session = nil end
                    local target = Containing(line.timestamp, session)
                    if not target and session then target = NewDay(session) end
                    if not target then
                        stats.convOrphans = stats.convOrphans + 1   -- no jornada and no session to hold it
                    else
                        Remember(known, "CHAT", subject, line.timestamp)
                        plan.convOps[#plan.convOps + 1] = { range = target, line = line }
                        stats.convAdded = stats.convAdded + 1
                    end
                end
            end
        end
    end
    return plan
end

-- Applying --------------------------------------------------------------------------------
-- Inserts `item` into `list` keeping it in time order (after everything not newer than it).
local function InsertByTime(list, item)
    local position = #list
    while position >= 1 and type(list[position]) == "table"
        and type(list[position].timestamp) == "number" and list[position].timestamp > item.timestamp do
        position = position - 1
    end
    table.insert(list, position + 1, item)
    return position + 1
end

function ns.ApplyImport(plan)
    local DB = ns.EnsureDatabase()
    local selectedDay = DB.days[ns.selectedDay]

    -- New jornadas first, in time order, each after the last jornada that started before it.
    -- Existing jornadas keep their order and are not touched; only their numbers can shift.
    if #plan.newDays > 0 then
        local ordered = {}
        for index = 1, DB.currentDay do
            if type(DB.days[index]) == "table" then ordered[#ordered + 1] = DB.days[index] end
        end
        local hadCurrent = #ordered > 0 and DB.currentDay >= 1
        local starts = {}
        for _, day in ipairs(ordered) do starts[day] = (RangeOfDay(day, false)) end
        table.sort(plan.newDays, function(a, b) return a.lo < b.lo end)
        for _, range in ipairs(plan.newDays) do
            local position = 0
            for index, day in ipairs(ordered) do
                if starts[day] and starts[day] <= range.lo then position = index end
            end
            position = position + 1
            -- The jornada being played now stays the last one.
            if hadCurrent and position > #ordered then position = #ordered end
            table.insert(ordered, position, range.day)
            starts[range.day] = range.lo
        end
        for index = 1, math.max(DB.currentDay, #ordered) do DB.days[index] = nil end
        for index, day in ipairs(ordered) do DB.days[index] = day end
        DB.currentDay = #ordered
        for index, day in ipairs(ordered) do
            if day == selectedDay then ns.selectedDay = index end
        end
    end

    for _, op in ipairs(plan.ops) do
        local day, entry = op.range.day, op.entry
        day.events = day.events or {}
        entry.seed = InsertByTime(day.events, entry)
        entry.characterProfile, entry.contextualTone = ns.ChooseMood(entry.type)
        entry.prose = ns.ComposeEntry(entry)
        if entry.type == "DISCOVERY" then DB.visited[entry.text] = true end
    end
    for _, op in ipairs(plan.convOps) do
        local day = op.range.day
        day.conversations = day.conversations or {}
        InsertByTime(day.conversations, op.line)
    end
    ns.RefreshIfVisible()
end

-- The command ---------------------------------------------------------------------------------
local function TypeBreakdown(stats)
    local parts = {}
    for _, info in ipairs(ns.TYPE_INFO) do
        if stats.added[info.key] then parts[#parts + 1] = info.key .. " " .. stats.added[info.key] end
    end
    return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

local function Count(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function PrintSummary(plan, dryRun)
    local s = plan.stats
    Say(string.format("Importación desde AJProbe%s: %d registros de actividad (%d de este personaje, %d de otros) y %d mensajes de chat.",
        dryRun and " (PRUEBA)" or "", s.logRead, s.mine, s.other, s.chatRead))
    Say(string.format("%s: %s%s y %s. Jornadas nuevas: %d.",
        dryRun and "Se añadirían" or "Añadidos", Count(s.addedTotal, "acontecimiento", "acontecimientos"), TypeBreakdown(s),
        Count(s.convAdded, "conversación", "conversaciones"), s.newDays))
    Say(string.format("Omitidos: %d duplicados, %d con valores secretos (%d con texto neutro), %d de tipos desactivados, "
        .. "%d botines sin calidad conocida, %d lugares ya conocidos o sin subzona; %d registros no generan entrada.",
        s.duplicates, s.secretSkipped + s.secretNeutral, s.secretNeutral, s.typeOff, s.noQuality,
        s.revisits + s.zoneOnly, s.ignored + s.foreign))
    if s.chatMine > 0 and s.convOff > 0 then
        Say(string.format("Hay %d mensajes de conversación de este personaje, pero las conversaciones están desactivadas "
            .. "y no se importan. Actívalas con /diario conversaciones on y repite la importación.", s.convOff))
    elseif s.chatMine > 0 then
        Say(string.format("Conversaciones: %d duplicadas, %d secretas, %d fuera de los canales guardados, %d sin jornada.",
            s.convDuplicates, s.convSecret, s.convIgnored, s.convOrphans))
    end
    if s.noQuality > 0 then
        Say("Algunos botines aún no estaban en la memoria del juego: se han pedido. Repite /diario importar en unos segundos.")
    end
    local nothingNew = s.addedTotal == 0 and s.convAdded == 0
    if dryRun then
        Say(string.format("PRUEBA: no se ha guardado nada. Resumen: +%d acontecimientos, +%d conversaciones, %d duplicados.%s",
            s.addedTotal, s.convAdded, s.duplicates, nothingNew and "" or " Escribe /diario importar para importar de verdad."))
    else
        Say(string.format("Resumen: +%d acontecimientos, +%d conversaciones, %d jornadas nuevas, %d duplicados omitidos.%s",
            s.addedTotal, s.convAdded, s.newDays, s.duplicates, nothingNew and " No había nada nuevo que importar." or ""))
    end
end

-- /diario importar [prueba]
function ns.RunImport(dryRun)
    local planned, plan, problem = pcall(ns.PlanImport)
    if not planned then
        Say("La importación falló al leer los datos y no ha cambiado nada: " .. ns.StripPosition(plan))
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler("AdventureJournal: error en /diario importar: " .. tostring(plan)) end
        return
    end
    if not plan then
        Say(tostring(problem))
        return
    end
    ns.lastImport = plan.stats
    if not dryRun then
        local applied, err = pcall(ns.ApplyImport, plan)
        if not applied then
            Say("La importación falló al guardar: " .. ns.StripPosition(err) .. ". Haz /reload y comprueba el diario antes de repetirla.")
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler("AdventureJournal: error al aplicar /diario importar: " .. tostring(err)) end
            return
        end
    end
    PrintSummary(plan, dryRun)
end
