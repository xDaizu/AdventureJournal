-- Scripted play session for AdventureJournal. Mirrors the M0 smoke test plus
-- the edge cases the code handles (dedupe windows, uncached items, group loot,
-- boss double events, every slash command). Runs three times, each on top of the
-- previous run's SavedVariables: a fresh login, a /reload (must continue the same
-- jornada), and a second real login (must start a new one).
local H = ...
local S, fire, advance, slash, note = H.S, H.fire, H.advance, H.slash, H.note

local function UIState(label)
    local f = _G.AdventureJournalBookFrame
    if not f then note(label .. ": book not created") return end
    note(string.format("%s: shown=%s title=%q page=%q prev=%s next=%s", label, tostring(f.shown),
        tostring(f.dayTitle and f.dayTitle.text), tostring(f.pageNumber and f.pageNumber.text),
        tostring(f.prevButton and f.prevButton.enabled), tostring(f.nextButton and f.nextButton.enabled)))
end

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end

S.items[7098] = { name = "Colmillo astillado", quality = 0, cached = true, link = Link("|cff9d9d9d", 7098, "Colmillo astillado") }
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = false, link = Link("|cffa335ee", 5555, "Espada épica") }
S.items[6666] = { name = "Anillo verde", quality = 2, cached = false, link = Link("|cff1eff00", 6666, "Anillo verde") }

local function Days() return AdventureJournalDB.currentDay end

fire("ADDON_LOADED", "SomeOtherAddon")
fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")

if H.mode == "login" or H.mode == "relogin" then
    -- A real login: the zone is still nil when the world loads (observed in M0).
    fire("PLAYER_ENTERING_WORLD", true, false)
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    fire("ZONE_CHANGED_NEW_AREA")
    note(H.mode .. ": currentDay = " .. Days())
