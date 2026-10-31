local _, ns = ...

-- Decodes the raid plan export of the UnityWiki raid planner. UnityWiki owns the format
-- (docs/addon-export.md there): base64(zlib(JSON)) with the version in the JSON's `protocol` key.
-- Pure Lua apart from LibDeflate, which the caller passes in, and NoteTemplate (loaded first), so tests/plan-codec
-- can run it outside the game.
local PlanCodec = {}
ns.PlanCodec = PlanCodec

-- Protocol versions this addon can read
PlanCodec.PROTOCOLS = { 1, 2 }
PlanCodec.SLOTS = 40   -- names per layout: 8 groups of 5, MRT's raid groups order

local byte, char, sub, find, concat, floor = string.byte, string.char, string.sub, string.find, table.concat, math.floor

------------------------------------------------------------------------------------------------ base64 ---

local BASE64 = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do
        BASE64[byte(alphabet, i)] = i - 1
    end
end

-- Standard base64 (not URL-safe). Whitespace is skipped; anything else outside the alphabet is an error.
function PlanCodec.Base64Decode(text)
    local out, n = {}, 0
    local acc, bits = 0, 0
    for i = 1, #text do
        local c = byte(text, i)
        local value = BASE64[c]
        if value then
            acc = acc * 64 + value
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local p = 2 ^ bits
                n = n + 1
                out[n] = char(floor(acc / p))
                acc = acc % p
            end
        elseif c == 61 then   -- "=": padding, the end
            break
        elseif c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then
            return nil
        end
    end
    return concat(out)
end

-------------------------------------------------------------------------------------------------- JSON ---

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(code)
    if code < 0x80 then
        return char(code)
    elseif code < 0x800 then
        return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40,
        0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local decodeValue

