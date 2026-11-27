local ADDON, ns = ...
-- Strings of holidays and module areas (0.9), all six languages
ns.AddLocale("enUS", {
  HOL_OPENS = "from %s (%s)",
  TYPE_CLOSED = "This event type is not available right now (area locked or holiday not running).",
  AREA_ONLY_GM = "Only the guild master unlocks the areas of a module.",
  AREA_PVP = "PvP",
  AREA_PVE = "PvE",
  AREA_UNLOCK = "Unlocked for the guild:",
  AREA_ON = "unlocked",
  AREA_OFF = "locked",
  AREA_LOCKED_HINT = "Locked by the guild master (Settings > Modules).",
})
ns.AddLocale("deDE", {
  HOL_OPENS = "ab %s (%s)",
  TYPE_CLOSED = "Diese Event-Art ist gerade nicht verfügbar (Bereich gesperrt oder Feiertag läuft nicht).",
  AREA_ONLY_GM = "Nur der Gildenmeister schaltet die Bereiche eines Moduls frei.",
  AREA_PVP = "PvP",
  AREA_PVE = "PvE",
  AREA_UNLOCK = "Für die Gilde freigeschaltet:",
  AREA_ON = "freigeschaltet",
  AREA_OFF = "gesperrt",
  AREA_LOCKED_HINT = "Vom Gildenmeister gesperrt (Einstellungen > Module).",
})
ns.AddLocale("frFR", {
  HOL_OPENS = "dès le %s (%s)",
  TYPE_CLOSED = "Ce type d'évènement n'est pas disponible pour l'instant (domaine verrouillé ou fête pas en cours).",
  AREA_ONLY_GM = "Seul le maître de guilde déverrouille les domaines d'un module.",
  AREA_PVP = "JcJ",
  AREA_PVE = "JcE",
  AREA_UNLOCK = "Déverrouillé pour la guilde :",
  AREA_ON = "déverrouillé",
  AREA_OFF = "verrouillé",
  AREA_LOCKED_HINT = "Verrouillé par le maître de guilde (Paramètres > Modules).",
})
ns.AddLocale("esES", {
  HOL_OPENS = "desde el %s (%s)",
  TYPE_CLOSED = "Este tipo de evento no está disponible ahora (área bloqueada o la festividad no está en curso).",
  AREA_ONLY_GM = "Solo el maestro de hermandad desbloquea las áreas de un módulo.",
  AREA_PVP = "JcJ",
  AREA_PVE = "JcE",
  AREA_UNLOCK = "Desbloqueado para la hermandad:",
  AREA_ON = "desbloqueado",
  AREA_OFF = "bloqueado",
  AREA_LOCKED_HINT = "Bloqueado por el maestro de hermandad (Ajustes > Módulos).",
})
ns.AddLocale("itIT", {
  HOL_OPENS = "dal %s (%s)",
  TYPE_CLOSED = "Questo tipo di evento ora non è disponibile (area bloccata o festività non in corso).",
  AREA_ONLY_GM = "Solo il maestro di gilda sblocca le aree di un modulo.",
  AREA_PVP = "PvP",
  AREA_PVE = "PvE",
  AREA_UNLOCK = "Sbloccato per la gilda:",
  AREA_ON = "sbloccato",
  AREA_OFF = "bloccato",
  AREA_LOCKED_HINT = "Bloccato dal maestro di gilda (Impostazioni > Moduli).",
})
ns.AddLocale("ptBR", {
  HOL_OPENS = "a partir de %s (%s)",
  TYPE_CLOSED = "Este tipo de evento não está disponível agora (área bloqueada ou feriado fora do período).",
  AREA_ONLY_GM = "Só o mestre da guilda desbloqueia as áreas de um módulo.",
  AREA_PVP = "JxJ",
  AREA_PVE = "JxA",
  AREA_UNLOCK = "Desbloqueado para a guilda:",
  AREA_ON = "desbloqueado",
  AREA_OFF = "bloqueado",
  AREA_LOCKED_HINT = "Bloqueado pelo mestre da guilda (Configurações > Módulos).",
})
