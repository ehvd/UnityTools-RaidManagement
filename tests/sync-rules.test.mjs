// Runs Modules/SyncRules.lua in fengari (a Lua VM in JavaScript). Run with `make test`.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..').replaceAll('\\', '/');

// Metas and messages travel as "key=value;key=value" strings ("" for nil); numbers stay numbers
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/SyncRules.lua"))("UnityTools-RaidManagement", ns)
local R = ns.SyncRules

local function parse(text)
    if text == "" then return nil end
    local t = {}
    for key, value in text:gmatch("([^=;]+)=([^;]*)") do
        t[key] = tonumber(value) or value
    end
    return t
end

function planWins(theirs, mine) return tostring(R.PlanWins(parse(theirs), parse(mine))) end
function activeWins(theirs, mine) return tostring(R.ActiveWins(parse(theirs), parse(mine))) end
function validate(text)
    local msg, why = R.Validate(parse(text))
    return msg and "ok" or why
end
function identity(eventId, generatedAt)
    return R.Identity({ event = { id = eventId }, generatedAt = generatedAt })
end
function meta(chosenAt, importedAt)
    local m = R.Meta({ event = { id = "e1" }, generatedAt = 100, chosenAt = chosenAt ~= "" and tonumber(chosenAt) or nil,
        importedAt = tonumber(importedAt), active = "x:1", activeAt = 7 }, "Me")
    return m.id .. "|" .. m.c .. "|" .. m.g .. "|" .. m.a .. "|" .. m.at .. "|" .. m.s
end
local function serialize(m)
    return "id=" .. m.id .. ";c=" .. m.c .. ";g=" .. m.g .. ";s=" .. m.s