local function skip(s, i)
    return (find(s, "[^ \t\r\n]", i)) or (#s + 1)
end

local function decodeString(s, i)
    -- i is just past the opening quote
    local parts, n = {}, 0
    while true do
        local j = find(s, '["\\]', i)
        if not j then error("unterminated string", 0) end
        n = n + 1
        parts[n] = sub(s, i, j - 1)
        if sub(s, j, j) == '"' then
            return concat(parts), j + 1
        end
        local e = sub(s, j + 1, j + 1)
        if e == "u" then
            local code = tonumber(sub(s, j + 2, j + 5), 16)
            if not code then error("bad \\u escape", 0) end
            i = j + 6
            if code >= 0xD800 and code <= 0xDBFF and sub(s, i, i + 1) == "\\u" then
                local low = tonumber(sub(s, i + 2, i + 5), 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                    code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                    i = i + 6
                end
            end
            n = n + 1
            parts[n] = utf8(code)
        else
            local plain = ESCAPES[e]
            if not plain then error("bad escape", 0) end
            n = n + 1
            parts[n] = plain
            i = j + 2
        end
    end
end

local function decodeArray(s, i)
    local list, n = {}, 0
    i = skip(s, i)
    if sub(s, i, i) == "]" then return list, i + 1 end
    while true do
        local value
        value, i = decodeValue(s, i)
        n = n + 1
        list[n] = value
        i = skip(s, i)
        local c = sub(s, i, i)
        if c == "]" then return list, i + 1 end
        if c ~= "," then error("expected , or ] in an array", 0) end
        i = i + 1
    end
end

local function decodeObject(s, i)
    local object = {}
    i = skip(s, i)
    if sub(s, i, i) == "}" then return object, i + 1 end
    while true do
        if sub(s, i, i) ~= '"' then error("expected a key", 0) end
        local key
        key, i = decodeString(s, i + 1)
        i = skip(s, i)
        if sub(s, i, i) ~= ":" then error("expected :", 0) end
        object[key], i = decodeValue(s, i + 1)
        i = skip(s, i)
        local c = sub(s, i, i)
        if c == "}" then return object, i + 1 end
        if c ~= "," then error("expected , or } in an object", 0) end
        i = skip(s, i + 1)
    end
end

-- JSON null is nil: an object key with null is absent (`event.startsAt` of an event without a start time)
decodeValue = function(s, i)
    i = skip(s, i)
    local c = sub(s, i, i)
    if c == "{" then return decodeObject(s, i + 1) end
    if c == "[" then return decodeArray(s, i + 1) end
    if c == '"' then return decodeString(s, i + 1) end
    if sub(s, i, i + 3) == "true" then return true, i + 4 end
    if sub(s, i, i + 4) == "false" then return false, i + 5 end
    if sub(s, i, i + 3) == "null" then return nil, i + 4 end
    local number = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if number and number ~= "" and tonumber(number) then
        return tonumber(number), i + #number
    end
    error("unexpected character at " .. i, 0)
end

-- Returns the value, or nil and an error message
function PlanCodec.JSONDecode(text)
    local ok, value, i = pcall(decodeValue, text, 1)
    if not ok then return nil, value end
    if skip(text, i) <= #text then return nil, "trailing characters" end
    return value
end

-- A short fingerprint of a string (djb2 over its bytes, as 8 hex digits): enough to tell whether two strings
-- of the export are the same without keeping both in the SavedVariables
function PlanCodec.Checksum(text)
    local h = 5381.0   -- floats, and two 16 bit halves for the output: also right where integers are 32 bit
    for i = 1, #text do
        h = (h * 33 + byte(text, i)) % 4294967296.0
    end
    return string.format("%04x%04x", floor(h / 65536), floor(h % 65536))
end

---------------------------------------------------------------------------------------------- the plan ---

function PlanCodec.IsSupported(protocol)
    for _, supported in ipairs(PlanCodec.PROTOCOLS) do
        if protocol == supported then return true end
    end
    return false
end

-- Text -> the decoded JSON table, or nil and an error code: "empty", "base64", "zlib", "json", "notPlan".
-- Whether its protocol is supported and its shape are checked separately (Check).
function PlanCodec.Decode(text, LibDeflate)
    text = text and text:gsub("%s+", "") or ""
    if text == "" then return nil, "empty" end
    local compressed = PlanCodec.Base64Decode(text)
    if not compressed or compressed == "" then return nil, "base64" end
    local json = LibDeflate:DecompressZlib(compressed)
    if not json then return nil, "zlib" end
    local data = PlanCodec.JSONDecode(json)
    if data == nil then return nil, "json" end
    if type(data) ~= "table" or type(data.protocol) ~= "number" then return nil, "notPlan" end
    return data
end

local function isString(v) return type(v) == "string" end

local function isStrings(list)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if not isString(list[i]) then return false end
    end
    return true
end

-- Protocol 2's people: name -> { class?, role? }
local function checkPeople(people)
    if type(people) ~= "table" then return "people" end
    for name, person in pairs(people) do
        if not isString(name) or type(person) ~= "table" or (person.class ~= nil and not isString(person.class))
            or (person.role ~= nil and not isString(person.role)) then
            return "people." .. tostring(name)
        end
    end
    return nil
end

-- Protocol 2's template and slots of one encounter: both or neither, slots numbered 1, 2, 3 ... and every marker
-- of the template naming one of them
local function checkTemplate(encounter, path)
    local template, slots = encounter.template, encounter.slots
    if template == nil and slots == nil then return nil end
    if not isString(template) then return path .. ".template" end
    if type(slots) ~= "table" then return path .. ".slots" end
    for i, slot in ipairs(slots) do
        local at = path .. ".slots[" .. i .. "]"
        if type(slot) ~= "table" or slot.n ~= i or not isString(slot.token) or not isString(slot.key)
            or not isString(slot.kind) or type(slot.multi) ~= "boolean" or not isStrings(slot.holders)
            or not isStrings(slot.candidates) then
            return at
        end
        if slot.pad ~= nil and type(slot.pad) ~= "number" then return at .. ".pad" end
        if slot.sep ~= nil and not isString(slot.sep) then return at .. ".sep" end
    end
    if ns.NoteTemplate.UnknownMarker(template, slots) then return path .. ".template" end
    return nil
end

-- Returns nil when the plan is usable, or the path of the first thing that is not.
-- Keys this addon does not know are ignored (the wiki may add some without a new protocol). Protocol 2's keys
-- (people; per encounter encounterId, template, slots) are checked when they are there; people must be.
function PlanCodec.Check(data)
    if type(data.event) ~= "table" then return "event" end
    if not isString(data.event.title) then return "event.title" end
    if data.event.startsAt ~= nil and type(data.event.startsAt) ~= "number" then return "event.startsAt" end
    if type(data.layouts) ~= "table" or type(data.layouts.default) ~= "table" then return "layouts.default" end
    for key, names in pairs(data.layouts) do
        if type(names) ~= "table" or #names ~= PlanCodec.SLOTS then return "layouts." .. tostring(key) end
        for slot = 1, PlanCodec.SLOTS do
            if not isString(names[slot]) then return "layouts." .. tostring(key) .. "[" .. slot .. "]" end
        end
    end
    if data.people ~= nil or data.protocol >= 2 then
        local problem = checkPeople(data.people)
        if problem then return problem end
    end
    if type(data.encounters) ~= "table" then return "encounters" end
    for i, encounter in ipairs(data.encounters) do
        local path = "encounters[" .. i .. "]"
        if type(encounter) ~= "table" or not isString(encounter.key) or not isString(encounter.label)
            or not isString(encounter.note) then
            return path
        end
        if not isString(encounter.layout) or not data.layouts[encounter.layout] then return path .. ".layout" end
        if encounter.raid ~= nil and not isString(encounter.raid) then return path .. ".raid" end
        if encounter.encounterId ~= nil and type(encounter.encounterId) ~= "number" then
            return path .. ".encounterId"
        end
        -- A note edited in game (issue #25): only in plans that come through the sync, never in an export
        if encounter.customNote ~= nil and not isString(encounter.customNote) then return path .. ".customNote" end
        local problem = checkTemplate(encounter, path)
        if problem then return problem end
    end
    if data.gargul ~= nil and (type(data.gargul) ~= "table" or not isString(data.gargul.string)) then
        return "gargul"
    end
    return nil
end
