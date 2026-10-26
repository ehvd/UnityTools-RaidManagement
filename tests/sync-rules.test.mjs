// Runs Modules/SyncRules.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Metas and messages travel as "key=value;key=value" strings ("" for nil); numbers stay numbers
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/SyncRules.lua"))("UnityTools-RaidManagement", ns)
local R = ns.SyncRules

local function parse(text)
    if text == "" then return nil end
    local t = {}
    for key, value in text:gmatch("([^=;]+)=([^;]*)") do
        t[key] = tonumber(value) or value
    end
    return t
end

function planWins(theirs, mine) return tostring(R.PlanWins(parse(theirs), parse(mine))) end
function activeWins(theirs, mine) return tostring(R.ActiveWins(parse(theirs), parse(mine))) end
function validate(text)
    local msg, why = R.Validate(parse(text))
    return msg and "ok" or why
end
function identity(eventId, generatedAt)
    return R.Identity({ event = { id = eventId }, generatedAt = generatedAt })
end
function meta(chosenAt, importedAt)
    local m = R.Meta({ event = { id = "e1" }, generatedAt = 100, chosenAt = chosenAt ~= "" and tonumber(chosenAt) or nil,
        importedAt = tonumber(importedAt), active = "x:1", activeAt = 7 }, "Me")
    return m.id .. "|" .. m.c .. "|" .. m.g .. "|" .. m.a .. "|" .. m.at .. "|" .. m.s
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const a of args) lua.lua_pushstring(L, to_luastring(String(a)));
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

const m = (fields) => Object.entries(fields).map(([k, v]) => `${k}=${v}`).join(';');
const wins = (theirs, mine) => call('planWins', theirs ? m(theirs) : '', mine ? m(mine) : '') === 'true';

test('a plan replaces no plan, and no plan replaces nothing', () => {
  assert.equal(wins({ id: 'e1@100', c: 5, g: 100, s: 'A' }, null), true);
  assert.equal(wins(null, { id: 'e1@100', c: 5, g: 100, s: 'A' }), false);
});

test('copies of the same export never replace each other', () => {
  assert.equal(wins({ id: 'e1@100', c: 900, g: 100, s: 'A' }, { id: 'e1@100', c: 5, g: 100, s: 'B' }), false);
});

test('the most recently chosen plan wins, even an older export', () => {
  assert.equal(wins({ id: 'e1@100', c: 50, g: 100, s: 'A' }, { id: 'e2@200', c: 40, g: 200, s: 'B' }), true);
  assert.equal(wins({ id: 'e2@200', c: 40, g: 200, s: 'B' }, { id: 'e1@100', c: 50, g: 100, s: 'A' }), false);
});

test('chosen at the same time: the newer export wins, then the name that sorts first', () => {
  assert.equal(wins({ id: 'e2@200', c: 50, g: 200, s: 'B' }, { id: 'e1@100', c: 50, g: 100, s: 'A' }), true);
  assert.equal(wins({ id: 'e2@100', c: 50, g: 100, s: 'Aldreth' }, { id: 'e1@100', c: 50, g: 100, s: 'Brumm' }), true);
  assert.equal(wins({ id: 'e2@100', c: 50, g: 100, s: 'Brumm' }, { id: 'e1@100', c: 50, g: 100, s: 'Aldreth' }), false);
});

test('two clients always agree on the winner (no ping-pong)', () => {
  const plans = [
    { id: 'e1@100', c: 50, g: 100, s: 'A' }, { id: 'e2@200', c: 50, g: 200, s: 'B' },
    { id: 'e3@100', c: 60, g: 100, s: 'C' }, { id: 'e4@100', c: 60, g: 100, s: 'D' },
  ];
  for (const a of plans) {
    for (const b of plans) {
      if (a === b) continue;
      assert.notEqual(wins(a, b), wins(b, a), `${a.id} vs ${b.id}`);
    }
  }
});

test('the active encounter follows the newer choice, for the same plan only', () => {
  const act = (theirs, mine) => call('activeWins', m(theirs), m(mine)) === 'true';
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 20 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), true);
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 5 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), false);
  assert.equal(act({ id: 'e2@100', a: 'mc:garr', at: 20 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), false);
});

test('the meta of a plan falls back to the import time when nothing chose it', () => {
  assert.equal(call('meta', '', 42), 'e1@100|42|100|x:1|7|Me');
  assert.equal(call('meta', 99, 42), 'e1@100|99|100|x:1|7|Me');
  assert.equal(call('identity', 'abc', 123), 'abc@123');
});

test('messages are validated, other versions recognised', () => {
  assert.equal(call('validate', 't=state;v=1;id=e1@100;c=5;g=100'), 'ok');
  assert.equal(call('validate', 't=state;v=1'), 'ok');               // a client without a plan
  assert.equal(call('validate', 't=request;v=1;id=e1@100'), 'ok');
  assert.equal(call('validate', 't=plan;v=1;p=abc'), 'ok');
  assert.equal(call('validate', 't=force;v=1;p=abc'), 'ok');
  assert.equal(call('validate', 't=state;v=2;id=e1@100'), 'version');
  assert.equal(call('validate', 't=hello;v=1'), 'invalid');
  assert.equal(call('validate', 't=request;v=1'), 'invalid');
  assert.equal(call('validate', 't=plan;v=1'), 'invalid');
  assert.equal(call('validate', 't=state;v=1;c=soon'), 'invalid');
  assert.equal(call('validate', ''), 'invalid');
});