else
    -- /reload: the zone is known, and the current jornada continues.
    S.zone, S.subZone = "Durotar", "Valle de los Retos"
    local before = Days()
    local endedAtBefore = AdventureJournalDB.days[before].endedAt
    fire("PLAYER_ENTERING_WORLD", false, true)
    fire("ZONE_CHANGED_NEW_AREA")
    note(string.format("reload: currentDay %d -> %d; endedAt before = %s, after = %s", before, Days(),
        tostring(endedAtBefore), tostring(AdventureJournalDB.days[Days()].endedAt)))
    advance(20); fire("PLAYER_DEAD")
    note("reload: the new entry went into jornada " .. Days() .. ", which now has " .. #AdventureJournalDB.days[Days()].events .. " entries")
    fire("PLAYER_ENTERING_WORLD", false, false)   -- a loading screen inside the game: nothing happens
    note("reload: after another PLAYER_ENTERING_WORLD, currentDay = " .. Days())
    slash("")
    UIState("reload: first /diario")
    slash("")
    UIState("reload: second /diario")
    slash("anterior")
    UIState("reload: /diario anterior (only one jornada exists)")
    slash("hoy")
    UIState("reload: /diario hoy")
    fire("PLAYER_LOGOUT")
    return
end

if H.mode == "relogin" then
    -- Second real login on top of a diary that already has a jornada.
    note("relogin: place already visited, no DISCOVERY expected; jornadas = " .. Days())
    note("relogin: visited places = " .. (function() local n = 0 for _ in pairs(AdventureJournalDB.visited) do n = n + 1 end return n end)())
    note("relogin: UISpecialFrames before the book exists = " .. table.concat(UISpecialFrames, ","))
    slash("")
    UIState("relogin: first /diario")
    note("relogin: UISpecialFrames = " .. table.concat(UISpecialFrames, ","))
    slash("")
    UIState("relogin: second /diario")
    slash("anterior")
    UIState("relogin: /diario anterior")
    slash("hoy")
    UIState("relogin: /diario hoy")
    slash("ABRIR")
    UIState("relogin: /diario ABRIR")
    -- Escape closes the book: the game hides every frame in UISpecialFrames.
    for _, name in ipairs(UISpecialFrames) do if _G[name] then _G[name]:Hide() end end
    UIState("relogin: after Escape")
    -- A blue item that was already settled earlier is not pending any more.
    fire("GET_ITEM_INFO_RECEIVED", 1234, true)
    fire("PLAYER_LOGOUT")
    return
end

advance(10); S.subZone = "El Cubil"; fire("ZONE_CHANGED")
fire("ZONE_CHANGED_INDOORS")                           -- same place: no new entry
advance(4); fire("GOSSIP_SHOW")
advance(5); fire("GOSSIP_SHOW")                        -- same NPC within 20 s: ignored
advance(25); fire("GOSSIP_SHOW")                       -- logged again
S.npcName = nil; advance(1); fire("GOSSIP_SHOW")       -- no name: fallback text

S.questLog = { { title = "Tu lugar en el mundo", questID = 4641 } }
S.questTitles[4641] = "Tu lugar en el mundo"
advance(3); fire("QUEST_TURNED_IN", 4641, 40, 0)
fire("QUEST_TURNED_IN", 4641, 40, 0)                   -- duplicate within 3 s: ignored
S.questLog = {}
advance(1); fire("QUEST_TURNED_IN", 9999, 0, 0)        -- title unknown: ID fallback

advance(14); S.subZone = "Valle de los Retos"; fire("ZONE_CHANGED")   -- revisit: no entry now (bug #5 fixed)
advance(3); S.zone, S.subZone = nil, ""; fire("ZONE_CHANGED")             -- zone not readable yet: ignored
S.zone, S.subZone = "Durotar", "Valle de los Retos"

advance(2); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[7098].link .. ".", "", "", "", "Volgajin")
advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: |cnIQ3:|Hitem:1234::::|h[Escudo azul]|h|r.", "", "", "", "Volgajin")
advance(1); fire("CHAT_MSG_LOOT", "Thrall recibe el botín: " .. S.items[1234].link .. ".", "", "", "", "Thrall")  -- group loot: ignored (bug #6 fixed)
advance(1); fire("CHAT_MSG_LOOT", "Recibes: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")                 -- pushed item
advance(1); fire("CHAT_MSG_LOOT", "Recibes el botín: " .. S.items[1234].link .. "x2.", "", "", "", "Volgajin")     -- stack of two
advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5555].link .. ".", "", "", "", "Volgajin")         -- uncached
S.items[5555].cached = true
fire("GET_ITEM_INFO_RECEIVED", 5555, true)
advance(1); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[6666].link .. ".", "", "", "", "Volgajin")         -- uncached, green
S.items[6666].cached = true
fire("GET_ITEM_INFO_RECEIVED", 6666, true)
fire("GET_ITEM_INFO_RECEIVED", 4242, true)             -- unrelated item
fire("CHAT_MSG_LOOT", "Recibes botín: 3 de plata.", "", "", "", "Volgajin")
fire("CHAT_MSG_LOOT", nil)

advance(30); fire("BOSS_KILL", 1144, "Jefe de prueba")
fire("ENCOUNTER_END", 1144, "Jefe de prueba", 1, 5, 1) -- same boss within 5 s: ignored
advance(1); fire("ENCOUNTER_END", 1145, "Otro jefe", 1, 5, 0)   -- wipe: ignored
advance(1); fire("ENCOUNTER_END", 1145, "Otro jefe", 1, 5, 1)

advance(20); fire("PLAYER_DEAD")
advance(5); fire("CHAT_MSG_WHISPER", "texto privado", "Amigo-OtroReino")
fire("CHAT_MSG_WHISPER", "texto", "")

-- Chat echo: only boss kills, deaths and epic loot by default (settings.chat).
note("chat mode starts as " .. tostring(AdventureJournalDB.settings.chat))
slash("chat")
slash("chat todo");       advance(30); fire("GOSSIP_SHOW")
slash("chat nada");       advance(30); fire("GOSSIP_SHOW"); advance(1); fire("PLAYER_DEAD")
slash("chat importante"); advance(30); fire("GOSSIP_SHOW"); advance(1); fire("PLAYER_DEAD")
slash("chat raro")
note("chat mode ends as " .. tostring(AdventureJournalDB.settings.chat))

UIState("before /diario")
slash("")
UIState("first /diario")
slash("")
UIState("second /diario")
slash("anterior")
UIState("/diario anterior")
slash("hoy")
UIState("/diario hoy")
slash("ABRIR")
UIState("/diario ABRIR")
slash("algo raro")
AdventureJournal_ToggleUI()
UIState("binding toggle")
note("book body:\n" .. tostring(_G.AdventureJournalBookFrame.body.text))

fire("PLAYER_LOGOUT")
