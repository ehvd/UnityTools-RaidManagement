// Runs Modules/FallbackRules.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// encounters: "key:label:encounterId" entries joined by "|" (an empty id: none); "" for nil arguments.
// The answer comes back as "index:killed" or "-:reason".
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/FallbackRules.lua"))("UnityTools-RaidManagement", ns)
local R = ns.FallbackRules

local function plan(encounters, fallback, active)
    local p = { encounters = {}, fallback = fallback ~= "" and fallback or nil, active = active ~= "" and active or nil }
    for key, label, id in encounters:gmatch("([^:|]+):([^:|]+):(%d*)") do
        p.encounters[#p.encounters + 1] = { key = key, label = label, encounterId = tonumber(id) }
    end
    return p
end

function decide(encounters, fallback, active, killId, killName, success, leader)
    local index, why = R.Decide(plan(encounters, fallback, active),
        { encounterId = tonumber(killId), name = killName, success = success == "1" }, leader == "1")
    if index then return index .. ":" .. why end
    return "-:" .. why
end

function decideWithoutPlan()
    local index, why = R.Decide(nil, { encounterId = 663, name = "Lucifron", success = true }, true)
    return tostring(index) .. ":" .. why
end

function encounter(encounters, fallback)
    local e = R.Encounter(plan(encounters, fallback, ""))
    return e and e.label or "-"
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const arg of args) lua.lua_pushstring(L, to_luastring(String(arg)));
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

// A protocol 2 night: trash without an ID, two bosses with Blizzard's encounter IDs
const MC = 'trash:Trash:|luci:Lucifron:663|mag:Magmadar:664';
// The same night from protocol 1: no IDs
const MC1 = 'trash:Trash:|luci:Lucifron:|mag:Magmadar:';

const kill = ({ encounters = MC, fallback = 'trash', active = 'luci', id = 663, name = 'Lucifron', success = 1, leader = 1 } = {}) =>
  call('decide', encounters, fallback, active, id, name, success, leader);

test('a kill of a boss in the plan switches to the fallback, named by the plan', () => {
  assert.equal(kill(), '1:Lucifron');
  assert.equal(kill({ id: 664, name: 'Magmadar', active: 'mag' }), '1:Magmadar');
});

test('only the raid leader switches', () => {
  assert.equal(kill({ leader: 0 }), '-:leader');
});

test('a wipe does not switch', () => {
  assert.equal(kill({ success: 0 }), '-:wipe');
});

test('no fallback, or a fallback no longer in the plan, does not switch', () => {
  assert.equal(kill({ fallback: '' }), '-:none');
  assert.equal(kill({ fallback: 'gone' }), '-:none');
  assert.equal(call('decideWithoutPlan'), 'nil:none');
});

test('the fallback already active does not switch', () => {
  assert.equal(kill({ active: 'trash' }), '-:active');
});

test('with encounter IDs, a boss not in the plan does not switch', () => {
  assert.equal(kill({ id: 610, name: 'Razorgore the Untamed' }), '-:boss');
});

test('without encounter IDs (protocol 1), any kill switches, named by the game', () => {
  assert.equal(kill({ encounters: MC1, id: 610, name: 'Razorgore the Untamed' }), '1:Razorgore the Untamed');
  assert.equal(kill({ encounters: MC1, success: 0 }), '-:wipe');
});

test('the fallback can be any encounter of the plan, also with no encounter active', () => {
  assert.equal(kill({ fallback: 'mag', active: '' }), '3:Lucifron');
});

test('Encounter finds the chosen fallback, or nothing', () => {
  assert.equal(call('encounter', MC, 'trash'), 'Trash');
  assert.equal(call('encounter', MC, 'gone'), '-');
  assert.equal(call('encounter', MC, ''), '-');
});
