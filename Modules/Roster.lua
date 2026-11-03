local _, ns = ...

-- The raid's members as one string for the UnityWiki raid planner (issue #47), to compare a plan with who is really
-- in the raid. UnityWiki owns the format (docs/addon-roster.md there, roster protocol 1): base64(zlib(JSON)), the
-- plan export's encoding, with `protocol` the JSON's first key and `kind` "roster".
-- Pure Lua apart from LibDeflate, which the caller passes in, so tests/roster can run it outside the game; the rows
-- come from GetRaidRosterInfo in UI/RosterSection.lua.
local Roster = {}
ns.Roster = Roster

Roster.PROTOCOL = 1
Roster.KIND = "roster"
Roster.MAX_MEMBERS = 40

local byte, find, sub, concat, floor, format = string.byte, string.find, string.sub, table.concat, math.floor,
    string.format

------------------------------------------------------------------------------------------------ members ---

-- "Name-Realm" -> "Name", "Realm", split at the first hyphen: a character name never holds one and a realm may
-- (Zeta-Azjol-Nerub is Zeta of Azjol-Nerub). A bare name is from `ownRealm`.
function Roster.SplitName(name, ownRealm)
    local hyphen = find(name, "-", 1, true)
    if hyphen then
        return sub(name, 1, hyphen - 1), sub(name, hyphen + 1)
    end
    return name, ownRealm
end

-- One row of GetRaidRosterInfo's returns ({ name, rank, subgroup, level, class, fileName, zone, online, ... }) ->
-- a member of the payload, or nil while the game has not loaded the row yet (no name or no class token)
function Roster.Member(row, ownRealm)
    if type(row.name) ~= "string" or row.name == "" or type(row.fileName) ~= "string" or row.fileName == "" then
        return nil
    end
    local name, realm = Roster.SplitName(row.name, ownRealm)
    return {
        name = name,
        realm = realm,
        class = row.fileName,
        level = row.level or 0,
        group = row.subgroup or 1,
        rank = row.rank or 0,
        online = row.online == true,
        zone = row.zone or "",
    }
end

-- The rows of the raid (in raid index order) -> the payload, made by `player` of `realm` at `now` (unix seconds),
-- and how many rows were left out because the game had not loaded them yet
function Roster.Payload(rows, player, realm, now)
    local members, skipped = {}, 0
    for _, row in ipairs(rows) do
        local member = #members < Roster.MAX_MEMBERS and Roster.Member(row, realm)
        if member then
            members[#members + 1] = member
        else
            skipped = skipped + 1
        end
    end
    return {
        protocol = Roster.PROTOCOL,
        kind = Roster.KIND,
        generatedAt = now,
        by = (Roster.SplitName(player, realm)),
        realm = realm,
        members = members,
    }, skipped
end

------------------------------------------------------------------------------------------------- encode ---

-- The keys in the order they are written: `protocol` first, as the format requires; the rest as the wiki's doc
-- lists them
local PAYLOAD_KEYS = { "protocol", "kind", "generatedAt", "by", "realm", "members" }
local MEMBER_KEYS = { "name", "realm", "class", "level", "group", "rank", "online", "zone" }

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
    ["\t"] = "\\t" }

local function encodeValue(v)
    local t = type(v)
    if t == "string" then
        -- Bytes from 0x80 up (UTF-8 names) go as they are; JSON only needs " \ and control characters
        return '"' .. v:gsub('[%c"\\]', function(c) return ESCAPES[c] or format("\\u%04x", byte(c)) end) .. '"'
    elseif t == "number" then
        return format("%.0f", v)   -- integers only here; %.0f is exact also where %d is 32 bit
    elseif t == "boolean" then
        return tostring(v)
    end
    error("a " .. t .. " in the roster", 0)
end

local function encodeObject(object, keys)
    local out = {}
    for i, key in ipairs(keys) do
        out[i] = '"' .. key .. '":' .. (key == "members" and object[key] or encodeValue(object[key]))
    end
    return "{" .. concat(out, ",") .. "}"
end

-- Compact JSON of a payload, keys in a fixed order
function Roster.JSONEncode(payload)
    local members = {}
    for i, member in ipairs(payload.members) do
        members[i] = encodeObject(member, MEMBER_KEYS)
    end
    local copy = {}
    for key, value in pairs(payload) do copy[key] = value end
    copy.members = "[" .. concat(members, ",") .. "]"
    return encodeObject(copy, PAYLOAD_KEYS)
end

local ALPHABET = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do ALPHABET[i - 1] = sub(alphabet, i, i) end
end

-- Standard base64 (not URL-safe) with "=" padding, one line
function Roster.Base64Encode(bytes)
    local out, n = {}, 0
    for i = 1, #bytes, 3 do
        local a, b, c = byte(bytes, i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        n = n + 1
        out[n] = ALPHABET[floor(v / 262144)] .. ALPHABET[floor(v / 4096) % 64]
            .. (b and ALPHABET[floor(v / 64) % 64] or "=") .. (c and ALPHABET[v % 64] or "=")
    end
    return concat(out)
end

-- A payload -> base64(zlib(JSON)), the string the wiki's Paste raid roster reads
function Roster.Encode(payload, LibDeflate)
    return Roster.Base64Encode(LibDeflate:CompressZlib(Roster.JSONEncode(payload)))
end
