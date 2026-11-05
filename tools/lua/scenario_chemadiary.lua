-- T1: a diary written by Chema's Forever line (1.1.0-Forever, github.com/xDaizu/AdventureJournal main
-- at fa20e9f) is loaded by this line. The fixture is hand-written in the shape that code saves (its
-- Events.lua EnsureDatabase / EnsureSessionStarted / AddEntry), quirks included: `version = 2`,
-- `visitedZones` / `knownMounts` / `knownAchievements` and no `settings` or `visited`, `mainZone` on
-- each jornada and never an `endedAt`, the entry types that line has and this one does not
-- (QUEST_ACCEPT, REVISIT, MOUNT, ACHIEVEMENT, GUILD), `header` and `travelMethod`, mood phrases
-- ending in a full stop, lower-case sentences after a full stop, and its "un jefe poderoso" boss.
--
-- Variants (H.variant):
--   chema      that diary, in three modes (login, /reload, second login): the "clasico" profile is
--              applied once and only once, Chema's places are not discovered again, every key and
--              jornada of Chema's is byte-identical afterwards, the profile's choices are in effect.
--   roundtrip  one of this line's diaries after the player went back to Chema's version for a while:
--              `settings` exists (so no profile is applied and the player's choices stay), `version`
--              was reset to 2, and Chema's version added a place to `visitedZones` and a jornada.
--              Also ns.ApplyProfile and hand-edited values of the new settings.
local H = ...
local S, fire, advance, slash, note = H.S, H.fire, H.advance, H.slash, H.note

-- Deterministic text of a value, to compare tables byte for byte.
local function Text(value, indent)
    indent = indent or ""
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = indent .. "  [" .. tostring(k) .. "] = " .. Text(value[k], indent .. "  ") end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = true, link = Link("|cffa335ee", 5555, "Espada épica") }

