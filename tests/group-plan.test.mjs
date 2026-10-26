// Runs Modules/GroupPlan.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Lua side: compare(layoutJSON-ish, roster) through a tiny line format, the result back as JSON
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/GroupPlan.lua"))("UnityTools-RaidManagement", ns)
local GroupPlan = ns.GroupPlan

local function split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return out
end

local function quote(s) return '"' .. s .. '"' end
local function list(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = quote(v) end
    return "[" .. table.concat(out, ",") .. "]"
end

-- layout: 40 names joined by "|"; roster: "Name:group" entries joined by "|"
function run(layoutText, rosterText)
    local layout = split(layoutText, "|")
    local roster = {}
    if rosterText ~= "" then
        for _, entry in ipairs(split(rosterText, "|")) do
            local name, group = entry:match("^(.*):(%d+)$")
            roster[#roster + 1] = { name = name, group = tonumber(group) }
        end
    end
    local r = GroupPlan.Compare(layout, roster)
    return '{"list":' .. list(r.list) .. ',"missing":' .. list(r.missing) .. ',"extra":' .. list(r.extra)
        .. ',"misplaced":' .. r.misplaced .. '}'
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function compare(layout, roster) {
  const padded = Array.from({ length: 40 }, (_, i) => layout[i] ?? '');
  lua.lua_getglobal(L, to_luastring('run'));
  lua.lua_pushstring(L, to_luastring(padded.join('|')));
  lua.lua_pushstring(L, to_luastring(roster.map(([name, group]) => `${name}:${group}`).join('|')));
  if (lua.lua_pcall(L, 2, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = JSON.parse(to_jsstring(lua.lua_tostring(L, -1)));
  lua.lua_pop(L, 1);
  return out;
}

// Slot helper: group g (1-8), position p (1-5) -> index in the 40-name layout
const slot = (g, p) => (g - 1) * 5 + (p - 1);

test('a raid that matches the plan has nothing misplaced, missing or extra', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  layout[slot(1, 2)] = 'Brumm';
  layout[slot(2, 1)] = 'Cyra';
  const r = compare(layout, [['Aldreth', 1], ['Brumm', 1], ['Cyra', 2]]);
  assert.equal(r.misplaced, 0);
  assert.deepEqual(r.missing, []);
  assert.deepEqual(r.extra, []);
  assert.equal(r.list[slot(2, 1)], 'Cyra');
});

test('players in the wrong group are counted', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  layout[slot(3, 2)] = 'Brumm';
  const r = compare(layout, [['Aldreth', 2], ['Brumm', 3]]);
  assert.equal(r.misplaced, 1);
});

test("names match ignoring case and realm, and the list uses the raid's spelling", () => {
  const layout = [];
  layout[slot(1, 1)] = 'aldreth';
  layout[slot(1, 2)] = 'Brumm-Pyrewood Village';
  const r = compare(layout, [['Aldreth', 1], ['Brumm-Firemaw', 4]]);
  assert.equal(r.list[slot(1, 1)], 'Aldreth');
  assert.equal(r.list[slot(1, 2)], 'Brumm-Firemaw');
  assert.equal(r.misplaced, 1);
  assert.deepEqual(r.missing, []);
});

test('planned players not in the raid are missing and leave their slot empty', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  layout[slot(1, 2)] = 'Ghost';
  const r = compare(layout, [['Aldreth', 1]]);
  assert.deepEqual(r.missing, ['Ghost']);
  assert.equal(r.list[slot(1, 2)], '');
  assert.equal(r.list.length, 40);
});

test('raid members not in the plan are extra, in roster order', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  const r = compare(layout, [['Zed', 5], ['Aldreth', 1], ['Pug', 8]]);
  assert.deepEqual(r.extra, ['Zed', 'Pug']);
});

test('a name planned twice counts once (the first slot)', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  layout[slot(2, 1)] = 'Aldreth';
  const r = compare(layout, [['Aldreth', 1]]);
  assert.equal(r.misplaced, 0);
  assert.equal(r.list[slot(1, 1)], 'Aldreth');
  assert.equal(r.list[slot(2, 1)], '');
});

test('an empty raid makes every planned name missing', () => {
  const layout = [];
  layout[slot(1, 1)] = 'Aldreth';
  layout[slot(8, 5)] = 'Brumm';
  const r = compare(layout, []);
  assert.deepEqual(r.missing, ['Aldreth', 'Brumm']);
  assert.deepEqual(r.extra, []);
});
