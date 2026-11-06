-- Events.lua: event registration and handlers, entry creation, session start/end.
local addonName, ns = ...
local SafeString = ns.SafeString

local eventFrame = CreateFrame("Frame")
local currentPlace = ""
local sessionStarted = false
local lastQuestID, lastQuestAt
local lastBossName, lastBossAt
local lastNPCName, lastNPCTime
local pendingLoot = {}   -- [itemID] = itemLink, waiting for GET_ITEM_INFO_RECEIVED
local pendingGiver       -- T4a: { name, at } the quest giver seen at QUEST_DETAIL
local lastAcceptID, lastAcceptAt
local transport          -- T4a: { method, expires } the last hearthstone / teleport cast
local lastEnemy          -- T4a: name of the hostile non-player target when combat began
local sessionGuild       -- T4a: the last guild name read, so a leave can say which guild

-- Chat echo policy (bug: spam). settings.chat: "all", "important" (default) or "off".
-- Important = boss kills, deaths and epic (or better) loot.
function ns.ShouldEchoToChat(entry)
    local settings = ns.DB and ns.DB.settings
    local mode = settings and settings.chat or ns.DEFAULT_SETTINGS.chat
    if mode == "all" then return true end
    if mode == "off" then return false end
    return entry.type == "BOSS" or entry.type == "DEATH"
        or (entry.type == "LOOT" and (tonumber(entry.itemQuality) or 0) >= 4)
end

function ns.AddEntry(eventType, description, extra)
    local DB = ns.DB
    if not DB then return end
    local day = DB.days[DB.currentDay]
    if not day then return end

    -- A type the player switched off is not logged. The handlers have already updated
    -- their dedupe state and the visited places by now, so switching a type on again
    -- does not replay what happened while it was off.
    if not ns.IsTypeEnabled(eventType) then
        ns.Debug("AddEntry: tipo %s desactivado en las opciones, no se anota", tostring(eventType))
        return
    end

    local profile, tone = ns.ChooseMood(eventType)
    local entry = {
        type = eventType,
        text = SafeString(description, "Acontecimiento sin descripción"),
        place = ns.GetPlace(),
        zone = SafeString(ns.GetZoneText(), "Desconocido"),
        subZone = SafeString(ns.GetSubZoneText(), ""),
        time = date("%H:%M:%S"),
        timestamp = time(),
        characterProfile = profile,
        contextualTone = tone,
        seed = #(day.events or {}) + 1,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            -- Secrets cannot be saved (they would become nil); drop them.
            if ns.IsSecret(value) then
                ns.Debug("AddEntry: campo %s descartado por ser secreto", tostring(key))
            else
                entry[key] = value
            end
        end
    end
    entry.prose, entry.header = ns.ComposeEntry(entry)
    day.events = day.events or {}
    table.insert(day.events, entry)
    ns.RefreshIfVisible()
    if ns.ShouldEchoToChat(entry) then
        print(string.format("|cFF00FF00[Diario]|r %s", entry.text))
    end
end

-- A real login starts a new jornada. A /reload continues the current one: the
-- game fires PLAYER_LOGOUT on a reload, so `endedAt` is cleared again.
-- PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi) tells them apart; it also
-- fires on every loading screen, hence the sessionStarted guard.
local function StartSession(isReloadingUi)
    if sessionStarted then return end
    sessionStarted = true
    local DB = ns.EnsureDatabase()

    local resumable = DB.days[DB.currentDay]
    if isReloadingUi and DB.currentDay >= 1 and type(resumable) == "table" then
        resumable.endedAt = nil
        ns.selectedDay = DB.currentDay
        currentPlace = ns.GetPlace()
        if ns.GetZoneText() and not ns.IsSecret(ns.GetZoneText()) then DB.visited[currentPlace] = true end
        print(string.format("|cFFFFD700[Diario]|r Continúas la jornada %d.", DB.currentDay))
        return
    end

    DB.currentDay = DB.currentDay + 1
    local n = DB.currentDay
    DB.days[n] = {
        startedAt = date("%Y-%m-%d %H:%M:%S"),
        dateLabel = date("%d/%m/%Y"),
        events = {},
    }
    ns.selectedDay = n
    currentPlace = ns.GetPlace()
    print(string.format("|cFFFFD700[Diario]|r Comienza la jornada %d. Tu historia continúa.", n))
