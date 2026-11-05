-- Messages.lua (M6): turns what the game says into diary entries for the types added in M6
-- (LEVEL, GROUP, REPUTATION, SKILL, SPELL). The live handlers (Events.lua) and the AJProbe import
-- (Import.lua) both call these functions, so a live entry and an imported one are the same entry
-- and read the same.
--
-- A "candidate" is { type = "LEVEL", text = "...", extra = { ...fields stored in the entry },
-- secret = true when a neutral text stands in for an unreadable value }.
--
-- Every parser takes plain strings or numbers only. The callers check ns.IsSecret first: a secret
-- never gets here. Patterns come from the client's own global strings (ns.GlobalFormats), never from
-- a literal in one language.
local addonName, ns = ...

-- Seconds within which two entries of the same type and subject are the same event. Used by the
-- live handlers and, for the import, against both the diary and the records of the same run.
ns.DEDUPE_WINDOW = { LEVEL = 10, GROUP = 3 }

-- The subject two entries must share to be the same event, for the M6 types; nil for any other
-- type (Import.lua has its own rule for those). `source` is the entry or candidate extra table.
function ns.NewTypeSubject(kind, text, source)
    if kind == "LEVEL" then
        if type(source.level) == "number" then return "level:" .. source.level end
        return text
    end
    if kind == "GROUP" then return (source.groupEvent or "") .. "\1" .. text end
    return nil
end

-- A message from the system chat (CHAT_MSG_SYSTEM) -> a candidate for one of the types below, or nil.
-- Never called with a secret; the caller checks.
function ns.SystemMessageCandidate(message)
    if type(message) ~= "string" then return nil end
    return ns.GroupCandidate(message)
end

-- LEVEL -------------------------------------------------------------------------------
-- PLAYER_LEVEL_UP: the new level is the first argument. An unreadable level (a secret, or not a
-- number) gives the neutral text, without a number.
function ns.LevelCandidate(level)
    if not ns.IsSecret(level) and type(level) == "number" and level >= 1 and level == math.floor(level) then
        return { type = "LEVEL", text = string.format("He alcanzado el nivel %d", level), extra = { level = level } }
    end
    return { type = "LEVEL", text = ns.NEUTRAL_TEXT.LEVEL, secret = true }
end

-- GROUP -------------------------------------------------------------------------------
-- Who joined or left the player's group, from the system messages. The names come from the
-- client's own strings. The message carries the name, GROUP_JOINED does not (and AJProbe's records
-- show GROUP_JOINED firing when a group is formed, even before anybody accepted):
--   join       "<Name> se une al grupo."          ERR_JOINED_GROUP_S, ERR_RAID_MEMBER_ADDED_S
--   leave      "<Name> deja el grupo."            ERR_LEFT_GROUP_S, ERR_RAID_MEMBER_REMOVED_S
--   selfleave  "Dejas el grupo."                  ERR_LEFT_GROUP_YOU
--   disband    "Tu grupo se ha disuelto."         ERR_GROUP_DISBANDED
--   youjoin    GROUP_JOINED of an instance group  no names (the system messages are not reliable there)
local GROUP_GLOBALS = {
    "ERR_JOINED_GROUP_S", "ERR_RAID_MEMBER_ADDED_S", "ERR_LEFT_GROUP_S", "ERR_RAID_MEMBER_REMOVED_S",
    "ERR_LEFT_GROUP_YOU", "ERR_GROUP_DISBANDED",
}
local GROUP_KIND = {
    ERR_JOINED_GROUP_S = "join", ERR_RAID_MEMBER_ADDED_S = "join",
    ERR_LEFT_GROUP_S = "leave", ERR_RAID_MEMBER_REMOVED_S = "leave",
    ERR_LEFT_GROUP_YOU = "selfleave", ERR_GROUP_DISBANDED = "disband",
}
local GROUP_TEXT = {
    selfleave = "He dejado el grupo",
    disband = "Mi grupo se ha disuelto",
    youjoin = "un grupo",
}

function ns.GetGroupFormats()
    return ns.GlobalFormats("group", GROUP_GLOBALS)
end

function ns.GroupCandidate(message)
    local item, values = ns.MatchFormats(ns.GetGroupFormats(), message)
    if not item then return nil end
    local kind = GROUP_KIND[item.name]
    local text = GROUP_TEXT[kind]
    if not text then
        text = ns.PlayerNameFromText(values[1])
        if not text then return nil end
    end
    return { type = "GROUP", text = text, extra = { groupEvent = kind } }
end

-- GROUP_JOINED(partyCategory, partyGUID): only a group of the instance category (a dungeon group
-- put together by the game) makes an entry, with no names.
function ns.GroupJoinedCandidate(category)
    if ns.IsSecret(category) or type(category) ~= "number" then return nil end
    if category ~= (LE_PARTY_CATEGORY_INSTANCE or 2) then return nil end
    return { type = "GROUP", text = GROUP_TEXT.youjoin, extra = { groupEvent = "youjoin" } }
end
