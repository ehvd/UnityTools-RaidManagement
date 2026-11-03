// Runs Modules/Roster.lua in fengari: the string it makes from the raid roster must be UnityWiki's roster (protocol 1
// of docs/addon-roster.md there), which the planner's Paste raid roster reads. Run with `make test`.
//
// fixtures/addon-roster/ is a copy of UnityWiki's src/lib/__fixtures__/addon-roster/: raid.json is what
// GetRaidRosterInfo returned (nil as null) plus player, realm and time, payload.json the JSON the addon must build
// from it, export.txt one string of it. LibDeflate is replaced by Node's zlib, as in plan-codec.test.mjs (under
// fengari LibDeflate does not work); the compression itself is covered by the in-game check.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { deflateSync, inflateSync } from 'node:zlib';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/NoteTemplate.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/Roster.lua"))("UnityTools-RaidManagement", ns)
local LibDeflate = {
    CompressZlib = function(_, data) return node_deflate(data) end,
    DecompressZlib = function(_, data) return node_inflate(data) end,
}
local Roster = ns.Roster

-- The roster string of raid.json's shape (given as JSON), and how many rows were left out
function export(inputJSON)
    local input = assert(ns.PlanCodec.JSONDecode(inputJSON))
    local payload, skipped = Roster.Payload(input.raid, input.player, input.realm, input.time)
    return Roster.Encode(payload, LibDeflate) .. " " .. skipped
end

-- A roster string read back the way the addon reads the wiki's strings (base64, zlib, JSON): its member count
function decode(text)
    local data, code = ns.PlanCodec.Decode(text, LibDeflate)
    if not data then return "ERR:" .. code end
    return data.kind .. " " .. data.protocol .. " " .. #data.members
end

