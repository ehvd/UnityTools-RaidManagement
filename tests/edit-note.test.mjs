// Runs the note editing of Modules/PlanImport.lua (issue #25) in fengari, with the few WoW and Ace3 globals it
// touches stubbed. Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Answers travel as strings: "nil" for nil, "true"/"false" for booleans
const SHIM = `
local now = 1000
function GetServerTime() return now end
function UnitName() return "Leader" end
function LibStub() return {} end
format = string.format
local messages = {}
local modules = {}
UnityToolsRaidManagement = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    db = { global = {} },
    NewModule = function(_, name) modules[name] = {}; return modules[name] end,
    SendMessage = function(_, name) messages[#messages + 1] = name end,
}
local UTRM = UnityToolsRaidManagement
local ns = {}
assert(loadfile(ROOT .. "/Modules/SyncRules.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanImport.lua"))("UnityTools-RaidManagement", ns)
local PlanImport = modules.PlanImport

local function show(v) return v == nil and "nil" or tostring(v) end

function reset()
    now = 1000
    messages = {}
    UTRM.db.global.plan = {
        event = { id = "e1" }, generatedAt = 100, importedAt = 500, chosenAt = 500,
        encounters = {
            { key = "mc:1", label = "Lucifron", note = "plan note", layout = "default" },
            { key = "mc:2", label = "Magmadar", note = "", layout = "default" },
        },
    }
end

function noplan() UTRM.db.global.plan = nil end

function edit(key, text)
    now = now + 1
    local ok, message = PlanImport:EditNote(key, text ~= "\\0" and text or nil)
    return show(ok) .. "|" .. show(message)
end

function custom(i) return show(UTRM.db.global.plan.encounters[tonumber(i)].customNote) end
function noteOf(i) return PlanImport:NoteOf(UTRM.db.global.plan.encounters[tonumber(i)]) end
function planNote(i) return UTRM.db.global.plan.encounters[tonumber(i)].note end
function revisedAt()
    local plan = UTRM.db.global.plan
    return show(plan.revision and plan.revision.at) .. "|" .. show(plan.chosenAt)
end
function messageList() return table.concat(messages, ",") end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const arg of args) lua.lua_pushstring(L, to_luastring(String(arg)));
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = lua.lua_isnil(L, -1) ? undefined : to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

const RESET = '\0';   // EditNote(key, nil)

test('without a hand edit the plan note is the note', () => {
  call('reset');
  assert.equal(call('noteOf', 1), 'plan note');
  assert.equal(call('custom', 1), 'nil');
});

test('saving a note keeps it next to the plan note and makes an edit', () => {
  call('reset');
  assert.equal(call('edit', 'mc:1', 'hand edit'), 'true|nil');
  assert.equal(call('custom', 1), 'hand edit');
  assert.equal(call('noteOf', 1), 'hand edit');
  assert.equal(call('planNote', 1), 'plan note');
  assert.equal(call('revisedAt'), '1001|1001');
  assert.equal(call('messageList'), 'UTRM_PLAN_EDITED');
});

test('an empty note is a hand edit too', () => {
  call('reset');
  assert.equal(call('edit', 'mc:1', ''), 'true|nil');
  assert.equal(call('noteOf', 1), '');
});

test('reset brings back the plan note', () => {
  call('reset');
  call('edit', 'mc:1', 'hand edit');
  assert.equal(call('edit', 'mc:1', RESET), 'true|nil');
  assert.equal(call('custom', 1), 'nil');
  assert.equal(call('noteOf', 1), 'plan note');
  assert.equal(call('messageList'), 'UTRM_PLAN_EDITED,UTRM_PLAN_EDITED');
});

test('saving the plan note again removes the hand edit', () => {
  call('reset');
  call('edit', 'mc:1', 'hand edit');
  assert.equal(call('edit', 'mc:1', 'plan note'), 'true|nil');
  assert.equal(call('custom', 1), 'nil');
});

test('nothing changed is no edit', () => {
  call('reset');
  assert.equal(call('edit', 'mc:1', 'plan note'), 'false|nil');
  assert.equal(call('edit', 'mc:1', RESET), 'false|nil');
  call('edit', 'mc:1', 'hand edit');
  assert.equal(call('edit', 'mc:1', 'hand edit'), 'false|nil');
  assert.equal(call('revisedAt'), '1003|1003');
  assert.equal(call('messageList'), 'UTRM_PLAN_EDITED');
});

test('an encounter that is gone or a missing plan is reported', () => {
  call('reset');
  assert.equal(call('edit', 'mc:9', 'x'), 'false|This encounter is no longer in the raid plan.');
  assert.equal(call('revisedAt'), 'nil|500');
  call('noplan');
  assert.equal(call('edit', 'mc:1', 'x'), 'false|No raid plan imported yet.');
});