end

-- Returns false only while the item is not cached yet (keep it pending). Returns
-- true once it is settled: logged, or dropped for being below settings.lootQuality (bug #11;
-- rare by default, epic in the "clasico" profile).
local function TryLogLoot(itemLink, itemID)
    local _, _, quality = ns.GetItemInfoSafe(itemLink or itemID)
    if not quality then return false end
    if quality >= ns.GetLootQuality() then
        local displayLink = itemLink
        if not displayLink then
            local _, link = ns.GetItemInfoSafe(itemID)
            displayLink = link
        end
        ns.AddEntry("LOOT", displayLink or ("un objeto (ID " .. tostring(itemID) .. ")"), {
            itemQuality = quality,
            itemLink = displayLink,
            itemID = itemID,
        })
    end
    return true
end

-- Dedupe for the M6 types: the same subject within its window (ns.DEDUPE_WINDOW) is one event.
local recentSubjects = {}
local function IsRepeat(kind, subject)
    local key = kind .. "" .. subject
    local now = time()
    local last = recentSubjects[key]
    recentSubjects[key] = now
    return last ~= nil and now - last <= (ns.DEDUPE_WINDOW[kind] or 5)
end

-- Logs a candidate from Messages.lua unless it repeats a recent one.
local function LogCandidate(candidate)
    local subject = ns.NewTypeSubject(candidate.type, candidate.text, candidate.extra or {}) or candidate.text
    if IsRepeat(candidate.type, subject) then return end
    ns.AddEntry(candidate.type, candidate.text, candidate.extra)
end

local handlers = {}

handlers.ADDON_LOADED = function(loadedName)
    if loadedName == addonName then
        ns.EnsureDatabase()
        -- M4b: the conversation events are registered only while the option is on.
        if ns.UpdateConversationEvents then ns.UpdateConversationEvents() end
    end
end

-- T4b: the mounts the player already has are known, so none of them is logged as new. Chema's tables
-- (`knownMounts`, `knownAchievements`, keys are tostring(id)) are used as they are and only ever
-- added to. `mountsSeeded` is this line's own flag: his scan never worked (bug), so his table cannot
-- tell whether the journal was ever read. Nothing is seeded while the journal gives no mounts (not
-- loaded yet): the next try is later.
local function KnownTable(name)
    local DB = ns.DB
    if type(DB[name]) ~= "table" then DB[name] = {} end
    return DB[name]
end

local function SeedKnownMounts()
    local DB = ns.DB
    if not DB or DB.mountsSeeded == true then return true end
    local ids = ns.GetMountIDs()
    if not ids then return false end
    local known = KnownTable("knownMounts")
    for _, mountID in ipairs(ids) do
        local _, collected = ns.GetMountInfo(mountID)
        if collected then known[tostring(mountID)] = true end
    end
    DB.mountsSeeded = true
    return true
end

local function ScheduleMountSeed()
    if not ns.HasMountJournal() then return end
    if not (C_Timer and C_Timer.After) then SeedKnownMounts() return end
    C_Timer.After(5, function()
        if not SeedKnownMounts() then C_Timer.After(30, SeedKnownMounts) end
    end)
end

handlers.PLAYER_ENTERING_WORLD = function(_, isReloadingUi)
    sessionGuild = ns.CurrentGuildName() or sessionGuild
    StartSession(isReloadingUi == true)
    ScheduleMountSeed()
end

handlers.PLAYER_LOGOUT = function()
    local DB = ns.DB
    if DB and DB.days and DB.days[DB.currentDay] then
        DB.days[DB.currentDay].endedAt = date("%Y-%m-%d %H:%M:%S")
    end
