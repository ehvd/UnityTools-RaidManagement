// Runs Modules/EncounterList.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// A plan: encounters "key:label:encounterId:layout" joined by "|" (empty id: none), the active and fallback keys.
// describe() shows the result as "keys / active / fallback / layouts", keys "key=label" joined by ",".
// Bosses is a stub of the boss table of issue #43 (Modules/Bosses.lua).
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/EncounterList.lua"))("UnityTools-RaidManagement", ns)
local E = ns.EncounterList

local Bosses = {}
function Bosses.Raids()
    return { { slug = "molten-core", name = "Molten Core" }, { slug = "blackwing-lair", name = "Blackwing Lair" },
        { slug = "ahn-qiraj", name = "Temple of Ahn'Qiraj" } }
end

local plan
function make(encounters, active, fallback)
    plan = { encounters = {}, layouts = { default = {} }, active = active ~= "" and active or nil,
        fallback = fallback ~= "" and fallback or nil,
        event = { raids = { { slug = "ahn-qiraj" }, { slug = "molten-core" } } } }
    for key, label, id, layout in encounters:gmatch("([^:|]+:?[^:|]*):([^:|]+):(%d*):([^:|]+)") do
        plan.encounters[#plan.encounters + 1] = { key = key, label = label, encounterId = tonumber(id), layout = layout,
            note = "n" }
        plan.layouts[layout] = {}
    end
    return "ok"
end