-- A diary as Chema's Forever line saves it after three sessions (the second one a /reload, which
-- that line turns into a jornada of its own).
local function ChemaDiary()
    return {
        version = 2,
        currentDay = 3,
        visitedZones = { ["Valle de los Retos, Durotar"] = true, ["El Cubil, Durotar"] = true, ["Orgrimmar"] = true },
        knownMounts = { ["6"] = true },
        knownAchievements = { ["6"] = true },
        days = {
            [1] = {
                startedAt = "2026-11-04 18:57:25", dateLabel = "04/11/2026", mainZone = "Valle de los Retos, Durotar",
                events = {
                    { type = "DISCOVERY", text = "Valle de los Retos, Durotar", place = "Valle de los Retos, Durotar",
                      time = "18:57:25", timestamp = 1793815045, contextualTone = "con la curiosidad a flor de piel.",
                      seed = 42, travelMethod = "ON_FOOT", header = "Llegada a Valle de los Retos, Durotar",
                      prose = "Descubrí por primera vez la región de Valle de los Retos, Durotar a pie de camino. con la curiosidad a flor de piel." },
                    { type = "QUEST_ACCEPT", text = "Tu lugar en el mundo", npc = "Gornek", questID = 4641,
                      place = "Valle de los Retos, Durotar", time = "18:59:02", timestamp = 1793815142,
                      contextualTone = "con el ánimo firme y la mente despejada.", seed = 17,
                      prose = "Acepté el encargo «Tu lugar en el mundo» de manos de Gornek mientras me encontraba en Valle de los Retos, Durotar. con el ánimo firme y la mente despejada." },
                    { type = "DISCOVERY", text = "El Cubil, Durotar", place = "El Cubil, Durotar",
                      time = "19:01:20", timestamp = 1793815280, contextualTone = "con la curiosidad a flor de piel.",
                      seed = 63, travelMethod = "ON_FOOT", header = "Nuevos Horizontes: El Cubil, Durotar",
                      prose = "Descubrí por primera vez la región de El Cubil, Durotar a pie de camino. con la curiosidad a flor de piel." },
                    { type = "QUEST", text = "Tu lugar en el mundo", place = "El Cubil, Durotar",
                      time = "19:01:27", timestamp = 1793815287, contextualTone = "procurando no confiarme demasiado.", seed = 88,
                      prose = "Al fin concluyó el encargo «Tu lugar en el mundo» en El Cubil, Durotar. procurando no confiarme demasiado." },
                    { type = "REVISIT", text = "Valle de los Retos, Durotar", place = "Valle de los Retos, Durotar",
                      time = "19:05:40", timestamp = 1793815540, contextualTone = "avanzando con paso firme por un camino ya conocido.",
                      seed = 9, travelMethod = "ON_FOOT", header = "Regreso a Valle de los Retos, Durotar",
                      prose = "Volví a recorrer a pie las tierras de Valle de los Retos, Durotar. avanzando con paso firme por un camino ya conocido." },
                },
            },
            [2] = {
                startedAt = "2026-11-04 19:20:03", dateLabel = "04/11/2026", mainZone = "Orgrimmar",
                events = {
                    { type = "DISCOVERY", text = "Orgrimmar", place = "Orgrimmar", time = "19:22:10", timestamp = 1793816530,
                      contextualTone = "maravillado por la atmósfera singular de este paraje.", seed = 31, travelMethod = "TAXI",
                      header = "Vuelo hacia Orgrimmar",
                      prose = "Aterricé en Orgrimmar tras completar la travesía en grifo/mantícora. maravillado por la atmósfera singular de este paraje." },
                    { type = "MOUNT", text = "Lobo de las nieves", mountID = 6, place = "Orgrimmar", time = "19:30:00",
                      timestamp = 1793817000, contextualTone = "con el ánimo firme y la mente despejada.", seed = 4,
                      prose = "Conseguí la montura Lobo de las nieves en Orgrimmar. Una adición notable para las largas travesías." },
                    { type = "ACHIEVEMENT", text = "Acontecimiento sin descripción", achievementID = 6, place = "Orgrimmar",
                      time = "19:31:00", timestamp = 1793817060, contextualTone = "con el ánimo firme y la mente despejada.", seed = 77,
                      prose = "Completé con éxito el logro «Acontecimiento sin descripción» mientras exploraba Orgrimmar." },
                },
            },
            [3] = {
                startedAt = "2026-11-04 20:02:41", dateLabel = "04/11/2026", mainZone = "Orgrimmar",
                events = {
                    { type = "GUILD", text = "Los Errantes", place = "Orgrimmar", time = "20:02:50", timestamp = 1793818970,
                      contextualTone = "con el ánimo firme y la mente despejada.", seed = 55,
                      prose = "Me sumé a las filas de «Los Errantes» con la intención de defender su nombre y sus colores." },
                    { type = "DEATH", text = "He caído en combate", killer = "Jabalí moteado", place = "Valle de los Retos, Durotar",
                      time = "20:15:12", timestamp = 1793819712, contextualTone = "maldiciendo mi suerte y jurando venganza.", seed = 23,
                      prose = "Caí derrotado por Jabalí moteado en Valle de los Retos, Durotar. Regresaré para saldar esta cuenta. maldiciendo mi suerte y jurando venganza." },
                    { type = "BOSS", text = "un jefe poderoso", place = "Sima Ígnea", time = "20:40:00", timestamp = 1793821200,
                      contextualTone = "con el ánimo firme y la mente despejada.", seed = 12,
                      prose = "Logré doblegar a un jefe poderoso en las tierras de Sima Ígnea. con el ánimo firme y la mente despejada." },
                    { type = "LOOT", text = Link("|cffa335ee", 5555, "Espada épica"), place = "Sima Ígnea", time = "20:41:00",
                      timestamp = 1793821260, contextualTone = "con el ánimo firme y la mente despejada.", seed = 60,
                      prose = "El botín cobrado en Sima Ígnea incluyó " .. Link("|cffa335ee", 5555, "Espada épica") .. ". con el ánimo firme y la mente despejada." },
                },
            },
        },
    }
end

-- Everything of Chema's that this line must never change.
local CHEMA_KEYS = { "visitedZones", "knownMounts", "knownAchievements" }
local function CheckChemaUntouched(label, reference, oldDays)
    local db = AdventureJournalDB
    for _, key in ipairs(CHEMA_KEYS) do
        assert(Text(db[key]) == Text(reference[key]), label .. ": " .. key .. " changed")
    end
    for _, day in ipairs(oldDays) do
        assert(Text(db.days[day]) == Text(reference.days[day]), label .. ": jornada " .. day .. " changed")
    end
    note(label .. ": " .. table.concat(CHEMA_KEYS, ", ") .. " and jornadas " .. table.concat(oldDays, ", ")
        .. " are byte-identical to the diary as it was saved before this load")
end