end

handlers.QUEST_TURNED_IN = function(questID)
    if ns.IsSecret(questID) then
        ns.Debug("QUEST_TURNED_IN: questID secreto, se usa el texto neutro")
        questID = nil
    end
    if not questID or questID ~= lastQuestID or not lastQuestAt or time() - lastQuestAt > 3 then
        lastQuestID, lastQuestAt = questID, time()
        ns.AddEntry("QUEST", ns.GetQuestTitle(questID), { questID = questID })
    end
end

local UNKNOWN_BOSS = ns.NEUTRAL_TEXT.BOSS

handlers.BOSS_KILL = function(_, bossName)
    if ns.IsSecret(bossName) then ns.Debug("BOSS_KILL: nombre secreto, se usa el texto neutro") end
    bossName = SafeString(bossName, UNKNOWN_BOSS)
    if bossName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
        lastBossName, lastBossAt = bossName, time()
        ns.AddEntry("BOSS", bossName)
    end
end

handlers.ENCOUNTER_END = function(_, encounterName, _, _, success)
    -- Without a readable success flag we cannot tell a kill from a wipe. BOSS_KILL
    -- covers the kill, so skip.
    if ns.IsSecret(success) then
        ns.Debug("ENCOUNTER_END: success secreto, se ignora")
        return
    end
    if success == 1 and encounterName then
        if ns.IsSecret(encounterName) then
            ns.Debug("ENCOUNTER_END: nombre secreto, se usa el texto neutro")
            encounterName = UNKNOWN_BOSS
        end
        if encounterName ~= lastBossName or not lastBossAt or time() - lastBossAt > 5 then
            lastBossName, lastBossAt = encounterName, time()
            ns.AddEntry("BOSS", encounterName)
        end
    end
end

handlers.PLAYER_DEAD = function()
    -- deathKiller (T4a): the enemy fought when combat began. There is no combat log, so it is not
    -- known to be the killer; the prose says so. With the setting off nothing is added.
    local extra
    if lastEnemy and ns.GetSetting("deathKiller") == true then extra = { killer = lastEnemy } end
    lastEnemy = nil
    ns.AddEntry("DEATH", "He caído en combate", extra)
end

-- T4a: the last hostile non-player target when combat starts. UnitName and the unit tests can be
-- secret inside instances: then nothing is kept and the death entry names no one.
handlers.PLAYER_REGEN_DISABLED = function()
    lastEnemy = nil
    if ns.GetSetting("deathKiller") ~= true then return end
    if not (UnitCanAttack and UnitIsPlayer) then return end
    local name = ns.UnitNameSafe("target")
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return end
    local okAttack, canAttack = pcall(UnitCanAttack, "player", "target")
    local okPlayer, isPlayer = pcall(UnitIsPlayer, "target")
    if not (okAttack and okPlayer) or ns.IsSecret(canAttack) or ns.IsSecret(isPlayer) then return end
    if canAttack == true and isPlayer ~= true and isPlayer ~= 1 then lastEnemy = name end
end

-- Combat ended without dying: the enemy no longer explains a later death (a fall, say). If the
-- player is dead here, PLAYER_DEAD still needs it.
handlers.PLAYER_REGEN_ENABLED = function()
    local dead = false
    if UnitIsDeadOrGhost then
        local ok, result = pcall(UnitIsDeadOrGhost, "player")
        dead = ok and not ns.IsSecret(result) and result == true
    end
    if not dead then lastEnemy = nil end
end