end
-- The meta of plan e1@100 held by \`holder\`, chosen at \`chosenAt\`, after the edits "by@at,by@at" (in order) the way
-- PlanImport:Edit makes them
function edited(holder, chosenAt, edits)
    local plan = { event = { id = "e1" }, generatedAt = 100, chosenAt = tonumber(chosenAt) }
    for by, at in edits:gmatch("([^@,]+)@(%d+)") do
        at = tonumber(at)
        plan.revision = R.Revise(plan.revision, by, at)
        plan.chosenAt = R.EditChosenAt(plan.chosenAt, at)
    end
    return serialize(R.Meta(plan, holder))
end
function isRevision(n, by, at)
    if n == "" then return tostring(R.IsRevision(nil)) end
    return tostring(R.IsRevision({ n = tonumber(n), by = by ~= "" and by or nil, at = tonumber(at) }))
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
if (lauxlib.luaL_dostring(L, to_luastring(SHIM)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));

function call(name, ...args) {
  lua.lua_getglobal(L, to_luastring(name));
  for (const a of args) lua.lua_pushstring(L, to_luastring(String(a)));
  if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const out = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return out;
}

const m = (fields) => Object.entries(fields).map(([k, v]) => `${k}=${v}`).join(';');
const wins = (theirs, mine) => call('planWins', theirs ? m(theirs) : '', mine ? m(mine) : '') === 'true';

test('a plan replaces no plan, and no plan replaces nothing', () => {
  assert.equal(wins({ id: 'e1@100', c: 5, g: 100, s: 'A' }, null), true);
  assert.equal(wins(null, { id: 'e1@100', c: 5, g: 100, s: 'A' }), false);
});

test('copies of the same export never replace each other', () => {
  assert.equal(wins({ id: 'e1@100', c: 900, g: 100, s: 'A' }, { id: 'e1@100', c: 5, g: 100, s: 'B' }), false);
});

test('the most recently chosen plan wins, even an older export', () => {
  assert.equal(wins({ id: 'e1@100', c: 50, g: 100, s: 'A' }, { id: 'e2@200', c: 40, g: 200, s: 'B' }), true);
  assert.equal(wins({ id: 'e2@200', c: 40, g: 200, s: 'B' }, { id: 'e1@100', c: 50, g: 100, s: 'A' }), false);
});

test('chosen at the same time: the newer export wins, then the name that sorts first', () => {
  assert.equal(wins({ id: 'e2@200', c: 50, g: 200, s: 'B' }, { id: 'e1@100', c: 50, g: 100, s: 'A' }), true);
  assert.equal(wins({ id: 'e2@100', c: 50, g: 100, s: 'Aldreth' }, { id: 'e1@100', c: 50, g: 100, s: 'Brumm' }), true);
  assert.equal(wins({ id: 'e2@100', c: 50, g: 100, s: 'Brumm' }, { id: 'e1@100', c: 50, g: 100, s: 'Aldreth' }), false);
});

test('two clients always agree on the winner (no ping-pong)', () => {
  const plans = [
    { id: 'e1@100', c: 50, g: 100, s: 'A' }, { id: 'e2@200', c: 50, g: 200, s: 'B' },
    { id: 'e3@100', c: 60, g: 100, s: 'C' }, { id: 'e4@100', c: 60, g: 100, s: 'D' },
  ];
  for (const a of plans) {
    for (const b of plans) {
      if (a === b) continue;
      assert.notEqual(wins(a, b), wins(b, a), `${a.id} vs ${b.id}`);
    }
  }
});

test('the active encounter follows the newer choice, for the same plan only', () => {
  const act = (theirs, mine) => call('activeWins', m(theirs), m(mine)) === 'true';
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 20 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), true);
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 5 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), false);
  assert.equal(act({ id: 'e2@100', a: 'mc:garr', at: 20 }, { id: 'e1@100', a: 'mc:lucifron', at: 10 }), false);
  // A newcomer with the same plan but no active encounter yet: ours is newer, so a source answers them
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 20 }, { id: 'e1@100' }), true);
  // ...and their missing encounter never replaces ours
  assert.equal(act({ id: 'e1@100' }, { id: 'e1@100', a: 'mc:garr', at: 20 }), false);
  // Two choices in the same server second: the window makes the later one a hair newer
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 100.001 }, { id: 'e1@100', a: 'mc:lucifron', at: 100 }), true);
  assert.equal(act({ id: 'e1@100', a: 'mc:garr', at: 100 }, { id: 'e1@100', a: 'mc:lucifron', at: 100 }), false);
});

test('the meta of a plan falls back to the import time when nothing chose it', () => {
  assert.equal(call('meta', '', 42), 'e1@100|42|100|x:1|7|Me');
  assert.equal(call('meta', 99, 42), 'e1@100|99|100|x:1|7|Me');
  assert.equal(call('identity', 'abc', 123), 'abc@123');
});

test('messages are validated, other versions recognised', () => {
  assert.equal(call('validate', 't=state;v=2;id=e1@100;c=5;g=100'), 'ok');
  assert.equal(call('validate', 't=state;v=2;id=e1@100/1:Lead:900;c=5;g=100'), 'ok');
  assert.equal(call('validate', 't=state;v=2'), 'ok');               // a client without a plan
  assert.equal(call('validate', 't=request;v=2;id=e1@100'), 'ok');
  assert.equal(call('validate', 't=plan;v=2;p=abc'), 'ok');
  assert.equal(call('validate', 't=force;v=2;p=abc'), 'ok');
  assert.equal(call('validate', 't=state;v=1;id=e1@100'), 'version'); // 0.1.0: its identity has no revision
  assert.equal(call('validate', 't=state;v=3;id=e1@100'), 'version');
  assert.equal(call('validate', 't=hello;v=2'), 'invalid');
  assert.equal(call('validate', 't=request;v=2'), 'invalid');
  assert.equal(call('validate', 't=plan;v=2'), 'invalid');
  assert.equal(call('validate', 't=state;v=2;c=soon'), 'invalid');
  assert.equal(call('validate', ''), 'invalid');
});

// Edits (PlanImport:Edit): a new revision and chosen now
const ed = (holder, chosenAt, edits) => call('edited', holder, chosenAt, edits);
const winsText = (theirs, mine) => call('planWins', theirs, mine) === 'true';

test('the identity of an edited plan carries its revision', () => {
  assert.equal(ed('Lead', 1000, ''), 'id=e1@100;c=1000;g=100;s=Lead');
  assert.equal(ed('Lead', 1000, 'Lead@1200'), 'id=e1@100/1:Lead:1200;c=1200;g=100;s=Lead');
  assert.equal(ed('Lead', 1000, 'Lead@1200,Assist@1300'), 'id=e1@100/2:Assist:1300;c=1300;g=100;s=Lead');
});

test('an edited copy beats the unedited one, whoever holds them', () => {
  for (const [editor, other] of [['Lead', 'Aaron'], ['Aaron', 'Zed']]) {
    const edit = ed(editor, 1000, `${editor}@1200`);
    const plain = ed(other, 1000, '');
    assert.equal(winsText(edit, plain), true, `${editor}'s edit vs ${other}`);
    assert.equal(winsText(plain, edit), false, `${other} vs ${editor}'s edit`);
  }
});

