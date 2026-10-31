local _, ns = ...

-- Rebuilds an encounter's note from the template and slots of export protocol 2: the second pass of the wiki's
-- renderer (`fillTemplate` in UnityWiki's src/lib/addon-export.ts, spelled out in its docs/addon-export.md,
-- "The second pass"). The wiki resolves the token language; this only puts names where the slot markers are,
-- drops the `[[ ]]` stretches whose slots are empty and tidies the lines the way the wiki does, so a template
-- with the export's holders gives the export's `note` byte for byte (tests/note-template.test.mjs).
-- Pure Lua, no WoW API.
local NoteTemplate = {}
ns.NoteTemplate = NoteTemplate

-- A slot marker, `{{s:3}}`; the capture is the slot's `n` as written
NoteTemplate.MARKER = "{{s:(%d+)}}"

-- The wiki's class colours (CLASS_HEX in src/lib/raid-notes.ts), lower case as the notes write them
NoteTemplate.CLASS_HEX = {
    WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569", PRIEST = "ffffff",
    DEATHKNIGHT = "c41f3b", SHAMAN = "0070de", MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a",
}

local byte, sub, find, gsub, gmatch, concat = string.byte, string.sub, string.find, string.gsub, string.gmatch,
    table.concat

local MARKER = NoteTemplate.MARKER

-- A name in its class colour, or bare when its person or class is not known
function NoteTemplate.ColouredName(name, people)
    local person = people and people[name]
    local hex = type(person) == "table" and NoteTemplate.CLASS_HEX[person.class]
    if not hex then return name end
    return "|cff" .. hex .. name .. "|r"
end

-- A slot's text, unpadded: its holders coloured and joined with its `sep` (only the first holder of a slot
-- that is not `multi`). "" when it has no holders.
function NoteTemplate.SlotText(slot, people)
    local holders = slot.holders or {}
    local last = slot.multi and #holders or math.min(#holders, 1)
    local names = {}
    for i = 1, last do
        names[i] = NoteTemplate.ColouredName(holders[i], people)
    end
    return concat(names, slot.sep or "")
end

-- How wide a text shows: colour codes (`|c` and 8 hex digits, `|r`) take no room. Counted in UTF-16 code units
-- like the wiki's JavaScript `length`: one per UTF-8 character, two for a character of four bytes.
function NoteTemplate.Width(text)
    local width, i, n = 0, 1, #text
    while i <= n do
        local c = byte(text, i)
        if c == 124 and find(text, "^|[cC]%x%x%x%x%x%x%x%x", i) then         -- "|"
            i = i + 10
        elseif c == 124 and find(text, "^|[rR]", i) then
            i = i + 2
        else
            if c < 0x80 or c >= 0xC0 then width = width + 1 end
            if c >= 0xF0 then width = width + 1 end
            i = i + 1
        end
    end
    return width
end

-- Spaces on the right up to `pad` shown characters; never cut
function NoteTemplate.Pad(text, pad)
    local width = pad and NoteTemplate.Width(text) or 0
    if not pad or width >= pad then return text end
    return text .. string.rep(" ", pad - width)
end

-- The "]]" closing the "[[" at `start`, or nil when it never closes
local function matchingClose(text, start)
    local depth, i = 0, start
    while true do
        local open = find(text, "[[", i, true)
        local close = find(text, "]]", i, true)
        if not close then return nil end
        if open and open < close then
            depth = depth + 1
            i = open + 2
        else
            depth = depth - 1
            if depth == 0 then return close end
            i = close + 2
        end
    end
end

-- Whether a stretch goes: any marker in it has an empty slot
local function drops(content, value)
    for n in gmatch(content, MARKER) do
        if value(n) == "" then return true end
    end
    return false
end

-- Every stretch resolved, innermost first. keepOuter leaves the outermost brackets for the line pass.
local function stretches(text, value, keepOuter)
    if not find(text, "[[", 1, true) then return text end
    local out, i = {}, 1
    while true do
        local open = find(text, "[[", i, true)
        if not open then
            out[#out + 1] = sub(text, i)
            break
        end
        out[#out + 1] = sub(text, i, open - 1)
        local close = matchingClose(text, open)
        if not close then   -- an unclosed "[[" stays as it is written
            out[#out + 1] = sub(text, open)
            break
        end
        local content = stretches(sub(text, open + 2, close - 1), value, false)
        if keepOuter then
            out[#out + 1] = "[[" .. content .. "]]"
        elseif not drops(content, value) then
            out[#out + 1] = content
        end
        i = close + 2
    end
    return concat(out)
end

local function lines(text)
    local list = {}
    for line in gmatch(text .. "\n", "([^\n]*)\n") do
        list[#list + 1] = line
    end
    return list
end

-- The note: `template` with the holders of `slots` (protocol 2's list, keyed by `n`) put in, names coloured from
-- `people`. A marker without a slot counts as empty (PlanCodec.Check refuses such a plan).
function NoteTemplate.Render(template, slots, people)
    local byN, texts = {}, {}
    for _, slot in ipairs(slots or {}) do
        byN[string.format("%d", slot.n)] = slot
    end
    local function value(n)
        if not texts[n] then
            texts[n] = byN[n] and NoteTemplate.SlotText(byN[n], people) or ""
        end
        return texts[n]
    end

    -- 1. collapse nesting, 2. drop the lines that are exactly one stretch that goes, 3. resolve the rest, fill in
    local text = stretches(template, value, true)
    if find(text, "[[", 1, true) then
        local kept = {}
        for _, line in ipairs(lines(text)) do
            local content = line:match("^[ \t]*%[%[([^%[%]\n]*)%]%][ \t]*$")
            if not (content and drops(content, value)) then kept[#kept + 1] = line end
        end
        text = concat(kept, "\n")
    end
    text = gsub(stretches(text, value, false), MARKER, function(n)
        return NoteTemplate.Pad(value(n), byN[n] and byN[n].pad)
    end)

    -- 4. per line: no spaces before punctuation, no trailing whitespace; 5. at most one blank line in a row,
    -- none at the ends
    local tidy = lines(text)
    for i, line in ipairs(tidy) do
        tidy[i] = gsub(gsub(line, " +([%.,!%?;:])", "%1"), "%s+$", "")
    end
    text = gsub(concat(tidy, "\n"), "\n\n\n+", "\n\n")
    return (gsub(gsub(text, "^\n+", ""), "\n+$", ""))
end

-- nil when every marker of `template` names one of `slots`, else the first marker that does not
function NoteTemplate.UnknownMarker(template, slots)
    local known = {}
    for _, slot in ipairs(slots) do
        known[string.format("%d", slot.n)] = true
    end
    for n in gmatch(template, MARKER) do
        if not known[n] then return n end
    end
    return nil
end
