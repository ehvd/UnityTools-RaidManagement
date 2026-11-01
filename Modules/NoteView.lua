local _, ns = ...

-- A note as Method Raid Tools shows it to one player: its blocks for some players, classes or groups kept or
-- left out. MRT's own rules (txtWithIcons and the GSUB_ functions in its Note.lua, checked against MRT 5335) only
-- look at the player who reads the note, so they are mirrored here for any player. Pure Lua, no WoW API
-- (tests/note-view.test.mjs).
--
--   {p:Name,Other}...{/p}     only those players; {!p:...} everybody else
--   {c:Mage,Warlock}...{/c}   only those classes (names in English or the game's language, short names, numbers)
--   {classunique:Mage,Priest}...{/classunique}   only the first of those classes that is in the raid
--   {g2}...{/g}               only group 2 ({g25}: groups 2 and 5); {!g2} everybody else
--   {0}...{/0}                nobody
-- Role blocks ({h}, {t}, {d}) are not used by MRT in Classic (no specializations); races, encounters, zones and
-- phases do not depend on the player chosen, so they stay (their tags are left out with the other tags).
-- For everyone (no player chosen) every one of these blocks goes, negated ones and role blocks too: what is left
-- is what every raid member sees.
local NoteView = {}
ns.NoteView = NoteView

-- MRT's class numbers (the game's class IDs)
NoteView.CLASS_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
    WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

-- The names MRT knows besides the game's own: English, short and numbers ("8" is Shaman in MRT too)
local CLASS_ALIAS = {
    warrior = 1, paladin = 2, hunter = 3, rogue = 4, priest = 5, deathknight = 6, shaman = 7, mage = 8, warlock = 9,
    monk = 10, druid = 11, demonhunter = 12, evoker = 13,
    war = 1, pal = 2, hun = 3, rog = 4, pri = 5, dk = 6, sham = 7, lock = 9, dru = 11, dh = 12, dragon = 13,
}
for i = 1, 13 do CLASS_ALIAS[tostring(i)] = i end
CLASS_ALIAS["8"] = 7

local function split(list)
    local out = {}
    for entry in (list .. ","):gmatch("([^,]*),") do out[#out + 1] = entry end
    return out
end

-- An entry of a list as MRT compares it: without colours, lower case
local function plain(entry)
    return (entry:gsub("|?|c........", ""):gsub("|?|r", ""):lower())
end

local function shown(found, anti, msg)
    if (found and anti == "") or (not found and anti == "!") then return msg end
    return ""
end

-- `viewer`: { name, class (WARRIOR...), group (1-8), classes (the class tokens in the raid, as a set),
-- classNames (the game's class names, lower case, to class tokens) }. nil: everyone, only the text outside the
-- blocks.
function NoteView.For(text, viewer)
    local everyone = viewer == nil
    viewer = viewer or {}
    if everyone then
        text = text:gsub("{[Hh]}.-{/[Hh]}", ""):gsub("{[Tt]}.-{/[Tt]}", ""):gsub("{[Dd]}.-{/[Dd]}", "")
    end
    local myName = plain((viewer.name or ""):match("^[^%-]*"))
    local myClass = NoteView.CLASS_ID[viewer.class or ""]
    local myGroup = tostring(viewer.group or 1)

    local function classOf(entry)
        local token = viewer.classNames and viewer.classNames[entry]
        return (token and NoteView.CLASS_ID[token]) or CLASS_ALIAS[entry]
    end

    local function player(anti, list, msg)
        if everyone then return "" end
        local found = false
        for _, entry in ipairs(split(list)) do
            if plain(entry):match("^[^%-]*") == myName then found = true break end
        end
        return shown(found, anti, msg)
    end

    local function class(anti, list, msg)
        if everyone then return "" end
        local found = false
        for _, entry in ipairs(split(list)) do
            if myClass and classOf(plain(entry)) == myClass then found = true break end
        end
        return shown(found, anti, msg)
    end

    local present = {}
    for token in pairs(viewer.classes or {}) do
        if NoteView.CLASS_ID[token] then present[NoteView.CLASS_ID[token]] = true end
    end
    local function classUnique(list, msg)
        if everyone then return "" end
        for _, entry in ipairs(split(list)) do
            local id = classOf(plain(entry))
            if id and present[id] then
                return id == myClass and msg or ""
            end
        end
        return ""
    end

    local function group(anti, groups, msg)
        if everyone then return "" end
        return shown(groups:find(myGroup, 1, true) ~= nil, anti, msg)
    end

    return (text:gsub("{0}.-{/0}", "")
        :gsub("(\n{!?[CcPpGg]:?[^}]+})\n", "%1")
        :gsub("\n({/[CcPpGg]}\n)", "%1")
        :gsub("{(!?)[Pp]:([^}]+)}(.-){/[Pp]}", player)
        :gsub("{(!?)[Cc]:([^}]+)}(.-){/[Cc]}", class)
        :gsub("{[Cc][Ll][Aa][Ss][Ss][Uu][Nn][Ii][Qq][Uu][Ee]:([^}]+)}(.-){/[Cc][Ll][Aa][Ss][Ss][Uu][Nn][Ii][Qq][Uu][Ee]}",
            classUnique)
        :gsub("{(!?)[Gg](%d+)}(.-){/[Gg]}", group))
end

-- The group (1-8) a player has in a layout of 40 names (MRT's raid-groups order), 1 when they have none, as MRT
-- counts a player it does not find
function NoteView.GroupIn(layout, name, key)
    key = key or function(n) return (n:match("^[^%-]*")):lower() end
    local wanted = key(name)
    for slot, planned in ipairs(layout or {}) do
        if planned ~= "" and key(planned) == wanted then return math.floor((slot - 1) / 5) + 1 end
    end
    return 1
end