local function Settings(label)
    local db = AdventureJournalDB
    local s = db.settings
    local off = {}
    for _, info in ipairs(H.ns.TYPE_INFO) do
        if not H.ns.IsTypeEnabled(info.key) then off[#off + 1] = info.key end
    end
    local chema = {}
    for _, key in ipairs({ "QUEST_ACCEPT", "REVISIT", "MOUNT", "ACHIEVEMENT", "GUILD" }) do
        chema[#chema + 1] = key .. "=" .. tostring(s.types[key])
    end
    note(string.format("%s: version=%s origin=%s profile=%s chat=%s lootQuality=%s showProfile=%s conversations=%s",
        label, tostring(db.version), tostring(db.origin), tostring(s.profile), tostring(s.chat), tostring(s.lootQuality),
        tostring(s.showProfile), tostring(s.conversations)))
    note(label .. ": types off = " .. (#off > 0 and table.concat(off, ", ") or "none") .. "; Chema's types (for T4): " .. table.concat(chema, ", "))
    note(label .. ": visited places = " .. Count(db.visited))
end

local function NewEntries(label, day)
    local list = {}
    for _, entry in ipairs(AdventureJournalDB.days[day].events) do
        list[#list + 1] = entry.type .. " «" .. tostring(entry.text) .. "»"
    end
    note(label .. ": jornada " .. day .. " has " .. #list .. " entries: " .. table.concat(list, "; "))
end

if H.variant == "chema" then
    if H.mode == "login" then AdventureJournalDB = ChemaDiary() end
    local reference = ChemaDiary()

    fire("ADDON_LOADED", "AdventureJournal")
    Settings(H.mode .. ": after ADDON_LOADED")
    CheckChemaUntouched(H.mode .. ": after load", reference, { 1, 2, 3 })
    fire("ADDON_LOADED", "AdventureJournal")   -- idempotent: nothing is applied twice
    fire("PLAYER_LOGIN")

    if H.mode == "login" then
        fire("PLAYER_ENTERING_WORLD", true, false)
        note("login: currentDay " .. AdventureJournalDB.currentDay .. " (a new jornada after Chema's three)")
        -- Places Chema's version already saw: not discovered again.
        S.zone, S.subZone = "Durotar", "Valle de los Retos"; fire("ZONE_CHANGED_NEW_AREA")
        advance(10); S.subZone = "El Cubil"; fire("ZONE_CHANGED")
        advance(10); S.zone, S.subZone = "Orgrimmar", ""; fire("ZONE_CHANGED_NEW_AREA")
        -- A place nobody saw: discovered, and echoed (chat "all", as in Chema's version).
        advance(10); S.zone, S.subZone = "Los Baldíos", "El Cruce"; fire("ZONE_CHANGED_NEW_AREA")
        -- Types Chema's version never logged are off in the "clasico" profile.
        S.npcName = "Thrall"; advance(30); fire("GOSSIP_SHOW")
        advance(5); fire("CHAT_MSG_WHISPER", "¿Vienes?", "Garona-Zandalar")
        advance(5); fire("PLAYER_LEVEL_UP", 7)
        advance(5); fire("CHAT_MSG_SYSTEM", "Garona se une al grupo.")
        -- Loot: epic or better only (lootQuality 4); a rare item is not logged.
        advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[1234].link .. ".", "", "", "", "Volgajin")
        advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5555].link .. ".", "", "", "", "Volgajin")
        advance(5); fire("PLAYER_DEAD")
        NewEntries("login", 4)

        -- The book shows Chema's jornadas from their stored prose.
        slash("hoy ")   -- trailing space, as Chema's version accepted
        note("login: /diario hoy (with a trailing space) shows: " .. tostring(_G.AdventureJournalBookFrame.dayTitle.text)
            .. ", shown=" .. tostring(_G.AdventureJournalBookFrame.shown))
        H.ns.OpenAtDay(2)
        note("login: book on jornada 2 (Chema's):\n" .. tostring(_G.AdventureJournalBookFrame.body.text))
        AdventureJournal_Toggle()   -- Chema's global name for the toggle
        note("login: AdventureJournal_Toggle() -> shown=" .. tostring(_G.AdventureJournalBookFrame.shown))
        SlashCmdList["ADVENTUREJOURNALDIAG"]("")   -- /ajdiag, Chema's diagnostic command
        note("login: /ajdiag printed " .. #S.prints .. " chat lines so far (see chat output)")

        -- The player changes a setting: the profile must not come back on later loads.
        slash("chat importante")
        CheckChemaUntouched("login: end of session", reference, { 1, 2, 3 })
        fire("PLAYER_LOGOUT")
    elseif H.mode == "reload" then
        fire("PLAYER_ENTERING_WORLD", false, true)
        note("reload: currentDay " .. AdventureJournalDB.currentDay .. ", chat stays as the player set it: "
            .. tostring(AdventureJournalDB.settings.chat))
        CheckChemaUntouched("reload: end of session", reference, { 1, 2, 3 })
        fire("PLAYER_LOGOUT")
    else
        fire("PLAYER_ENTERING_WORLD", true, false)
        S.zone, S.subZone = "Durotar", "El Cubil"; fire("ZONE_CHANGED_NEW_AREA")   -- known: nothing
        advance(10); S.zone, S.subZone = "Los Baldíos", "El Cruce"; fire("ZONE_CHANGED_NEW_AREA")   -- known since login
        NewEntries("relogin", AdventureJournalDB.currentDay)
        CheckChemaUntouched("relogin: end of session", reference, { 1, 2, 3 })
        fire("PLAYER_LOGOUT")
    end

elseif H.variant == "roundtrip" then
    -- One of this line's diaries (saved before T1: no lootQuality, no profile) after the player
    -- used Chema's version for a session: it rewrote `version` to 2, created its three tables,
    -- added Orgrimmar to `visitedZones` and a jornada of its own. `settings` survived (that
    -- version keeps keys it does not know), so this is not a first load of a Chema diary.
    local function Diary()
        local chema = ChemaDiary()
        return {
            version = 2,
            currentDay = 2,
            visited = { ["Valle de los Retos, Durotar"] = true },
            visitedZones = { ["Valle de los Retos, Durotar"] = true, ["Orgrimmar"] = true },
            knownMounts = {},
            knownAchievements = {},
            settings = {
                chat = "off", showProfile = true, conversations = false,
                types = { QUEST = true, BOSS = true, DEATH = true, LOOT = false, DISCOVERY = true, NPC = true, CHAT = true,
                          LEVEL = true, GROUP = true, REPUTATION = true, SKILL = true, SPELL = true },
            },
            days = {
                [1] = {
                    startedAt = "2026-11-04 18:57:25", endedAt = "2026-11-04 19:18:57", dateLabel = "04/11/2026",
                    events = {
                        { type = "DISCOVERY", text = "Valle de los Retos, Durotar", place = "Valle de los Retos, Durotar",
                          zone = "Durotar", subZone = "Valle de los Retos", time = "18:57:25", timestamp = 1793815045,
                          characterProfile = "Explorador", contextualTone = "con la curiosidad de quien acaba de encontrar un lugar nuevo", seed = 1,
                          prose = "Mis pasos me condujeron hasta Valle de los Retos, Durotar. Me detuve un momento para observar el lugar; con la curiosidad de quien acaba de encontrar un lugar nuevo." },
                    },
                },
                [2] = chema.days[2],   -- written by Chema's version while the player was on it
            },
        }
    end
    AdventureJournalDB = Diary()
    local reference = Diary()

    fire("ADDON_LOADED", "AdventureJournal")
    Settings("after ADDON_LOADED")
    CheckChemaUntouched("after load", reference, { 1, 2 })
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    S.zone, S.subZone = "Orgrimmar", ""; fire("ZONE_CHANGED_NEW_AREA")   -- seen by Chema's version: nothing
    advance(10); S.zone, S.subZone = "Durotar", "Razor Hill"; fire("ZONE_CHANGED_NEW_AREA")   -- new
    advance(5); fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[5555].link .. ".", "", "", "", "Volgajin")   -- LOOT off (player's choice)
    NewEntries("roundtrip", AdventureJournalDB.currentDay)

    -- Profiles applied by hand (the panel and a command come in T5).
    note("ApplyProfile('clasico') -> " .. tostring(H.ns.ApplyProfile("clasico")))
    Settings("after clasico")
    note("ApplyProfile('ampliado') -> " .. tostring(H.ns.ApplyProfile("ampliado")))
    Settings("after ampliado")
    note("ApplyProfile('otro') -> " .. tostring(H.ns.ApplyProfile("otro")) .. ", profile stays " .. tostring(AdventureJournalDB.settings.profile))

    -- Hand-edited values of the new settings fall back to the defaults.
    AdventureJournalDB.settings.lootQuality = "4"
    AdventureJournalDB.settings.profile = "raro"
    H.ns.EnsureDatabase()
    note(string.format("hand-edited lootQuality \"4\" and profile \"raro\" -> %s, %s",
        tostring(AdventureJournalDB.settings.lootQuality), tostring(AdventureJournalDB.settings.profile)))
    AdventureJournalDB.settings.lootQuality = 9
    H.ns.EnsureDatabase()
    note("hand-edited lootQuality 9 -> " .. tostring(AdventureJournalDB.settings.lootQuality))
    CheckChemaUntouched("end of session", reference, { 1, 2 })
    fire("PLAYER_LOGOUT")
end