function describe()
    local keys, layouts = {}, {}
    for i, e in ipairs(plan.encounters) do keys[i] = e.key .. "=" .. e.label end
    for key in pairs(plan.layouts) do layouts[#layouts + 1] = key end
    table.sort(layouts)
    return table.concat(keys, ",") .. " / " .. tostring(plan.active) .. " / " .. tostring(plan.fallback) .. " / "
        .. table.concat(layouts, ",")
end

local function out(a, b) return tostring(a) .. ":" .. tostring(b) end

function add(label, slug, key, id)
    local boss = slug ~= "" and { slug = slug, key = key, encounterId = tonumber(id) } or nil
    local index, why = E.Add(plan, label, boss)
    if not index then return out(index, why) end
    local e = plan.encounters[index]
    return table.concat({ index, e.key, e.label, tostring(e.raid), tostring(e.encounterId), e.note, e.layout }, "|")
end

function remove(key)
    local removed, active = E.Remove(plan, key)
    return out(removed and removed.key or removed, active)
end

function rename(key, label) return out(E.Rename(plan, key, label)) end
function move(key, by) return out(E.Move(plan, key, tonumber(by))) end
function hasBoss(id) return tostring(E.HasBoss(plan, tonumber(id))) end

function raids()
    local slugs = {}
    for i, raid in ipairs(E.Raids(Bosses, plan)) do slugs[i] = raid.slug end
    return table.concat(slugs, ",")
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

const MC = 'x:1:Welcome::default|molten-core:trash:Trash::default|molten-core:lucifron:Lucifron:663:Lucifron'
  + '|molten-core:magmadar:Magmadar:664:default';
const night = (active = 'molten-core:lucifron', fallback = 'molten-core:trash') => call('make', MC, active, fallback);
const describe = () => call('describe');

test('a custom encounter gets the next x key, an empty note and the night\'s groups', () => {
  night();
  assert.equal(call('add', '  Trash after Sartura ', '', '', ''), '5|x:2|Trash after Sartura|nil|nil||default');
  assert.equal(call('add', 'More', '', '', ''), '6|x:3|More|nil|nil||default');
});

test('a boss gets a raid:boss key, its raid and its encounter ID; a second copy a new key', () => {
  night();
  assert.equal(call('add', 'Garr', 'molten-core', 'garr', 666), '5|molten-core:garr|Garr|molten-core|666||default');
  assert.equal(call('add', 'Lucifron', 'molten-core', 'lucifron', 663),
    '6|molten-core:lucifron-2|Lucifron|molten-core|663||default');
  assert.equal(call('add', 'Lucifron', 'molten-core', 'lucifron', 663),
    '7|molten-core:lucifron-3|Lucifron|molten-core|663||default');
  assert.equal(call('add', 'Geddon', 'molten-core', 'molten-core:geddon', 668).split('|')[1], 'molten-core:geddon');
});

test('an encounter needs a name', () => {
  night();
  assert.equal(call('add', '   ', '', '', ''), 'nil:label');
  assert.equal(describe().split(' / ')[0].split(',').length, 4);
});

test('removing an encounter that is neither active nor the fallback changes nothing else', () => {
  night();
  assert.equal(call('remove', 'x:1'), 'x:1:nil');
  assert.equal(describe(),
    'molten-core:trash=Trash,molten-core:lucifron=Lucifron,molten-core:magmadar=Magmadar / molten-core:lucifron'
    + ' / molten-core:trash / Lucifron,default');
});

test('removing the active encounter makes the next one active', () => {
  night();
  assert.equal(call('remove', 'molten-core:lucifron'), 'molten-core:lucifron:3');
  assert.equal(describe().split(' / ')[1], 'molten-core:magmadar');
});

test('removing the active last encounter makes the one before it active, the only one none', () => {
  night('molten-core:magmadar');
  assert.equal(call('remove', 'molten-core:magmadar'), 'molten-core:magmadar:3');
  assert.equal(describe().split(' / ')[1], 'molten-core:lucifron');
  call('make', 'x:1:Welcome::default', 'x:1', 'x:1');
  assert.equal(call('remove', 'x:1'), 'x:1:nil');
  assert.equal(describe(), ' / nil / nil / default');
});

test('removing the fallback encounter sets the note after a kill to none', () => {
  night();
  call('remove', 'molten-core:trash');
  assert.equal(describe().split(' / ')[2], 'nil');
});

test('an encounter\'s own groups go with it, unless another encounter uses them; the night\'s groups stay', () => {
  night();
  call('remove', 'molten-core:lucifron');
  assert.equal(describe().split(' / ')[3], 'default');
  call('make', 'a:A::shared|b:B::shared|c:C::default', '', '');
  call('remove', 'a');
  assert.equal(describe().split(' / ')[3], 'default,shared');
  call('remove', 'b');
  call('remove', 'c');
  assert.equal(describe().split(' / ')[3], 'default');
});

test('removing an encounter no longer in the plan', () => {
  night();
  assert.equal(call('remove', 'gone'), 'nil:encounter');
});

test('renaming changes the label only', () => {
  night();
  assert.equal(call('rename', 'molten-core:lucifron', ' Luci '), 'true:nil');
  assert.equal(describe().split(' / ')[0].split(',')[2], 'molten-core:lucifron=Luci');
  assert.equal(call('rename', 'molten-core:lucifron', 'Luci'), 'nil:unchanged');
  assert.equal(call('rename', 'molten-core:lucifron', ' '), 'nil:label');
  assert.equal(call('rename', 'gone', 'X'), 'nil:encounter');
});

test('moving up and down, not past the ends; active and fallback keep their keys', () => {
  night();
  assert.equal(call('move', 'molten-core:lucifron', -1), '2:nil');
  assert.equal(call('move', 'molten-core:lucifron', -1), '1:nil');
  assert.equal(call('move', 'molten-core:lucifron', -1), 'nil:edge');
  assert.equal(call('move', 'molten-core:magmadar', 1), 'nil:edge');
  assert.equal(call('move', 'x:1', 1), '3:nil');
  assert.equal(call('move', 'x:1', 1), '4:nil');
  assert.equal(describe(),
    'molten-core:lucifron=Lucifron,molten-core:trash=Trash,molten-core:magmadar=Magmadar,x:1=Welcome'
    + ' / molten-core:lucifron / molten-core:trash / Lucifron,default');
  assert.equal(call('move', 'gone', 1), 'nil:encounter');
});

test('the boss picker lists the plan\'s raids first, then the rest of the boss table', () => {
  night();
  assert.equal(call('raids'), 'ahn-qiraj,molten-core,blackwing-lair');
});

test('HasBoss finds a boss already in the plan', () => {
  night();
  assert.equal(call('hasBoss', 663), 'true');
  assert.equal(call('hasBoss', 999), 'false');
  assert.equal(call('hasBoss', ''), 'false');
});
