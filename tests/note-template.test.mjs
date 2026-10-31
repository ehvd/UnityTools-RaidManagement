// Runs Modules/NoteTemplate.lua in fengari (a Lua VM in JavaScript) against UnityWiki's protocol 2 fixture
// (src/lib/__fixtures__/addon-export/payload.json there, copied into tests/fixtures): every encounter's template,
// filled with its holders, must give the wiki's `note` byte for byte. Run with `make test`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const PAYLOAD = JSON.parse(readFileSync(join(root, 'tests', 'fixtures', 'wiki-export-payload.json'), 'utf8'));

// The arguments travel as JSON, decoded with the addon's own decoder
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/NoteTemplate.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
local T, Codec = ns.NoteTemplate, ns.PlanCodec

function render(template, slots, people)
    return T.Render(template, Codec.JSONDecode(slots), Codec.JSONDecode(people))
end

function width(text)
    return T.Width(text)
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root.replaceAll('\\', '/')));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const arg of args) lua.lua_pushstring(L, to_luastring(arg));
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = lua.lua_isnumber(L, -1) ? lua.lua_tonumber(L, -1) : to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

const render = (template, slots = [], people = PAYLOAD.people) =>
  call('render', template, JSON.stringify(slots), JSON.stringify(people));
const encounter = (key) => structuredClone(PAYLOAD.encounters.find((e) => e.key === key));
// One slot, `{{s:1}}`
const slot = (holders, extra = {}) => ({ n: 1, token: 'X', key: 'x', kind: 'custom', multi: true, sep: ', ', holders, candidates: holders, ...extra });

test('every encounter of the wiki fixture renders to its note', () => {
  const withTemplate = PAYLOAD.encounters.filter((e) => e.template !== undefined);
  assert.equal(withTemplate.length, PAYLOAD.encounters.length, 'the fixture has an encounter without a template');
  for (const { key, template, slots, note } of withTemplate) {
    assert.equal(render(template, slots), note, key);
  }
});

test('changed holders rebuild the note', () => {
  const lucifron = encounter('molten-core:lucifron');
  const byN = (n) => lucifron.slots[n - 1];
  for (const n of [1, 2, 11]) byN(n).holders = ['Brunhild'];   // one job: role=tank&order=1
  byN(4).holders = ['Fenlyn'];                                  // TANK3: the far add line comes back
  byN(10).holders = [];                                         // no paladin healer: " - ..." goes
  byN(8).holders = ['Siggi'];                                   // a warlock list, for the test's sake
  byN(12).holders = [];
  assert.equal(render(lucifron.template, lucifron.slots), [
    '{rt1} |cffc79c6eBrunhild|r on Lucifron, |cffc79c6eBrunhild|r taunts',
    '{rt2} |cffc79c6eBrunhild|r  adds',
    '{rt3} |cfff58cbaFenlyn|r on the far add',
    'Heals: |cffffffffZoë|r   | |cfff58cbaFenlyn|r|',
    'Decurse: |cff69ccf0Siggi|r, |cff69ccf0Ember|r Banish: |cff69ccf0Siggi|r',
    '{rt4} |cffc79c6eBrunhild|r',
    '|cffc79c6eBrunhild|r: pulls',
    '{spell:19702}  kicks, |cffc79c6eBrunhild|r calls it',
  ].join('\n'));
});

test('a stretch drops when any of its slots is empty, nested ones inside out', () => {
  const tank = { ...slot(['Aldreth'], { multi: false }), sep: undefined };
  const heal = { ...slot(['Fenlyn'], { multi: false }), n: 2, sep: undefined };
  const t = '[[{rt4} {{s:1}}[[ - {{s:2}}]]]]';
  assert.equal(render(t, [tank, heal]), '{rt4} |cffc79c6eAldreth|r - |cfff58cbaFenlyn|r');
  assert.equal(render(t, [tank, { ...heal, holders: [] }]), '{rt4} |cffc79c6eAldreth|r');
  assert.equal(render(`a\n${t}\nb`, [{ ...tank, holders: [] }, heal]), 'a\nb');
  assert.equal(render('a\n[[x {{s:1}} {{s:2}}]]', [tank, { ...heal, holders: [] }]), 'a');
  assert.equal(render('[[no slot here]] ok', []), 'no slot here ok');
});