function base64(bytes)
    return Roster.Base64Encode(bytes)
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root.replaceAll('\\', '/')));
lua.lua_setglobal(L, to_luastring('ROOT'));
for (const [name, fn] of [['node_inflate', inflateSync], ['node_deflate', deflateSync]]) {
  lua.lua_register(L, to_luastring(name), (state) => {
    try {
      lua.lua_pushstring(state, new Uint8Array(fn(Buffer.from(lauxlib.luaL_checkstring(state, 1)))));
    } catch {
      lua.lua_pushnil(state);
    }
    return 1;
  });
}
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function call(name, arg) {
  lua.lua_getglobal(L, to_luastring(name));
  lua.lua_pushstring(L, typeof arg === 'string' ? to_luastring(arg) : arg);
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

// The string and how many rows were left out
function exportRoster(input) {
  const [text, skipped] = call('export', JSON.stringify(input)).split(' ');
  return { text, skipped: Number(skipped) };
}
// What the wiki's decodeAddonString does: base64, inflate, JSON.parse
const jsonOf = (text) => inflateSync(Buffer.from(text, 'base64')).toString('utf8');
const decode = (text) => JSON.parse(jsonOf(text));

const fixture = (file) => readFileSync(join(root, 'tests', 'fixtures', 'addon-roster', file), 'utf8');
const RAID = JSON.parse(fixture('raid.json'));
const PAYLOAD = JSON.parse(fixture('payload.json'));
const EXPORT = fixture('export.txt').trim();

const CLASSES = ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID'];
function row(i, extra = {}) {
  const fileName = CLASSES[i % CLASSES.length];
  return {
    name: `Member${i + 1}`, rank: i === 0 ? 2 : 0, subgroup: Math.floor(i / 5) + 1, level: 60,
    class: fileName.charAt(0) + fileName.slice(1).toLowerCase(), fileName, zone: 'Naxxramas', online: true,
    isDead: false, role: null, isML: false, ...extra,
  };
}
const raidOf = (rows) => ({ player: 'Member1', realm: 'PyrewoodVillage', time: 1793612345, raid: rows });

test('base64 matches Node for every length mod 3', () => {
  for (let n = 0; n < 40; n++) {
    const bytes = Buffer.from(Array.from({ length: n }, (_, i) => (i * 97 + n * 13) % 256));
    assert.equal(call('base64', new Uint8Array(bytes)), bytes.toString('base64'), `${n} bytes`);
  }
});

test('the wiki fixture: raid.json gives payload.json, protocol first', () => {
  const { text, skipped } = exportRoster(RAID);
  assert.equal(skipped, 0);
  assert.deepEqual(decode(text), PAYLOAD);
  assert.match(jsonOf(text), /^\{"protocol":1,"kind":"roster",/);
  assert.ok(jsonOf(text).includes('Tracedeneïge'), 'UTF-8 goes as it is');
  assert.equal(exportRoster(RAID).text, text, 'one roster gives one string');
});

test("the wiki fixture's export.txt reads as payload.json, also with the addon's own decoder", () => {
  assert.deepEqual(decode(EXPORT), PAYLOAD);
  assert.equal(call('decode', EXPORT), 'roster 1 10');
  assert.equal(call('decode', exportRoster(RAID).text), 'roster 1 10');
});

test('names split at the first hyphen; bare names are from our realm', () => {
  const members = decode(exportRoster(RAID).text).members;
  const zeta = members.find((m) => m.name === 'Zeta');
  assert.equal(zeta.realm, 'Azjol-Nerub');
  assert.equal(members.find((m) => m.name === 'Moonbeam').realm, 'Firemaw');
  assert.equal(members.find((m) => m.name === 'Arrowyn').realm, 'PyrewoodVillage');
  assert.ok(members.every((m) => !m.name.includes('-')));
});

test('offline members: online nil or false is false, zone nil is ""', () => {
  const rows = [
    row(0),
    row(1, { online: null, zone: null }),
    row(2, { online: false, zone: 'Offline' }),
    row(3, { name: 'Faraway-Azjol-Nerub', online: null, zone: null }),
  ];
  const members = decode(exportRoster(raidOf(rows)).text).members;
  assert.deepEqual(members.map((m) => [m.online, m.zone]),
    [[true, 'Naxxramas'], [false, ''], [false, 'Offline'], [false, '']]);
  assert.deepEqual([members[3].name, members[3].realm], ['Faraway', 'Azjol-Nerub']);
});

test('a full raid: 40 members in raid index order, all eight groups, every key there', () => {
  const rows = Array.from({ length: 40 }, (_, i) => row(i));
  const { text, skipped } = exportRoster(raidOf(rows));
  const payload = decode(text);
  assert.equal(skipped, 0);
  assert.equal(payload.members.length, 40);
  assert.deepEqual(payload.members.map((m) => m.name), rows.map((r) => r.name));
  assert.deepEqual([...new Set(payload.members.map((m) => m.group))], [1, 2, 3, 4, 5, 6, 7, 8]);
  for (const member of payload.members) {
    assert.deepEqual(Object.keys(member).sort(), ['class', 'group', 'level', 'name', 'online', 'rank', 'realm', 'zone']);
  }
  assert.deepEqual(Object.keys(payload), ['protocol', 'kind', 'generatedAt', 'by', 'realm', 'members']);
  assert.equal(payload.by, 'Member1');
});

test('rows the game has not loaded yet are left out and counted; never more than 40 members', () => {
  const rows = [row(0), row(1, { name: null }), row(2, { fileName: null }), row(3)];
  const { text, skipped } = exportRoster(raidOf(rows));
  assert.equal(skipped, 2);
  assert.deepEqual(decode(text).members.map((m) => m.name), ['Member1', 'Member4']);

  const many = exportRoster(raidOf(Array.from({ length: 41 }, (_, i) => row(i))));
  assert.equal(decode(many.text).members.length, 40);
  assert.equal(many.skipped, 1);
});

test('an empty raid gives an empty member list, not an object', () => {
  const payload = decode(exportRoster(raidOf([])).text);
  assert.deepEqual(payload.members, []);
});

// UnityWiki, when it is checked out next to this repo (or next to a folder above this worktree)
function wikiDir() {
  for (let dir = root; dirname(dir) !== dir; dir = dirname(dir)) {
    const candidate = join(dirname(dir), 'UnityWiki');
    if (existsSync(join(candidate, 'src', 'lib', 'addon-roster.ts'))) return candidate;
  }
  return null;
}

test("the fixture copy is the wiki's, and the wiki's readRoster reads the strings", async (t) => {
  const wiki = wikiDir();
  if (!wiki) {
    t.skip('UnityWiki not found next to this repo');
    return;
  }
  const theirs = join(wiki, 'src', 'lib', '__fixtures__', 'addon-roster');
  for (const file of ['raid.json', 'payload.json', 'export.txt']) {
    assert.deepEqual(readFileSync(join(theirs, file), 'utf8').trim(), fixture(file).trim(),
      `tests/fixtures/addon-roster/${file} differs from UnityWiki's: copy it again`);
  }
  let module;
  try {
    module = await import(pathToFileURL(join(wiki, 'src', 'lib', 'addon-roster.ts')).href);
  } catch (error) {
    t.skip(`UnityWiki's addon-roster.ts does not load in this Node: ${error.message}`);
    return;
  }
  const fromFixture = module.readRoster(exportRoster(RAID).text);
  assert.ok(fromFixture.ok, fromFixture.message);
  assert.deepEqual(fromFixture.roster, PAYLOAD);
  const full = module.readRoster(exportRoster(raidOf(Array.from({ length: 40 }, (_, i) => row(i, { online: i % 3 ? true : null })))).text);
  assert.ok(full.ok, full.message);
  assert.equal(full.roster.members.length, 40);
});
