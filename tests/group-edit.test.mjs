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

test('a draft copies every layout and which layout each encounter uses', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.layouts.default[1] = "Draft"
    return plan.layouts.default[1] .. " " .. draft.uses.twins .. " " .. draft.uses.rag .. " "
      .. tostring(GroupEdit.SameDraft(draft, GroupEdit.NewDraft(plan)))
      .. tostring(GroupEdit.SameDraft(GroupEdit.CopyDraft(draft), draft))`), 'Aldreth Twins swap default falsetrue');
});

test('the named layouts are sorted and leave Default out', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.layouts["aq default"] = names("")
    return table.concat(GroupEdit.LayoutKeys(draft), ",")`), 'aq default,Twins swap');
});

test('the users of a layout are its encounters in the draft, in plan order', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.uses.golemagg = "Twins swap"
    local labels = {}
    for _, e in ipairs(GroupEdit.UsersOf(plan, draft, "Twins swap")) do labels[#labels + 1] = e.label end
    for _, e in ipairs(GroupEdit.UsersOf(plan, draft, "Twins swap", "golemagg")) do labels[#labels + 1] = e.label end
    return table.concat(labels, ",")`), 'Golemagg,Twins,Twins');
});

test('an encounter naming a missing layout uses Default', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.uses.rag = "Gone"
    return GroupEdit.LayoutOf(draft, "rag") .. " " .. GroupEdit.LayoutOf(draft, "twins")`), 'default Twins swap');
});

test('a layout name must be new in any case, and Default is taken', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    return tostring(GroupEdit.CheckLayoutName(draft, "  ")) .. " " .. tostring(GroupEdit.CheckLayoutName(draft, "DEFAULT"))
      .. " " .. tostring(GroupEdit.CheckLayoutName(draft, "twins SWAP ")) .. " "
      .. tostring(GroupEdit.CheckLayoutName(draft, "MC Default"))`), 'empty taken taken nil');
});

test('a new layout copies the encounter\'s layout and only that encounter moves to it', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    local key = GroupEdit.NewLayout(draft, "twins", " Twins own ")
    draft.layouts[key][2] = "Own"
    return key .. "|" .. draft.uses.twins .. "|" .. draft.layouts[key][1] .. "|" .. draft.layouts["Twins swap"][2]
      .. "|" .. draft.uses.rag .. "|" .. #draft.layouts[key] .. "|" .. plan.encounters[3].layout`),
  'Twins own|Twins own|Swap||default|40|Twins swap');
});

test('a new layout with a taken name or for a missing encounter is refused', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    local a, why = GroupEdit.NewLayout(draft, "rag", "twins swap")
    local b, why2 = GroupEdit.NewLayout(draft, "gone", "New")
    return tostring(a) .. why .. " " .. tostring(b) .. why2 .. " " .. draft.uses.rag`),
  'niltaken nilencounter default');
});

test('an encounter can use any layout of the draft', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    local key = GroupEdit.UseLayout(draft, "rag", "Twins swap")
    local a, why = GroupEdit.UseLayout(draft, "rag", "Gone")
    local b, why2 = GroupEdit.UseLayout(draft, "gone", "default")
    return key .. " " .. draft.uses.rag .. " " .. tostring(a) .. why .. " " .. tostring(b) .. why2`),
  'Twins swap Twins swap nillayout nilencounter');
});

