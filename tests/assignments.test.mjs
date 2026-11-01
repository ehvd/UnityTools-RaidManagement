// Runs Modules/Assignments.lua in fengari (a Lua VM in JavaScript) against UnityWiki's protocol 2 fixture
// (tests/fixtures/wiki-export-payload.json): the jobs of an encounter, changing their holders, and the note they
// rebuild. Run with `make test`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const PAYLOAD = JSON.parse(readFileSync(join(root, 'tests', 'fixtures', 'wiki-export-payload.json'), 'utf8'));

// The arguments travel as JSON, decoded with the addon's own decoder; `steps` is a list of
// { set = token, name } / { toggle = token, name } applied to the jobs before the result is taken.
// Results come back as JSON from a small encoder (arrays are tables with [1], objects the rest).
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/NoteTemplate.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/Assignments.lua"))("UnityTools-RaidManagement", ns)
local A, Codec = ns.Assignments, ns.PlanCodec

local function encode(value)
    local t = type(value)
    if t == "string" then return string.format("%q", value):gsub("\\\\\\n", "\\\\n") end
    if t ~= "table" then return tostring(value) end
    local parts = {}
    if value[1] ~= nil or next(value) == nil then
        for i, item in ipairs(value) do parts[i] = encode(item) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = encode(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function jobOf(jobs, token)
    for _, job in ipairs(jobs) do
        for _, t in ipairs(job.tokens) do
            if t == token then return job end
        end
    end
    error("no job " .. token)
end

function run(encounterJson, stepsJson, peopleJson)
    local encounter, steps, people = Codec.JSONDecode(encounterJson), Codec.JSONDecode(stepsJson),
        Codec.JSONDecode(peopleJson)
    local jobs = A.Jobs(encounter)
    for _, step in ipairs(steps) do
        if step.set then A.Set(jobOf(jobs, step.set), step.name) end
        if step.toggle then A.Toggle(jobOf(jobs, step.toggle), step.name) end
    end
    local result = {
        jobs = jobs,
        changed = A.Changed(encounter, jobs),
        invalid = A.Validate(jobs) or false,
        preview = A.Preview(encounter, jobs, people),
        hasTemplate = A.HasTemplate(encounter),
    }
    local before = encounter.note
    result.applied = A.Apply(encounter, jobs, people)
    result.slots = encounter.slots
    result.untouched = before
    return encode(result)
end

function hasTemplate(encounterJson)
    return tostring(A.HasTemplate(Codec.JSONDecode(encounterJson)))
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root.replaceAll('\\', '/')));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function run(encounter, steps = [], people = PAYLOAD.people) {
  lua.lua_getglobal(L, to_luastring('run'));
  for (const arg of [encounter, steps, people]) lua.lua_pushstring(L, to_luastring(JSON.stringify(arg)));
  if (lua.lua_pcall(L, 3, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = JSON.parse(to_jsstring(lua.lua_tostring(L, -1)));
  lua.lua_pop(L, 1);
  return result;
}

function hasTemplate(encounter) {
  lua.lua_getglobal(L, to_luastring('hasTemplate'));
  lua.lua_pushstring(L, to_luastring(JSON.stringify(encounter)));
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = to_jsstring(lua.lua_tostring(L, -1)) === 'true';
  lua.lua_pop(L, 1);
  return result;
}

const encounter = (key) => structuredClone(PAYLOAD.encounters.find((e) => e.key === key));
const holdersOf = (result, token) => result.jobs.find((job) => job.tokens.includes(token)).holders;

test('jobs: one per key, in slot order; none and list slots are not offered', () => {
  const { jobs } = run(encounter('molten-core:lucifron'));
  assert.deepEqual(jobs[0].tokens, ['TANK1', 'MT']);
  assert.deepEqual(jobs[0].holders, ['Aldreth']);
  assert.deepEqual(jobs[0].candidates, ['Aldreth', 'Brunhild', 'Fenlyn']);
  const keys = jobs.map((job) => job.key);
  assert.equal(new Set(keys).size, keys.length, 'a key twice');
  const welcome = run(encounter('x:1')).jobs;
  assert.deepEqual(welcome.map((job) => job.tokens), [['@Kicker']]);   // LEADER and MAGO1 are kind none
  assert.equal(welcome[0].multi, true);
});

test('no changes: the preview is the export note, nothing changed', () => {
  for (const enc of PAYLOAD.encounters) {
    const result = run(structuredClone(enc));
    assert.equal(result.changed, 0, enc.key);
    assert.equal(result.preview, enc.note, enc.key);
    assert.equal(result.invalid, false, enc.key);
  }
});

test('changing a job changes every slot of its key and rebuilds the note', () => {
  const result = run(encounter('molten-core:lucifron'), [{ set: 'MT', name: 'Brunhild' }]);
  assert.equal(result.changed, 1);
  assert.deepEqual(holdersOf(result, 'TANK1'), ['Brunhild']);
  for (const slot of result.slots.filter((s) => s.key === 'role=tank&order=1')) {
    assert.deepEqual(slot.holders, ['Brunhild'], slot.token);
  }
  assert.match(result.preview, /^\{rt1\} \|cffc79c6eBrunhild\|r on Lucifron, \|cffc79c6eBrunhild\|r taunts/);
  assert.equal(result.applied, result.preview);
});

test('emptying a job drops its [[ ]] stretch; filling it brings it back', () => {
  const lucifron = encounter('molten-core:lucifron');
  const filled = run(lucifron, [{ set: 'TANK3', name: 'Fenlyn' }]);
  assert.match(filled.preview, /\n\{rt3\} \|cfff58cbaFenlyn\|r on the far add\n/);
  const emptied = run(encounter('molten-core:lucifron'), [{ set: 'TANK2' }]);
  assert.deepEqual(holdersOf(emptied, 'TANK2'), []);
  // TANK2 has pad 10: the empty slot is ten spaces after "{rt2} ", as on the wiki
  assert.match(emptied.preview, /\n\{rt2\} {11}adds\n/);
});

test('custom assignments: several holders in the order they were added, with the slot separator', () => {
  const steps = [{ toggle: '@Kicker', name: 'Kael' }, { toggle: '@Kicker', name: 'Ember' },
    { toggle: '@Kicker', name: 'Kael' }];
  const result = run(encounter('x:1'), steps);
  assert.deepEqual(holdersOf(result, '@Kicker'), ['Siggi', 'Ember', 'Kael']);
  assert.match(result.preview, /Kicks: \|cff69ccf0Siggi\|r > \|cff69ccf0Ember\|r > \|cfffff569Kael\|r$/);
  const nobody = run(encounter('x:1'), [{ toggle: '@Kicker', name: 'Kael' }, { toggle: '@Kicker', name: 'Siggi' }]);
  assert.equal(nobody.preview, 'Welcome to MC and AQ, 8 coming!\nKicks:');
});

test('validation: one holder for a job of one, nobody twice, candidates only', () => {
  const lucifron = encounter('molten-core:lucifron');
  lucifron.slots[0].holders = ['Aldreth', 'Brunhild'];
  lucifron.slots[1].holders = ['Aldreth', 'Brunhild'];
  assert.equal(run(lucifron).invalid, 'TANK1');
  assert.equal(run(encounter('molten-core:lucifron'), [{ set: 'TANK1', name: 'Kael' }]).invalid, 'TANK1');
  assert.equal(run(encounter('x:1'), [{ toggle: '@Kicker', name: 'Nobody' }]).invalid, '@Kicker');
});

test('only encounters with a template and slots can be rebuilt (protocol 1 has neither)', () => {
  const { template, slots, ...protocol1 } = encounter('molten-core:lucifron');
  assert.ok(template && slots);
  assert.equal(hasTemplate(protocol1), false);
  assert.equal(hasTemplate({ ...protocol1, template }), false);
  assert.equal(hasTemplate(encounter('molten-core:trash')), true);   // a template with no slots
});

test('candidates in alphabetical order, ignoring case and accents', () => {
  const lucifron = encounter('molten-core:lucifron');
  const names = ['Rigwar', 'jasmine', 'Tracedeneïge', 'Durance', 'Jmdruid', 'Tracedeneige', 'Ämber', 'Jugildina'];
  for (const slot of lucifron.slots.filter((s) => s.token === 'TANK1' || s.token === 'MT')) slot.candidates = names;
  assert.deepEqual(run(lucifron).jobs[0].candidates,
    ['Ämber', 'Durance', 'jasmine', 'Jmdruid', 'Jugildina', 'Rigwar', 'Tracedeneige', 'Tracedeneïge']);
});
