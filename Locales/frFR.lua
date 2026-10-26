local _, ns = ...
local L = ns.NewTranslation("frFR")
if not L then return end

L["Version %s"] = "Version %s"
L["Commands:"] = "Commandes :"
L["show the addon version"] = "affiche la version de l'addon"
L["open the raid note editor"] = "ouvre l'éditeur de la note de raid"
L["send <text> as the Method Raid Tools note (\\n starts a new line)"] = "envoie <text> comme note de Method Raid Tools (\\n commence une nouvelle ligne)"

L["Method Raid Tools is not loaded."] = "Method Raid Tools n'est pas chargé."
L["This version of Method Raid Tools is not supported (its note has changed)."] = "Cette version de Method Raid Tools n'est pas prise en charge (sa note a changé)."
L["Method Raid Tools could not send the note."] = "Method Raid Tools n'a pas pu envoyer la note."
L["Note sent to Method Raid Tools."] = "Note envoyée à Method Raid Tools."
L["Note sent, but you are not raid leader or assistant: players who only accept notes from promoted players ignore it."] = "Note envoyée, mais vous n'êtes ni chef de raid ni assistant : les joueurs qui n'acceptent que les notes des joueurs promus l'ignorent."
L["Raid note"] = "Note de raid"
L["Note text. Method Raid Tools markup works: {rt1}, {spell:12345}, colours."] = "Texte de la note. Le balisage de Method Raid Tools fonctionne : {rt1}, {spell:12345}, couleurs."
L["Send"] = "Envoyer"
L["Reload from MRT"] = "Recharger depuis MRT"
