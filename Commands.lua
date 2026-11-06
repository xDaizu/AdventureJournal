-- Commands.lua: slash commands and the key binding (Bindings.xml).
-- These are the addon's only globals besides AdventureJournalDB.
local addonName, ns = ...

BINDING_HEADER_ADVENTUREJOURNAL = "Diario de Aventuras"
BINDING_NAME_ADVENTUREJOURNAL_TOGGLE = "Abrir / cerrar el diario"

-- Called by the key binding in Bindings.xml.
function AdventureJournal_ToggleUI()
    ns.ToggleUI()
end

-- The name Chema's Forever line (1.1.0-Forever) gave the same function: kept so macros and
-- bindings written for that version still work after updating.
function AdventureJournal_Toggle()
    ns.ToggleUI()
end

-- WoW Forever's addon menu (the minimap button). AdventureJournal_Forever.toc names this
-- function in its AddonCompartmentFunc line; the Vanilla TOC has no such line, so Classic
-- Era never calls it. It must be global, and receives (addonName, buttonName, menuButtonFrame).
-- In-game behaviour on Forever: verify in M3/M5.
function AdventureJournal_OnAddonCompartmentClick()
    ns.ToggleUI()
end

local PREFIX = "|cFFFFD700[Diario]|r "
local function Say(text) print(PREFIX .. text) end

