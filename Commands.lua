-- Commands.lua: slash commands and the key binding (Bindings.xml).
-- These are the addon's only globals besides AdventureJournalDB.
local addonName, ns = ...

BINDING_HEADER_ADVENTUREJOURNAL = "Diario de Aventuras"
BINDING_NAME_ADVENTUREJOURNAL_TOGGLE = "Abrir / cerrar el diario"

-- Called by the key binding in Bindings.xml.
function AdventureJournal_ToggleUI()
    ns.ToggleUI()
end

SLASH_ADVENTUREJOURNAL1 = "/diario"
SLASH_ADVENTUREJOURNAL2 = "/journal"
SlashCmdList["ADVENTUREJOURNAL"] = function(message)
    local command = string.lower(message or "")
    if command == "" or command == "abrir" then
        ns.ToggleUI()
    elseif command == "hoy" or command == "actual" then
        ns.OpenAtDay(ns.DB and ns.DB.currentDay or 1)
    elseif command == "anterior" then
        ns.OpenAtDay((ns.DB and ns.DB.currentDay or 1) - 1)
    else
        print("|cFFFFD700[Diario]|r Usa /diario, /diario hoy o /diario anterior.")
    end
end