handlers.CHAT_MSG_LOOT = function(message)
    if ns.IsSecret(message) then
        -- The item cannot be read, so there is nothing to log.
        ns.Debug("CHAT_MSG_LOOT: mensaje secreto, se omite")
        return
    end
    -- Loot switched off: skip the item lookups (and the pending list) as well.
    if not ns.IsTypeEnabled("LOOT") then
        ns.Debug("CHAT_MSG_LOOT: botín desactivado en las opciones, se omite")
        return
    end
    if type(message) == "string" then
        if not ns.IsOwnLootMessage(message) then
            ns.Debug("CHAT_MSG_LOOT: botín de otro jugador, se omite")
            return
        end
        -- Any colour prefix: |cffRRGGBB (Classic Era) or |cnIQ<n>: (possibly Forever).
        local itemLink = string.match(message, "|c[^|]*|Hitem:.-|h%[.-%]|h|r")
        if itemLink then
            local itemID = tonumber(string.match(itemLink, "|Hitem:(%d+)"))
            if not TryLogLoot(itemLink, itemID) and itemID then
                pendingLoot[itemID] = itemLink
                ns.RequestItemData(itemID)
            end
        end
    end
end

-- Also handles ITEM_DATA_LOAD_RESULT (same arguments: itemID, success).
handlers.GET_ITEM_INFO_RECEIVED = function(itemID, success)
    if ns.IsSecret(itemID) or ns.IsSecret(success) then return end
    local link = itemID and pendingLoot[itemID]
    if link then
        pendingLoot[itemID] = nil
        if success then TryLogLoot(link, itemID) end
    end
end
handlers.ITEM_DATA_LOAD_RESULT = handlers.GET_ITEM_INFO_RECEIVED

