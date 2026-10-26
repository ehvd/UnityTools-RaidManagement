// Walks through the in-game test plan (tests/fixtures/raid-groups-test-plan.mjs) as the raid plan window would:
// decodes the string with Modules/PlanCodec.lua, then for every encounter in order compares its layout with the raid
// (Modules/GroupPlan.lua), checks the status Modules/RaidGroups.lua would show and moves the two characters where
// MRT's sorter would put them. Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';
import fengari from 'fengari';
import { BAR, BOG, STEPS, encode, payload } from './fixtures/raid-groups-test-plan.mjs';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/GroupPlan.lua"))("UnityTools-RaidManagement", ns)
local LibDeflate = { DecompressZlib = function(_, data) return node_inflate(data) end }

-- Decodes the string into PLAN; returns "" or the problem
function load(text)
    local data, code = ns.PlanCodec.Decode(text, LibDeflate)
    if not data then return "decode: " .. code end
    if not ns.PlanCodec.IsSupported(data.protocol) then return "protocol " .. data.protocol end
    local problem = ns.PlanCodec.Check(data)
    if problem then return "check: " .. problem end
    PLAN = data
    return ""
end

function encounterCount() return #PLAN.encounters end

-- Compares encounter i's layout with the roster "Name:group|Name:group"; returns
-- "misplaced;missing names,;extra names,;list entries for Bogartlover and Bartababbi"
function compare(i, rosterText)
    local roster = {}
    for name, group in rosterText:gmatch("([^:|]+):(%d+)") do
        roster[#roster + 1] = { name = name, group = tonumber(group) }
    end
    local encounter = PLAN.encounters[i]
    local r = ns.GroupPlan.Compare(PLAN.layouts[encounter.layout], roster)
    local placed = {}
    for slot = 1, 40 do
        if r.list[slot] ~= "" then placed[#placed + 1] = r.list[slot] .. "@" .. math.floor((slot - 1) / 5) + 1 end
    end
    return r.misplaced .. ";" .. table.concat(r.missing, ",") .. ";" .. table.concat(r.extra, ",") .. ";"
        .. table.concat(placed, ",") .. ";" .. encounter.label .. ";" .. encounter.note
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
lua.lua_register(L, to_luastring('node_inflate'), (state) => {
  try {
    lua.lua_pushstring(state, new Uint8Array(inflateSync(Buffer.from(lauxlib.luaL_checkstring(state, 1)))));
  } catch {
    lua.lua_pushnil(state);
  }
  return 1;
});
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const a of args) {
    if (typeof a === 'number') lua.lua_pushinteger(L, a);
    else lua.lua_pushstring(L, to_luastring(a));
  }
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = lua.lua_type(L, -1) === lua.LUA_TNUMBER ? lua.lua_tonumber(L, -1) : to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

// The "(1 missing, 1 not in the plan)" suffix of Modules/RaidGroups.lua
function counts(missing, extra) {
  const parts = [];
  if (missing.length) parts.push(`${missing.length} missing`);
  if (extra.length) parts.push(`${extra.length} not in the plan`);
  return parts.length ? ` (${parts.join(', ')})` : '';
}

test('the test plan decodes and passes the addon checks', () => {
  assert.equal(call('load', encode(payload())), '');
  assert.equal(call('encounterCount'), STEPS.length);
});

test('every encounter, in order, gives the expected status and groups', () => {
  call('load', encode(payload()));
  // The raid is formed with both characters in group 1
  let roster = { [BOG]: 1, [BAR]: 1 };
  STEPS.forEach((step, i) => {
    const out = call('compare', i + 1, Object.entries(roster).map(([n, g]) => `${n}:${g}`).join('|'));
    const [misplacedText, missingText, extraText, placedText, label] = out.split(';');
    const misplaced = Number(misplacedText);
    const missing = missingText ? missingText.split(',') : [];
    const extra = extraText ? extraText.split(',') : [];
    assert.equal(label, step.label);

    const status = misplaced === 0
      ? `Groups already match${counts(missing, extra)}`
      : `Sorting groups...${counts(missing, extra)}`;
    assert.ok(step.expect.startsWith(status), `${step.label}: status "${status}", the note says "${step.expect}"`);

    // MRT moves every planned character who is in the raid to the group of its first slot; others stay.
    // Only names of raid members may reach MRT.
    const planned = new Map();
    for (const entry of placedText ? placedText.split(',') : []) {
      const [name, group] = entry.split('@');
      assert.ok(name in roster, `${step.label}: the list names ${name}, who is not in the raid`);
      if (!planned.has(name)) planned.set(name, Number(group));
    }
    roster = Object.fromEntries(Object.entries(roster).map(([name, group]) => [name, planned.get(name) ?? group]));
    assert.deepEqual(roster, step.after, `${step.label}: groups after sorting`);
  });
});

test('names in other spellings reach MRT as the raid spells them', () => {
  call('load', encode(payload()));
  const index = STEPS.findIndex((s) => s.layout === 'Case and realm');
  const out = call('compare', index + 1, `${BOG}:8|${BAR}:8`);
  assert.equal(out.split(';')[3], `${BOG}@1,${BAR}@1`);
});

test('the string stays short enough to paste comfortably', () => {
  assert.ok(encode(payload()).length < 4000);
});
