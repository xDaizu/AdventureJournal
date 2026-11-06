-- T5: the profile UI. The panel's Perfil row (with its confirmation), /diario perfil, the loot threshold
-- (panel button and /diario botin; the LOOT label follows it), the enemy in a death (panel check box and
-- /diario enemigo), "con cambios" when a setting moved away from the profile, and the one-time hint for a
-- diary that came from Chema's version.
-- Variants (H.variant):
--   panel      a fresh diary of this line, in login, /reload and second login. Where the stub has no
--              Settings API (stub `nosettings`) the same steps go through the commands only.
--   chemaold   a diary from Chema's version that already loaded here before T5 (origin = "chema",
--              settings present, no `chemaHintShown`): the hint is shown once, at the first loading
--              screen, and never again (login, /reload, second login).
-- Stub `nopopup` (no StaticPopup): the profile buttons ask for a second click instead.
local H = ...
local S, fire, advance, slash, note, ns = H.S, H.fire, H.advance, H.slash, H.note, H.ns

local function Link(color, id, name) return color .. "|Hitem:" .. id .. "::::::::1::::::::::|h[" .. name .. "]|h|r" end
S.items[2222] = { name = "Botas verdes", quality = 2, cached = true, link = Link("|cff1eff00", 2222, "Botas verdes") }
S.items[1234] = { name = "Escudo azul", quality = 3, cached = true, link = Link("|cff0070dd", 1234, "Escudo azul") }
S.items[5555] = { name = "Espada épica", quality = 4, cached = true, link = Link("|cffa335ee", 5555, "Espada épica") }

local function Settings() return AdventureJournalDB.settings end

local function Loot(id)
    advance(5)
    fire("CHAT_MSG_LOOT", "Recibes botín: " .. S.items[id].link .. ".", "", "", "", "Volgajin")
end

local function LootCount()
    local n = 0
    for _, entry in ipairs(AdventureJournalDB.days[AdventureJournalDB.currentDay].events) do
        if entry.type == "LOOT" then n = n + 1 end
    end
    return n
end

