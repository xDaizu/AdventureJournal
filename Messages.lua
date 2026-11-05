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
ns.DEDUPE_WINDOW = { LEVEL = 10 }

-- The subject two entries must share to be the same event, for the M6 types; nil for any other
-- type (Import.lua has its own rule for those). `source` is the entry or candidate extra table.
function ns.NewTypeSubject(kind, text, source)
    if kind == "LEVEL" then
        if type(source.level) == "number" then return "level:" .. source.level end
        return text
    end
    return nil
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
