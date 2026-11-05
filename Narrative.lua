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
    elseif entry.type == "GROUP" then
        local kind = entry.groupEvent
        if kind == "join" then
            if variant == 1 then
                return string.format("En %s se sumó %s a mi grupo. Caminar acompañado cambia el sabor de cualquier aventura.", place, subject)
            elseif variant == 2 then
                return string.format("%s se unió a mi grupo en %s. No es poca cosa tener a alguien que te cubra la espalda.", subject, place)
            end
            return string.format("Mi grupo creció en %s: %s se nos unió. Veremos qué da de sí la compañía.", place, subject)
        elseif kind == "leave" then
            if variant == 1 then
                return string.format("En %s, %s dejó el grupo. El camino volvió a quedarse un poco más solo.", place, subject)
            elseif variant == 2 then
                return string.format("%s se separó de mi grupo en %s. Cada cual sigue su propio rumbo.", subject, place)
            end
            return string.format("En %s, %s abandonó el grupo; ojalá nos volvamos a cruzar.", place, subject)
        elseif kind == "selfleave" then
            if variant == 1 then
                return string.format("En %s dejé el grupo y seguí mi propio camino. %s.", place, sentenceTone)
            end
            return string.format("Dejé el grupo en %s. A veces el mejor paso es el que se da en solitario.", place)
        elseif kind == "disband" then
            return string.format("En %s el grupo se disolvió y cada cual tomó su rumbo. %s.", place, sentenceTone)
        elseif kind == "youjoin" then
            return string.format("En %s me uní a un grupo para afrontar una instancia. No sabría decir con quién caminé.", place)
        end
        return string.format("Algo cambió en mi grupo en %s.", place)
    elseif entry.type == "REPUTATION" then
        local standing = SafeString(entry.standing, "")
        if entry.repEvent == "standing" and standing ~= "" then
            if variant == 1 then
                return string.format("En %s mi relación con %s cambió: ahora soy %s ante ellos. %s.", place, subject, standing, sentenceTone)
            elseif variant == 2 then
                return string.format("Ante %s ya soy %s. Lo supe en %s, y no es poca cosa.", subject, standing, place)
            end
            return string.format("%s me tiene ahora por %s; lo comprobé en %s.", subject, standing, place)
        end
        if variant == 1 then
            return string.format("En %s empecé a ganarme la confianza de %s. %s.", place, subject, sentenceTone)
        elseif variant == 2 then
            return string.format("Mis actos en %s no pasaron desapercibidos para %s: su opinión de mí empieza a mejorar.", place, subject)
        end
        return string.format("%s empieza a mirarme con mejores ojos, y todo ocurrió en %s. %s.", subject, place, sentenceTone)
    elseif entry.type == "SKILL" then
        local rank = type(entry.rank) == "number" and entry.rank or nil
        if entry.skillEvent == "rank" and rank then
            if variant == 1 then
                return string.format("En %s mi destreza en %s llegó a %d. Se nota la práctica. %s.", place, subject, rank, sentenceTone)
            elseif variant == 2 then
                return string.format("%s ya está en %d. Lo noté en %s: la repetición acaba dando sus frutos.", subject, rank, place)
            end
            return string.format("A fuerza de insistir, mi habilidad en %s subió a %d en %s.", subject, rank, place)
        end
        if variant == 1 then
            return string.format("En %s aprendí algo que no sabía: %s. %s.", place, subject, sentenceTone)
        elseif variant == 2 then
            return string.format("Una habilidad nueva se suma a mi repertorio en %s: %s.", place, subject)
        end
        return string.format("%s: una destreza más que anotar. Fue en %s. %s.", subject, place, sentenceTone)
    elseif entry.type == "SPELL" then
        local what = "un nuevo hechizo"
        if entry.learnKind == "ability" then what = "una nueva habilidad" elseif entry.learnKind == "passive" then what = "una nueva habilidad pasiva" end
        if variant == 1 then
            return string.format("En %s aprendí %s: %s. %s.", place, what, subject, sentenceTone)
        elseif variant == 2 then
            return string.format("Hay %s más en mi repertorio: %s. Lo aprendí en %s.", what, subject, place)
        end
        return string.format("%s entra a formar parte de lo que sé hacer (%s, aprendido en %s).", subject, what, place)
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
