// Runs Modules/NewPlan.lua in fengari (a Lua VM in JavaScript): a plan made in game has the shape of an import, so
// PlanCodec.Check accepts it. Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Lua side: a plan as canonical JSON (sorted keys) so JavaScript can compare it
const SHIM = `
ns = {}
assert(loadfile(ROOT .. "/Modules/NoteTemplate.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/Bosses.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/NewPlan.lua"))("UnityTools-RaidManagement", ns)
NewPlan, Codec = ns.NewPlan, ns.PlanCodec

local function canon(v)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('[%c"\\\\]', function(c)
            if c == '"' or c == "\\\\" then return "\\\\" .. c end
            return string.format("\\\\u%04x", c:byte())
        end) .. '"'
    elseif t == "number" then
        return string.format("%d", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "null"
    elseif next(v) == nil then
        return "{}"
    elseif #v > 0 then
        local out = {}
        for i = 1, #v do out[i] = canon(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = canon(k) .. ":" .. canon(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

-- { plan, error, check } as JSON
function build(options)
    local plan, err = NewPlan.Build(options)
    return canon({ plan = plan or false, err = err or false, check = plan and (Codec.Check(plan) or "ok") or false })
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function run(code) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

const build = (options) => JSON.parse(run(`return build(${options})`));
const empty = Array.from({ length: 40 }, () => '');

test('one raid: Trash, then the bosses in kill order with encounter IDs and empty notes', () => {
  const { plan, check } = build('{ title = "MC night", raids = { "molten-core" }, player = "Aldreth", now = 1790000000 }');
  assert.equal(check, 'ok');
  assert.equal(plan.protocol, 2);
  assert.equal(plan.generatedAt, 1790000000);
  assert.deepEqual(plan.event, {
    id: 'addon:Aldreth:1790000000', title: 'MC night', raids: [{ slug: 'molten-core', name: 'Molten Core' }],
  });
  assert.equal(plan.encounters.length, 11);
  assert.deepEqual(plan.encounters[0], { key: 'molten-core:trash', label: 'Trash', raid: 'molten-core', note: '', layout: 'default' });
  assert.deepEqual(plan.encounters[1], {
    key: 'molten-core:lucifron', label: 'Lucifron', raid: 'molten-core', encounterId: 663, note: '', layout: 'default',
  });
  assert.equal(plan.encounters[10].key, 'molten-core:ragnaros');
  assert.ok(plan.encounters.every((e) => e.template === undefined && e.slots === undefined));
  assert.equal(plan.gargul, undefined);
  assert.deepEqual(plan.layouts, { default: empty });
  assert.deepEqual(plan.people, {});
});

test('several raids: each raid its own Trash, named after the raid, in the chosen order', () => {
  const { plan, check } = build('{ title = "x", raids = { "onyxias-lair", "ahn-qiraj" }, player = "A", now = 1 }');
  assert.equal(check, 'ok');
  assert.deepEqual(plan.encounters.map((e) => e.key), [
    'onyxias-lair:trash', 'onyxias-lair:onyxia', 'ahn-qiraj:trash', 'ahn-qiraj:skeram', 'ahn-qiraj:bug-trio',
    'ahn-qiraj:sartura', 'ahn-qiraj:fankriss', 'ahn-qiraj:viscidus', 'ahn-qiraj:huhuran', 'ahn-qiraj:twin-emperors',
    'ahn-qiraj:ouro', 'ahn-qiraj:cthun',
  ]);
  assert.equal(plan.encounters[0].label, "Trash (Onyxia's Lair)");
  assert.equal(plan.encounters[2].label, 'Trash (Temple of Ahn\'Qiraj)');
});

test('the raid as it is now becomes the night\'s groups, and everybody in them a person', () => {
  const { plan, check } = build(`{ title = "x", raids = { "naxxramas" }, player = "A", now = 1, roster = {
    { name = "Aldreth", group = 1, class = "WARRIOR" },
    { name = "Zoë", group = 3, class = "PRIEST" },
    { name = "Brunhild-Firemaw", group = 1 },
    { name = "Aldreth", group = 2, class = "WARRIOR" },
  } }`);
  assert.equal(check, 'ok');
  const expected = [...empty];
  expected[0] = 'Aldreth';
  expected[1] = 'Brunhild-Firemaw';
  expected[10] = 'Zoë';
  assert.deepEqual(plan.layouts.default, expected);
  assert.deepEqual(plan.people, { Aldreth: { class: 'WARRIOR' }, 'Brunhild-Firemaw': {}, 'Zoë': { class: 'PRIEST' } });
});

test('a sixth member of a group is left out rather than moved', () => {
  const roster = Array.from({ length: 6 }, (_, i) => `{ name = "P${i}", group = 8 }`).join(',');
  const { plan } = build(`{ title = "x", raids = { "molten-core" }, player = "A", now = 1, roster = { ${roster} } }`);
  assert.deepEqual(plan.layouts.default.slice(35), ['P0', 'P1', 'P2', 'P3', 'P4']);
  assert.equal(plan.people.P5, undefined);
});

test('translate gives the labels and raid names', () => {
  const { plan } = build(`{ title = "x", raids = { "molten-core", "onyxias-lair" }, player = "A", now = 1,
    translate = function(text) return "<" .. text .. ">" end }`);
  assert.equal(plan.event.raids[0].name, '<Molten Core>');
  assert.equal(plan.encounters[0].label, '<Trash (%s)>'.replace('%s', '<Molten Core>'));
  assert.equal(plan.encounters[1].label, '<Lucifron>');
});

test('no title or no raid is refused', () => {
  assert.equal(build('{ title = "  ", raids = { "molten-core" }, now = 1 }').err, 'title');
  assert.equal(build('{ title = "x", raids = {}, now = 1 }').err, 'raids');
  assert.equal(build('{ title = "x", raids = { "karazhan" }, now = 1 }').err, 'raid:karazhan');
});

test('the title is trimmed', () => {
  assert.equal(build('{ title = "  MC  ", raids = { "molten-core" }, player = "A", now = 1 }').plan.event.title, 'MC');
});

test('a plan made in game is told apart from an export', () => {
  assert.equal(run('return tostring(NewPlan.IsMadeInGame(NewPlan.Build({ title = "x", raids = { "molten-core" }, player = "A", now = 1 })))'),
    'true');
  assert.equal(run('return tostring(NewPlan.IsMadeInGame({ event = { id = "1234567890" } }))'), 'false');
  assert.equal(run('return tostring(NewPlan.IsMadeInGame(nil))'), 'false');
});

test('the default title is the raids and the day', () => {
  assert.equal(run('return NewPlan.DefaultTitle({ "Molten Core", "Onyxia\'s Lair" }, "2026-11-02")'),
    "Molten Core + Onyxia's Lair 2026-11-02");
  assert.equal(run('return NewPlan.DefaultTitle({}, "2026-11-02")'), '2026-11-02');
});
