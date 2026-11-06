-- M5: a generated diary of 250 jornadas with 20 entries each (a schema v2 diary saved before
-- M5, so its settings table only has `chat`). The book must stay cheap: with a ScrollBox the
-- index creates frames for the visible rows only; the fallback (old buttons) creates one
-- Button per jornada, which is exactly what M5 set out to avoid, so the run reports it and
-- does not fail. Stub variants: noscrollbox (functions missing), noscrolltemplates (functions
-- exist, templates do not), both ending in the button index.
-- What this cannot show: how the real ScrollBox lays rows out or scrolls (see tools/README.md).
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns
H.noDump = true   -- 5000 entries do not belong in a report

local DAYS, PER_DAY = 250, 20
local TYPES = { "QUEST", "BOSS", "DEATH", "LOOT", "DISCOVERY", "NPC", "CHAT" }

AdventureJournalDB = { version = 2, currentDay = DAYS, visited = {}, settings = { chat = "off" }, days = {} }
for day = 1, DAYS do
    local events = {}
    for index = 1, PER_DAY do
        local kind = TYPES[(day + index) % #TYPES + 1]
        events[index] = {
            type = kind, text = "Asunto " .. day .. "." .. index,
            prose = "Anotación " .. index .. " de la jornada " .. day .. ".",
            place = "Durotar", zone = "Durotar", subZone = "",
            time = string.format("%02d:%02d:00", index % 24, day % 60), timestamp = 1793815000 + day * 1000 + index,
            -- Every other jornada predates the mood: no characterProfile at all.
            characterProfile = (day % 2 == 0) and "Heroico" or nil,
            contextualTone = (day % 2 == 0) and "con el ánimo firme" or nil, seed = index,
        }
    end
    AdventureJournalDB.days[day] = { startedAt = "2026-11-04 10:00:00", endedAt = "2026-11-04 11:00:00",
        dateLabel = "04/11/2026", events = events }
end

fire("ADDON_LOADED", "AdventureJournal")
local settings = AdventureJournalDB.settings
local typesOn = 0
for _, on in pairs(settings.types) do if on then typesOn = typesOn + 1 end end
note(string.format("old v2 diary loaded: version %d, settings.chat kept = %s, defaults added: showProfile=%s, %d types on",
    AdventureJournalDB.version, tostring(settings.chat), tostring(settings.showProfile), typesOn))
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
note("after login: currentDay = " .. AdventureJournalDB.currentDay)

local function FrameCount() return #S.frames end
local function Book() return _G.AdventureJournalBookFrame end

-- Opening the book builds it and fills the index.
local framesBefore = FrameCount()
slash("")
local created = FrameCount() - framesBefore
local book = Book()
note("index mode: " .. ns.GetIndexMode())
note("frames created by opening the book once: " .. (created > 80 and "more than 80 (" .. created .. ")" or "at most 80 (" .. created .. ")"))
if book.indexMode == "scrollbox" then
    -- The point of M5: the cost does not depend on the number of jornadas.
    assert(created <= 80, "the ScrollBox index created " .. created .. " frames for " .. (DAYS + 1) .. " jornadas")
    note("ScrollBox rows created: " .. #book.indexBox.pool .. " (visible rows + 1) for " .. (DAYS + 1) .. " jornadas")
else
    note("fallback buttons created: " .. (function() local n = 0 for _ in pairs(book.dayButtons) do n = n + 1 end return n end)()
        .. " (one per jornada, as before M5)")
end
note("book shows: " .. tostring(book.dayTitle.text) .. ", page " .. tostring(book.pageNumber.text))

-- Refreshing (an entry arrives while the book is open) must not create frames.
local framesOpen = FrameCount()
for _ = 1, 20 do advance(2); fire("PLAYER_DEAD") end
note("20 entries added while the book is open: new frames = " .. (FrameCount() - framesOpen)
    .. ", jornada " .. AdventureJournalDB.currentDay .. " now has " .. #AdventureJournalDB.days[AdventureJournalDB.currentDay].events .. " entries")
slash("hoy"); slash("anterior"); slash("hoy")
note("after /diario hoy, anterior, hoy: new frames = " .. (FrameCount() - framesOpen))

-- Choosing a jornada from the index.
local function IndexRowFor(day)
    if book.indexBox then
        for _, frame in ipairs(book.indexBox.pool) do
            if frame.shown and frame.elementData == day then return frame end
        end
        return nil
    end
    return book.dayButtons[day]
end
local top = IndexRowFor(AdventureJournalDB.currentDay)
note("newest jornada is in the index: " .. tostring(top ~= nil) .. "; its label: " .. tostring(top and top.text))
if book.indexBox then
    note("jornada 100 on screen before scrolling: " .. tostring(IndexRowFor(100) ~= nil))
    S.ScrollStubTo(book.indexBox, DAYS + 1 - 100 - 5)   -- row `offset + 1` is on top; the index is newest first
    local row = IndexRowFor(100)
    note("jornada 100 on screen after scrolling: " .. tostring(row ~= nil) .. "; its label: " .. tostring(row and row.text))
    row.scripts.OnClick(row)
else
    IndexRowFor(100).scripts.OnClick(IndexRowFor(100))
end
note("clicked jornada 100: " .. tostring(book.dayTitle.text) .. ", page " .. tostring(book.pageNumber.text))
slash("animo on")
note("jornada 100 (has a mood), mood shown, first lines: " .. string.sub(book.body.text, 1, 60):gsub("\n", " | "))
ns.SelectDay(101)
note("jornada 101 (no mood stored), mood shown, first lines: " .. string.sub(book.body.text, 1, 60):gsub("\n", " | "))
ns.SelectDay(1)
slash("")   -- hide
note("selected 1, then hidden: shown = " .. tostring(book.shown))
note("frames in total at the end: " .. (FrameCount() - framesBefore) .. " since before the book existed")
local errorCount = 0
for _ in pairs(ns.handlerErrors) do errorCount = errorCount + 1 end
note("handler errors = " .. errorCount .. "; errors reaching the game's error handler = " .. #S.errors)
fire("PLAYER_LOGOUT")
