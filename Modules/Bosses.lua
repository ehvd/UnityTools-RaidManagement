local _, ns = ...

-- The raids and bosses of Classic Era, for plans made in game (issue #43) and the encounter list (#44). It mirrors
-- UnityWiki: the raid slugs and boss keys are the wiki's (loot_source keys), the encounter IDs its
-- src/lib/encounter-ids.ts (Blizzard's, what ENCOUNTER_END reports), the names and the kill order its loot data
-- (db/migrations/0032_raid_loot_data.sql); tests/bosses.test.mjs checks them against a UnityWiki checkout. A fight
-- with several bosses is one encounter, as in game (the Bug Trio 710, the Twin Emperors 715, the Four Horsemen 1121).
-- Names are English here; L translates them where they are shown. Pure Lua, so tests/bosses.test.mjs can run it.
local Bosses = {}
ns.Bosses = Bosses

local RAIDS = {
    {
        slug = "molten-core", name = "Molten Core",
        bosses = {
            { "lucifron", "Lucifron", 663 },
            { "magmadar", "Magmadar", 664 },
            { "gehennas", "Gehennas", 665 },
            { "garr", "Garr", 666 },
            { "shazzrah", "Shazzrah", 667 },
            { "geddon", "Baron Geddon", 668 },
            { "golemagg", "Golemagg the Incinerator", 670 },
            { "sulfuron", "Sulfuron Harbinger", 669 },
            { "majordomo", "Majordomo Executus", 671 },
            { "ragnaros", "Ragnaros", 672 },
        },
    },
    {
        slug = "onyxias-lair", name = "Onyxia's Lair",
        bosses = {
            { "onyxia", "Onyxia", 1084 },
        },
    },
    {
        slug = "blackwing-lair", name = "Blackwing Lair",
        bosses = {
            { "razorgore", "Razorgore the Untamed", 610 },
            { "vaelastrasz", "Vaelastrasz the Corrupt", 611 },
            { "broodlord", "Broodlord Lashlayer", 612 },
            { "firemaw", "Firemaw", 613 },
            { "ebonroc", "Ebonroc", 614 },
            { "flamegor", "Flamegor", 615 },
            { "chromaggus", "Chromaggus", 616 },
            { "nefarian", "Nefarian", 617 },
        },
    },
    {
        slug = "zul-gurub", name = "Zul'Gurub",
        bosses = {
            { "jeklik", "High Priestess Jeklik", 784 },
            { "venoxis", "High Priest Venoxis", 785 },
            { "marli", "High Priestess Mar'li", 786 },
            { "mandokir", "Bloodlord Mandokir", 787 },
            { "edge-of-madness", "Edge of Madness", 788 },
            { "gahzranka", "Gahz'ranka", 789 },
            { "thekal", "High Priest Thekal", 790 },
            { "arlokk", "High Priestess Arlokk", 791 },
            { "jindo", "Jin'do the Hexxer", 792 },
            { "hakkar", "Hakkar", 793 },
        },
    },
    {
        slug = "ruins-of-ahn-qiraj", name = "Ruins of Ahn'Qiraj",
        bosses = {
            { "kurinnaxx", "Kurinnaxx", 718 },
            { "rajaxx", "General Rajaxx", 719 },
            { "moam", "Moam", 720 },
            { "buru", "Buru the Gorger", 721 },
            { "ayamiss", "Ayamiss the Hunter", 722 },
            { "ossirian", "Ossirian the Unscarred", 723 },
        },
    },
    {
        slug = "ahn-qiraj", name = "Temple of Ahn'Qiraj",
        bosses = {
            { "skeram", "The Prophet Skeram", 709 },
            { "bug-trio", "The Bug Trio", 710 },
            { "sartura", "Battleguard Sartura", 711 },
            { "fankriss", "Fankriss the Unyielding", 712 },
            { "viscidus", "Viscidus", 713 },
            { "huhuran", "Princess Huhuran", 714 },
            { "twin-emperors", "Twin Emperors", 715 },
            { "ouro", "Ouro", 716 },
            { "cthun", "C'Thun", 717 },
        },
    },
    {
        slug = "naxxramas", name = "Naxxramas",
        bosses = {
            { "anubrekhan", "Anub'Rekhan", 1107 },
            { "faerlina", "Grand Widow Faerlina", 1110 },
            { "maexxna", "Maexxna", 1116 },
            { "noth", "Noth the Plaguebringer", 1117 },
            { "heigan", "Heigan the Unclean", 1112 },
            { "loatheb", "Loatheb", 1115 },
            { "razuvious", "Instructor Razuvious", 1113 },
            { "gothik", "Gothik the Harvester", 1109 },
            { "four-horsemen", "The Four Horsemen", 1121 },
            { "patchwerk", "Patchwerk", 1118 },
            { "grobbulus", "Grobbulus", 1111 },
            { "gluth", "Gluth", 1108 },
            { "thaddius", "Thaddius", 1120 },
            { "sapphiron", "Sapphiron", 1119 },
            { "kelthuzad", "Kel'Thuzad", 1114 },
        },
    },
}

local bySlug, byId = {}, {}
for _, raid in ipairs(RAIDS) do
    bySlug[raid.slug] = raid
    for _, boss in ipairs(raid.bosses) do
        byId[boss[3]] = { slug = raid.slug, key = boss[1], label = boss[2], encounterId = boss[3] }
    end
end

-- The raids in the game's order: { { slug, name }, ... } (new tables, the caller may keep or change them)
function Bosses.Raids()
    local list = {}
    for i, raid in ipairs(RAIDS) do
        list[i] = { slug = raid.slug, name = raid.name }
    end
    return list
end

-- The raid `slug`'s name, or nil for a raid this table does not know
function Bosses.RaidName(slug)
    return bySlug[slug] and bySlug[slug].name
end

-- The bosses of raid `slug` in kill order: { { key, label, encounterId }, ... }; {} for a raid it does not know
function Bosses.Of(slug)
    local list = {}
    for i, boss in ipairs(bySlug[slug] and bySlug[slug].bosses or {}) do
        list[i] = { key = boss[1], label = boss[2], encounterId = boss[3] }
    end
    return list
end

-- The boss that encounter ID `encounterId` is: { slug, key, label, encounterId }, or nil
function Bosses.Find(encounterId)
    local boss = byId[encounterId]
    return boss and { slug = boss.slug, key = boss.key, label = boss.label, encounterId = boss.encounterId }
end