local function SettingsLine()
    local off = {}
    for _, info in ipairs(ns.VisibleTypes()) do
        if not ns.IsTypeEnabled(info.key) then off[#off + 1] = info.key end
    end
    return string.format("profile=%s status=%q chat=%s lootQuality=%s deathKiller=%s typesOff=[%s]",
        tostring(Settings().profile), ns.ProfileStatus(), tostring(Settings().chat), tostring(Settings().lootQuality),
        tostring(Settings().deathKiller), table.concat(off, ","))
end

local function ControlsLine()
    local c = ns.optionsControls
    if not c then return "(no options panel)" end
    local buttons = {}
    for _, name in ipairs(ns.PROFILE_ORDER) do buttons[#buttons + 1] = name .. "=" .. tostring(c.profileButtons[name].text) end
    return string.format("status=%q buttons[%s] loot button=%q LOOT label=%q LOOT=%s deathKiller=%s chat=%q",
        tostring(c.profileStatus.text), table.concat(buttons, " "), tostring(c.loot.text), tostring(c.types.LOOT.label.text),
        c.types.LOOT:GetChecked() and "on" or "off", c.deathKiller:GetChecked() and "on" or "off", tostring(c.chat.text))
end

local function Click(widget, checked)
    if checked ~= nil then widget:SetChecked(checked) end   -- a click toggles the box before OnClick
    widget.scripts.OnClick(widget)
end

local function LastPopup()
    local dialog = S.popups[#S.popups]
    if not dialog then return "(none)" end
    return string.format("%s shown=%s data=%s text=%q", dialog.which, tostring(dialog.shown), tostring(dialog.data), dialog.text)
end

local function Prints(from)
    local out = {}
    for index = from + 1, #S.prints do out[#out + 1] = "   " .. S.prints[index] end
    return #out > 0 and table.concat(out, "\n") or "   (nothing)"
end

-- Chema's version, after it was already loaded by T1..T4 (settings present, clásico applied).
local function ChemaOldDiary()
    return {
        version = 3, currentDay = 1, origin = "chema",
        visitedZones = { ["Orgrimmar"] = true }, knownMounts = { ["6"] = true }, knownAchievements = {},
        visited = { ["Orgrimmar"] = true },
        settings = { chat = "all", lootQuality = 4, profile = "clasico", deathKiller = true, showProfile = false,
            conversations = false,
            types = { QUEST = true, BOSS = true, DEATH = true, LOOT = true, DISCOVERY = true, NPC = false, CHAT = false,
                LEVEL = false, GROUP = false, REPUTATION = false, SKILL = false, SPELL = false, QUEST_ACCEPT = true,
                REVISIT = true, MOUNT = true, ACHIEVEMENT = true, GUILD = true } },
        days = { [1] = { startedAt = "2026-11-04 18:57:25", dateLabel = "04/11/2026", events = {} } },
    }
end

if H.variant == "chemaold" then
    if H.mode == "login" then AdventureJournalDB = ChemaOldDiary() end
    fire("ADDON_LOADED", "AdventureJournal")
    fire("PLAYER_LOGIN")
    local function HintLines(from)
        local n = 0
        for index = from + 1, #S.prints do
            if string.find(S.prints[index], "1.1.0-Forever", 1, true)
                or string.find(S.prints[index], "Este aviso no se repite", 1, true) then
                n = n + 1
            end
        end
        return n
    end
    local before = #S.prints
    S.zone, S.subZone = "Orgrimmar", ""
    fire("PLAYER_ENTERING_WORLD", H.mode ~= "reload", H.mode == "reload")
    note(string.format("%s: hint lines printed at the loading screen = %d; chemaHintShown = %s; %s", H.mode, HintLines(before),
        tostring(AdventureJournalDB.chemaHintShown), SettingsLine()))
    local later = #S.prints
    fire("PLAYER_ENTERING_WORLD", false, false)   -- a later loading screen in the same session
    note("a later loading screen in the same session: hint lines = " .. HintLines(later))
    fire("PLAYER_LOGOUT")
    return
end

-- variant "panel" ----------------------------------------------------------------------------
fire("ADDON_LOADED", "AdventureJournal")
fire("PLAYER_LOGIN")
S.zone, S.subZone = "Durotar", "Valle de los Retos"
fire("PLAYER_ENTERING_WORLD", H.mode ~= "reload", H.mode == "reload")
slash("opciones")
local c = ns.optionsControls
note("popup available = " .. tostring(StaticPopup_Show ~= nil) .. "; panel = " .. tostring(c ~= nil)
    .. (c and ("; in a scroll frame = " .. tostring(c.scroll ~= nil) .. ", content height " .. tostring(c.contentHeight)) or ""))

if H.mode == "login" then
    note("fresh diary: " .. SettingsLine())
    note("controls: " .. ControlsLine())

    -- The loot threshold: the button cycles and the LOOT label follows; only items at or above it are logged.
    Loot(1234)
    note("rare item with the threshold at rare: LOOT entries = " .. LootCount())
    if c then Click(c.loot) else slash("botin épico") end
    note("threshold to epic: " .. ControlsLine())
    Loot(1234)
    note("rare item with the threshold at epic: LOOT entries = " .. LootCount())
    Loot(5555)
    note("epic item with the threshold at epic: LOOT entries = " .. LootCount())
    if c then
        Click(c.loot)
        note("loot button once more: " .. tostring(c.loot.text) .. " / " .. tostring(c.types.LOOT.label.text))
        Click(c.loot)
        note("and again (wraps): " .. tostring(c.loot.text) .. " / " .. tostring(c.types.LOOT.label.text))
        Loot(2222)
        note("uncommon item with the threshold at uncommon: LOOT entries = " .. LootCount())
    end
    slash("botin raro")
    slash("botin poco común")
    slash("botin")
    slash("botin xyz")
    slash("botin épico")
    slash("tipos")
    note("after the commands: " .. SettingsLine())
    note("controls: " .. ControlsLine())

    -- The enemy in a death.
    if c then Click(c.deathKiller, true) else slash("enemigo on") end
    note("enemy in deaths on: " .. SettingsLine())
    slash("enemigo")
    slash("enemigo off")
    slash("enemigo on")
    note("controls: " .. ControlsLine())

    -- The profile row. Confirmation first: nothing changes until it is accepted.
    if c then
        local before = #S.prints
        Click(c.profileButtons.clasico)
        note("Clásico clicked: " .. (StaticPopup_Show and LastPopup() or ("button now reads " .. tostring(c.profileButtons.clasico.text))))
        note("before confirming: " .. SettingsLine())
        if StaticPopup_Show then
            S.PressPopup("cancel")
            note("cancelled: " .. SettingsLine())
            Click(c.profileButtons.clasico)
            S.PressPopup("accept")
        else
            -- The other button disarms the first; closing the panel disarms too.
            Click(c.profileButtons.ampliado)
            note("Ampliado clicked instead: clasico=" .. tostring(c.profileButtons.clasico.text) .. ", ampliado=" .. tostring(c.profileButtons.ampliado.text))
            ns.optionsPanel:Hide()
            note("panel closed: ampliado=" .. tostring(c.profileButtons.ampliado.text) .. "; " .. SettingsLine())
            ns.optionsPanel:Show()
            Click(c.profileButtons.clasico)
            Click(c.profileButtons.clasico)
        end
        note("confirmed: " .. SettingsLine())
        note("controls: " .. ControlsLine())
        note("chat after applying:\n" .. Prints(before))
    else
        slash("perfil clasico")
        note("applied by command: " .. SettingsLine())
    end

    -- A setting changed by hand: "con cambios"; changed back: the profile's name again.
    slash("tipos nivel on")
    note("LEVEL on by hand: " .. SettingsLine())
    note("controls: " .. ControlsLine())
    slash("tipos nivel off")
    note("LEVEL off again: " .. SettingsLine())

    -- The commands.
    local before = #S.prints
    slash("perfil")
    slash("perfil raro")
    slash("perfil clasico")
    slash("perfil ampliado")
    note("commands:\n" .. Prints(before))
    note("after /diario perfil ampliado: " .. SettingsLine())
    note("controls: " .. ControlsLine())

    -- Settings that equal the other profile are named after it (here: the record says clásico).
    Settings().profile = "clasico"
    note("record says clasico, settings are ampliado's: status " .. ns.ProfileStatus())
    Settings().profile = "ampliado"

    -- What survives: clásico, then the loot threshold moved to legendary.
    slash("perfil clasico")
    slash("botin legendario")
    note("end of login: " .. SettingsLine())
    fire("PLAYER_LOGOUT")
    return
end

-- /reload and second login: the settings and the panel are as they were left.
note(H.mode .. ": " .. SettingsLine())
note("controls: " .. ControlsLine())
note("diary of this line: hint flag = " .. tostring(AdventureJournalDB.chemaHintShown))
if H.mode == "reload" then
    slash("botin raro")
    note("threshold back to rare: " .. SettingsLine())
end
fire("PLAYER_LOGOUT")
