-- A diary saved by the pre-M4 addon (schema v1) is loaded by the current code.
-- Jornadas must stay byte-for-byte what they were; `visited` is seeded from the
-- DISCOVERY entries already in the diary, so those places are not logged again.
-- The fixture is hand-written in the shape the M0/M1 code saved (see the README
-- schema), including its quirks: no `endedAt` on the last jornada, lower-case
-- sentences in the stored prose, an empty jornada.
local H = ...
local S, fire, advance, slash, note = H.S, H.fire, H.advance, H.slash, H.note

AdventureJournalDB = {
    version = 1,
    currentDay = 3,
    days = {
        [1] = {
            startedAt = "2026-11-04 18:57:25", endedAt = "2026-11-04 19:18:57", dateLabel = "04/11/2026",
            events = {
                { type = "DISCOVERY", text = "Valle de los Retos, Durotar", place = "tierras desconocidas",
                  zone = "Durotar", subZone = "Valle de los Retos", time = "18:57:25", timestamp = 1793815045,
                  characterProfile = "Explorador", contextualTone = "con la curiosidad de quien acaba de encontrar un lugar nuevo", seed = 1,
                  prose = "Mis pasos me condujeron hasta Valle de los Retos, Durotar. Me detuve un momento para observar el lugar; con la curiosidad de quien acaba de encontrar un lugar nuevo." },
                { type = "QUEST", text = "Tu lugar en el mundo", questID = 4641, place = "El Cubil, Durotar",
                  zone = "Durotar", subZone = "El Cubil", time = "19:01:27", timestamp = 1793815287,
                  characterProfile = "Cínico", contextualTone = "con más ironía que paciencia", seed = 2,
                  prose = "La jornada me llevó a resolver «Tu lugar en el mundo» en El Cubil, Durotar. con más ironía que paciencia. Al menos hoy he cumplido con mi parte." },
                { type = "DISCOVERY", text = "El Cubil, Durotar", place = "El Cubil, Durotar",
                  zone = "Durotar", subZone = "El Cubil", time = "19:01:20", timestamp = 1793815280,
                  characterProfile = "Explorador", contextualTone = "con la curiosidad de quien acaba de encontrar un lugar nuevo", seed = 3,
                  prose = "Mis pasos me condujeron hasta El Cubil, Durotar." },
            },
        },
        [2] = { startedAt = "2026-11-04 19:19:51", endedAt = "2026-11-04 19:20:45", dateLabel = "04/11/2026", events = {} },
        [3] = {
            startedAt = "2026-11-04 19:32:54", dateLabel = "04/11/2026",
            events = {
                { type = "LOOT", text = "|cff0070dd|Hitem:1234::::::::1::::::::::|h[Escudo azul]|h|r", itemID = 1234, itemQuality = 3,
                  itemLink = "|cff0070dd|Hitem:1234::::::::1::::::::::|h[Escudo azul]|h|r",
                  place = "Valle de los Retos, Durotar", zone = "Durotar", subZone = "Valle de los Retos",
                  time = "19:33:10", timestamp = 1793817190, characterProfile = "Entusiasmado",
                  contextualTone = "con la agradable impresión de que el viaje empieza a dar sus frutos", seed = 1,
                  prose = "La fortuna se dejó notar en Valle de los Retos, Durotar: apareció Escudo azul. con la agradable impresión de que el viaje empieza a dar sus frutos." },
            },
        },
    },
}
local original = {}
for day, data in pairs(AdventureJournalDB.days) do original[day] = #data.events end

S.items[1234] = { name = "Escudo azul", quality = 3, cached = true,
    link = "|cff0070dd|Hitem:1234::::::::1::::::::::|h[Escudo azul]|h|r" }

fire("ADDON_LOADED", "AdventureJournal")
local db = AdventureJournalDB
local visited = 0
for _ in pairs(db.visited) do visited = visited + 1 end
note(string.format("after load: version = %d, currentDay = %d, settings.chat = %s, visited places = %d",
    db.version, db.currentDay, tostring(db.settings.chat), visited))
for day, count in pairs(original) do
    assert(#db.days[day].events == count, "migration changed the entries of jornada " .. day)
end
note("old jornadas keep their entries: " .. original[1] .. " / " .. original[2] .. " / " .. original[3])
fire("ADDON_LOADED", "AdventureJournal")   -- the migration is idempotent
note("loading twice: version = " .. db.version)

fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
S.zone, S.subZone = "Durotar", "Valle de los Retos"
fire("ZONE_CHANGED_NEW_AREA")                       -- seeded from the old diary: no DISCOVERY
advance(10); S.subZone = "El Cubil"; fire("ZONE_CHANGED")   -- same
advance(10); S.zone, S.subZone = "Orgrimmar", ""; fire("ZONE_CHANGED_NEW_AREA")   -- really new
advance(10); S.zone, S.subZone = "Durotar", "El Cubil"; fire("ZONE_CHANGED_NEW_AREA")   -- back: nothing
note("new jornada: " .. db.currentDay .. " with " .. #db.days[db.currentDay].events .. " entries")

H.ns.OpenAtDay(1)
note("book on jornada 1 (an old v1 jornada):\n" .. tostring(_G.AdventureJournalBookFrame.body.text))
fire("PLAYER_LOGOUT")
