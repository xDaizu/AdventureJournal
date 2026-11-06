-- T2: renders every prose template of every type, for both sexes, and fails on a defect:
-- a leftover "{...}" or "%s", "nil", "..", ". .", a lower-case letter after a full stop, a doubled
-- space, or a header that is empty. It also checks the mood lists and that the choice is deterministic.
local H = ...
local ns, note = H.ns, H.note
local P = ns.PROSE
local failures = {}
local function Fail(where, text, why)
    failures[#failures + 1] = string.format("%s: %s -> %q", where, why, text)
end

local function Check(where, text, isHeader)
    if type(text) ~= "string" or text == "" then return Fail(where, tostring(text), "empty") end
    if string.find(text, "[{}]") then Fail(where, text, "leftover brace") end
    if string.find(text, "%%[sd]") then Fail(where, text, "leftover %s") end
    if string.find(text, "nil") then Fail(where, text, "nil") end
    if string.find(text, "%.%.") then Fail(where, text, "double dot") end
    if string.find(text, "%. %.") then Fail(where, text, "dot space dot") end
    if string.find(text, "  ") then Fail(where, text, "double space") end
    if string.find(text, "%. %l") then Fail(where, text, "lower case after full stop") end
    if string.find(text, "^%l") then Fail(where, text, "starts in lower case") end
    if not isHeader and string.find(text, "[%.!»%)]$") == nil then Fail(where, text, "no final stop") end
end

local TONE = "con el ánimo firme y la mente despejada."
local counts = {}

-- Entry shapes per template list. `unnamed` variants are rendered too.
local function Render(label, entry)
    for _, female in ipairs({ false, true }) do
        local prose, header = ns.ComposeEntry(entry, female)
        local where = label .. (female and " [f]" or " [m]") .. " seed=" .. tostring(entry.seed)
        Check(where, prose)
        if header ~= nil then Check(where .. " header", header, true) end
        counts[label] = (counts[label] or 0) + 1
    end
end

local function Seeds(n) return n end
local SHAPES = {
    { "QUEST", { type = "QUEST", text = "La masacre de Rocadura" }, 20 },
    { "QUEST unnamed", { type = "QUEST", text = ns.NEUTRAL_TEXT.QUEST }, 10 },
    { "QUEST id", { type = "QUEST", text = "una misión (ID 123)" }, 10 },
    { "QUEST_ACCEPT", { type = "QUEST_ACCEPT", text = "Cuernos rotos", npc = "Gornek" }, 20 },
    { "QUEST_ACCEPT no npc", { type = "QUEST_ACCEPT", text = "Cuernos rotos" }, 20 },
    { "QUEST_ACCEPT unnamed", { type = "QUEST_ACCEPT", text = ns.NEUTRAL_TEXT.QUEST, npc = "Gornek" }, 8 },
    { "BOSS", { type = "BOSS", text = "Hogger" }, 20 },
    { "BOSS unnamed", { type = "BOSS", text = ns.NEUTRAL_TEXT.BOSS }, 20 },
    { "DEATH killer", { type = "DEATH", text = "He caído en combate", killer = "Hogger" }, 20 },
    { "DEATH none", { type = "DEATH", text = "He caído en combate" }, 20 },
    { "LOOT", { type = "LOOT", text = "[Espada rúnica]" }, 20 },
    { "LEVEL", { type = "LEVEL", text = "He alcanzado el nivel 12", level = 12 }, 20 },
    { "LEVEL unnamed", { type = "LEVEL", text = ns.NEUTRAL_TEXT.LEVEL }, 10 },
    { "NPC", { type = "NPC", text = "Gornek" }, 20 },
    { "CHAT", { type = "CHAT", text = "Thrall" }, 10 },
    { "GROUP join", { type = "GROUP", text = "Jaina", groupEvent = "join" }, 10 },
    { "GROUP leave", { type = "GROUP", text = "Jaina", groupEvent = "leave" }, 10 },
    { "GROUP selfleave", { type = "GROUP", text = "He dejado el grupo", groupEvent = "selfleave" }, 10 },
    { "GROUP disband", { type = "GROUP", text = "Mi grupo se ha disuelto", groupEvent = "disband" }, 10 },
    { "GROUP youjoin", { type = "GROUP", text = "un grupo", groupEvent = "youjoin" }, 10 },
    { "GROUP other", { type = "GROUP", text = "x" }, 2 },
    { "REPUTATION gain", { type = "REPUTATION", text = "Orgrimmar", repEvent = "gain" }, 10 },
    { "REPUTATION standing", { type = "REPUTATION", text = "Orgrimmar", repEvent = "standing", standing = "Amistoso" }, 10 },
    { "SKILL new", { type = "SKILL", text = "Herrería", skillEvent = "new" }, 10 },
    { "SKILL rank", { type = "SKILL", text = "Herrería", skillEvent = "rank", rank = 50 }, 10 },
    { "SPELL spell", { type = "SPELL", text = "Inmolar", learnKind = "spell" }, 10 },
    { "SPELL ability", { type = "SPELL", text = "Carga", learnKind = "ability" }, 10 },
    { "SPELL passive", { type = "SPELL", text = "Maestría", learnKind = "passive" }, 10 },
    { "MOUNT", { type = "MOUNT", text = "Lobo veloz" }, 10 },
    { "FLIGHT_POINT", { type = "FLIGHT_POINT", text = "x" }, 10 },
    { "GUILD join", { type = "GUILD", text = "Los Errantes" }, 10 },
    { "GUILD leave", { type = "GUILD", text = "Los Errantes", guildEvent = "leave" }, 10 },
    { "ACHIEVEMENT", { type = "ACHIEVEMENT", text = "Explorador" }, 10 },
    { "DISCOVERY", { type = "DISCOVERY", text = "Valle de los Retos, Durotar" }, 3 },
    { "REVISIT", { type = "REVISIT", text = "Valle de los Retos, Durotar" }, 3 },
}
for _, shape in ipairs(SHAPES) do
    for seed = 1, shape[3] + 1 do
        local entry = {}
        for k, v in pairs(shape[2]) do entry[k] = v end
        entry.place, entry.seed, entry.contextualTone = "Durotar", seed, TONE
        Render(shape[1], entry)
    end
end
-- Every travel method, discovery and revisit, every header.
for _, method in ipairs({ "HEARTHSTONE", "TELEPORT", "TAXI", "ON_FOOT", "bogus" }) do
    for _, kind in ipairs({ "DISCOVERY", "REVISIT" }) do
        for seed = 1, 4 do
            Render(kind .. " " .. method, { type = kind, text = "Orgrimmar", place = "Orgrimmar", travelMethod = method,
                seed = seed, contextualTone = TONE })
        end
    end
end
-- Tones with and without the final stop, an empty tone, a missing tone, a weird seed, a secret-free hostile name.
Render("tone without stop", { type = "LOOT", text = "x", place = "p", seed = 1, contextualTone = "con calma" })
Render("tone empty", { type = "LOOT", text = "x", place = "p", seed = 1, contextualTone = "" })
Render("tone missing", { type = "LOOT", text = "x", place = "p", seed = 1 })
Render("seed missing", { type = "LOOT", text = "x", place = "p", contextualTone = TONE })
Render("seed negative", { type = "LOOT", text = "x", place = "p", seed = -7, contextualTone = TONE })
Render("seed fraction", { type = "LOOT", text = "x", place = "p", seed = 2.5, contextualTone = TONE })
Render("name with braces", { type = "LOOT", text = "[Cinta {a|b} %s]", place = "p", seed = 1, contextualTone = TONE })
-- (the brace name trips the brace check on purpose: it must reach the output untouched)
local braceProse = ns.ComposeEntry({ type = "LOOT", text = "[Cinta {a|b} %s]", place = "p", seed = 1, contextualTone = TONE })
assert(string.find(braceProse, "[Cinta {a|b} %s]", 1, true), "a name with braces was altered: " .. braceProse)
-- Remove the three failures that the brace test caused deliberately.
local kept = {}
for _, f in ipairs(failures) do
    if not string.find(f, "name with braces", 1, true) then kept[#kept + 1] = f end
end
failures = kept

-- Unknown types fall back to the text.
assert(ns.ComposeEntry({ type = "WHATEVER", text = "hola" }) == "hola", "unknown type fallback")

-- Moods: every list item, both sexes; the label is non-empty; the phrase carries no final stop.
for category, list in pairs(P.MOODS) do
    assert(#list == 20, category .. " must have 20 phrases, has " .. #list)
    for index, item in ipairs(list) do
        for _, female in ipairs({ false, true }) do
            local phrase = type(item) == "table" and item[1] or item
            local text = P.Gender(phrase, female)
            if string.find(text, "[{}%.]") then Fail("mood " .. category .. index, text, "bad mood phrase") end
        end
    end
end
for _, eventType in ipairs({ "QUEST", "BOSS", "DEATH", "LOOT", "DISCOVERY", "REVISIT", "LEVEL", "NPC" }) do
    local label, tone = ns.ChooseMood(eventType, true)
    if type(label) ~= "string" or label == "" or string.find(label, "[{}]") then Fail("label " .. eventType, tostring(label), "bad label") end
    if type(tone) ~= "string" or tone == "" or string.find(tone, "[{}%.]") then Fail("tone " .. eventType, tostring(tone), "bad tone") end
end

-- Template sizes: Chema's counts.
local EXPECT = { QUEST = 20, QUEST_ACCEPT = 20, BOSS = 20, DEATH = 20, LOOT = 20, LEVEL = 20, NPC = 20,
    MOUNT = 10, FLIGHT_POINT = 10, GUILD_join = 10, ACHIEVEMENT = 10,
    CHAT = 10, GROUP_join = 10, GROUP_leave = 10, GROUP_selfleave = 10, GROUP_disband = 10, GROUP_youjoin = 10,
    REPUTATION_gain = 10, REPUTATION_standing = 10, SKILL_new = 10, SKILL_rank = 10, SPELL = 10, GUILD_leave = 10 }
for key, n in pairs(EXPECT) do
    assert(#P.TEMPLATES[key] == n, key .. " should have " .. n .. " variants, has " .. #P.TEMPLATES[key])
end

-- Determinism: same entry, same text.
local e = { type = "BOSS", text = "Hogger", place = "Durotar", seed = 5, contextualTone = TONE }
assert(ns.ComposeEntry(e, false) == ns.ComposeEntry(e, false), "not deterministic")
-- The sexes differ where a word agrees with the player (BOSS variant 7, seed 6).
local a = ns.ComposeEntry({ type = "BOSS", text = "Hogger", place = "x", seed = 6, contextualTone = TONE }, false)
local b = ns.ComposeEntry({ type = "BOSS", text = "Hogger", place = "x", seed = 6, contextualTone = TONE }, true)
assert(a ~= b and string.find(a, "victorioso") and string.find(b, "victoriosa"), "gender variants: " .. a .. " / " .. b)

-- PlayerIsFemale follows UnitSex, and a secret or a failing call is masculine.
local realUnitSex = UnitSex
UnitSex = function() return 3 end
assert(ns.PlayerIsFemale() == true, "sex 3")
UnitSex = function() return 2 end
assert(ns.PlayerIsFemale() == false, "sex 2")
UnitSex = function() return H.S.SECRET_NUMBER end
assert(ns.PlayerIsFemale() == false, "secret sex")
UnitSex = function() error("boom") end
assert(ns.PlayerIsFemale() == false, "failing UnitSex")
UnitSex = nil
assert(ns.PlayerIsFemale() == false, "no UnitSex")
UnitSex = realUnitSex

local keys = {}
for k in pairs(counts) do keys[#keys + 1] = k end
table.sort(keys)
local total = 0
for _, k in ipairs(keys) do total = total + counts[k] end
note(string.format("%d renders of %d shapes, %d failures", total, #keys, #failures))
for _, f in ipairs(failures) do note("FAIL " .. f) end
if #failures > 0 then error(#failures .. " prose defect(s); first: " .. failures[1]) end
