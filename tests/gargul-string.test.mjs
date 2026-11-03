// Runs Modules/GargulString.lua in fengari against the formats Gargul's TMB importer takes. Run with `make test`.
// LibDeflate is replaced by Node's zlib, as in plan-codec.test.mjs.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { deflateSync, inflateSync } from 'node:zlib';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/NoteTemplate.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/GargulString.lua"))("UnityTools-RaidManagement", ns)
local LibDeflate = { DecompressZlib = function(_, data) return node_inflate(data) end }

function check(text)
    local format, result = ns.GargulString.Check(text, LibDeflate)
    if not format then return "ERR:" .. result end
    return format .. "|" .. result
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
lua.lua_register(L, to_luastring('node_inflate'), (state) => {
  try {
    lua.lua_pushstring(state, new Uint8Array(inflateSync(Buffer.from(lauxlib.luaL_checkstring(state, 1)))));
  } catch {
    lua.lua_pushnil(state);
  }
  return 1;
});
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function check(text) {
  lua.lua_getglobal(L, to_luastring('check'));
  lua.lua_pushstring(L, to_luastring(text));
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}
const format = (text) => check(text).split('|')[0];

const compress = (text) => deflateSync(text).toString('base64');
// What /loot-policy gives (the shape of tests/fixtures/raid-groups-test-plan.mjs)
const LOOT_POLICY = { wishlists: { 19019: ['aldreth|1|1|0', 'zoe|2|1|0'] }, groups: { 1: 'UNITY' }, loot: '', notes: {}, tiers: {} };

test('the /loot-policy string: base64 over zlib over TMB JSON', () => {
  const text = compress(JSON.stringify(LOOT_POLICY));
  assert.equal(check(text), `tmb.compressed|${text}`);
});

test('surrounding whitespace is trimmed from what is stored', () => {
  const text = compress(JSON.stringify(LOOT_POLICY));
  assert.equal(check(`  \n${text}\r\n `), `tmb.compressed|${text}`);
});

test('TMB JSON as it is', () => {
  assert.equal(format(JSON.stringify(LOOT_POLICY)), 'tmb');
});

test('loot priorities, item notes or tiers alone are something to import', () => {
  assert.equal(format(compress(JSON.stringify({ wishlists: [], loot: '19019 > Warrior' }))), 'tmb.compressed');
  assert.equal(format(compress(JSON.stringify({ notes: { 19019: 'tanks first' } }))), 'tmb.compressed');
  assert.equal(format(compress(JSON.stringify({ tiers: { 19019: 'S' } }))), 'tmb.compressed');
});

test('TMB JSON with nothing to import is refused', () => {
  assert.equal(check(compress(JSON.stringify({ wishlists: {}, groups: {}, loot: '', notes: {}, tiers: {} }))), 'ERR:nothing');
  assert.equal(check('{"wishlists":{}}'), 'ERR:nothing');
});

test("Gargul's item CSV", () => {
  assert.equal(format('6948,zhorax[1],feth[2],arvada[3]\n1372,ratomir[1],zhorax[2]\nMain:tonio,vejusatko\nAlt:ratomir'), 'csv');
  assert.equal(format('6948,vejusatko,zhorax\n1372,ratomir,tonio|zhorax'), 'csv');
  assert.equal(format(compress('6948,vejusatko,zhorax')), 'csv.compressed');
});

test('CSV without a player or a valid item is refused', () => {
  assert.equal(check('6948,'), 'ERR:csv');
  assert.equal(check('0,zhorax'), 'ERR:csv');
  assert.equal(check('6948, , \nMain:tonio'), 'ERR:csv');
});

test('DFT', () => {
  const dft = '"18814^Choker of the Fire Lord\n            |cffc79c6eAldreth|r: |1\n            |cff69ccf0Zoe|r: |2";'
    + '"18815^Essence\nFree Roll"';
  assert.equal(format(dft), 'dft');
});

test('DFT without priorities is refused', () => {
  assert.equal(check('"18814^Choker of the Fire Lord\nFree Roll"'), 'ERR:dft');
  assert.equal(check('"abc^Nothing"'), 'ERR:dft');
});

test('RRobin JSON', () => {
  assert.equal(format('{\n"reserves": [{"itemid": 19019, "character": "Aldreth", "priority": 1}]\n}'), 'rrobin');
  assert.equal(check('{\n"reserves": []\n}'), 'ERR:rrobin');
});

test('broken strings are refused, never an error', () => {
  assert.equal(check(''), 'ERR:empty');
  assert.equal(check(' \n\t '), 'ERR:empty');
  assert.equal(check('not a gargul string!'), 'ERR:base64');
  assert.equal(check('{\n"foo": 1\n}'), 'ERR:base64');
  assert.equal(check('aGVsbG8gd29ybGQ='), 'ERR:zlib');
  const text = compress(JSON.stringify(LOOT_POLICY));
  assert.equal(check(text.slice(0, text.length / 2)), 'ERR:zlib');
  assert.equal(check(compress('this is not json')), 'ERR:json');
  assert.equal(check(compress('[1, 2, 3')), 'ERR:json');
  assert.equal(check('{"wishlists": [1, 2'), 'ERR:json');
});

test('a raid plan export is not a Gargul string', () => {
  assert.equal(check(compress(JSON.stringify({ protocol: 2, event: { id: '1' }, encounters: [] }))), 'ERR:nothing');
});
