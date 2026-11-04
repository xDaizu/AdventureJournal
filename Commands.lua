-- Commands.lua: slash commands and the key binding (Bindings.xml).
-- These are the addon's only globals besides AdventureJournalDB.
local addonName, ns = ...

BINDING_HEADER_ADVENTUREJOURNAL = "Diario de Aventuras"
BINDING_NAME_ADVENTUREJOURNAL_TOGGLE = "Abrir / cerrar el diario"

-- Called by the key binding in Bindings.xml.
function AdventureJournal_ToggleUI()
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
        for _, info in ipairs(ns.TYPE_INFO) do
            if not ns.IsTypeEnabled(info.key) then table.insert(off, info.key) end
        end
        Say(string.format("Tipos desactivados: %s. Ánimo en el libro: %s",
            #off > 0 and table.concat(off, ", ") or "ninguno", ns.GetSetting("showProfile") and "sí" or "no"))
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
    Say("Panel de opciones: " .. ns.GetOptionsStatus())
    Say("Índice del libro: " .. ns.GetIndexMode())
    local compartmentField = ns.GetAddonField("AddonCompartmentFunc")
    Say(string.format("Menú de addons (AddonCompartmentFunc): TOC = %s, función global = %s",
        compartmentField and tostring(compartmentField) or "no declarado o no legible",
        type(_G.AdventureJournal_OnAddonCompartmentClick) == "function" and "sí" or "NO"))
    Say(string.format("Patrones de botín propio: %d (0 = se acepta todo el botín)", #ns.GetOwnLootPatterns()))

    for _, row in ipairs(ns.GetApiBranches()) do Say(row[1] .. ": " .. row[2]) end
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
            entry.prose = ns.ComposeEntry(entry)
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
    if key and enabled ~= nil then
        ns.SetTypeEnabled(key, enabled)
        Say(string.format("%s: %s.", key, enabled and "se anota" or "NO se anota"))
        return
    end
    if typeWord ~= "" and not key then Say("No conozco el tipo «" .. typeWord .. "».") end
    local lines = {}
    for _, info in ipairs(ns.TYPE_INFO) do
        table.insert(lines, string.format("%s (%s): %s", info.label, info.words[1], YesNo(ns.IsTypeEnabled(info.key))))
    end
    Say("Se anota en el diario: " .. table.concat(lines, "; ") .. ".")
    Say("Cambiar: /diario tipos <misiones|jefes|muertes|botin|lugares|pnj|susurros> <on|off>")
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

-- /diario opciones: opens the panel, or lists the commands when it cannot.
local function OpenOptions()
    local ok, reason = ns.OpenOptions()
    if ok then return end
    Say("No he podido abrir el panel de opciones (" .. tostring(reason) .. "). Si no aparece, búscalo en "
        .. "Esc > Opciones > AddOns > Diario de Aventuras. Mientras tanto, todo se puede cambiar con comandos:")
    Say("/diario chat <todo|importante|nada>  ·  /diario tipos <tipo> <on|off>  ·  /diario animo <on|off>  ·  /diario conversaciones <on|off>")
    SetTypes("", "")
end

SLASH_ADVENTUREJOURNAL1 = "/diario"
SLASH_ADVENTUREJOURNAL2 = "/journal"
SlashCmdList["ADVENTUREJOURNAL"] = function(message)
    local command = string.lower(message or "")
    local word, arg1, arg2 = string.match(command, "^(%S+)%s*(%S*)%s*(%S*)$")
    if command == "" or command == "abrir" then
        ns.ToggleUI()
    elseif command == "hoy" or command == "actual" then
        ns.OpenAtDay(ns.DB and ns.DB.currentDay or 1)
    elseif command == "anterior" then
        ns.OpenAtDay((ns.DB and ns.DB.currentDay or 1) - 1)
    elseif word == "diag" and arg1 == "" then
        PrintDiagnostics()
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
    elseif (word == "importar" or word == "import") and arg2 == "" then
        if arg1 == "" then
            ns.RunImport(false)
        elseif arg1 == "prueba" or arg1 == "test" then
            ns.RunImport(true)
        else
            Say("Usa /diario importar (lee AJProbe y rellena el diario) o /diario importar prueba (solo cuenta, no guarda nada).")
        end
    else
        Say("Usa /diario, /diario hoy, /diario anterior, /diario opciones, /diario chat, /diario tipos, /diario animo, /diario conversaciones, /diario importar, /diario diag o /diario debug.")
    end
end