test('only a line that is exactly one stretch goes; other stretches lose their own text', () => {
  const empty = slot([]);
  assert.equal(render('a\n  [[x {{s:1}}]]\t\nb', [empty]), 'a\nb');
  assert.equal(render('a\n[[x {{s:1}}]] tail\nb', [empty]), 'a\n tail\nb');
  assert.equal(render('a\n[[x [y] {{s:1}}]]\nb', [empty]), 'a\n\nb');
  assert.equal(render('a\n[[x {{s:1}}]]', [empty]), 'a');
  assert.equal(render('[[x {{s:1}}]]\nb', [empty]), 'b');
  assert.equal(render('a\n[[x\n{{s:1}}]]\nb', [empty]), 'a\n\nb');
});

test('unclosed and stray brackets stay as they are written', () => {
  const one = slot(['Pencil']);
  assert.equal(render('a [[b {{s:1}}', [one]), 'a [[b Pencil');
  assert.equal(render('a ]] b', []), 'a ]] b');
  assert.equal(render('[[[x {{s:1}}]]', [one]), '[x Pencil');
  assert.equal(render('[[x]]]', []), 'x]');
});

test('padding counts what shows, never cuts, and pads an empty slot', () => {
  const pad = (holders, width, after = '|') => render(`{{s:1}}${after}`, [slot(holders, { pad: width })]);
  assert.equal(pad(['Zoë'], 6), '|cffffffffZoë|r   |');
  assert.equal(pad(['Pencil'], 8), 'Pencil  |');
  assert.equal(pad(['Brunhild', 'Kael'], 4), '|cffc79c6eBrunhild|r, |cfffff569Kael|r|');
  assert.equal(pad([], 3), '   |');
  assert.equal(pad(['Pencil'], 9, ': end'), 'Pencil: end');   // the punctuation rule eats it
  assert.equal(pad(['Pencil'], 9, ''), 'Pencil');           // and so does the trailing trim
});

test('the width of a text is its UTF-16 length without colour codes, like the wiki\'s', () => {
  assert.equal(call('width', 'Zoë'), 3);
  assert.equal(call('width', 'a😀b'), 4);
  assert.equal(call('width', '|cFFabcdefX|R|r'), 1);
  assert.equal(call('width', '||cffffffffr'), 2);   // "|" then a colour code, then "r"
  assert.equal(call('width', '|cffxyz'), 7);
});

test('names: coloured by class, bare without one, sep only between names', () => {
  assert.equal(render('{{s:1}}', [slot(['Pencil', 'Nobody', 'Kael'], { sep: '\n' })]), 'Pencil\nNobody\n|cfffff569Kael|r');
  assert.equal(render('{{s:1}}', [slot(['Kael', 'Siggi'], { multi: false })]), '|cfffff569Kael|r');
  assert.equal(render('{{s:1}}', [{ ...slot(['Kael', 'Siggi']), sep: undefined }]), '|cfffff569Kael|r|cff69ccf0Siggi|r');
  assert.equal(render('{{s:1}}', [slot(['Aldreth'])], {}), 'Aldreth');
});

test('the lines are tidied like the wiki: punctuation, trailing space, blank runs, ends', () => {
  assert.equal(render('\n\n  a  ,b !  \n\n\n\nc\t \n\n', []), '  a,b!\n\nc');
  assert.equal(render('{{s:1}} , x', [slot([])]), ', x');
  assert.equal(render('{{s:9}} unknown', []), ' unknown');
});
