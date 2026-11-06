-- Narrative.lua: moods and the Spanish prose of each entry type.
--
-- T2: the prose is Chema's (his Locales.lua at fa20e9f, 1.1.0-Forever), for everyone (decision D2),
-- with his typos fixed and feminine variants (decision D3). The types his line never had (CHAT, GROUP,
-- REPUTATION, SKILL, SPELL, LEVEL without a level) have variants written in his voice.
--
-- Template syntax (no string.format, so a value can never break the format):
--   {place} {name} {npc} {killer} {level} {rank} {standing} {what}   the entry's values
--   {mood}   the mood phrase as stored (lower case), for use after ";" or ","
--   {Mood}   the same phrase with its first letter capitalised, to open a sentence
--   {masculino|femenino}   picked by the player's sex (ns.PlayerIsFemale)
-- A list item is a string, or { "text", unnamed = "text" }: the second one is used when the name is
-- unknown (a secret or unreadable value replaced by ns.NEUTRAL_TEXT, or no killer), so no sentence
-- reads "El temible una criatura temible".
-- The variant is (seed % #list) + 1, with the entry's seed (its position in the jornada): the same
-- entry always gets the same text. Stored prose is never rewritten.
local addonName, ns = ...
local SafeString = ns.SafeString
local NEUTRAL = ns.NEUTRAL_TEXT

-- Moods --------------------------------------------------------------------------------------
-- Chema's four categories, 20 phrases each, without his final "." (the templates add it). A GENERAL
-- phrase carries the label shown with the showProfile option; the other categories take the label
-- of their entry type (TYPE_LABEL).
local MOODS = {
    DISCOVERY = {
        "con la mirada atenta a cualquier detalle imprevisto",
        "con la fascinación de adentrarme en territorio desconocido",
        "procurando no bajar la guardia en este nuevo paraje",
        "preguntándome qué secretos esconderá este lugar",
        "con el entusiasmo renovado ante lo que pueda encontrar",
        "sintiendo el peso del aire en esta zona insólita",
        "con la curiosidad a flor de piel",
        "observando cada rincón antes de dar el siguiente paso",
        "estudiando los relieves del terreno con cautela",
        "con la sensación de estar pisando tierra inexplorada",
        "respirando el ambiente propio de esta nueva región",
        "manteniendo los sentidos alerta ante cualquier movimiento",
        "con la impaciencia de descubrir qué hay tras la siguiente colina",
        "avanzando con paso medido por estas tierras vírgenes",
        "{sorprendido|sorprendida} por los paisajes que se abren ante mí",
        "con el mapa en mente y la mirada en el horizonte",
        "sintiendo que cada rincón guarda una historia por contar",
        "{preparado|preparada} para responder ante cualquier peligro inesperado",
        "{maravillado|maravillada} por la atmósfera singular de este paraje",
        "{listo|lista} para dejar mi impronta en estas fronteras lejanas",
    },
    REVISIT = {
        "recordando viejas batallas disputadas en estos caminos",
        "con la tranquilidad de quien ya conoce los peligros del terreno",
        "pensando en cuánto han cambiado las cosas desde mi última visita",
        "avanzando con paso firme por un camino ya conocido",
        "sin entretenerme más de lo estrictamente necesario",
        "atento a si algún nuevo peligro acecha en la zona",
        "notando cómo la nostalgia se mezcla con el deber",
        "reconociendo las referencias del paisaje a cada trecho",
        "con la certeza de saber exactamente hacia dónde me dirijo",
        "observando los viejos senderos con familiaridad",
        "sabiendo de antemano qué criaturas me saldrán al paso",
        "reviviendo en silencio las primeras jornadas en estas tierras",
        "sintiendo la comodidad de un terreno que no me guarda secretos",
        "con la soltura de quien ha recorrido este trayecto mil veces",
        "comprobando si las sombras de antaño aún habitan el lugar",
        "moviéndome con agilidad entre los caminos habituales",
        "sintiendo que el tiempo pasa, pero el peligro permanece",
        "con la compostura de quien regresa con más experiencia",
        "repasando en la mente las vivencias de anteriores travesías",
        "prosiguiendo el viaje por senderos de sobra conocidos",
    },
    DEATH = {
        "con la amarga certeza de que debí ser más prudente",
        "maldiciendo mi suerte y jurando venganza",
        "con la lección aprendida a un precio demasiado alto",
        "sabiendo que la muerte es solo un tropiezo en mi camino",
        "con el orgullo herido pero la determinación intacta",
        "asimilando el amargo sabor de la derrota",
        "prometiendo no cometer el mismo error en el próximo intento",
        "sintiendo cómo la rabia aviva las ganas de volver a luchar",
        "guardando un silencio sombrío mientras recupero el aliento",
        "con la mente centrada en cómo cambiar las tornas a mi favor",
        "recordando que en Azeroth la confianza se paga cara",
        "con los puños cerrados y el deseo de revancha ardiendo",
        "reconociendo la superioridad temporal del rival",
        "sacudiéndome el polvo del suelo tras un choque fatal",
        "con la fría promesa de un retorno implacable",
        "sabiendo que cada caída solo me hace más fuerte",
        "repasando en mi cabeza el segundo en que todo falló",
        "con la resolución firme de no dejar esta afrenta sin respuesta",
        "mirando al frente mientras rehago mis fuerzas",
        "apretando los dientes ante un final imprevisto",
    },
    GENERAL = {
        { "con el ánimo firme y la mente despejada", "{Heroico|Heroica}" },
        { "con más ironía que paciencia", "{Cínico|Cínica}" },
        { "con los nervios despiertos y la mano en la empuñadura", "Salvaje" },
        { "reflexionando sobre los acontecimientos recientes", "{Erudito|Erudita}" },
        { "procurando no confiarme demasiado", "{Cauteloso|Cautelosa}" },
        { "pensando en el largo camino que aún me aguarda", "{Melancólico|Melancólica}" },
        { "observando con recelo las sombras del camino", "{Cauteloso|Cautelosa}" },
        { "ajustando mis pertrechos para lo que esté por venir", "{Cauteloso|Cautelosa}" },
        { "sintiendo el cansancio acumulado en las piernas", "{Melancólico|Melancólica}" },
        { "con la templanza que otorga el hábito de viajar", "{Erudito|Erudita}" },
        { "manteniendo una actitud serena ante la adversidad", "{Heroico|Heroica}" },
        { "con el pensamiento puesto en el descanso de la próxima posada", "{Cínico|Cínica}" },
        { "avanzando sin prisa pero sin pausa", "{Cauteloso|Cautelosa}" },
        { "sopesando cada decisión antes de actuar", "{Erudito|Erudita}" },
        { "con la mente puesta en la siguiente meta", "{Heroico|Heroica}" },
        { "notando el peso de la armadura sobre los hombros", "{Melancólico|Melancólica}" },
        { "con la determinación intacta a pesar de las dificultades", "{Heroico|Heroica}" },
        { "escuchando el rumor del viento entre la vegetación", "Salvaje" },
        { "con el espíritu preparado para cualquier eventualidad", "{Cauteloso|Cautelosa}" },
        { "contemplando el horizonte con determinación", "{Heroico|Heroica}" },
    },
}
local MOOD_CATEGORY = { DISCOVERY = "DISCOVERY", REVISIT = "REVISIT", DEATH = "DEATH" }
local TYPE_LABEL = {
    DEATH = "{Derrotado|Derrotada}", BOSS = "{Aliviado|Aliviada}", LOOT = "{Entusiasmado|Entusiasmada}",
    DISCOVERY = "{Explorador|Exploradora}", REVISIT = "{Viajero|Viajera}", LEVEL = "{Orgulloso|Orgullosa}",
}
-- Entries without a mood (saved before it existed, or the demo diary) get this one.
local DEFAULT_TONE = "con el ánimo sereno"

-- Zone entries: a header per travel method (Chema's red headers) and one body each --------------
-- travelMethod arrives in T4; until then every place is ON_FOOT.
local ZONE_HEADERS = {
    HEARTHSTONE = { "Regreso en Piedra del Hogar: {name}", "Retorno Mágico a {name}" },
    TELEPORT = { "Teletransporte a {name}", "Llegada Portal: {name}" },
    TAXI = { "Vuelo hacia {name}", "Desembarco Aéreo en {name}" },
    ON_FOOT = { "Llegada a {name}", "Nuevos Horizontes: {name}", "Explorando {name}" },
    ON_FOOT_REVISIT = { "Regreso a {name}", "Viejos Caminos en {name}", "Explorando {name}" },
}
local ZONE_BODIES = {
    HEARTHSTONE = "Invoqué el poder de mi piedra del hogar para regresar a {name}. {Mood}.",
    TELEPORT = "Crucé un umbral mágico que me canalizó directamente hasta {name}. {Mood}.",
    TAXI = "Aterricé en {name} tras completar la travesía en grifo/mantícora. {Mood}.",
    ON_FOOT = "Descubrí por primera vez la región de {name} a pie de camino. {Mood}.",
    ON_FOOT_REVISIT = "Volví a recorrer a pie las tierras de {name}. {Mood}.",
}

-- Templates per type ---------------------------------------------------------------------------
local T = {}

T.QUEST = {
    "En {place} cumplí finalmente con lo acordado al finalizar «{name}». {Mood}.",
    "La jornada dio sus frutos en {place} tras dar por terminada la tarea «{name}». {Mood}.",
    "Dejé atrás la misión «{name}» completada con éxito mientras recorría {place}. {Mood}.",
    "Al fin concluyó el encargo «{name}» en {place}. {Mood}.",
    "Cerré el asunto de «{name}» mientras permanecía en {place}. {Mood}.",
    "Los habitantes de {place} mostraron su agradecimiento tras completar «{name}». {Mood}.",
    "Puse fin a las complicaciones de «{name}» durante mi paso por {place}. {Mood}.",
    "Cumplí hasta el último detalle del encargo «{name}» en tierras de {place}. {Mood}.",
    "Tras no pocos esfuerzos en {place}, logré rematar la misión «{name}». {Mood}.",
    "Entregué el trabajo de «{name}» antes de proseguir el camino por {place}. {Mood}.",
    "El deber me reclamó en {place} y respondí completando «{name}». {Mood}.",
    "Una preocupación menos en {place} tras solventar «{name}». {Mood}.",
    "{Satisfecho|Satisfecha} por haber culminado «{name}» con éxito en {place}. {Mood}.",
    "La promesa hecha en {place} quedó saldada al resolver «{name}». {Mood}.",
    "Dejé resuelta la encomienda «{name}» mientras exploraba {place}. {Mood}.",
    "El esfuerzo invertido en «{name}» valió la pena al recorrer {place}. {Mood}.",
    "Se dio por concluido el compromiso con «{name}» en {place}. {Mood}.",
    "Un nuevo logro anotado en mi haber tras finalizar «{name}» en {place}. {Mood}.",
    "Tras superar varios contratiempos en {place}, di por finalizada la misión «{name}». {Mood}.",
    "Anoté la resolución de «{name}» en mi cuaderno de viaje mientras permanecía en {place}. {Mood}.",
}
-- The title could not be read.
T.QUEST_UNNAMED = {
    "En {place} cumplí con lo acordado, aunque el nombre del encargo se me ha borrado de la memoria. {Mood}.",
    "La jornada dio sus frutos en {place} tras dar por terminada una tarea cuyo nombre no anoté. {Mood}.",
    "Al fin concluyó otro encargo en {place}, uno cuyo nombre no llegué a apuntar. {Mood}.",
    "Cerré un asunto pendiente mientras permanecía en {place}. {Mood}.",
    "Cumplí hasta el último detalle de un encargo en tierras de {place}. {Mood}.",
    "Una preocupación menos en {place} tras solventar una misión de la que no guardo el nombre. {Mood}.",
    "{Satisfecho|Satisfecha} por haber culminado otra misión con éxito en {place}. {Mood}.",
    "Entregué el trabajo encomendado antes de proseguir el camino por {place}. {Mood}.",
    "El deber me reclamó en {place} y respondí completando una misión más. {Mood}.",
    "La promesa hecha en {place} quedó saldada, aunque el nombre del encargo se me escapa. {Mood}.",
}

T.QUEST_ACCEPT = {
    "Acepté el encargo «{name}» de manos de {npc} mientras me encontraba en {place}. {Mood}.",
    "Me comprometí con {npc} a llevar a cabo la misión «{name}» en {place}. {Mood}.",
    "Escuché la petición de {npc} en {place} y asumí la encomienda «{name}». {Mood}.",
    "Anoté en mis tareas pendientes la petición «{name}» tras hablar con {npc} en {place}. {Mood}.",
    "Un nuevo objetivo fijado en {place}: {npc} me encomendó la misión «{name}». {Mood}.",
    "Atendí a {npc} en {place} y acepté hacerme cargo de «{name}». {Mood}.",
    "Me puse a disposición de {npc} para cumplir con «{name}» en tierras de {place}. {Mood}.",
    "Sumé una nueva responsabilidad tras aceptar la propuesta de {npc} sobre «{name}» en {place}. {Mood}.",
    "Comencé las indagaciones para el asunto «{name}» por petición de {npc} en {place}. {Mood}.",
    "Acepté la encomienda de {npc} respecto a «{name}» mientras exploraba {place}. {Mood}.",
    "Tomé el encargo «{name}» que me ofreció {npc} en {place} con intención de resolverlo pronto. {Mood}.",
    "El camino me llevó ante {npc} en {place}, donde acepté la misión «{name}». {Mood}.",
    "Me ofrecí a prestar ayuda a {npc} con «{name}» durante mi estancia en {place}. {Mood}.",
    "Anoté los detalles indicados por {npc} para la misión «{name}» en {place}. {Mood}.",
    "Recibí las instrucciones de {npc} para la tarea «{name}» en {place}. {Mood}.",
    "Firmé el compromiso con {npc} para resolver «{name}» en {place}. {Mood}.",
    "Un nuevo cometido requiere mi atención en {place} tras hablar con {npc}: «{name}». {Mood}.",
    "Acepté la petición de {npc} sobre «{name}» en {place} sin dudarlo. {Mood}.",
    "Inicié la tarea «{name}» a petición de {npc} mientras recorría {place}. {Mood}.",
    "Prometí a {npc} ocuparme del asunto «{name}» durante mi paso por {place}. {Mood}.",
}
T.QUEST_ACCEPT_UNNAMED = {
    "Acepté un nuevo encargo de manos de {npc} mientras me encontraba en {place}. {Mood}.",
    "Me comprometí con {npc} a llevar a cabo una misión en {place}. {Mood}.",
    "Escuché la petición de {npc} en {place} y asumí la encomienda. {Mood}.",
    "Un nuevo objetivo fijado en {place}: {npc} me encomendó una misión. {Mood}.",
    "Atendí a {npc} en {place} y acepté hacerme cargo de su petición. {Mood}.",
    "Recibí las instrucciones de {npc} para una nueva tarea en {place}. {Mood}.",
    "Prometí a {npc} ocuparme de un asunto durante mi paso por {place}. {Mood}.",
    "Sumé una nueva responsabilidad tras aceptar la propuesta de {npc} en {place}. {Mood}.",
}

T.BOSS = {
    "En {place} me enfrenté a {name}. La lucha fue encarnizada y, cuando el polvo se asentó, continuaba en pie. {Mood}.",
    { "El temible {name} sucumbió ante mi fuerza en {place}. {Mood}.",
      unnamed = "Una criatura temible sucumbió ante mi fuerza en {place}. {Mood}." },
    "Una encarnizada contienda en {place} acabó con la caída de {name}. {Mood}.",
    "Logré doblegar a {name} en las tierras de {place}. {Mood}.",
    "La amenaza que representaba {name} en {place} quedó neutralizada tras un combate implacable. {Mood}.",
    "No hubo piedad en {place}: {name} mordió el polvo tras un enfrentamiento brutal. {Mood}.",
    { "Desafié al poderoso {name} en {place} y salí {victorioso|victoriosa} contra todo pronóstico. {Mood}.",
      unnamed = "Desafié a una criatura temible en {place} y salí {victorioso|victoriosa} contra todo pronóstico. {Mood}." },
    "El suelo de {place} se estremeció durante la batalla contra {name}, pero mi determinación no cedió. {Mood}.",
    "Cobré la cabeza de {name} tras una prueba de fuerza y temple en {place}. {Mood}.",
    "Ni toda la ferocidad de {name} bastó para salvarle de la derrota en {place}. {Mood}.",
    "Puse fin al reinado de terror de {name} mientras exploraba {place}. {Mood}.",
    "El enfrentamiento contra {name} en {place} exigió hasta el último de mis recursos, pero la victoria fue mía. {Mood}.",
    "Tras un cruce de golpes legendario en {place}, {name} acabó rindiendo el aliento. {Mood}.",
    "Añadí la derrota de {name} a mi historial de grandes gestas en {place}. {Mood}.",
    "Se entonarán canciones sobre la caída de {name} en {place}. {Mood}.",
    "Vencí a {name} en su propio territorio dentro de {place}. {Mood}.",
    "El destino de {name} quedó sellado en {place} tras una sangrienta escaramuza. {Mood}.",
    "Superé el desafío mortífero que suponía {name} en las profundidades de {place}. {Mood}.",
    { "La bestia conocida como {name} sucumbió al fin en {place}. {Mood}.",
      unnamed = "Una bestia temible sucumbió al fin en {place}. {Mood}." },
    "Dejé el cadáver de {name} atrás en {place} y proseguí mi camino. {Mood}.",
}

-- {killer} is Chema's field (entry.killer). Without one (this line until T4 adds deathKiller, and every
-- death whose enemy is unknown) the unnamed text is used: it never invents an enemy.
T.DEATH = {
    { "La aventura se detuvo bruscamente en {place}. Sucumbí ante {killer}; {mood}.",
      unnamed = "La aventura se detuvo bruscamente en {place}. Sucumbí sin remedio; {mood}." },
    { "Mis fuerzas fallaron en {place} frente a {killer}. {Mood}.",
      unnamed = "Mis fuerzas fallaron en {place}. {Mood}." },
    { "El camino se tiñó de peligro en {place} cuando {killer} me superó en combate. {Mood}.",
      unnamed = "El camino se tiñó de peligro en {place} y no salí con vida. {Mood}." },
    { "Caí {derrotado|derrotada} por {killer} en {place}. Regresaré para saldar esta cuenta. {Mood}.",
      unnamed = "Caí {derrotado|derrotada} en {place}. Regresaré para saldar esta cuenta. {Mood}." },
    { "Un descuido en {place} le valió a {killer} la oportunidad de acabarme. {Mood}.",
      unnamed = "Un descuido en {place} bastó para acabar conmigo. {Mood}." },
    { "La muerte me alcanzó en {place} a manos de {killer}. {Mood}.",
      unnamed = "La muerte me alcanzó en {place}. {Mood}." },
    { "Mordí el polvo en {place} tras un fatal choque contra {killer}. {Mood}.",
      unnamed = "Mordí el polvo en {place} tras un choque fatal. {Mood}." },
    { "El cruce de armas en {place} concluyó en tragedia a favor de {killer}. {Mood}.",
      unnamed = "El cruce de armas en {place} concluyó en tragedia. {Mood}." },
    { "Fui {rebasado|rebasada} por el poder de {killer} en pleno {place}. {Mood}.",
      unnamed = "Fui {rebasado|rebasada} por el peligro en pleno {place}. {Mood}." },
    { "Las sombras se cerraron sobre mí en {place} cuando {killer} asestó el golpe definitivo. {Mood}.",
      unnamed = "Las sombras se cerraron sobre mí en {place} cuando llegó el golpe definitivo. {Mood}." },
    { "Un trágico desenlace me esperaba en {place}: {killer} acabó con mi vida. {Mood}.",
      unnamed = "Un trágico desenlace me esperaba en {place}. {Mood}." },
    { "El combate contra {killer} en {place} sobrepasó mis defensas. {Mood}.",
      unnamed = "El combate en {place} sobrepasó mis defensas. {Mood}." },
    { "Apreté los dientes al caer en {place} tras la embestida de {killer}. {Mood}.",
      unnamed = "Apreté los dientes al caer en {place}. {Mood}." },
    { "La fría caricia de la derrota me envolvió en {place} a causa de {killer}. {Mood}.",
      unnamed = "La fría caricia de la derrota me envolvió en {place}. {Mood}." },
    { "Pagué con mi vida un exceso de confianza en {place} frente a {killer}. {Mood}.",
      unnamed = "Pagué con mi vida un exceso de confianza en {place}. {Mood}." },
    { "El destino me fue adverso en {place} al cruzarme en el camino de {killer}. {Mood}.",
      unnamed = "El destino me fue adverso en {place}. {Mood}." },
    { "Mi viaje se interrumpió momentáneamente en {place} tras la victoria de {killer}. {Mood}.",
      unnamed = "Mi viaje se interrumpió momentáneamente en {place}. {Mood}." },
    { "No pude contener la ferocidad de {killer} en {place}. {Mood}.",
      unnamed = "No pude contener lo que me aguardaba en {place}. {Mood}." },
    { "Sucumbí en el terreno hostil de {place}, {abatido|abatida} por {killer}. {Mood}.",
      unnamed = "Sucumbí en el terreno hostil de {place}. {Mood}." },
    { "Mi aliento se apagó en {place} frente a {killer}, pero volveré a ponerme en pie. {Mood}.",
      unnamed = "Mi aliento se apagó en {place}, pero volveré a ponerme en pie. {Mood}." },
}

T.LOOT = {
    "La fortuna se dejó notar en {place}: me hice con {name}. {Mood}.",
    "Entre los restos hallados en {place} encontré un valioso botín: {name}. {Mood}.",
    "Un hallazgo notable en {place}: {name} ha pasado a mi posesión. {Mood}.",
    "El camino recompensó mis esfuerzos en {place} con {name}. {Mood}.",
    "Añadí a mis pertrechos {name} tras explorar {place}. {Mood}.",
    "Las tierras de {place} me regalaron un descubrimiento interesante: {name}. {Mood}.",
    "La suerte estuvo de mi lado en {place} al conseguir {name}. {Mood}.",
    "Rebuscando entre lo encontrado en {place}, di con {name}. {Mood}.",
    "Un merecido premio a la tenacidad en {place}: {name}. {Mood}.",
    "No todos los días se encuentra algo como {name} recorriendo {place}. {Mood}.",
    "Mi paciencia en {place} dio frutos al reclamar {name}. {Mood}.",
    "Guardé con cuidado {name} en mi mochila mientras permanecía en {place}. {Mood}.",
    "El azar me sonrió en {place} al toparme con {name}. {Mood}.",
    "Un útil objeto se suma a mi inventario en {place}: {name}. {Mood}.",
    "Registré la zona de {place} y no me fui con las manos vacías; obtuve {name}. {Mood}.",
    "El botín cobrado en {place} incluyó {name}. {Mood}.",
    "Incluso en los rincones más oscuros de {place} se hallan tesoros como {name}. {Mood}.",
    "Aumenté mis recursos en {place} tras hacerme con {name}. {Mood}.",
    "Un valioso hallazgo en {place} que sin duda me servirá más adelante: {name}. {Mood}.",
    "Comprobé con satisfacción el hallazgo de {name} durante mi estancia en {place}. {Mood}.",
}

-- Chema's LEVEL_UP is this line's LEVEL.
T.LEVEL = {
    "Alcancé el nivel {level} mientras exploraba {place}. Me siento con mayor fortaleza. {Mood}.",
    "Sopló un viento de renovación en {place}: ¡he ascendido al nivel {level}! {Mood}.",
    "El esfuerzo y las batallas libradas en {place} dieron su fruto al alcanzar el nivel {level}. {Mood}.",
    "Un nuevo hito en mi camino por {place} al llegar al nivel {level}. {Mood}.",
    "Sentí cómo mi poder crecía en {place}; ahora ostento el nivel {level}. {Mood}.",
    "Las vivencias acumuladas en {place} me han llevado hasta el nivel {level}. {Mood}.",
    "Di un paso más en mi desarrollo personal en {place} al alcanzar el nivel {level}. {Mood}.",
    "Mi dominio y destreza aumentaron en {place} al subir al nivel {level}. {Mood}.",
    "Un destello de energía me envolvió en {place}: ya soy nivel {level}. {Mood}.",
    "Con el nivel {level} recién adquirido en {place}, me preparo para mayores retos. {Mood}.",
    "La experiencia obtenida en {place} se tradujo en el nivel {level}. {Mood}.",
    "Forjé una mayor resistencia durante mi estancia en {place} al llegar al nivel {level}. {Mood}.",
    "Superé mis propios límites en {place} y alcancé el nivel {level}. {Mood}.",
    "Anoté con orgullo mi ascenso al nivel {level} mientras recorría {place}. {Mood}.",
    "Cada combate en {place} me acerca a la maestría; ¡ahora soy nivel {level}! {Mood}.",
    "El camino en {place} me ha curtido lo suficiente como para ascender al nivel {level}. {Mood}.",
    "Siento la sangre hervir de determinación en {place} tras lograr el nivel {level}. {Mood}.",
    "Un avance significativo en mis facultades tras alcanzar el nivel {level} en {place}. {Mood}.",
    "El constante aprendizaje en {place} dio sus frutos al subir al nivel {level}. {Mood}.",
    "Renové mis votos de aventura en {place} tras coronar el nivel {level}. {Mood}.",
}
-- The level could not be read (a secret).
T.LEVEL_UNNAMED = {
    "Sentí cómo mi poder crecía en {place}; algo había cambiado por dentro. {Mood}.",
    "Sopló un viento de renovación en {place}: ¡he subido de nivel! {Mood}.",
    "El esfuerzo y las batallas libradas en {place} dieron su fruto: subí de nivel. {Mood}.",
    "Un nuevo hito en mi camino por {place}: he crecido en experiencia. {Mood}.",
    "Las vivencias acumuladas en {place} me han hecho más fuerte. {Mood}.",
    "Mi dominio y destreza aumentaron en {place} al subir de nivel. {Mood}.",
    "Un destello de energía me envolvió en {place}: ya no soy quien era al partir. {Mood}.",
    "Superé mis propios límites en {place} y subí de nivel. {Mood}.",
    "Anoté con orgullo un nuevo ascenso mientras recorría {place}. {Mood}.",
    "El camino en {place} me ha curtido lo suficiente como para dar un paso más. {Mood}.",
}

T.NPC = {
    "En {place} crucé unas palabras con {name}. {Mood}.",
    "Durante mi paso por {place} mantuve una breve conversación con {name}. {Mood}.",
    "Me detuve a charlar con {name} en las inmediaciones de {place}. {Mood}.",
    "Escuché atentamente lo que {name} tenía que decir en {place}. {Mood}.",
    "Un encuentro curioso en {place}: entablé contacto con {name}. {Mood}.",
    "Intercambié noticias sobre los caminos con {name} en {place}. {Mood}.",
    "Consulté ciertos detalles con {name} mientras permanecía en {place}. {Mood}.",
    "En pleno {place} me crucé con {name}, quien me ofreció su particular punto de vista. {Mood}.",
    "Compartí unos minutos de charla con {name} en {place} antes de proseguir. {Mood}.",
    "Aproveché mi estancia en {place} para hablar con {name}. {Mood}.",
    "Recibí valiosos consejos de {name} al encontrarme en {place}. {Mood}.",
    "Coincidí con {name} en la zona de {place}. {Mood}.",
    "Intercambié un saludo cordial con {name} durante mi trayecto por {place}. {Mood}.",
    "El camino en {place} me llevó hasta {name}, con quien conversé un rato. {Mood}.",
    "Escuché los rumores que circulaban de boca de {name} en {place}. {Mood}.",
    "Establecí conversación con {name} mientras recorría {place}. {Mood}.",
    -- Chema's "tras encontrármelo" assumed the NPC is male.
    "Anoté las palabras de {name} tras nuestro encuentro en {place}. {Mood}.",
    "Un momento de respiro en {place} charlando con {name}. {Mood}.",
    "Crucé opiniones sobre el estado de la región con {name} en {place}. {Mood}.",
    "Dejé constancia de mi encuentro con {name} en las tierras de {place}. {Mood}.",
}

-- A whisper received: {name} is the sender ("alguien" when unreadable), never the message.
T.CHAT = {
    "Recibí noticias de {name} mientras me encontraba en {place}. Incluso en los caminos más solitarios llegan voces de otros aventureros.",
    "Un susurro de {name} me alcanzó en {place}. {Mood}.",
    "Durante mi paso por {place}, {name} me hizo llegar unas palabras.",
    "En {place} recibí un mensaje de {name}. {Mood}.",
    "Las palabras de {name} llegaron hasta mí en {place}. {Mood}.",
    "Mientras recorría {place}, {name} quiso hablar conmigo en confianza.",
    "Anoté que {name} me buscó con un susurro en {place}. {Mood}.",
    "Ni en {place} se está a salvo de las noticias: {name} me escribió.",
    "Un mensaje discreto de {name} me encontró en {place}. {Mood}.",
    "En las tierras de {place} me llegó la voz de {name}. {Mood}.",
}

-- GROUP: {name} is the player who joins or leaves.
T.GROUP_join = {
    "En {place} se sumó {name} a mi grupo. Caminar en compañía cambia el sabor de cualquier aventura.",
    "{name} se unió a mi grupo en {place}. No es poca cosa tener a alguien que te cubra la espalda.",
    "Mi grupo creció en {place}: {name} se unió a la marcha. {Mood}.",
    "Acogí a {name} en mi grupo mientras recorría {place}. {Mood}.",
    "Un nuevo par de manos para la causa: {name} se unió a nosotros en {place}.",
    "Desde {place}, {name} comparte camino conmigo. {Mood}.",
    "Sumé a {name} a mi grupo durante mi paso por {place}. Veremos qué da de sí la compañía.",
    "En {place} cerré filas con {name}; juntos llegaremos más lejos. {Mood}.",
    "{name} decidió acompañarme por las tierras de {place}. {Mood}.",
    "Anoté la llegada de {name} a mi grupo en {place}. {Mood}.",
}
T.GROUP_leave = {
    "En {place}, {name} dejó el grupo. El camino volvió a quedarse un poco más solo.",
    "{name} se separó de mi grupo en {place}. Cada cual sigue su propio rumbo.",
    "En {place}, {name} abandonó el grupo; ojalá nos volvamos a cruzar.",
    "Me despedí de {name} en {place}, donde nuestros caminos se separaron. {Mood}.",
    "{name} tomó otro rumbo al dejar el grupo en {place}. {Mood}.",
    "Las filas del grupo menguaron en {place}: {name} siguió su propio camino.",
    "Perdí la compañía de {name} durante mi paso por {place}. {Mood}.",
    "En las tierras de {place}, {name} se despidió del grupo. {Mood}.",
    "Anoté la marcha de {name}, que dejó el grupo en {place}. {Mood}.",
    "{name} partió por su cuenta en {place}. Que la fortuna le acompañe.",
}
T.GROUP_selfleave = {
    "En {place} dejé el grupo y seguí mi propio camino. {Mood}.",
    "Dejé el grupo en {place}. A veces el mejor paso es el que se da en solitario.",
    "Me despedí de mis compañeros en {place} para proseguir por mi cuenta. {Mood}.",
    "Abandoné el grupo durante mi paso por {place}. {Mood}.",
    "En {place} decidí que era hora de viajar de nuevo en solitario. {Mood}.",
    "Tomé mi propio rumbo en {place}, lejos del grupo. {Mood}.",
    "Me separé del grupo en las tierras de {place}. {Mood}.",
    "Puse fin a mi paso por el grupo mientras recorría {place}. {Mood}.",
    "En {place} volví a quedarme a solas con el camino. {Mood}.",
    "Me retiré del grupo en {place}, con la vista puesta en mis propios asuntos.",
}
T.GROUP_disband = {
    "En {place} el grupo se disolvió y cada cual tomó su rumbo. {Mood}.",
    "El grupo llegó a su fin en {place}. {Mood}.",
    "Nuestra compañía se deshizo en {place}; cada cual partió por su lado.",
    "En las tierras de {place} se disolvió el grupo con el que viajaba. {Mood}.",
    "Se rompieron las filas en {place}: el grupo dejó de existir. {Mood}.",
    "Anoté la disolución del grupo durante mi paso por {place}. {Mood}.",
    "Cada miembro del grupo siguió su camino tras separarnos en {place}.",
    "El grupo se deshizo en {place}, y con él la compañía de estos días. {Mood}.",
    "En {place} quedó disuelto el grupo. {Mood}.",
    "Terminó en {place} la andadura del grupo. {Mood}.",
}
-- A dungeon group put together by the game: no names.
T.GROUP_youjoin = {
    "En {place} me uní a un grupo para afrontar una instancia. No sabría decir con quién caminé.",
    "Formé parte de un grupo reunido en {place} para adentrarnos en una instancia. {Mood}.",
    "El destino me juntó en {place} con desconocidos dispuestos a afrontar una instancia.",
    "Acudí a la llamada de un grupo en {place}, rumbo a una instancia. {Mood}.",
    "En {place} me sumé a una partida de aventureros para afrontar una instancia.",
    "Una instancia me aguardaba: en {place} entré a formar parte de un grupo. {Mood}.",
    "Me uní a una expedición en {place}, sin saber muy bien quiénes serían mis compañeros.",
    "Respondí a la convocatoria de un grupo en {place}. {Mood}.",
    "En {place} me sumé a un grupo recién formado para afrontar una instancia.",
    "Anoté mi ingreso en un grupo de instancia durante mi paso por {place}. {Mood}.",
}
T.GROUP_other = { "Algo cambió en mi grupo en {place}." }

-- REPUTATION: {name} is the faction. {standing} comes from the game's own message, already in the
-- form the client uses for this character, so it is only placed where it describes the player.
T.REPUTATION_gain = {
    "En {place} empecé a ganarme la confianza de {name}. {Mood}.",
    "Mis actos en {place} no pasaron desapercibidos para {name}: su opinión de mí empieza a mejorar.",
    "{name} empieza a mirarme con mejores ojos, y todo ocurrió en {place}. {Mood}.",
    "Mi nombre empieza a sonar entre las filas de {name} tras lo ocurrido en {place}. {Mood}.",
    "Gané el favor de {name} durante mi paso por {place}. {Mood}.",
    "Los esfuerzos en {place} reforzaron mi relación con {name}. {Mood}.",
    "Anoté un gesto de aprecio de {name} mientras recorría {place}. {Mood}.",
    "En las tierras de {place}, {name} reconoció mi ayuda. {Mood}.",
    "Un paso más en mi relación con {name}, dado en {place}. {Mood}.",
    "Mi reputación con {name} creció en {place}. {Mood}.",
}
T.REPUTATION_standing = {
    "En {place} mi relación con {name} cambió: ahora soy {standing} ante ellos. {Mood}.",
    "Ante {name} ya soy {standing}. Lo supe en {place}, y no es poca cosa.",
    "{name} me tiene ahora por {standing}; lo comprobé en {place}.",
    "Desde lo ocurrido en {place}, {name} me considera {standing}. {Mood}.",
    "Anoté en {place} que ya soy {standing} para {name}. {Mood}.",
    "Las noticias llegaron en {place}: para {name} ahora soy {standing}.",
    "Mi trato con {name} dio un giro en {place}; ahora me consideran {standing}. {Mood}.",
    "En las tierras de {place} supe que {name} me tiene por {standing}. {Mood}.",
    "Ser {standing} ante {name}: eso me deparó mi paso por {place}. {Mood}.",
    "Para {name} ya no soy quien era: ahora soy {standing}. Ocurrió en {place}.",
}

-- SKILL: {name} is the skill, {rank} its new value.
T.SKILL_new = {
    "En {place} aprendí algo que no sabía: {name}. {Mood}.",
    "Una habilidad nueva se suma a mi repertorio en {place}: {name}.",
    "Empecé a dar mis primeros pasos en {name} durante mi estancia en {place}. {Mood}.",
    "Añadí {name} a mis conocimientos mientras recorría {place}. {Mood}.",
    "En las tierras de {place} me inicié en {name}. {Mood}.",
    "Un nuevo saber para mi cuaderno: {name}. Lo anoté en {place}.",
    "Mi repertorio creció en {place} con {name}. {Mood}.",
    "Comencé a practicar {name} durante mi paso por {place}. {Mood}.",
    "Desde {place}, {name} forma parte de lo que sé hacer. {Mood}.",
    "Anoté mi iniciación en {name} mientras permanecía en {place}. {Mood}.",
}
T.SKILL_rank = {
    "En {place} mi destreza en {name} llegó a {rank}. Se nota la práctica. {Mood}.",
    "Mi habilidad en {name} ya está en {rank}. Lo noté en {place}: la repetición acaba dando sus frutos.",
    "A fuerza de insistir, mi habilidad en {name} subió a {rank} en {place}.",
    "Alcancé {rank} puntos en {name} durante mi estancia en {place}. {Mood}.",
    "La práctica constante en {place} llevó mi dominio de {name} hasta {rank}. {Mood}.",
    "Un avance notable en {name}: {rank} puntos, logrados en {place}.",
    "Mis manos ganaron soltura con {name} en {place}; ya voy por {rank}. {Mood}.",
    "Anoté en {place} que mi destreza en {name} ha llegado a {rank}. {Mood}.",
    "Pulí mi técnica en {name} mientras recorría {place} hasta llegar a {rank}. {Mood}.",
    "En las tierras de {place}, mi dominio de {name} alcanzó {rank}. {Mood}.",
}

-- SPELL: {name} is the spell; {what} says what kind ("un nuevo hechizo", "una nueva habilidad"...),
-- so no word in these sentences has to agree with it.
T.SPELL = {
    "En {place} aprendí {what}: {name}. {Mood}.",
    "Mi repertorio suma {what}: {name}. Fue en {place}.",
    "{name} entra a formar parte de lo que sé hacer desde mi paso por {place}.",
    "Dominé {what} durante mi estancia en {place}: {name}. {Mood}.",
    "Mis estudios en {place} dieron fruto con {what}: {name}.",
    "Incorporé {name} a mis artes mientras recorría {place}. {Mood}.",
    "Un nuevo saber me acompaña desde {place}: {name}. {Mood}.",
    "En las tierras de {place} desentrañé los secretos de {name}. {Mood}.",
    "Anoté en mi cuaderno {what}, fruto de mi paso por {place}: {name}.",
    "Sumé {what} a mi repertorio en {place}: {name}. {Mood}.",
}
local SPELL_WHAT = { spell = "un nuevo hechizo", ability = "una nueva habilidad", passive = "una nueva habilidad pasiva" }

-- Chema's secondary types: no mood. MOUNT, ACHIEVEMENT and GUILD become live types in T4; until then
-- these render the entries his line saved without prose (none known) and the harness.
T.MOUNT = {
    "He obtenido una nueva montura ({name}). Mis desplazamientos en {place} serán mucho más veloces.",
    "Añadí a {name} a mis establos mientras me hallaba en {place}. Ahorraré mucho tiempo en el camino.",
    "Sumé a mi colección la montura {name} durante mi estancia en {place}.",
    "Un nuevo e imponente compañero de viaje: {name}. Recomponer el camino por {place} será más ágil.",
    "A partir de hoy recorreré los parajes de {place} a lomos de {name}.",
    "Conseguí la montura {name} en {place}. Una adición notable para las largas travesías.",
    "El viaje por {place} resultará más llevadero tras hacerme con {name}.",
    "Estrené a mi nueva montura ({name}) abriendo paso por los caminos de {place}.",
    "Adquirí a {name} para mis desplazamientos. Recorrer {place} ya no será tan fatigoso.",
    "Aumenté mi movilidad en {place} tras asegurar el uso de {name}.",
}

T.FLIGHT_POINT = {
    "Habilité una nueva conexión con el maestro de vuelo en {place}.",
    "Descubrí la ruta de vuelo de {place}. Un punto clave para replegarme o viajar rápidamente.",
    "Establecí contacto con el encargado de los grifos/mantícoras en {place}.",
    "Añadí el puesto de aviación de {place} a mi mapa de rutas aéreas.",
    "Aseguré una nueva parada de transporte aéreo al hablar con el maestro de vuelo en {place}.",
    "Las alas del servicio de transporte en {place} quedan a mi entera disposición desde hoy.",
    "Registré las coordenadas de vuelo de {place} para agilizar futuros desplazamientos.",
    "Un enlace aéreo fundamental desbloqueado en la zona de {place}.",
    "Marqué la posición del maestro de vuelo en {place} para volver cuando la necesidad apriete.",
    "Facilité mis próximos trayectos al sintonizar la ruta de transporte en {place}.",
}

T.GUILD_join = {
    "He pasado a formar parte oficialmente de la hermandad «{name}».",
    "Uní mis fuerzas a las de la hermandad «{name}» para afrontar mayores desafíos.",
    "Acepté la invitación de «{name}» y ahora comparto estandarte con sus miembros.",
    "Sello mi lealtad con la hermandad «{name}». La aventura en solitario da paso al trabajo en equipo.",
    "Me sumé a las filas de «{name}» con la intención de defender su nombre y sus colores.",
    "Un nuevo capítulo comienza tras incorporarme a las filas de «{name}».",
    "Caminaremos bajo la misma bandera: pasé a integrar la hermandad «{name}».",
    "Encontré cobijo y camaradería entre los integrantes de «{name}».",
    "Firmé mi compromiso de hermandad con «{name}».",
    "Formalicé mi ingreso en «{name}», {dispuesto|dispuesta} a aportar mi grano de arena a la causa.",
}
-- Chema's line wrote a departure with the joining texts (a bug); a departure has its own.
T.GUILD_leave = {
    "Dejé atrás la hermandad «{name}». Toca seguir el camino bajo otra bandera, o bajo ninguna.",
    "Me despedí de los integrantes de «{name}» y abandoné sus filas.",
    "Mi estandarte ya no es el de «{name}»: he dejado la hermandad.",
    "Rompí mi compromiso con la hermandad «{name}».",
    "Un capítulo se cierra: ya no formo parte de «{name}».",
    "Salí de las filas de «{name}», con la mirada puesta en nuevos rumbos.",
    "Abandoné la hermandad «{name}». Cada cual sigue su propio camino.",
    "Mi paso por «{name}» ha terminado.",
    "Devolví el tabardo de «{name}» y seguí mi camino.",
    "Dejé de caminar bajo la bandera de «{name}».",
}

T.ACHIEVEMENT = {
    "Completé con éxito el logro «{name}» mientras exploraba {place}.",
    "Anoté una proeza en mi expediente tras conseguir el logro «{name}» en {place}.",
    "Un hito personal alcanzado en {place}: «{name}».",
    "Mis hazañas en {place} fueron reconocidas al desbloquear el logro «{name}».",
    "Se registró la proeza «{name}» durante mi periplo por {place}.",
    "Sumé a mi registro el logro «{name}» tras los acontecimientos en {place}.",
    "La constancia en {place} tuvo recompensa en forma del logro «{name}».",
    "Inscribí el logro «{name}» en la memoria de mis viajes por {place}.",
    "Superé los requisitos de la proeza «{name}» estando en {place}.",
    "Un motivo más de orgullo en mi trayectoria: he culminado «{name}» en {place}.",
}

-- Rendering ------------------------------------------------------------------------------------
-- A mood phrase starts in lower case; capitalise one that opens a sentence (bug #13).
-- Only an ASCII first letter is touched, so multi-byte UTF-8 text is never cut.
local function Sentence(text)
    return (string.gsub(text, "^%l", string.upper))
end

local function Gender(text, female)
    return (string.gsub(text, "{([^{}|]*)|([^{}|]*)}", function(masculine, feminine)
        if female then return feminine end
        return masculine
    end))
end

-- Fills {key} from values. An unknown key is left as it is, so the harness catches it.
local function Fill(template, values, female)
    return (string.gsub(Gender(template, female), "{(%a+)}", function(key)
        local value = values[key]
        if value == nil then return nil end
        return tostring(value)
    end))
end

local function Pick(list, seed, unnamed)
    local item = list[(seed % #list) + 1]
    if type(item) == "table" then
        if unnamed and item.unnamed then return item.unnamed end
        return item[1]
    end
    return item
end

-- Stored tones may end in "." (Chema's diaries) or not (this line's); the templates add their own.
local function NormaliseTone(tone)
    tone = string.gsub(tone, "^%s+", "")
    tone = string.gsub(tone, "[%s%.]+$", "")
    if tone == "" then return DEFAULT_TONE end
    return tone
end

local function IsUnknownQuest(title)
    return title == NEUTRAL.QUEST or string.find(title, "^una misión %(ID %d+%)$") ~= nil
end

-- Returns profile, tone: the label shown with the showProfile option, and the mood phrase.
-- `female` defaults to the player's sex.
function ns.ChooseMood(eventType, female)
    if female == nil then female = ns.PlayerIsFemale() end
    local list = MOODS[MOOD_CATEGORY[eventType] or "GENERAL"]
    local item = list[math.random(1, #list)]
    local phrase, label = item, TYPE_LABEL[eventType]
    if type(item) == "table" then
        phrase = item[1]
        label = label or item[2]
    end
    return Gender(label or "{Heroico|Heroica}", female), Gender(phrase, female)
end

-- Returns prose, header. `header` is only given to place entries (DISCOVERY, REVISIT): Chema's red
-- headers. `female` defaults to the player's sex.
function ns.ComposeEntry(entry, female)
    if female == nil then female = ns.PlayerIsFemale() end
    local seed = type(entry.seed) == "number" and math.floor(entry.seed) or 1
    if seed < 0 then seed = -seed end
    local tone = NormaliseTone(SafeString(entry.contextualTone, DEFAULT_TONE))
    local name = SafeString(entry.text, "un acontecimiento inesperado")
    local values = {
        place = SafeString(entry.place, "algún lugar del mundo"),
        name = name,
        mood = tone,
        Mood = Sentence(tone),
    }
    local kind = entry.type
    local list, unnamed

    if kind == "DISCOVERY" or kind == "REVISIT" then
        local method = type(entry.travelMethod) == "string" and ZONE_BODIES[entry.travelMethod] and entry.travelMethod
            or "ON_FOOT"
        if method == "ON_FOOT" and kind == "REVISIT" then method = "ON_FOOT_REVISIT" end
        local headers = ZONE_HEADERS[method]
        local header = Fill(headers[(seed % #headers) + 1], values, female)
        return Sentence(Fill(ZONE_BODIES[method], values, female)), header
    elseif kind == "QUEST" then
        list = IsUnknownQuest(name) and T.QUEST_UNNAMED or T.QUEST
    elseif kind == "QUEST_ACCEPT" then
        values.npc = SafeString(entry.npc, NEUTRAL.NPC)
        list = IsUnknownQuest(name) and T.QUEST_ACCEPT_UNNAMED or T.QUEST_ACCEPT
    elseif kind == "BOSS" then
        list, unnamed = T.BOSS, name == NEUTRAL.BOSS
    elseif kind == "DEATH" then
        local killer = SafeString(entry.killer, "")
        values.killer = killer
        list, unnamed = T.DEATH, killer == ""
    elseif kind == "LOOT" or kind == "NPC" or kind == "CHAT" or kind == "MOUNT"
        or kind == "FLIGHT_POINT" or kind == "ACHIEVEMENT" then
        list = T[kind]
    elseif kind == "LEVEL" then
        if type(entry.level) == "number" then
            values.level = entry.level
            list = T.LEVEL
        else
            list = T.LEVEL_UNNAMED
        end
    elseif kind == "GROUP" then
        list = T["GROUP_" .. tostring(entry.groupEvent)] or T.GROUP_other
    elseif kind == "REPUTATION" then
        local standing = SafeString(entry.standing, "")
        if entry.repEvent == "standing" and standing ~= "" then
            values.standing = standing
            list = T.REPUTATION_standing
        else
            list = T.REPUTATION_gain
        end
    elseif kind == "SKILL" then
        if entry.skillEvent == "rank" and type(entry.rank) == "number" then
            values.rank = entry.rank
            list = T.SKILL_rank
        else
            list = T.SKILL_new
        end
    elseif kind == "SPELL" then
        values.what = SPELL_WHAT[entry.learnKind] or SPELL_WHAT.spell
        list = T.SPELL
    elseif kind == "GUILD" then
        list = entry.guildEvent == "leave" and T.GUILD_leave or T.GUILD_join
    end

    if not list then return name end
    return Sentence(Fill(Pick(list, seed, unnamed), values, female))
end

-- For the harness (tools/lua/scenario_prose.lua): every list, read only.
ns.PROSE = { MOODS = MOODS, TEMPLATES = T, ZONE_HEADERS = ZONE_HEADERS, ZONE_BODIES = ZONE_BODIES,
    SPELL_WHAT = SPELL_WHAT, Gender = Gender }
