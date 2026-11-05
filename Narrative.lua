-- Narrative.lua: moods and the Spanish prose templates for each entry type.
local addonName, ns = ...
local SafeString = ns.SafeString

local MOODS = {
    { "Heroico", "con el ánimo firme y la sensación de que aún queda mucho por hacer" },
    { "Cínico", "con más ironía que paciencia y la esperanza puesta en la recompensa" },
    { "Salvaje", "con los nervios despiertos y ganas de resolverlo todo por la fuerza" },
    { "Erudito", "atento a los detalles y tratando de comprender lo ocurrido" },
    { "Cauteloso", "sin bajar la guardia y procurando no confiarme" },
    { "Melancólico", "pensando en el largo camino recorrido y en quienes quedaron atrás" },
}

-- Returns profile, tone. Fixed for some entry types, random for the rest.
function ns.ChooseMood(eventType)
    if eventType == "DEATH" then
        return "Derrotado", "con la amarga certeza de que esta vez el enemigo fue más rápido"
    elseif eventType == "BOSS" then
        return "Aliviado", "con el pulso todavía acelerado y la satisfacción de seguir en pie"
    elseif eventType == "LOOT" then
        return "Entusiasmado", "con la agradable impresión de que el viaje empieza a dar sus frutos"
    elseif eventType == "DISCOVERY" then
        return "Explorador", "con la curiosidad de quien acaba de encontrar un lugar nuevo"
    elseif eventType == "LEVEL" then
        return "Orgulloso", "con el orgullo tranquilo de quien sabe cuánto camino cuesta llegar hasta aquí"
    end
    local mood = MOODS[math.random(1, #MOODS)]
    return mood[1], mood[2]
end

-- Mood phrases start in lower case; capitalise one that opens a sentence (bug #13).
-- Only an ASCII first letter is touched, so multi-byte UTF-8 text is never cut.
local function Sentence(text)
    return (string.gsub(text, "^%l", string.upper))
end

function ns.ComposeEntry(entry)
    local place = SafeString(entry.place, "algún lugar del mundo")
    local subject = SafeString(entry.text, "un acontecimiento inesperado")
    local tone = SafeString(entry.contextualTone, "con el ánimo sereno")
    local sentenceTone = Sentence(tone)
    local variant = (entry.seed or 1) % 3

    if entry.type == "QUEST" then
        if variant == 1 then
            return string.format("En %s terminé la tarea «%s». %s. No parece que las obligaciones vayan a darme tregua.", place, subject, sentenceTone)
        elseif variant == 2 then
            return string.format("La jornada me llevó a resolver «%s» en %s. %s. Al menos hoy he cumplido con mi parte.", subject, place, sentenceTone)
        end
        return string.format("Queda atrás una tarea más: «%s», completada en %s. %s.", subject, place, sentenceTone)
    elseif entry.type == "BOSS" then
        return string.format("En %s me enfrenté a %s. La lucha fue intensa y, cuando el polvo se asentó, seguía en pie: %s.", place, subject, tone)
    elseif entry.type == "DEATH" then
        return string.format("La aventura se detuvo en %s. Caí antes de poder continuar; %s. Tendré que regresar con más cuidado.", place, tone)
    elseif entry.type == "LOOT" then
        return string.format("La fortuna se dejó notar en %s: apareció %s. %s.", place, subject, sentenceTone)
    elseif entry.type == "DISCOVERY" then
        return string.format("Mis pasos me condujeron hasta %s. Me detuve un momento para observar el lugar; %s.", subject, tone)
    elseif entry.type == "NPC" then
        return string.format("En %s crucé unas palabras con %s. No sé si aquel encuentro tendrá importancia, pero merece quedar anotado.", place, subject)
    elseif entry.type == "CHAT" then
        return string.format("Recibí noticias de %s mientras me encontraba en %s. Incluso en los caminos más solitarios llegan voces de otros aventureros.", subject, place)
    elseif entry.type == "LEVEL" then
        local level = type(entry.level) == "number" and entry.level or nil
        if not level then
            return string.format("En %s noté que algo había cambiado por dentro: había subido de nivel. %s.", place, sentenceTone)
        elseif variant == 1 then
            return string.format("En %s noté cómo algo cambiaba por dentro: alcancé el nivel %d. %s.", place, level, sentenceTone)
        elseif variant == 2 then
            return string.format("Subí al nivel %d en %s. No fue gratis, y se nota. %s.", level, place, sentenceTone)
        end
        return string.format("El nivel %d llegó cuando menos lo esperaba, en %s. %s.", level, place, sentenceTone)
    end
    return subject
end
