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
ns.DEDUPE_WINDOW = { LEVEL = 10, GROUP = 3, REPUTATION = 10, SKILL = 30, SPELL = 5 }

-- A skill entry is made for a new skill and every time a skill reaches a multiple of this
-- (user's choice 2026-11-05: "new + every 25 points"). Stateless on purpose: the live game and the
-- import apply the same rule to the same message.
ns.SKILL_STEP = 25

-- The subject two entries must share to be the same event, for the M6 types; nil for any other
-- type (Import.lua has its own rule for those). `source` is the entry or candidate extra table.
function ns.NewTypeSubject(kind, text, source)
    if kind == "LEVEL" then
        if type(source.level) == "number" then return "level:" .. source.level end
        return text
    end
    if kind == "GROUP" then return (source.groupEvent or "") .. "\1" .. text end
    if kind == "REPUTATION" then
        return (source.repEvent or "") .. "\1" .. text .. "\1" .. (source.standing or "")
    end
    if kind == "SKILL" then
        return (source.skillEvent or "") .. "\1" .. text .. "\1" .. tostring(source.rank or "")
    end
    if kind == "SPELL" then
        if type(source.spellID) == "number" then return "spell:" .. source.spellID end
        return text
    end
    return nil
end

-- Some entries happen once per jornada instead of once per time window: the first reputation gain
-- with each faction. Returns the key, or nil for an entry that has no such rule. `source` is the
-- entry (or the candidate's extra table).
function ns.OnceKey(kind, text, source)
    if kind == "REPUTATION" and source.repEvent == "gain" then return "rep\1" .. text end
    return nil
end

-- A name out of a game message: colour codes dropped, nil when nothing is left.
local function CleanName(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    if text == "" then return nil end
    return text
end

-- A message from the system chat (CHAT_MSG_SYSTEM) -> a candidate for one of the types below, or nil.
-- Never called with a secret; the caller checks.
function ns.SystemMessageCandidate(message)
    if type(message) ~= "string" then return nil end
    return ns.GroupCandidate(message) or ns.SpellCandidate(message)
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

-- REPUTATION --------------------------------------------------------------------------
-- CHAT_MSG_COMBAT_FACTION_CHANGE. Two kinds of entry (user's choice 2026-11-05):
--   gain      the FIRST reputation gain with each faction in each jornada, no figures
--             (FACTION_STANDING_INCREASED...; Classic Era and Forever word it differently, observed)
--   standing  the standing changed ("Ahora eres Amistoso con X"; FACTION_STANDING_CHANGED...)
-- Every global that starts with those names is used, so the variants (bonus, generic...) are covered
-- on whichever client; the faction is argument 1 of an increase, the standing argument 1 and the
-- faction argument 2 of a change (the order of the English strings; a translation that reorders
-- uses positional arguments, which the pattern builder honours).
function ns.GetReputationFormats()
    return ns.GlobalFormats("repgain", { "FACTION_STANDING_INCREASED" }, "FACTION_STANDING_INCREASED"),
        ns.GlobalFormats("repstanding", { "FACTION_STANDING_CHANGED" }, "FACTION_STANDING_CHANGED")
end

function ns.ReputationCandidate(message)
    if type(message) ~= "string" then return nil end
    local gains, changes = ns.GetReputationFormats()
    local item, values = ns.MatchFormats(changes, message)
    if item then
        local standing, faction = CleanName(values[1]), CleanName(values[2])
        if standing and faction then
            return { type = "REPUTATION", text = faction, extra = { repEvent = "standing", standing = standing } }
        end
        return nil
    end
    item, values = ns.MatchFormats(gains, message)
    if item then
        local faction = CleanName(values[1])
        if not faction then return nil end
        local extra = { repEvent = "gain" }
        return { type = "REPUTATION", text = faction, extra = extra, once = ns.OnceKey("REPUTATION", faction, extra) }
    end
    return nil
end

-- SKILL -------------------------------------------------------------------------------
-- CHAT_MSG_SKILL. A new skill ("Has ganado la siguiente habilidad: X", ERR_SKILL_GAINED_S) and a skill
-- reaching a multiple of ns.SKILL_STEP ("Tu habilidad en X ha subido a N.", ERR_SKILL_UP_SI). Every
-- ERR_SKILL_* string is read and classified by its arguments (a name and a number: a rank; a name
-- alone: a new skill), so a variant this client words differently is still understood.
function ns.GetSkillFormats()
    local formats = ns.GlobalFormats("skill", { "ERR_SKILL_UP_SI", "ERR_SKILL_GAINED_S" }, "ERR_SKILL_")
    for _, item in ipairs(formats) do
        if item.skillKind == nil then
            local order = item.compiled.order
            local names, numbers = 0, 0
            for _, spec in ipairs(order) do
                if spec.number then numbers = numbers + 1 else names = names + 1 end
            end
            if names == 1 and numbers == 1 and #order == 2 then item.skillKind = "rank"
            elseif names == 1 and numbers == 0 and #order == 1 then item.skillKind = "new"
            else item.skillKind = false end
        end
    end
    return formats
end

-- Returns a candidate; or nil and "ignored" (a message that is not a skill, or a skill-up that is not
-- on the threshold).
function ns.SkillCandidate(message)
    if type(message) ~= "string" then return nil, "ignored" end
    for _, item in ipairs(ns.GetSkillFormats()) do
        if item.skillKind then
            local values = ns.MatchFormat(item.compiled, message)
            if values then
                local name, rank
                for index, spec in ipairs(item.compiled.order) do
                    if spec.number then rank = values[spec.arg] else name = CleanName(values[spec.arg]) end
                end
                if not name then return nil, "ignored" end
                if item.skillKind == "new" then
                    return { type = "SKILL", text = name, extra = { skillEvent = "new" } }
                end
                if type(rank) ~= "number" or rank < ns.SKILL_STEP or rank % ns.SKILL_STEP ~= 0 then
                    return nil, "ignored"
                end
                return { type = "SKILL", text = name, extra = { skillEvent = "rank", rank = rank } }
            end
        end
    end
    return nil, "ignored"
end

-- SPELL -------------------------------------------------------------------------------
-- "Has aprendido un nuevo hechizo: [Inmolar]." in the system chat (ERR_LEARN_SPELL_S, and the ability
-- and passive forms). Each spell, and each rank (a rank is another spell ID), is one entry. The
-- spell link in the message gives the ID and the name; without a link the whole text is the name.
local SPELL_KIND = { ERR_LEARN_SPELL_S = "spell", ERR_LEARN_ABILITY_S = "ability", ERR_LEARN_PASSIVE_S = "passive" }

function ns.SpellCandidate(message)
    local formats = ns.GlobalFormats("spell", { "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_PASSIVE_S" })
    local item, values = ns.MatchFormats(formats, message)
    if not item then return nil end
    local shown = values[1]
    local name = string.match(shown, "|h%[(.-)%]|h") or CleanName(shown)
    if not name or name == "" then return nil end
    local spellID = tonumber(string.match(shown, "|Hspell:(%d+)"))
    return { type = "SPELL", text = name, extra = { spellID = spellID, learnKind = SPELL_KIND[item.name] } }
end

-- Diagnostics (/diario diag): which of the client's strings each M6 type found. A type with "ninguna"
-- cannot match anything on this client, so check the global names with /dump.
function ns.GetMessageStatus()
    local function names(list, extra)
        local out = {}
        for _, item in ipairs(list) do out[#out + 1] = item.name .. (extra and extra(item) or "") end
        return #out > 0 and table.concat(out, ", ") or "ninguna"
    end
    local gains, changes = ns.GetReputationFormats()
    return {
        { "Mensajes de grupo (de 6)", names(ns.GetGroupFormats()) },
        { "Mensajes de reputación: subidas", names(gains) },
        { "Mensajes de reputación: cambios de nivel", names(changes) },
        { "Mensajes de habilidades", names(ns.GetSkillFormats(), function(item) return " [" .. tostring(item.skillKind or "no se usa") .. "]" end) },
        { "Mensajes de hechizos (de 3)", names(ns.GlobalFormats("spell", { "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_PASSIVE_S" })) },
    }
end

-- Round trip (/diario diag mensajes): for every string a type reads, builds a sample sentence from the
-- client's own format with invented values, feeds it to the same parser the game events use and says
-- what came out. It touches nothing (no entry is made). If a line says NO, the client's sentence does
-- not match what the parser expects (a different argument order, a different shape).
local function FillFormat(format, values)
    local text = string.gsub(format, "%%(%d+)%$[sdifg]", function(index) return tostring(values[tonumber(index)]) end)
    local nextArg = 0
    text = string.gsub(text, "%%([%-%+ #0]*%d*%.?%d*[sdifg%%])", function(spec)
        if spec == "%" then return "%" end
        nextArg = nextArg + 1
        return tostring(values[nextArg])
    end)
    return text
end

function ns.SelfTestMessages()
    local rows = {}
    local function add(name, sample, result, ok)
        rows[#rows + 1] = { name, string.format("«%s» -> %s", sample, result), ok }
    end
    local function describe(candidate)
        if not candidate then return "NO lo reconoce", false end
        local detail = candidate.type .. " " .. tostring(candidate.extra and (candidate.extra.groupEvent or candidate.extra.repEvent
            or candidate.extra.skillEvent or candidate.extra.learnKind) or "") .. " «" .. tostring(candidate.text) .. "»"
        if candidate.extra and candidate.extra.standing then detail = detail .. " (nivel «" .. candidate.extra.standing .. "»)" end
        if candidate.extra and candidate.extra.rank then detail = detail .. " (" .. candidate.extra.rank .. ")" end
        return detail, true
    end
    for _, item in ipairs(ns.GetGroupFormats()) do
        local sample = FillFormat(item.format, { "Prueba" })
        local result, ok = describe(ns.GroupCandidate(sample))
        add(item.name, sample, result, ok)
    end
    local gains, changes = ns.GetReputationFormats()
    for _, item in ipairs(gains) do
        local sample = FillFormat(item.format, { "Prueba", 25, 25 })
        local candidate = ns.ReputationCandidate(sample)
        local result, ok = describe(candidate)
        add(item.name, sample, result, ok and candidate.text == "Prueba")
    end
    for _, item in ipairs(changes) do
        local sample = FillFormat(item.format, { "Amistoso", "Prueba" })
        local candidate = ns.ReputationCandidate(sample)
        local result, ok = describe(candidate)
        add(item.name, sample, result, ok and candidate.text == "Prueba" and candidate.extra.standing == "Amistoso")
    end
    for _, item in ipairs(ns.GetSkillFormats()) do
        if item.skillKind then
            local sample = FillFormat(item.format, { "Prueba", 50 })
            local candidate = ns.SkillCandidate(sample)
            local result, ok = describe(candidate)
            add(item.name, sample, result, ok and candidate.text == "Prueba")
        end
    end
    for _, name in ipairs({ "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_PASSIVE_S" }) do
        local format = _G[name]
        if type(format) == "string" then
            local sample = FillFormat(format, { "|cff71d5ff|Hspell:1:0|h[Prueba]|h|r" })
            local candidate = ns.SpellCandidate(sample)
            local result, ok = describe(candidate)
            add(name, sample, result, ok and candidate.text == "Prueba" and candidate.extra.spellID == 1)
        end
    end
    return rows
end
