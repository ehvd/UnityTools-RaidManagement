// Runs Modules/Bosses.lua in fengari (a Lua VM in JavaScript) and checks it against UnityWiki when UnityWiki is
// checked out next to this repo: the encounter IDs (src/lib/encounter-ids.ts) and the names and kill order (its loot
// data, db/migrations/0032_raid_loot_data.sql). Run with `make test`.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Lua side: the module's lists as JSON-ish text JavaScript can parse
const SHIM = `
ns = {}
assert(loadfile(ROOT .. "/Modules/Bosses.lua"))("UnityTools-RaidManagement", ns)
Bosses = ns.Bosses

local function str(s) return '"' .. s:gsub('"', '\\\\"') .. '"' end
function bossesJson(slug)
    local out = {}
    for i, b in ipairs(Bosses.Of(slug)) do
        out[i] = '{"key":' .. str(b.key) .. ',"label":' .. str(b.label) .. ',"encounterId":' .. b.encounterId .. '}'
    end
    return "[" .. table.concat(out, ",") .. "]"
end
function raidsJson()
    local out = {}
    for i, r in ipairs(Bosses.Raids()) do
        out[i] = '{"slug":' .. str(r.slug) .. ',"name":' .. str(r.name) .. ',"bosses":' .. bossesJson(r.slug) .. '}'
    end
    return "[" .. table.concat(out, ",") .. "]"
end
function findJson(id)
    local b = Bosses.Find(id)
    if not b then return "null" end
    return '{"slug":' .. str(b.slug) .. ',"key":' .. str(b.key) .. ',"label":' .. str(b.label)
        .. ',"encounterId":' .. b.encounterId .. '}'
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

const raids = JSON.parse(run('return raidsJson()'));
const find = (id) => JSON.parse(run(`return findJson(${id})`));

// UnityWiki next to this repo: the main checkout's sibling, also from a worktree under .claude/worktrees
function wikiRoot() {
  let dir = root;
  for (let i = 0; i < 6; i++) {
    const candidate = join(dir, '..', 'UnityWiki');
    if (existsSync(join(candidate, 'src', 'lib', 'encounter-ids.ts'))) return candidate;
    dir = join(dir, '..');
  }
  return null;
}

test('the raids are the seven Classic Era raids in the game order, with UnityWiki slugs', () => {
  assert.deepEqual(raids.map((r) => r.slug), [
    'molten-core', 'onyxias-lair', 'blackwing-lair', 'zul-gurub', 'ruins-of-ahn-qiraj', 'ahn-qiraj', 'naxxramas',
  ]);
});

test('fights with several bosses are one encounter', () => {
  const aq = raids.find((r) => r.slug === 'ahn-qiraj').bosses;
  assert.deepEqual(aq.find((b) => b.key === 'bug-trio'), { key: 'bug-trio', label: 'The Bug Trio', encounterId: 710 });
  assert.equal(aq.find((b) => b.key === 'twin-emperors').encounterId, 715);
  assert.equal(raids.find((r) => r.slug === 'naxxramas').bosses.find((b) => b.key === 'four-horsemen').encounterId, 1121);
  assert.equal(aq.length, 9);
});

test('Find gives the boss of an encounter ID, and nil for any other number', () => {
  assert.deepEqual(find(663), { slug: 'molten-core', key: 'lucifron', label: 'Lucifron', encounterId: 663 });
  assert.deepEqual(find(1114), { slug: 'naxxramas', key: 'kelthuzad', label: "Kel'Thuzad", encounterId: 1114 });
  assert.equal(find(50663), null);
  assert.equal(find(0), null);
});

test('Of gives an empty list for a raid it does not know, and new tables each time', () => {
  assert.equal(run('return #Bosses.Of("karazhan")'), '0');
  assert.equal(run('local a = Bosses.Of("molten-core") a[1].label = "x" return Bosses.Of("molten-core")[1].label'),
    'Lucifron');
});

test('every encounter ID appears once', () => {
  const ids = raids.flatMap((r) => r.bosses.map((b) => b.encounterId));
  assert.equal(new Set(ids).size, ids.length);
});

test('the encounter IDs and keys match UnityWiki when it is checked out next to this repo', (t) => {
  const wiki = wikiRoot();
  if (!wiki) {
    t.skip('UnityWiki not found next to this repo');
    return;
  }
  const source = readFileSync(join(wiki, 'src', 'lib', 'encounter-ids.ts'), 'utf8');
  // The object literal after `ENCOUNTER_IDS ... = ` is plain JavaScript
  const start = source.indexOf('= {', source.indexOf('ENCOUNTER_IDS')) + 2;
  const end = source.indexOf('\n};', start) + 2;
  const wikiIds = new Function(`return ${source.slice(start, end)};`)();
  const ours = Object.fromEntries(raids.map((r) => [r.slug, Object.fromEntries(r.bosses.map((b) => [b.key, b.encounterId]))]));
  assert.deepEqual(ours, wikiIds);
});

test('the boss names and kill order match UnityWiki loot data when it is checked out next to this repo', (t) => {
  const wiki = wikiRoot();
  const file = wiki && join(wiki, 'db', 'migrations', '0032_raid_loot_data.sql');
  if (!file || !existsSync(file)) {
    t.skip('UnityWiki not found next to this repo');
    return;
  }
  // ('raid', 'key', 'Name', 'boss' | 'umbrella', NULL, sort): the top level sources, not the bosses inside an umbrella
  const rows = [...readFileSync(file, 'utf8').matchAll(/\('([a-z-]+)', '([a-z-]+)', '((?:[^']|'')+)', '(boss|umbrella)', NULL, (\d+)\)/g)];
  const wikiBosses = {};
  for (const [, slug, key, name, , sort] of rows) {
    (wikiBosses[slug] ??= []).push({ key, label: name.replaceAll("''", "'"), sort: Number(sort) });
  }
  for (const raid of raids) {
    const expected = wikiBosses[raid.slug].sort((a, b) => a.sort - b.sort).map(({ key, label }) => ({ key, label }));
    assert.deepEqual(raid.bosses.map(({ key, label }) => ({ key, label })), expected, raid.slug);
  }
});
