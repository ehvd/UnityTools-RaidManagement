// Runs Modules/GroupEdit.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Lua side: layouts travel as 40 names joined by "|"
const SHIM = `
ns = {}
assert(loadfile(ROOT .. "/Modules/GroupPlan.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/GroupEdit.lua"))("UnityTools-RaidManagement", ns)
GroupEdit = ns.GroupEdit

function split(s)
    local out = {}
    for part in (s .. "|"):gmatch("(.-)|") do out[#out + 1] = part end
    return out
end
function join(t) return table.concat(t, "|") end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

// Runs a Lua chunk that returns one string
function run(code) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

// Slot helper: group g (1-8), position p (1-5) -> Lua slot number (1-40)
const slot = (g, p) => (g - 1) * 5 + p;

function layout(entries) {
  const names = Array.from({ length: 40 }, () => '');
  for (const [s, name] of Object.entries(entries)) names[s - 1] = name;
  return names.join('|');
}

// Applies Lua operations (`l` is the layout) and returns the layout as a { slot: name } object
function edit(start, ops) {
  const text = run(`local l = split("${start}") ${ops} return join(l)`);
  const out = {};
  text.split('|').forEach((name, i) => { if (name) out[i + 1] = name; });
  return out;
}

test('swapping two players exchanges their slots', () => {
  const start = layout({ [slot(1, 1)]: 'Aldreth', [slot(2, 3)]: 'Brumm' });
  assert.deepEqual(edit(start, `GroupEdit.Swap(l, ${slot(1, 1)}, ${slot(2, 3)})`),
    { [slot(1, 1)]: 'Brumm', [slot(2, 3)]: 'Aldreth' });
});

test('moving a player to an empty slot empties the old one', () => {
  const start = layout({ [slot(1, 1)]: 'Aldreth' });
  assert.deepEqual(edit(start, `GroupEdit.Swap(l, ${slot(1, 1)}, ${slot(8, 5)})`), { [slot(8, 5)]: 'Aldreth' });
});

test('placing a raid member from the list replaces the slot and the old player leaves', () => {
  const start = layout({ [slot(3, 2)]: 'Ghost', [slot(1, 1)]: 'Aldreth' });
  assert.deepEqual(edit(start, `GroupEdit.Place(l, ${slot(3, 2)}, "Ingrid-Firemaw")`),
    { [slot(1, 1)]: 'Aldreth', [slot(3, 2)]: 'Ingrid-Firemaw' });
});

test('placing a player who is already in the layout swaps, matching any spelling', () => {
  const start = layout({ [slot(1, 1)]: 'Aldreth', [slot(2, 1)]: 'Brumm' });
  assert.deepEqual(edit(start, `GroupEdit.Place(l, ${slot(2, 1)}, "aldreth-Firemaw")`),
    { [slot(1, 1)]: 'Brumm', [slot(2, 1)]: 'Aldreth' });
});

test('removing takes the player out of the layout', () => {
  const start = layout({ [slot(1, 1)]: 'Aldreth', [slot(1, 2)]: 'Brumm' });
  assert.deepEqual(edit(start, `GroupEdit.Remove(l, ${slot(1, 2)})`), { [slot(1, 1)]: 'Aldreth' });
});

test('a copy has 40 slots and does not share the table', () => {
  assert.equal(run(`
    local l = { "A" }
    local c = GroupEdit.Copy(l)
    c[1] = "B"
    return #c .. l[1] .. c[40] .. tostring(GroupEdit.Equal(l, { "A" }))`), '40Atrue');
});

test('a new layout key never reuses an existing one', () => {
  assert.equal(run(`return GroupEdit.NewKey({ default = {} }, "Ragnaros")`), 'Ragnaros');
  assert.equal(run(`return GroupEdit.NewKey({ Ragnaros = {}, ["Ragnaros (2)"] = {} }, "Ragnaros")`), 'Ragnaros (3)');
});

// A plan with two encounters on the night's groups and one on a named layout
const PLAN = `
  local function names(n) local t = {} for i = 1, 40 do t[i] = "" end t[1] = n return t end
  local plan = {
    layouts = { default = names("Aldreth"), ["Twins swap"] = names("Swap") },
    encounters = {
      { key = "rag", label = "Ragnaros", layout = "default" },
      { key = "golemagg", label = "Golemagg", layout = "default" },
      { key = "twins", label = "Twins", layout = "Twins swap" },
    },
  }
  local edited = names("Brumm")
`;

test('saving for every fight changes the night\'s groups', () => {
  assert.equal(run(`${PLAN}
    local key = GroupEdit.Save(plan, "rag", edited, false)
    return key .. " " .. plan.layouts.default[1] .. " " .. plan.encounters[2].layout`), 'default Brumm default');
});

test('saving for only this fight makes a named layout that only that encounter uses', () => {
  assert.equal(run(`${PLAN}
    local key = GroupEdit.Save(plan, "rag", edited, true)
    return key .. "|" .. plan.encounters[1].layout .. "|" .. plan.layouts.Ragnaros[1] .. "|"
      .. plan.layouts.default[1] .. "|" .. plan.encounters[2].layout .. "|" .. #plan.layouts.Ragnaros`),
  'Ragnaros|Ragnaros|Brumm|Aldreth|default|40');
});

test('the saved layout is a copy, not the editor\'s table', () => {
  assert.equal(run(`${PLAN}
    GroupEdit.Save(plan, "rag", edited, false)
    edited[1] = "Later"
    return plan.layouts.default[1]`), 'Brumm');
});

test('an encounter on a named layout saves into it, also with only this fight', () => {
  assert.equal(run(`${PLAN}
    local key = GroupEdit.Save(plan, "twins", edited, true)
    return key .. "|" .. plan.layouts["Twins swap"][1] .. "|" .. plan.encounters[3].layout`), 'Twins swap|Brumm|Twins swap');
});

test('saving an unchanged layout or a missing encounter changes nothing', () => {
  assert.equal(run(`${PLAN}
    local key, why = GroupEdit.Save(plan, "rag", names("Aldreth"), true)
    return tostring(key) .. " " .. why .. " " .. plan.encounters[1].layout`), 'nil unchanged default');
  assert.equal(run(`${PLAN}
    local key, why = GroupEdit.Save(plan, "gone", edited, false)
    return tostring(key) .. " " .. why`), 'nil encounter');
});
