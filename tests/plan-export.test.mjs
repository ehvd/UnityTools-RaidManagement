// Runs the export half of Modules/PlanCodec.lua (Payload, JSONEncode, Base64Encode, Encode) in fengari: the string it
// makes must be UnityWiki's own export (protocol 2 of docs/addon-export.md there), so this addon's import and the
// wiki's decodeAddon both read it. Run with `make test`.
//
// LibDeflate is replaced by Node's zlib, as in plan-codec.test.mjs (under fengari LibDeflate does not work); the
// compression itself is covered by the in-game check.
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
local LibDeflate = {
    CompressZlib = function(_, data) return node_deflate(data) end,
    DecompressZlib = function(_, data) return node_inflate(data) end,
}
local Codec = ns.PlanCodec

-- The export string of a stored plan (given as JSON), made at "now", the classes of the raid roster as JSON
function export(planJSON, now, classesJSON)
    local plan = assert(Codec.JSONDecode(planJSON))
    local classes = assert(Codec.JSONDecode(classesJSON))
    return Codec.Encode(Codec.Payload(plan, now, function(name) return classes[name] end), LibDeflate)
end

-- A payload as it was decoded (given as an export string) encoded again
function reencode(text)
    return Codec.Encode(assert(Codec.Decode(text, LibDeflate)), LibDeflate)
end

-- Decode and check, as the import does: the JSON of what it read, or the error / check code
function import(text)
    local data, code = Codec.Decode(text, LibDeflate)
    if not data then return "ERR:" .. code end
    if not Codec.IsSupported(data.protocol) then return "PROTOCOL:" .. data.protocol end
    local problem = Codec.Check(data)
    if problem then return "CHECK:" .. problem end
    return Codec.JSONEncode(data)
end

function base64(bytes)
    return Codec.Base64Encode(bytes)
end

function json(text)
    return Codec.JSONEncode(assert(Codec.JSONDecode(text)))
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

// Calls a global Lua function with strings and numbers; returns its string result (as bytes when `raw`)
function call(name, args, raw = false) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const arg of args) {
    if (typeof arg === 'number') lua.lua_pushnumber(L, arg);
    else lua.lua_pushstring(L, typeof arg === 'string' ? to_luastring(arg) : arg);
  }
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = raw ? Buffer.from(lua.lua_tostring(L, -1)) : to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

const exportPlan = (plan, now, classes = {}) => call('export', [JSON.stringify(plan), now, JSON.stringify(classes)]);
// What the wiki's decodeAddon does: base64, inflate, JSON.parse
const decode = (text) => JSON.parse(inflateSync(Buffer.from(text, 'base64')).toString('utf8'));
const jsonOf = (text) => inflateSync(Buffer.from(text, 'base64')).toString('utf8');

const WIKI_PAYLOAD = JSON.parse(readFileSync(join(root, 'tests', 'fixtures', 'wiki-export-payload.json'), 'utf8'));
const WIKI_EXPORT = readFileSync(join(root, 'tests', 'fixtures', 'wiki-export.txt'), 'utf8').trim();

// The plan as PlanImport:Read stores it: the payload's keys this addon keeps, plus what the addon adds in game
function stored(payload) {
  const plan = structuredClone(payload);
  Object.assign(plan, { importedAt: 1790000200, chosenAt: 1790000200, active: payload.encounters[0].key, activeAt: 1790000300 });
  return plan;
}

test('base64 matches Node for every length mod 3', () => {
  for (let n = 0; n < 40; n++) {
    const bytes = Buffer.from(Array.from({ length: n }, (_, i) => (i * 97 + n * 13) % 256));
    assert.equal(call('base64', [new Uint8Array(bytes)]), bytes.toString('base64'), `${n} bytes`);
  }
});