test('deleting a layout moves its encounters to Default; Default can\'t be deleted', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.uses.rag = "Twins swap"
    local moved = GroupEdit.DeleteLayout(draft, "Twins swap")
    local a, why = GroupEdit.DeleteLayout(draft, "default")
    local b, why2 = GroupEdit.DeleteLayout(draft, "Twins swap")
    return moved .. " " .. draft.uses.rag .. draft.uses.twins .. " " .. tostring(draft.layouts["Twins swap"]) .. " "
      .. tostring(a) .. why .. " " .. tostring(b) .. why2`),
  '2 defaultdefault nil nildefault nillayout');
});

test('the bench is the planned people neither in the groups nor in the raid, once each and sorted', () => {
  assert.equal(run(`
    local l = split("${layout({ [slot(1, 1)]: 'Aldreth' })}")
    local raid = { kael = true }
    local bench = GroupEdit.Bench({ "Zoë", "aldreth", "Kael", "", "Ember", "ember-Firemaw", "brumm" }, l,
      function(name) return raid[name:lower()] end)
    return table.concat(bench, ",")`), 'brumm,Ember,Zoë');
});

test('a player taken out of the groups goes to the bench, and a bench player fills a slot', () => {
  assert.equal(run(`
    local l = split("${layout({ [slot(1, 1)]: 'Aldreth', [slot(2, 1)]: 'Brumm' })}")
    local people = { "Aldreth", "Brumm", "Zoë" }
    local function nobody() return false end
    GroupEdit.Remove(l, ${slot(1, 1)})
    local first = table.concat(GroupEdit.Bench(people, l, nobody), ",")
    GroupEdit.Place(l, ${slot(2, 1)}, "Zoë")
    return first .. "|" .. table.concat(GroupEdit.Bench(people, l, nobody), ",") .. "|" .. l[${slot(2, 1)}]`),
  'Aldreth,Zoë|Aldreth,Brumm|Zoë');
});

test('a typed name is trimmed and capitalized as WoW spells it', () => {
  assert.equal(run(`return GroupEdit.CleanName("  aLDRETH ")`), 'Aldreth');
  assert.equal(run(`return GroupEdit.CleanName("brumm-Firemaw")`), 'Brumm-Firemaw');
  assert.equal(run(`return "[" .. GroupEdit.CleanName("   ") .. "]"`), '[]');
});

test('an empty name or one already in the plan or raid is refused', () => {
  assert.equal(run(`
    local taken = { aldreth = true }
    local function isTaken(name) return taken[name:lower()] end
    return tostring(GroupEdit.CheckNewName("", isTaken)) .. " " .. tostring(GroupEdit.CheckNewName("-Firemaw", isTaken))
      .. " " .. tostring(GroupEdit.CheckNewName("Aldreth", isTaken)) .. " "
      .. tostring(GroupEdit.CheckNewName("Zoë", isTaken))`),
  'empty empty taken nil');
});

test('adding a player puts them in the people, once, any spelling', () => {
  assert.equal(run(`${PLAN}
    local added = GroupEdit.AddPerson(plan, "Zoë", "MAGE")
    local again, why = GroupEdit.AddPerson(plan, "Zoë", "PRIEST")
    local planned, why2 = GroupEdit.AddPerson(plan, "aldreth-Firemaw", "PRIEST")
    return added .. " " .. plan.people["Zoë"].class .. " " .. tostring(again) .. why .. " " .. tostring(planned) .. why2`),
  'Zoë MAGE niltaken niltaken');
});

test('removing a player takes them out of the people and every layout', () => {
  assert.equal(run(`${PLAN}
    plan.people = { Swap = { class = "ROGUE" }, Brumm = { class = "MAGE" } }
    plan.layouts.default[5] = "swap-Firemaw"
    local changed = GroupEdit.RemovePerson(plan, "Swap")
    local again = GroupEdit.RemovePerson(plan, "Swap")
    return tostring(changed) .. " " .. tostring(again) .. " " .. tostring(plan.people.Swap) .. " ["
      .. plan.layouts["Twins swap"][1] .. "|" .. plan.layouts.default[5] .. "|" .. plan.layouts.default[1]
      .. "] " .. plan.people.Brumm.class`),
  'true false nil [||Aldreth] MAGE');
});

test('the uses of a player are the other encounters\' groups and the assignments naming them', () => {
  assert.equal(run(`${PLAN}
    plan.encounters[1].slots = { { n = 1, holders = { "Tank", "swap" } } }
    local draft = GroupEdit.NewDraft(plan)
    local uses = GroupEdit.UsesOf(plan, draft, "Swap", "default")
    local mine = GroupEdit.UsesOf(plan, draft, "Swap", "Twins swap")
    local out = {}
    for _, e in ipairs(uses.groups) do out[#out + 1] = e.label end
    out[#out + 1] = "/"
    for _, e in ipairs(uses.holds) do out[#out + 1] = e.label end
    return table.concat(out, ",") .. " " .. #mine.groups .. tostring(uses.night)`),
  'Twins,/,Ragnaros 0false');
});

test('the uses of a player follow the draft, not the saved plan', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.uses.rag = "Twins swap"
    local out = {}
    for _, e in ipairs(GroupEdit.UsesOf(plan, draft, "Swap", "default").groups) do out[#out + 1] = e.label end
    return table.concat(out, ",")`), 'Ragnaros,Twins');
});

test('Default counts as a use when no encounter is on it', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.uses.rag, draft.uses.golemagg = "Twins swap", "Twins swap"
    return tostring(GroupEdit.UsesOf(plan, draft, "Aldreth", "Twins swap").night)`), 'true');
});

test('saving the draft removes, adds, then stores every layout and which one each encounter uses', () => {
  assert.equal(run(`${PLAN}
    plan.people = { Swap = { class = "ROGUE" } }
    local draft = GroupEdit.NewDraft(plan)
    draft.layouts["Twins swap"][2] = "Zoë"
    GroupEdit.NewLayout(draft, "rag", "Rag")
    draft.layouts.Rag[3] = "Swap"
    local ok = GroupEdit.SaveDraft(plan, draft, { { name = "Zoë", class = "MAGE" } }, { "Swap" })
    draft.layouts.Rag[4] = "Later"
    return tostring(ok) .. " " .. tostring(plan.people.Swap) .. " " .. plan.people["Zoë"].class .. " ["
      .. plan.layouts["Twins swap"][1] .. "|" .. plan.layouts["Twins swap"][2] .. "] " .. plan.encounters[1].layout
      .. " [" .. plan.layouts.Rag[1] .. "|" .. plan.layouts.Rag[3] .. "|" .. plan.layouts.Rag[4] .. "]"`),
  'true nil MAGE [|Zoë] Rag [Aldreth||]');
});

test('saving a deleted layout removes it from the plan and its encounters use Default', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    GroupEdit.DeleteLayout(draft, "Twins swap")
    local ok = GroupEdit.SaveDraft(plan, draft, {}, {})
    return tostring(ok) .. " " .. tostring(plan.layouts["Twins swap"]) .. " " .. plan.encounters[3].layout`),
  'true nil default');
});

test('a draft with nothing new is unchanged', () => {
  assert.equal(run(`${PLAN}
    local key, why = GroupEdit.SaveDraft(plan, GroupEdit.NewDraft(plan), {}, { "Nobody" })
    return tostring(key) .. why .. " " .. tostring(plan.people)`),
  'nilunchanged nil');
});

test('a removed player is not saved back from any draft layout', () => {
  assert.equal(run(`${PLAN}
    local draft = GroupEdit.NewDraft(plan)
    draft.layouts["Twins swap"][9] = "aldreth"
    local ok = GroupEdit.SaveDraft(plan, draft, {}, { "Aldreth" })
    return tostring(ok) .. "[" .. plan.layouts.default[1] .. "|" .. plan.layouts["Twins swap"][9] .. "]"`),
  'true[|]');
});
