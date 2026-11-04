-- Commands.lua: slash commands and the key binding (Bindings.xml).
-- These are the addon's only globals besides AdventureJournalDB.
local addonName, ns = ...

BINDING_HEADER_ADVENTUREJOURNAL = "Diario de Aventuras"
BINDING_NAME_ADVENTUREJOURNAL_TOGGLE = "Abrir / cerrar el diario"

-- Called by the key binding in Bindings.xml.
function AdventureJournal_ToggleUI()
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
    end
    Say(string.format("Patrones de botín propio: %d (0 = se acepta todo el botín)", #ns.GetOwnLootPatterns()))

    for _, row in ipairs(ns.GetApiBranches()) do Say(row[1] .. ": " .. row[2]) end

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

local function SetDebug(arg1, arg2)
    if arg1 == "on" then
        ns.debug.on = true
        Say("Depuración activada: verás la carga de cada evento. /diario debug off la apaga.")
    elseif arg1 == "off" then
        ns.debug.on, ns.debug.secrets = false, false
        Say("Depuración y secretos simulados desactivados.")
    elseif arg1 == "secrets" then
        if arg2 == "off" then
            ns.debug.secrets = false
            Say("Secretos simulados desactivados.")
        else
            ns.debug.secrets, ns.debug.on = true, true
            Say("Secretos simulados ACTIVADOS (y la depuración). Los textos de los eventos se tratan como secretos. /diario debug secrets off o /reload lo apaga.")
        end
    else
        Say("Usa /diario debug on, /diario debug off o /diario debug secrets.")
    end
end

-- /diario chat: what the diary echoes to the chat window (settings.chat).
local CHAT_MODES = {
    todo = "all", all = "all",
    importante = "important", important = "important",
    nada = "off", off = "off",
}
local CHAT_MODE_NAMES = { all = "todo", important = "importante", off = "nada" }

local function SetChatMode(word)
    local settings = ns.EnsureDatabase().settings
    local mode = CHAT_MODES[word]
    if mode then
        settings.chat = mode
        Say("Mensajes en el chat: " .. CHAT_MODE_NAMES[mode] .. ".")
    else
        Say("Mensajes en el chat: " .. (CHAT_MODE_NAMES[settings.chat] or "?")
            .. ". Usa /diario chat todo, /diario chat importante (jefes, muertes y botín épico) o /diario chat nada.")
    end
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
    else
        Say("Usa /diario, /diario hoy, /diario anterior, /diario chat, /diario diag o /diario debug.")
    end
end