test('an edit in the same second as the import still beats the import', () => {
  const edit = ed('Zed', 1000, 'Zed@1000');   // Zed sorts after Aaron: the name must not decide
  const plain = ed('Aaron', 1000, '');
  assert.equal(winsText(edit, plain), true);
  assert.equal(winsText(plain, edit), false);
  // ...and a second edit in that same second beats the first
  const again = ed('Zed', 1000, 'Zed@1000,Zed@1000');
  assert.equal(winsText(again, ed('Aaron', 1000, 'Zed@1000')), true);
  assert.equal(winsText(ed('Aaron', 1000, 'Zed@1000'), again), false);
});

test('two edits of the same plan resolve to the newest', () => {
  const byLead = ed('Lead', 1000, 'Lead@1200');
  const byAssist = ed('Assist', 1000, 'Assist@1300');
  assert.equal(winsText(byAssist, byLead), true);
  assert.equal(winsText(byLead, byAssist), false);
  // An edit of an edit beats the edit it was made from
  const chained = ed('Lead', 1000, 'Assist@1300,Lead@1400');
  assert.equal(winsText(chained, ed('Assist', 1000, 'Assist@1300')), true);
  assert.equal(winsText(ed('Assist', 1000, 'Assist@1300'), chained), false);
});

test('the same revision never replaces itself', () => {
  const mine = ed('Lead', 1000, 'Lead@1200');
  // A synced copy keeps the editor's chosen time; even a later chosen time (a force sync) does not count
  const theirs = ed('Aaron', 1000, 'Lead@1200');
  const later = 'id=e1@100/1:Lead:1200;c=5000;g=100;s=Aaron';
  assert.equal(winsText(theirs, mine), false);
  assert.equal(winsText(mine, theirs), false);
  assert.equal(winsText(later, mine), false);
});

test('edited and unedited copies never ping-pong: exactly one side wins', () => {
  const copies = [
    ed('Aaron', 1000, ''), ed('Zed', 1000, 'Zed@1000'), ed('Lead', 1000, 'Lead@1200'),
    ed('Assist', 1000, 'Assist@1200'), ed('Bob', 1000, 'Lead@1200,Bob@1300'), 'id=e3@100;c=1300;g=100;s=Cid',
    'id=e2@200;c=1300;g=200;s=Dan',
  ];
  for (const a of copies) {
    for (const b of copies) {
      if (a === b) continue;
      assert.notEqual(winsText(a, b), winsText(b, a), `${a} vs ${b}`);
    }
  }
});

test('a revision received with a plan is checked', () => {
  assert.equal(call('isRevision', '', '', ''), 'true');       // the plan as imported
  assert.equal(call('isRevision', 1, 'Lead', 1200), 'true');
  assert.equal(call('isRevision', 1, '', 1200), 'false');
  assert.equal(call('isRevision', 'x', 'Lead', 1200), 'false');
});