-- /diario diag: what this client is, which API branches Compat took, which events
-- registered, and any handler errors. First thing to run on a new client.
local function PrintDiagnostics()
    Say("Diagnóstico de AdventureJournal " .. (ns.GetAddonVersion() or "?"))
    local version, build, _, toc = GetBuildInfo()
    Say(string.format("Cliente: %s (build %s), interfaz %s, WOW_PROJECT_ID %s",
        tostring(version), tostring(build), tostring(toc), tostring(WOW_PROJECT_ID)))
    Say(string.format("Detectado: IS_FOREVER=%s, IS_CLASSIC_ERA=%s, idioma %s",
        tostring(ns.IS_FOREVER), tostring(ns.IS_CLASSIC_ERA), tostring(GetLocale and GetLocale())))
    local inInstance, instanceType
    if IsInInstance then inInstance, instanceType = IsInInstance() end
    Say(string.format("Instancia: %s (%s). Zona: %s / %s",
        tostring(inInstance), tostring(instanceType),
        ns.Describe(ns.GetZoneText()), ns.Describe(ns.GetSubZoneText())))

    local DB = ns.DB
    if DB then
        local day = DB.days[DB.currentDay]
        local dayCount = 0
        for _ in pairs(DB.days) do dayCount = dayCount + 1 end
        Say(string.format("Base de datos: versión %s, jornada actual %s, %d jornadas, %d entradas hoy",
            tostring(DB.version), tostring(DB.currentDay), dayCount, day and day.events and #day.events or 0))
    else
        Say("Base de datos: NO inicializada")
    end

    if DB then
        local visitedCount = 0
        for _ in pairs(DB.visited) do visitedCount = visitedCount + 1 end
        Say(string.format("Lugares visitados: %d. Mensajes en el chat: %s", visitedCount, tostring(DB.settings.chat)))
        local off = {}
        for _, info in ipairs(ns.VisibleTypes()) do
            if not ns.IsTypeEnabled(info.key) then table.insert(off, info.key) end
        end
        Say(string.format("Tipos desactivados: %s. Ánimo en el libro: %s",
            #off > 0 and table.concat(off, ", ") or "ninguno", ns.GetSetting("showProfile") and "sí" or "no"))
        -- T1: the profile, the loot threshold, and what is left of a diary from Chema's Forever line.
        local function Count(t)
            local n = 0
            if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
            return n
        end
        Say(string.format("Perfil: %s (último aplicado: %s). Botín desde calidad %d. Enemigo en las muertes: %s. Diario de la versión de Chema: %s",
            ns.ProfileStatus(), tostring(ns.GetSetting("profile")), ns.GetLootQuality(), ns.GetSetting("deathKiller") == true and "sí" or "no",
            DB.origin == "chema" and string.format("sí (%d lugares, %d monturas y %d logros conservados)",
                Count(DB.visitedZones), Count(DB.knownMounts), Count(DB.knownAchievements)) or "no"))
    end
    do
        local chatOK, chatFailed = ns.GetConversationStatus()
        Say(string.format("Conversaciones: %s. Eventos de chat registrados: %d de %d%s",
            ns.ConversationsEnabled() and "SÍ (se guardan)" or "no", chatOK, #ns.CONVERSATION_EVENTS,
            #chatFailed > 0 and (" (no registrados: " .. table.concat(chatFailed, "; ") .. ")") or ""))
        local probe = _G.AJProbeDB
        if type(probe) == "table" then
            Say(string.format("AJProbe: presente, %d registros de actividad y %d mensajes (/diario importar los lee, sin modificarlos)",
                type(probe.log) == "table" and #probe.log or 0, type(probe.chat) == "table" and #probe.chat or 0))
        else
            Say("AJProbe: no está cargado (/diario importar no tendría de dónde leer)")
        end
    end
    do
        local now = time()
        Say(string.format("Lectura de fechas (time{...}, la usa /diario importar): %s",
            ns.ParseDateTime(date("%Y-%m-%d %H:%M:%S", now)) == now and "OK" or "NO funciona (se usarán las marcas de tiempo)"))
    end
    Say("Panel de opciones: " .. ns.GetOptionsStatus())
    Say("Índice del libro: " .. ns.GetIndexMode())
    local compartmentField = ns.GetAddonField("AddonCompartmentFunc")
    Say(string.format("Menú de addons (AddonCompartmentFunc): TOC = %s, función global = %s",
        compartmentField and tostring(compartmentField) or "no declarado o no legible",
        type(_G.AdventureJournal_OnAddonCompartmentClick) == "function" and "sí" or "NO"))
    Say(string.format("Patrones de botín propio: %d (0 = se acepta todo el botín)", #ns.GetOwnLootPatterns()))

    for _, row in ipairs(ns.GetApiBranches()) do Say(row[1] .. ": " .. row[2]) end
    Say("Textos del juego que reconocen los tipos nuevos (M6): /diario diag mensajes los repite solos.")
    for _, row in ipairs(ns.GetMessageStatus()) do Say("  " .. row[1] .. ": " .. row[2]) end
    Say("Interfaz (M5):")
    for _, row in ipairs(ns.GetUiFeatures()) do Say("  " .. row[1] .. ": " .. row[2]) end

    local registered, failed = {}, {}
    for _, event in ipairs(ns.EVENTS) do
        if ns.eventStatus[event] == true then
            table.insert(registered, event)
        else
            table.insert(failed, event .. " (" .. tostring(ns.eventStatus[event]) .. ")")
        end
    end
    Say("Eventos registrados (" .. #registered .. "): " .. table.concat(registered, ", "))
    Say("Eventos NO registrados (" .. #failed .. "): " .. (#failed > 0 and table.concat(failed, "; ") or "ninguno"))

    local errorLines = {}
    for event, record in pairs(ns.handlerErrors) do
        table.insert(errorLines, string.format("%s x%d: %s", event, record.count, record.message))
    end
    table.sort(errorLines)
    if #errorLines == 0 then
        Say("Errores en manejadores: ninguno")
    else
        Say("Errores en manejadores:")
        for _, line in ipairs(errorLines) do Say("  " .. line) end
    end
    Say(string.format("Depuración: %s, secretos simulados: %s",
        ns.debug.on and "ACTIVA" or "apagada", ns.debug.secrets and "ACTIVOS" or "apagados"))
end

-- /diario diag mensajes: only the M6 message strings (short enough for one screenshot).
local function PrintMessageDiagnostics()
    Say("Textos del juego que reconocen los tipos nuevos (nivel, grupo, reputación, habilidades, hechizos):")
    for _, row in ipairs(ns.GetMessageStatus()) do Say("  " .. row[1] .. ": " .. row[2]) end
    Say("Prueba de ida y vuelta (una frase inventada con cada texto del juego, pasada por el mismo lector; no anota nada):")
    local failed = 0
    for _, row in ipairs(ns.SelfTestMessages()) do
        if not row[3] then failed = failed + 1 end
        Say("  " .. (row[3] and "OK  " or "NO  ") .. row[1] .. ": " .. row[2])
    end
    Say("Si alguna línea dice «ninguna», ese tipo no puede reconocer nada en este cliente.")
    Say(failed == 0 and "RESULTADO: todos los textos se reconocen." or ("RESULTADO: " .. failed .. " texto(s) NO se reconocen: esos tipos fallarán en este cliente."))
end

-- A generated diary for trying the book with many jornadas: held in memory only (ns.demoDB, see
-- UI.lua), never saved, never mixed with the real diary. Every other jornada has no mood, like
-- diaries saved before the mood existed.
local DEMO_TYPES = { "QUEST", "BOSS", "DEATH", "LOOT", "DISCOVERY", "NPC", "CHAT" }

local function BuildDemoDiary(dayCount, perDay)
    local demo = { version = ns.SCHEMA_VERSION, currentDay = dayCount, visited = {}, settings = {}, days = {} }
    for day = 1, dayCount do
        local events = {}
        for index = 1, perDay do
            local entry = {
                type = DEMO_TYPES[(day + index) % #DEMO_TYPES + 1], text = "Asunto de prueba " .. day .. "." .. index,
                place = "Durotar", zone = "Durotar", subZone = "", seed = index,
                time = string.format("%02d:%02d:00", index % 24, day % 60),
            }
            if day % 2 == 0 then
                entry.characterProfile, entry.contextualTone = "Heroico", "con el ánimo firme"
            end
            entry.prose, entry.header = ns.ComposeEntry(entry)
            events[index] = entry
        end
        demo.days[day] = { dateLabel = "PRUEBA", events = events }
    end
    return demo
end

local function SetDebug(arg1, arg2)
    if arg1 == "on" then
        ns.debug.on = true
        Say("Depuración activada: verás la carga de cada evento. /diario debug off la apaga.")
    elseif arg1 == "off" then
        ns.debug.on, ns.debug.secrets, ns.debug.buttons = false, false, false
        if ns.demoDB then ns.demoDB = nil; ns.RefreshIfVisible() end
        Say("Depuración, secretos simulados y datos de prueba desactivados.")
    elseif arg1 == "demo" then
        if arg2 == "off" then
            ns.demoDB = nil
            ns.RefreshIfVisible()
            Say("Datos de prueba retirados: el libro vuelve a mostrar tu diario.")
        else
            ns.demoDB = BuildDemoDiary(250, 20)
            ns.OpenAtDay(250)
            Say("El libro muestra 250 jornadas de PRUEBA (solo en pantalla: no se guardan y tu diario no se toca). /diario debug demo off o /reload lo retira.")
        end
    elseif arg1 == "buttons" then
        ns.debug.buttons = true
        Say("Índice con botones (sin ScrollBox) para probar la alternativa. Solo vale si lo escribes ANTES de abrir el libro por primera vez tras /reload; /diario debug off o /reload lo apaga.")
    elseif arg1 == "secrets" then
        if arg2 == "off" then
            ns.debug.secrets = false
            Say("Secretos simulados desactivados.")
        else
            ns.debug.secrets, ns.debug.on = true, true
            Say("Secretos simulados ACTIVADOS (y la depuración). Los textos de los eventos se tratan como secretos. /diario debug secrets off o /reload lo apaga.")
        end
    else
        Say("Usa /diario debug on, /diario debug off, /diario debug secrets, /diario debug buttons o /diario debug demo.")
    end
end

-- Options by slash command. The options panel (Options.lua) changes the same settings;
-- these commands are the complete alternative when the panel is not available.

-- /diario chat: what the diary echoes to the chat window (settings.chat).
local CHAT_MODES = {
    todo = "all", all = "all",
    importante = "important", important = "important",
    nada = "off", off = "off",
}

local function SetChatMode(word)
    local mode = CHAT_MODES[word]
    if mode then
        ns.SetSetting("chat", mode)
        Say("Mensajes en el chat: " .. ns.CHAT_MODE_NAMES[mode] .. ".")
    else
        Say("Mensajes en el chat: " .. (ns.CHAT_MODE_NAMES[ns.EnsureDatabase().settings.chat] or "?")
            .. ". Usa /diario chat todo, /diario chat importante (jefes, muertes y botín épico) o /diario chat nada.")
    end
end

-- "on"/"off" words for the toggles below. Returns true, false, or nil when unclear.
local SWITCH_WORDS = {
    on = true, si = true, ["sí"] = true, activar = true, ["1"] = true,
    off = false, no = false, desactivar = false, ["0"] = false,
}

local function YesNo(value) return value and "sí" or "no" end

-- /diario tipos: which entry types are logged (settings.types).
local function SetTypes(typeWord, switchWord)
    ns.EnsureDatabase()
    local key = typeWord ~= "" and ns.TypeFromWord(typeWord) or nil
    local enabled = SWITCH_WORDS[switchWord]
    if key and not ns.IsTypeAvailable(key) then
        Say(key .. ": este cliente no tiene lo necesario para anotarlo.")
        return
    end
    if key and enabled ~= nil then
        ns.SetTypeEnabled(key, enabled)
        Say(string.format("%s: %s.", key, enabled and "se anota" or "NO se anota"))
        return
    end
    if typeWord ~= "" and not key then Say("No conozco el tipo «" .. typeWord .. "».") end
    local lines = {}
    for _, info in ipairs(ns.VisibleTypes()) do
        table.insert(lines, string.format("%s (%s): %s", ns.TypeLabel(info), info.words[1], YesNo(ns.IsTypeEnabled(info.key))))
    end
    Say("Se anota en el diario: " .. table.concat(lines, "; ") .. ".")
    local words = {}
    for _, info in ipairs(ns.VisibleTypes()) do table.insert(words, info.words[1]) end
    Say("Cambiar: /diario tipos <" .. table.concat(words, "|") .. "> <on|off>")
end

-- /diario animo: show the mood next to each entry's time in the book (settings.showProfile).
local function SetProfile(word)
    ns.EnsureDatabase()
    local enabled = SWITCH_WORDS[word]
    if enabled ~= nil then
        ns.SetSetting("showProfile", enabled)
        Say("Ánimo en el libro: " .. YesNo(enabled) .. ".")
    else
        Say("Ánimo en el libro: " .. YesNo(ns.GetSetting("showProfile")) .. ". Usa /diario animo on o /diario animo off.")
    end
end

-- /diario conversaciones: record RP conversations (settings.conversations). Off by default.
local function SetConversations(word)
    ns.EnsureDatabase()
    local enabled = SWITCH_WORDS[word]
    if enabled == true then
        ns.SetSetting("conversations", true)
        Say("Conversaciones: sí. Desde ahora se guardan en el diario los susurros (también de Battle.net), el chat de grupo y banda, "
            .. "y lo que digáis, gritéis o hagáis tú, tu grupo y tus amigos. Es texto de otros jugadores: /diario conversaciones off lo detiene. "
            .. "Dentro de instancias el chat es secreto y no se guarda.")
    elseif enabled == false then
        ns.SetSetting("conversations", false)
        Say("Conversaciones: no. Ya no se guarda ni se muestra nada de esto (lo ya guardado se conserva en el archivo, oculto).")
    else
        Say("Conversaciones: " .. YesNo(ns.ConversationsEnabled()) .. ". Usa /diario conversaciones on o /diario conversaciones off.")
    end
end

-- T5: profiles, the loot threshold and the enemy in a death ----------------------------------

-- What a profile writes, in one line each, for /diario perfil and the panel's confirmation.
ns.PROFILE_DESCRIPTIONS = {
    clasico = "lo que anotaba la versión 1.1.0-Forever de Chema: cada anotación en el chat, botín épico o mejor, "
        .. "el enemigo en las muertes y los lugares que vuelves a visitar; sin nivel, grupo, reputación, habilidades, hechizos, charlas con PNJ ni susurros",
    ampliado = "todo lo que anota esta versión: solo lo importante en el chat, botín raro o mejor, "
        .. "sin el enemigo en las muertes ni los lugares que vuelves a visitar",
}

local function TypeLabelOf(key)
    for _, info in ipairs(ns.TYPE_INFO) do
        if info.key == key then return ns.TypeLabel(info) end
    end
    return key
end

-- Applies a profile and says in the chat what it changed (ns.ApplyProfile's list), so the player can
-- undo any of it by hand. Used by /diario perfil and by the panel after its confirmation.
function ns.ApplyProfileAndReport(name)
    local ok, changes = ns.ApplyProfile(name)
    if not ok then return false end
    local settingsChanged, nowOn, nowOff = {}, {}, {}
    for _, change in ipairs(changes) do
        local kind, before, after = change[1], change[2], change[3]
        if kind == "chat" then
            settingsChanged[#settingsChanged + 1] = string.format("mensajes en el chat: %s (antes %s)",
                ns.CHAT_MODE_NAMES[after] or tostring(after), ns.CHAT_MODE_NAMES[before] or tostring(before))
        elseif kind == "lootQuality" then
            settingsChanged[#settingsChanged + 1] = string.format("botín desde %s (antes %s)",
                ns.LOOT_QUALITY_NAMES[after] or tostring(after), ns.LOOT_QUALITY_NAMES[before] or tostring(before))
        elseif kind == "deathKiller" then
            settingsChanged[#settingsChanged + 1] = "enemigo en las muertes: " .. YesNo(after) .. " (antes " .. YesNo(before) .. ")"
        elseif after then
            nowOn[#nowOn + 1] = TypeLabelOf(kind)
        else
            nowOff[#nowOff + 1] = TypeLabelOf(kind)
        end
    end
    Say("Perfil " .. ns.PROFILE_NAMES[name] .. " aplicado. Tus jornadas no cambian.")
    if #changes == 0 then
        Say("Ya tenías esos ajustes: no ha cambiado nada.")
        return true
    end
    if #settingsChanged > 0 then Say("Cambiado: " .. table.concat(settingsChanged, "; ") .. ".") end
    if #nowOn > 0 then Say("Ahora se anota: " .. table.concat(nowOn, ", ") .. ".") end
    if #nowOff > 0 then Say("Ya no se anota: " .. table.concat(nowOff, ", ") .. ".") end
    return true
end

local PROFILE_WORDS = {
    clasico = "clasico", ["clásico"] = "clasico", classic = "clasico",
    ampliado = "ampliado", extended = "ampliado",
}

-- /diario perfil [clasico|ampliado]. Typing the name is the confirmation; the panel asks first.
local function SetProfileByName(word)
    ns.EnsureDatabase()
    local name = PROFILE_WORDS[word]
    if name then
        ns.ApplyProfileAndReport(name)
        return
    end
    if word ~= "" then Say("No conozco el perfil «" .. word .. "».") end
    Say("Perfil: " .. ns.ProfileStatus() .. ".")
    for _, profileName in ipairs(ns.PROFILE_ORDER) do
        Say(ns.PROFILE_NAMES[profileName] .. ": " .. ns.PROFILE_DESCRIPTIONS[profileName] .. ".")
    end
    Say("Cambiar: /diario perfil clasico o /diario perfil ampliado (cambia de una vez los ajustes de arriba; luego puedes tocar cada uno).")
end

local LOOT_WORDS = {
    pococomun = 2, ["pococomún"] = 2, comun = 2, ["común"] = 2, poco = 2, verde = 2, ["2"] = 2,
    raro = 3, azul = 3, ["3"] = 3,
    epico = 4, ["épico"] = 4, morado = 4, ["4"] = 4,
    legendario = 5, naranja = 5, ["5"] = 5,
}

-- /diario botin <poco común|raro|épico|legendario>: the lowest quality logged as LOOT (settings.lootQuality).
local function SetLootQuality(arg1, arg2)
    ns.EnsureDatabase()
    local quality = LOOT_WORDS[arg1 .. arg2] or LOOT_WORDS[arg1]
    if quality then
        ns.SetSetting("lootQuality", quality)
        Say("Botín: se anota desde " .. ns.LOOT_QUALITY_NAMES[quality] .. " (" .. TypeLabelOf("LOOT") .. ").")
    else
        Say("Botín: se anota desde " .. ns.LOOT_QUALITY_NAMES[ns.GetLootQuality()]
            .. ". Usa /diario botin poco común, /diario botin raro, /diario botin épico o /diario botin legendario.")
    end
end

-- /diario enemigo on|off: name the last enemy fought in a death entry (settings.deathKiller).
local function SetDeathKiller(word)
    ns.EnsureDatabase()
    local enabled = SWITCH_WORDS[word]
    if enabled ~= nil then
        ns.SetSetting("deathKiller", enabled)
        Say("Enemigo en las muertes: " .. YesNo(enabled) .. ".")
    else
        Say("Enemigo en las muertes: " .. YesNo(ns.GetSetting("deathKiller") == true)
            .. ". Usa /diario enemigo on o /diario enemigo off. Sin registro de combate, es el último enemigo con el que luchaste, no siempre quien te mató.")
    end
end

-- Once per diary that came from Chema's version (origin = "chema", T1): say what happened to it and how
-- to see more. Called at every PLAYER_ENTERING_WORLD; `chemaHintShown` makes it a one-off.
function ns.ShowChemaHintOnce()
    local DB = ns.DB
    if not DB or DB.origin ~= "chema" or DB.chemaHintShown == true then return end
    DB.chemaHintShown = true
    Say("Tu diario viene de la versión 1.1.0-Forever: se ha conservado entero y se sigue anotando lo mismo que entonces (perfil Clásico).")
    Say("Esta versión puede anotar más: subidas de nivel, grupo, reputación, habilidades, hechizos, charlas con PNJ... "
        .. "Pruébalo con /diario perfil ampliado, o elige cada cosa en Esc > Opciones > AddOns > Diario de Aventuras (/diario opciones). Este aviso no se repite.")
end

-- /diario opciones: opens the panel, or lists the commands when it cannot.
local function OpenOptions()
    local ok, reason = ns.OpenOptions()
    if ok then return end
    Say("No he podido abrir el panel de opciones (" .. tostring(reason) .. "). Si no aparece, búscalo en "
        .. "Esc > Opciones > AddOns > Diario de Aventuras. Mientras tanto, todo se puede cambiar con comandos:")
    Say("/diario perfil <clasico|ampliado>  ·  /diario chat <todo|importante|nada>  ·  /diario tipos <tipo> <on|off>  ·  /diario botin <raro|épico|...>  ·  "
        .. "/diario enemigo <on|off>  ·  /diario animo <on|off>  ·  /diario conversaciones <on|off>")
    SetTypes("", "")
end

SLASH_ADVENTUREJOURNAL1 = "/diario"
SLASH_ADVENTUREJOURNAL2 = "/journal"
SlashCmdList["ADVENTUREJOURNAL"] = function(message)
    -- Surrounding spaces are ignored, as in Chema's version ("/diario hoy " works).
    local command = string.lower(string.match(message or "", "^%s*(.-)%s*$"))
    local word, arg1, arg2 = string.match(command, "^(%S+)%s*(%S*)%s*(%S*)$")
    if command == "" or command == "abrir" then
        ns.ToggleUI()
    elseif command == "hoy" or command == "actual" then
        ns.OpenAtDay(ns.DB and ns.DB.currentDay or 1)
    elseif command == "anterior" then
        ns.OpenAtDay((ns.DB and ns.DB.currentDay or 1) - 1)
    elseif word == "diag" and arg1 == "" then
        PrintDiagnostics()
    elseif word == "diag" and (arg1 == "mensajes" or arg1 == "messages") then
        PrintMessageDiagnostics()
    elseif word == "debug" then
        SetDebug(arg1, arg2)
    elseif word == "chat" then
        SetChatMode(arg1)
    elseif (word == "opciones" or word == "options" or word == "config") and arg1 == "" then
        OpenOptions()
    elseif word == "tipos" or word == "types" then
        SetTypes(arg1, arg2)
    elseif word == "animo" or word == "ánimo" or word == "mood" then
        SetProfile(arg1)
    elseif word == "conversaciones" or word == "conversations" or word == "conv" then
        SetConversations(arg1)
    elseif (word == "perfil" or word == "profile") and arg2 == "" then
        SetProfileByName(arg1)
    elseif word == "botin" or word == "botín" or word == "loot" then
        SetLootQuality(arg1, arg2)
    elseif word == "enemigo" or word == "killer" then
        SetDeathKiller(arg1)
    elseif (word == "importar" or word == "import") and arg2 == "" then
        if arg1 == "" then
            ns.RunImport(false)
        elseif arg1 == "prueba" or arg1 == "test" then
            ns.RunImport(true)
        else
            Say("Usa /diario importar (lee AJProbe y rellena el diario) o /diario importar prueba (solo cuenta, no guarda nada).")
        end
    else
        Say("Usa /diario, /diario hoy, /diario anterior, /diario opciones, /diario perfil, /diario chat, /diario tipos, /diario botin, /diario enemigo, /diario animo, /diario conversaciones, /diario importar, /diario diag o /diario debug.")
    end
end

-- /ajdiag: the diagnostic command of Chema's Forever line, kept as a short name for /diario diag.
SLASH_ADVENTUREJOURNALDIAG1 = "/ajdiag"
SlashCmdList["ADVENTUREJOURNALDIAG"] = function()
    PrintDiagnostics()
end
