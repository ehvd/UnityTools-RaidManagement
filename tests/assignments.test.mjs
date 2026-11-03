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

function groupTokens(tokensJson)
    local jobs = {}
    for i, token in ipairs(Codec.JSONDecode(tokensJson)) do jobs[i] = { tokens = { token } } end
    local out = {}
    for i, job in ipairs(A.GroupJobs(jobs)) do out[i] = job.tokens[1] end
    return encode(out)
end

-- The defaults of a plan: its defaults, the Default's jobs after \`steps\`, each encounter's overrides; with
-- \`save\`, SaveDefaults runs and the plan comes back too. \`keep\` runs KeepDefaults first.
function defaults(planJson, stepsJson, save, keep)
    local plan, steps = Codec.JSONDecode(planJson), Codec.JSONDecode(stepsJson)
    if keep then A.KeepDefaults(plan) end
    local d = A.Defaults(plan)
    local jobs = A.DefaultJobs(plan, d)
    for _, step in ipairs(steps) do
        if step.set then A.Set(jobOf(jobs, step.set), step.name) end
        if step.toggle then A.Toggle(jobOf(jobs, step.toggle), step.name) end
    end
    local overrides = {}
    for _, encounter in ipairs(plan.encounters) do
        overrides[encounter.key] = A.TakesPart(encounter) and A.Overrides(A.Jobs(encounter), d) or 0
    end
    local result = { defaults = d, jobs = jobs, overrides = overrides, changed = A.ChangedDefaults(d, jobs) }
    if save then
        result.rebuilt, result.kept = A.SaveDefaults(plan, d, jobs, plan.people)
    end
    result.plan = plan
    return encode(result)
end

-- An encounter's job back to the default: { ok, holders }
function useDefault(planJson, key, token)
    local plan = Codec.JSONDecode(planJson)
    local d = A.Defaults(plan)
    for _, encounter in ipairs(plan.encounters) do
        if encounter.key == key then
            local job = jobOf(A.Jobs(encounter), token)
            local ok = A.UseDefault(job, d)
            return encode({ ok = ok, holders = job.holders, override = A.IsOverride(job, d) })
        end
    end
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

function groupTokens(tokens) {
  lua.lua_getglobal(L, to_luastring('groupTokens'));
  lua.lua_pushstring(L, to_luastring(JSON.stringify(tokens)));
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const grouped = JSON.parse(to_jsstring(lua.lua_tostring(L, -1)));
  lua.lua_pop(L, 1);
  return grouped;
}

test('rows grouped by token without its number, groups and slots in the note order', () => {
  assert.deepEqual(groupTokens(['TANK1', 'HEALER1', 'TANK2', 'HEALER2', 'TANK3', 'HEALER3', 'TANK4']),
    ['TANK1', 'TANK2', 'TANK3', 'TANK4', 'HEALER1', 'HEALER2', 'HEALER3']);
  assert.deepEqual(groupTokens(['HEALER2', '@Kicker', 'TANK10', 'MT', 'HEALER1', '@Decurser', 'TANK9']),
    ['HEALER2', 'HEALER1', '@Kicker', 'TANK10', 'TANK9', 'MT', '@Decurser']);
});

test('candidates in alphabetical order, ignoring case and accents', () => {
  const lucifron = encounter('molten-core:lucifron');
  const names = ['Rigwar', 'jasmine', 'Tracedeneïge', 'Durance', 'Jmdruid', 'Tracedeneige', 'Ämber', 'Jugildina'];
  for (const slot of lucifron.slots.filter((s) => s.token === 'TANK1' || s.token === 'MT')) slot.candidates = names;
  assert.deepEqual(run(lucifron).jobs[0].candidates,
    ['Ämber', 'Durance', 'jasmine', 'Jmdruid', 'Jugildina', 'Rigwar', 'Tracedeneige', 'Tracedeneïge']);
});

// Default assignments (issue #59)

const plan = () => ({ people: PAYLOAD.people, encounters: structuredClone(PAYLOAD.encounters) });

function callLua(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const arg of args) {
    if (typeof arg === 'boolean') lua.lua_pushboolean(L, arg);
    else lua.lua_pushstring(L, to_luastring(typeof arg === 'string' ? arg : JSON.stringify(arg)));
  }
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = JSON.parse(to_jsstring(lua.lua_tostring(L, -1)));
  lua.lua_pop(L, 1);
  return result;
}

const defaults = (p, steps = [], save = false, keep = false) => callLua('defaults', p, steps, save, keep);
const encounterOf = (p, key) => p.encounters.find((e) => e.key === key);
const slotHolders = (p, key, token) => encounterOf(p, key).slots.find((s) => s.token === token).holders;

test('defaults without stored ones: each job\'s most common holders, ties to the first encounter', () => {
  const result = defaults(plan());
  assert.deepEqual(result.defaults['role=tank&order=1'], ['Aldreth']);    // Lucifron and the Bug Trio
  assert.deepEqual(result.defaults['role=healer&order=1'], ['Zoë']);      // Lucifron's Zoë against Magmadar's nobody
  assert.deepEqual(result.defaults['@kicker'], ['Kael', 'Siggi']);       // the Welcome's, the first encounter
  assert.equal(result.defaults['class=mage'], undefined);               // list and none jobs are not offered
  assert.deepEqual(result.overrides, {
    'x:1': 0, 'molten-core:trash': 0, 'molten-core:lucifron': 1, 'molten-core:magmadar': 1, 'ahn-qiraj:bug-trio': 0,
  });
  assert.equal(result.changed, 0);
});

test('stored defaults win; a job they do not name takes the most common holders', () => {
  const p = plan();
  p.assignmentDefaults = { 'role=tank&order=1': ['Brunhild'] };
  const result = defaults(p);
  assert.deepEqual(result.defaults['role=tank&order=1'], ['Brunhild']);
  assert.deepEqual(result.defaults['role=tank&order=2'], ['Brunhild']);
  assert.equal(result.overrides['ahn-qiraj:bug-trio'], 1);
  assert.equal(result.overrides['molten-core:lucifron'], 2);
});

test('the Default\'s jobs: every key, tokens and candidates of all encounters, grouped like an encounter\'s', () => {
  const { jobs } = defaults(plan());
  assert.deepEqual(jobs.map((job) => job.tokens[0]),
    ['@Kicker', 'TANK1', 'TANK2', 'TANK3', 'HEALER1', 'HEALER2', 'HEALER_PALADIN1', '@Tranq']);
  const tank1 = jobs.find((job) => job.key === 'role=tank&order=1');
  assert.deepEqual(tank1.tokens, ['TANK1', 'MT']);
  assert.deepEqual(tank1.holders, ['Aldreth']);
  const p = plan();
  encounterOf(p, 'ahn-qiraj:bug-trio').slots[0].candidates = ['Aldreth', 'Kael'];
  assert.deepEqual(defaults(p).jobs.find((job) => job.key === 'role=tank&order=1').candidates,
    ['Aldreth', 'Brunhild', 'Fenlyn', 'Kael']);
});

test('saving the Default changes the encounters that follow it and rebuilds their notes; overrides stay', () => {
  const result = defaults(plan(), [{ set: 'TANK1', name: 'Brunhild' }, { set: 'HEALER1', name: 'Fenlyn' }], true);
  assert.equal(result.changed, 2);
  assert.deepEqual(result.rebuilt, ['molten-core:lucifron', 'ahn-qiraj:bug-trio']);
  assert.deepEqual(result.kept, []);
  const p = result.plan;
  assert.deepEqual(slotHolders(p, 'molten-core:lucifron', 'MT'), ['Brunhild']);
  assert.deepEqual(slotHolders(p, 'molten-core:lucifron', 'HEALER1'), ['Fenlyn']);
  assert.deepEqual(slotHolders(p, 'ahn-qiraj:bug-trio', 'MT'), ['Brunhild']);
  assert.deepEqual(slotHolders(p, 'molten-core:magmadar', 'HEALER1'), []);   // its own (nobody): an override
  assert.match(encounterOf(p, 'molten-core:lucifron').note, /^\{rt1\} \|cffc79c6eBrunhild\|r on Lucifron/);
  assert.equal(encounterOf(p, 'molten-core:magmadar').note, encounterOf(plan(), 'molten-core:magmadar').note);
  assert.deepEqual(p.assignmentDefaults['role=tank&order=1'], ['Brunhild']);
  assert.deepEqual(p.assignmentDefaults['@kicker'], ['Kael', 'Siggi']);
  // Saved, the defaults are the stored ones: Magmadar's healer is still its only override
  const after = defaults(p);
  assert.equal(after.overrides['molten-core:magmadar'], 1);
  assert.equal(after.overrides['ahn-qiraj:bug-trio'], 0);
});

test('an encounter whose candidates do not include the new default keeps its holders', () => {
  const p = plan();
  for (const slot of encounterOf(p, 'ahn-qiraj:bug-trio').slots) slot.candidates = ['Aldreth', 'Brunhild'];
  const result = defaults(p, [{ set: 'TANK1', name: 'Fenlyn' }], true);
  assert.deepEqual(result.rebuilt, ['molten-core:lucifron']);
  assert.deepEqual(result.kept, ['ahn-qiraj:bug-trio']);
  assert.deepEqual(slotHolders(result.plan, 'ahn-qiraj:bug-trio', 'MT'), ['Aldreth']);
});

test('encounters with a hand-edited note take no part', () => {
  const p = plan();
  encounterOf(p, 'molten-core:lucifron').customNote = 'by hand';
  const result = defaults(p, [{ set: 'MT', name: 'Brunhild' }], true);
  assert.deepEqual(result.defaults['role=healer&order=1'], []);      // only Magmadar's left
  assert.deepEqual(result.rebuilt, ['ahn-qiraj:bug-trio']);
  assert.deepEqual(slotHolders(result.plan, 'molten-core:lucifron', 'MT'), ['Aldreth']);
});

test('KeepDefaults stores the defaults as they are, so an encounter change does not move them', () => {
  const p = defaults(plan(), [], false, true).plan;
  assert.deepEqual(p.assignmentDefaults['role=healer&order=1'], ['Zoë']);
  encounterOf(p, 'molten-core:lucifron').slots.find((s) => s.token === 'HEALER1').holders = [];
  assert.deepEqual(defaults(p).defaults['role=healer&order=1'], ['Zoë']);
  assert.equal(defaults(p).overrides['molten-core:lucifron'], 2);
});

test('an override goes back to the default, unless the default cannot fill it there', () => {
  const back = callLua('useDefault', plan(), 'molten-core:magmadar', 'HEALER1');
  assert.deepEqual(back, { ok: true, holders: ['Zoë'], override: false });
  const p = plan();
  p.assignmentDefaults = { 'role=healer&order=1': ['Aldreth'] };
  assert.deepEqual(callLua('useDefault', p, 'molten-core:magmadar', 'HEALER1'),
    { ok: false, holders: [], override: true });
});
