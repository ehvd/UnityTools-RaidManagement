// Runs Modules/NoteView.lua in fengari (a Lua VM in JavaScript): a note's blocks for players, classes and groups,
// kept or left out the way Method Raid Tools shows the note to one player. Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
assert(loadfile(ROOT .. "/Modules/NoteView.lua"))("UnityTools-RaidManagement", ns)
local NoteView, Codec = ns.NoteView, ns.PlanCodec

function view(text, viewerJson)
    local viewer = Codec.JSONDecode(viewerJson)
    if viewer == false then viewer = nil end
    return NoteView.For(text, viewer)
end

function groupIn(layoutJson, name)
    return tostring(NoteView.GroupIn(Codec.JSONDecode(layoutJson), name))
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
  const result = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

const view = (text, viewer) => call('view', text, JSON.stringify(viewer ?? false));

const KAEL = { name: 'Kael', class: 'ROGUE', group: 2, classes: { ROGUE: true, MAGE: true, PRIEST: true } };
const SIGGI = { name: 'Siggi', class: 'MAGE', group: 5, classes: { ROGUE: true, MAGE: true, PRIEST: true } };

test('everyone: only the text outside player, class, group and role blocks, negated ones too', () => {
  const note = 'Skeram\n{p:Kael}kick{/p}{!p:Kael}watch{/p}\n{g25}\nLeft\n{/g}\n{!g1}\nRight\n{/g}\n'
    + '{c:Mage}decurse{/c}{!c:Rogue}x{/c}{classunique:Mage}y{/classunique}{h}heal{/h}{T}taunt{/T}{d}dps{/d}'
    + '{0}hidden{/0}{rt8} all';
  assert.equal(view(note, null), 'Skeram\n\n\n\n{rt8} all');
});

test('player blocks: names without colours, realms or case; {!p} for the others', () => {
  const note = '{p:|cfffff569Kael|r,Ember}kick{/p} {!p:kael-Firemaw}watch{/p}';
  assert.equal(view(note, KAEL), 'kick ');
  assert.equal(view(note, SIGGI), ' watch');
  assert.equal(view('{P:KAEL}x{/P}', { ...KAEL, name: 'Kael-Firemaw' }), 'x');
});

test('class blocks: English, the game language, short names and numbers', () => {
  const note = '{c:Rogue}a{/c}{c:lock,Mage}b{/c}{c:8}c{/c}{!c:4}d{/c}{c:Schurke}e{/c}';
  assert.equal(view(note, KAEL), 'a');
  assert.equal(view(note, SIGGI), 'bd');                    // "8" is Shaman in MRT, not Mage
  assert.equal(view(note, { ...KAEL, classNames: { schurke: 'ROGUE' } }), 'ae');
});

test('classunique: only the first listed class that is in the raid', () => {
  const note = '{classunique:Druid,Mage,Rogue}decurse{/classunique}';
  assert.equal(view(note, SIGGI), 'decurse');
  assert.equal(view(note, KAEL), '');
});

test('group blocks: the digits list the groups, {!g} for the others', () => {
  const note = 'Left:\n{g25}\nGroups: 2, 5\n{/g}\nRight:\n{!g25}\nthe rest\n{/g}\n';
  // As in MRT: the line break after an opening tag and before a closing one go; a hidden block leaves its line
  assert.equal(view(note, KAEL), 'Left:\nGroups: 2, 5\nRight:\n\n');
  assert.equal(view(note, { ...KAEL, group: 3 }), 'Left:\n\nRight:\nthe rest\n');
});

test('{0} blocks are for nobody; other tags stay for the icons', () => {
  assert.equal(view('{0}hidden{/0}{rt1} {e:610}x{/e}', KAEL), '{rt1} {e:610}x{/e}');
});

test('group of a player in a layout: by name without realm, 1 when not there', () => {
  const layout = Array(40).fill('');
  layout[6] = 'Kael';
  layout[23] = 'Siggi';
  assert.equal(call('groupIn', JSON.stringify(layout), 'kael-Firemaw'), '2');
  assert.equal(call('groupIn', JSON.stringify(layout), 'Siggi'), '5');
  assert.equal(call('groupIn', JSON.stringify(layout), 'Ember'), '1');
});