-- T4a: how the player got here. Hearthstone and teleports are casts (by spell ID, not name), seen
-- at UNIT_SPELLCAST_SUCCEEDED and valid for a minute (Chema's line never expired them). A taxi is
-- read from UnitOnTaxi at the zone change. The list is a starting point: a cast that is not in it
-- reads as on foot; add its ID after seeing it with /diario debug on.
local TRAVEL_SPELLS = {
    [8690] = "HEARTHSTONE",     -- Hearthstone
    [556] = "HEARTHSTONE",      -- Astral Recall
    [3561] = "TELEPORT", [3562] = "TELEPORT", [3563] = "TELEPORT", [3565] = "TELEPORT",
    [3566] = "TELEPORT", [3567] = "TELEPORT",                      -- mage teleports (vanilla cities)
    [10059] = "TELEPORT", [11416] = "TELEPORT", [11417] = "TELEPORT", [11418] = "TELEPORT",
    [11419] = "TELEPORT", [11420] = "TELEPORT",                    -- mage portals (vanilla cities)
    [18960] = "TELEPORT",       -- Teleport: Moonglade
    [50977] = "TELEPORT",       -- Death Gate
}
ns.TRAVEL_SPELLS = TRAVEL_SPELLS
local TRANSPORT_SECONDS = 60

handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if ns.IsSecret(unit) or unit ~= "player" then return end
    if ns.IsSecret(spellID) or type(spellID) ~= "number" then return end
    local method = TRAVEL_SPELLS[spellID]
    if method then transport = { method = method, expires = time() + TRANSPORT_SECONDS } end
end

-- The travel method of this place change; every change uses up the last cast.
local function TakeTravelMethod()
    local method = "ON_FOOT"
    if ns.IsPlayerOnTaxi() then
        method = "TAXI"
    elseif transport and time() <= transport.expires then
        method = transport.method
    end
    transport = nil
    return method
end

-- A DISCOVERY is logged only the first time a place is seen (DB.visited); a place seen before is a
-- REVISIT (off by default).
local function OnZoneChanged()
    -- An unreadable zone is not a discovery: skip it instead of logging "unknown lands".
    local zone = ns.GetZoneText()
    if ns.IsSecret(zone) or ns.IsSecret(ns.GetSubZoneText()) then
        ns.Debug("ZONE_CHANGED: nombre de zona secreto, se omite")
        return
    end
    -- GetRealZoneText() can be nil right after a fresh login (observed).
    if not zone or zone == "" then return end
    local newPlace = ns.GetPlace()
    if newPlace ~= currentPlace then
        currentPlace = newPlace
        local method = TakeTravelMethod()
        local visited = ns.DB and ns.DB.visited
        if visited then
            if not visited[newPlace] then
                visited[newPlace] = true
                ns.AddEntry("DISCOVERY", newPlace, { travelMethod = method })
            else
                ns.AddEntry("REVISIT", newPlace, { travelMethod = method })
            end
        end
    end
end
handlers.ZONE_CHANGED_NEW_AREA = OnZoneChanged
handlers.ZONE_CHANGED = OnZoneChanged
handlers.ZONE_CHANGED_INDOORS = OnZoneChanged
handlers.MINIMAP_ZONE_CHANGED = OnZoneChanged

-- T4a: the quest giver, kept from the moment the quest is offered until it is accepted. A quest
-- with no NPC (from an item) clears it, so a giver is never carried over to another quest.
handlers.QUEST_DETAIL = function()
    pendingGiver = nil
    local name = ns.UnitNameSafe("npc")
    if ns.IsSecret(name) then
        ns.Debug("QUEST_DETAIL: nombre del PNJ secreto, no se guarda")
        return
    end
    if type(name) == "string" and name ~= "" then pendingGiver = { name = name, at = time() } end
end

local GIVER_SECONDS = 120

handlers.QUEST_ACCEPTED = function(first, second)
    local questID = ns.QuestIDFromAccepted(first, second)
    if ns.IsSecret(first) or ns.IsSecret(second) then ns.Debug("QUEST_ACCEPTED: argumento secreto") end
    local giver = pendingGiver
    pendingGiver = nil
    if questID and questID == lastAcceptID and lastAcceptAt and time() - lastAcceptAt <= ns.DEDUPE_WINDOW.QUEST_ACCEPT then
        return
    end
    lastAcceptID, lastAcceptAt = questID, time()
    local extra = { questID = questID }
    if giver and time() - giver.at <= GIVER_SECONDS then extra.npc = giver.name end
    ns.AddEntry("QUEST_ACCEPT", ns.GetQuestTitle(questID), extra)
end

-- T4a: the guild's name, kept so that leaving can say which guild it was.
handlers.PLAYER_GUILD_UPDATE = function()
    sessionGuild = ns.CurrentGuildName() or sessionGuild
end

-- T4b: NEW_MOUNT_ADDED(mountID). Once per mount ever (knownMounts); the name comes from the journal.
handlers.NEW_MOUNT_ADDED = function(mountID)
    if not ns.IsTypeEnabled("MOUNT") then return end   -- off (or no journal): the known tables are not touched
    if ns.IsSecret(mountID) or type(mountID) ~= "number" then
        ns.Debug("NEW_MOUNT_ADDED: ID ilegible, se omite")
        return
    end
    local known = KnownTable("knownMounts")
    local key = tostring(mountID)
    if known[key] then return end
    known[key] = true
    local candidate = ns.MountCandidate(mountID)
    if candidate then ns.AddEntry("MOUNT", candidate.text, candidate.extra) end
    SeedKnownMounts()   -- after the entry: the union includes this mount, which is already known
end

-- T4b: ACHIEVEMENT_EARNED(achievementID, alreadyEarned). Once per achievement ever (knownAchievements).
-- The payload is from Warcraft Wiki: not observed on Forever (no achievement was earned while AJProbe ran).
handlers.ACHIEVEMENT_EARNED = function(achievementID, alreadyEarned)
    if not ns.IsTypeEnabled("ACHIEVEMENT") then return end   -- off (or no achievements): the known tables are not touched
    if ns.IsSecret(achievementID) or type(achievementID) ~= "number" then
        ns.Debug("ACHIEVEMENT_EARNED: ID ilegible, se omite")
        return
    end
    local known = KnownTable("knownAchievements")
    local key = tostring(achievementID)
    if known[key] then return end
    known[key] = true
    if not ns.IsSecret(alreadyEarned) and alreadyEarned == true then return end   -- earned before (an alt, say)
    local candidate = ns.AchievementCandidate(achievementID)
    if candidate then ns.AddEntry("ACHIEVEMENT", candidate.text, candidate.extra) end
end

handlers.GOSSIP_SHOW = function()
    local rawName = ns.UnitNameSafe("npc")
    if ns.IsSecret(rawName) then ns.Debug("GOSSIP_SHOW: nombre del PNJ secreto, se usa el texto neutro") end
    local npcName = SafeString(rawName, ns.NEUTRAL_TEXT.NPC)
    if npcName ~= lastNPCName or not lastNPCTime or time() - lastNPCTime > 20 then
        lastNPCName, lastNPCTime = npcName, time()
        ns.AddEntry("NPC", npcName)
    end
end

-- Stores the sender name only, never the message text (privacy; see README).
handlers.CHAT_MSG_WHISPER = function(_, sender)
    if ns.IsSecret(sender) then
        ns.Debug("CHAT_MSG_WHISPER: remitente secreto, se usa el texto neutro")
        ns.AddEntry("CHAT", ns.NEUTRAL_TEXT.SENDER)
    elseif type(sender) == "string" and sender ~= "" then
        sender = string.match(sender, "^([^%-]+)") or sender
        ns.AddEntry("CHAT", sender)
    end
end

-- M6: the level reached. The new level is the first argument.
handlers.PLAYER_LEVEL_UP = function(level)
    if not ns.IsTypeEnabled("LEVEL") then return end
    if ns.IsSecret(level) then ns.Debug("PLAYER_LEVEL_UP: nivel secreto, se usa el texto neutro") end
    LogCandidate(ns.LevelCandidate(level))
end

-- M6: the system chat. Group joins and leaves arrive here by name. Skipped when unreadable (a secret
-- message in an instance), so nothing is guessed.
handlers.CHAT_MSG_SYSTEM = function(message)
    if not (ns.IsTypeEnabled("GROUP") or ns.IsTypeEnabled("SPELL") or ns.IsTypeEnabled("GUILD")) then return end
    if ns.IsSecret(message) then
        ns.Debug("CHAT_MSG_SYSTEM: mensaje secreto, se omite")
        return
    end
    local candidate = ns.SystemMessageCandidate(message, {
        playerName = ns.SafeString(ns.UnitNameSafe("player"), nil),
        guildName = ns.CurrentGuildName(),
        lastGuildName = sessionGuild,
    })
    if candidate and candidate.type == "GUILD" then
        -- Remember which guild the next leave is about.
        if candidate.extra.guildEvent == "leave" then
            sessionGuild = nil
        elseif candidate.text ~= ns.NEUTRAL_TEXT.GUILD then
            sessionGuild = candidate.text
        end
    end
    if candidate and ns.IsTypeEnabled(candidate.type) then LogCandidate(candidate) end
end

-- M6: reputation. The first gain with each faction in each jornada, and every change of standing.
-- `firstGainSeen` remembers the factions already logged in the current jornada; it is rebuilt from
-- the diary when the jornada changes, so a /reload does not log them a second time.
local firstGainSeen = { day = nil, keys = {} }

local function FirstGainKeys()
    local DB = ns.DB
    local day = DB and DB.days[DB.currentDay]
    if firstGainSeen.day ~= day then
        firstGainSeen.day, firstGainSeen.keys = day, {}
        if day and type(day.events) == "table" then
            for _, entry in ipairs(day.events) do
                if type(entry) == "table" and type(entry.text) == "string" then
                    local key = ns.OnceKey(entry.type, entry.text, entry)
                    if key then firstGainSeen.keys[key] = true end
                end
            end
        end
    end
    return firstGainSeen.keys
end

handlers.CHAT_MSG_COMBAT_FACTION_CHANGE = function(message)
    if not ns.IsTypeEnabled("REPUTATION") then return end
    if ns.IsSecret(message) then
        ns.Debug("CHAT_MSG_COMBAT_FACTION_CHANGE: mensaje secreto, se omite")
        return
    end
    local candidate = ns.ReputationCandidate(message)
    if not candidate then return end
    if candidate.once then
        local keys = FirstGainKeys()
        if keys[candidate.once] then return end
        keys[candidate.once] = true
    end
    LogCandidate(candidate)
end

-- M6: skills. A new skill, and a skill reaching a multiple of ns.SKILL_STEP.
handlers.CHAT_MSG_SKILL = function(message)
    if not ns.IsTypeEnabled("SKILL") then return end
    if ns.IsSecret(message) then
        ns.Debug("CHAT_MSG_SKILL: mensaje secreto, se omite")
        return
    end
    local candidate = ns.SkillCandidate(message)
    if candidate then LogCandidate(candidate) end
end

-- M6: GROUP_JOINED(partyCategory, partyGUID). Only a dungeon group is logged, without names.
handlers.GROUP_JOINED = function(category)
    if not ns.IsTypeEnabled("GROUP") then return end
    if ns.IsSecret(category) then
        ns.Debug("GROUP_JOINED: categoría secreta, se omite")
        return
    end
    local candidate = ns.GroupJoinedCandidate(category)
    if candidate then LogCandidate(candidate) end
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "QUEST_TURNED_IN", "BOSS_KILL", "ENCOUNTER_END", "PLAYER_DEAD",
    "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED",
    "GOSSIP_SHOW", "CHAT_MSG_WHISPER",
    "PLAYER_LEVEL_UP", "CHAT_MSG_SYSTEM", "GROUP_JOINED",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_SKILL",
    "QUEST_DETAIL", "QUEST_ACCEPTED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_GUILD_UPDATE",
    "NEW_MOUNT_ADDED", "ACHIEVEMENT_EARNED",
}
ns.EVENTS = EVENTS
for _, eventName in ipairs(EVENTS) do ns.RegisterEventSafe(eventFrame, eventName) end
-- Casts of the player only (hearthstone, teleports): a unit event, so no other unit's casts arrive.
ns.RegisterUnitEventSafe(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- Error isolation: a failing handler never stops the others. Each event name is
-- reported once to the game's error handler (so scriptErrors / BugSack show it);
-- later failures are only counted. /diario diag lists them.
ns.handlerErrors = {}   -- [event] = { count = n, message = first error }

local function ReportHandlerError(event, err)
    local record = ns.handlerErrors[event]
    if record then
        record.count = record.count + 1
        return
    end
    ns.handlerErrors[event] = { count = 1, message = tostring(err) }
    local text = string.format("AdventureJournal: error en el manejador de %s: %s", event, tostring(err))
    ns.Debug("%s", text)
    local errorHandler = geterrorhandler and geterrorhandler()
    if errorHandler then errorHandler(text) end
end

local function LogPayload(event, ...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = ns.Describe((select(index, ...)))
    end
    ns.Debug("%s(%s)", event, table.concat(parts, ", "))
end

-- One dispatcher per frame: it runs the handler for the event under pcall, applies the
-- simulated secrets of `/diario debug secrets` and prints the payload in debug mode.
-- Conversations.lua builds a second frame with it, so its handlers get the same treatment.
function ns.MakeDispatcher(handlerTable)
    return function(_, event, ...)
        local handler = handlerTable[event]
        if not handler then return end
        local ok, err
        if ns.debug.on or ns.debug.secrets then
            local args = { n = select("#", ...), ... }
            if ns.debug.secrets and event ~= "ADDON_LOADED" then
                for index = 1, args.n do args[index] = ns.Taint(args[index]) end
            end
            if ns.debug.on then LogPayload(event, unpack(args, 1, args.n)) end
            ok, err = pcall(handler, unpack(args, 1, args.n))
        else
            ok, err = pcall(handler, ...)
        end
        if not ok then ReportHandlerError(event, err) end
    end
end

eventFrame:SetScript("OnEvent", ns.MakeDispatcher(handlers))