test('JSON: escapes, UTF-8, colour codes and numbers come out as JSON.parse reads them', () => {
  const value = {
    note: '|cffc79c6eÄldreth|r {rt1} "quoted" \\ back/slash\n\ttab\r\u0001\u001f\u007f Zoë 😀 ||',
    big: 1790000100, negative: -3, fraction: 0.25, yes: true, no: false, list: [1, 'two', []],
  };
  const text = call('json', [JSON.stringify(value)]);
  assert.deepEqual(JSON.parse(text), value);
  assert.ok(!text.includes('\n') && !text.includes('\u0001'), 'control characters are escaped');
  assert.ok(text.includes('Zoë 😀'), 'UTF-8 goes as it is');
});

test('the wiki fixture encoded again decodes to the same payload, protocol first', () => {
  const text = call('reencode', [WIKI_EXPORT]);
  assert.deepEqual(decode(text), WIKI_PAYLOAD);
  assert.match(jsonOf(text), /^\{"protocol":2,/);
  assert.deepEqual(JSON.parse(call('import', [text])), JSON.parse(call('import', [WIKI_EXPORT])));
});

test('exporting the imported wiki fixture gives the wiki payload back', () => {
  const text = exportPlan(stored(WIKI_PAYLOAD), WIKI_PAYLOAD.generatedAt);
  assert.deepEqual(decode(text), WIKI_PAYLOAD);
  assert.equal(exportPlan(stored(WIKI_PAYLOAD), WIKI_PAYLOAD.generatedAt), text, 'one plan gives one string');
});

// A plan changed in game: a hand-edited note, other holders, a group override, a fallback and a revision
function edited() {
  const plan = stored(WIKI_PAYLOAD);
  const [, trash, lucifron, magmadar] = plan.encounters;
  trash.customNote = 'Pull slowly |cffff0000please|r\n"Zoë" heals';
  const tank = magmadar.slots.find((slot) => slot.kind === 'one');
  for (const slot of magmadar.slots) if (slot.key === tank.key) slot.holders = ['Newbie'];
  magmadar.note = 'whatever the template gives now';
  plan.layouts.Lucifron = [...plan.layouts.default];
  plan.layouts.Lucifron[8] = 'Stranger';
  plan.layouts.Lucifron[9] = 'Unknown';
  lucifron.layout = 'Lucifron';
  plan.layouts.Unused = [...plan.layouts.default];
  Object.assign(plan, {
    fallback: 'x:1', revision: { n: 2, by: 'Aldreth', at: 1790000400 }, syncedFrom: 'Brunhild',
  });
  return plan;
}

test('an edited plan exports the notes as used in game, the edited groups and everybody it names', () => {
  const now = 1790009999;
  const payload = decode(exportPlan(edited(), now, { Newbie: 'DRUID', Stranger: 'MAGE', Aldreth: 'PALADIN' }));
  assert.equal(payload.protocol, 2);
  assert.equal(payload.generatedAt, now);
  const [night, trash, lucifron, magmadar] = payload.encounters;
  assert.equal(trash.note, 'Pull slowly |cffff0000please|r\n"Zoë" heals');
  assert.ok(!('template' in trash) && !('slots' in trash), 'a hand-edited note goes without template and slots');
  assert.deepEqual(night, WIKI_PAYLOAD.encounters[0]);
  assert.equal(lucifron.layout, 'Lucifron');
  assert.equal(lucifron.template, WIKI_PAYLOAD.encounters[2].template);
  assert.equal(magmadar.note, 'whatever the template gives now');
  assert.ok(magmadar.slots.some((slot) => slot.holders[0] === 'Newbie'));
  assert.deepEqual(Object.keys(payload.layouts).sort(), ['Lucifron', 'default'], 'only the layouts in use');
  assert.equal(payload.layouts.Lucifron[8], 'Stranger');
  // The plan's people as they were, the others with the roster's class or none
  assert.deepEqual(payload.people.Aldreth, WIKI_PAYLOAD.people.Aldreth);
  assert.deepEqual(payload.people.Newbie, { class: 'DRUID' });
  assert.deepEqual(payload.people.Stranger, { class: 'MAGE' });
  assert.deepEqual(payload.people.Unknown, {});
  for (const key of ['active', 'activeAt', 'chosenAt', 'importedAt', 'syncedFrom', 'fallback', 'revision']) {
    assert.ok(!(key in payload), `${key} stays out`);
  }
  assert.deepEqual(payload.gargul, WIKI_PAYLOAD.gargul);
  assert.deepEqual(payload.event, WIKI_PAYLOAD.event);
});

test('an edited plan round-trips through the import and passes its check', () => {
  const text = exportPlan(edited(), 1790009999, { Newbie: 'DRUID' });
  const read = call('import', [text]);
  assert.doesNotMatch(read, /^(ERR|CHECK|PROTOCOL):/, read);
  assert.deepEqual(JSON.parse(read), decode(text));
});

test('a plan made in game (no url, no event id, no people, no Gargul) exports and imports', () => {
  const plan = {
    protocol: 2, generatedAt: 1, event: { title: 'Made in game' },
    layouts: { default: Array.from({ length: 40 }, (_, i) => (i < 3 ? `P${i}` : '')) },
    encounters: [{ key: 'x:1', label: 'Note', note: '', layout: 'default' }],
  };
  const text = exportPlan(plan, 5, { P0: 'WARRIOR' });
  assert.doesNotMatch(call('import', [text]), /^(ERR|CHECK|PROTOCOL):/);
  assert.deepEqual(decode(text).people, { P0: { class: 'WARRIOR' }, P1: {}, P2: {} });
  const empty = { ...plan, layouts: { default: Array(40).fill('') } };
  assert.match(jsonOf(exportPlan(empty, 5)), /"people":\{\}/, 'no people is an empty object');
});

test('a large night (40 people, 20 encounters, a long Gargul string) exports at a size the import takes', () => {
  const plan = stored(WIKI_PAYLOAD);
  plan.layouts.default = Array.from({ length: 40 }, (_, i) => `Raider${i + 1}`);
  const lucifron = WIKI_PAYLOAD.encounters[2];
  const note = Array.from({ length: 40 }, (_, i) => `{rt${(i % 8) + 1}} |cffc79c6eRaider${i}|r ${i * 7919} ä`).join('\n');
  plan.encounters = Array.from({ length: 20 }, (_, i) => ({
    ...structuredClone(lucifron), key: `molten-core:boss${i}`, label: `Boss ${i}`,
    ...(i % 2 ? { customNote: note } : {}),
  }));
  plan.gargul = { string: Buffer.from(Array.from({ length: 12000 }, (_, i) => (i * 7919) % 251)).toString('base64'), generatedAt: 1 };
  const text = exportPlan(plan, 1790000100);
  assert.ok(text.length < 60000, `${text.length} characters`);
  const read = call('import', [text]);
  assert.doesNotMatch(read, /^(ERR|CHECK|PROTOCOL):/, read);
  assert.equal(decode(text).encounters[1].note, note);
});

// The wiki's own decoder, when UnityWiki is checked out next to this repo (or next to a folder above this worktree)
function wikiDir() {
  for (let dir = root; dirname(dir) !== dir; dir = dirname(dir)) {
    const candidate = join(dirname(dir), 'UnityWiki');
    if (existsSync(join(candidate, 'src', 'lib', 'addon-export.ts'))) return candidate;
  }
  return null;
}

test('UnityWiki decodes the exported string when it is checked out next to this repo', async (t) => {
  const wiki = wikiDir();
  if (!wiki) {
    t.skip('UnityWiki not found next to this repo');
    return;
  }
  let module;
  try {
    module = await import(pathToFileURL(join(wiki, 'src', 'lib', 'addon-export.ts')).href);
  } catch (error) {
    t.skip(`UnityWiki's addon-export.ts does not load in this Node: ${error.message}`);
    return;
  }
  const text = exportPlan(edited(), 1790009999, { Newbie: 'DRUID' });
  assert.equal(module.addonProtocolOf(text), 2);
  assert.deepEqual(module.decodeAddon(text), decode(text));
  assert.deepEqual(module.decodeAddon(call('reencode', [WIKI_EXPORT])), WIKI_PAYLOAD);
});
