// Runs Modules/PlanCodec.lua in fengari, a Lua VM in JavaScript, against strings encoded the way UnityWiki encodes
// its raid plan export (src/lib/addon-export.ts there: base64 over Node's zlib over JSON).
// Run with `make test` (needs Node; `make test` runs `npm install` in tests/ first).
//
// LibDeflate is replaced by Node's zlib here: under fengari (Lua 5.3 semantics) LibDeflate inflates wrongly even
// "hello world", while in WoW's Lua 5.1 it is what WeakAuras and Gargul decode the same encoding with. So these tests
// cover the base64, JSON and shape checks of the addon; the inflate itself is covered by the in-game check.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { deflateSync, inflateSync } from 'node:zlib';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// The example string of UnityWiki's docs/addon-export.md (protocol 1)
const DOC_EXAMPLE =
  'eJzFktFv0zAQxv+V6p5T4g7arpb2UBU0QRJt0BHYpj2Y5JKaeHZqn9daXf535MKACe0Z6aSTvpPuvu+nO0BvDZnKKOCTBFrUaAVhvSTgk/mCMcYmjCXgrQIOG6Le8TT1WlIY98Hizpj6FfrUCllL3R77uFdCu3Ry8vrNdDY/XTBIAB9QE/ADyBo4PBuRJIXAoViNtGw3BAk4EpbcXx5Y9BB3O+C3B3DKt8Dh3ihCPa6MRUhAi/vjmqM4WkVxuBsSUCIYTy4er7ERXhHwW1iq2iJtIIH/UNEW6sp4TWh/RuowPE/Ela9kY42GGOEbRv75HynC+BeBoYjgSuiOjx6rpqnmi2qGv7I+WniiAfw3i+EugVbY1qtIyJGVOrLFD8GW0l7mxfx9WO98VoqwVdfhc55lpbP51Wl/uRW7vX177opyldm6/LSWaZYHtgx1s80uvnbTaWW+rLt+tv6upjfYfWzLvFAX+a7Yi+W7EzzfX5/Bi083DD8AlInGpw==';

// Lua side: decode a string and hand back the result as canonical JSON (sorted keys), or the error / check code
const SHIM = `
local ns = {}
assert(loadfile(ROOT .. "/Modules/PlanCodec.lua"))("UnityTools-RaidManagement", ns)
local LibDeflate = { DecompressZlib = function(_, data) return node_inflate(data) end }
local Codec = ns.PlanCodec

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
    elseif next(v) == nil then
        return "[]"
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

function checksum(text)
    return Codec.Checksum(text)
end

function run(text)
    local data, code = Codec.Decode(text, LibDeflate)
    if not data then return "ERR:" .. code end
    if not Codec.IsSupported(data.protocol) then return "PROTOCOL:" .. data.protocol end
    local problem = Codec.Check(data)
    if problem then return "CHECK:" .. problem end
    return canon(data)
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(root.replaceAll('\\', '/')));
lua.lua_setglobal(L, to_luastring('ROOT'));
// node_inflate(bytes) -> the inflated bytes, or nil like LibDeflate:DecompressZlib on a broken stream
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

function run(text) {
  lua.lua_getglobal(L, to_luastring('run'));
  lua.lua_pushstring(L, to_luastring(text));
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  const result = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return result;
}

// The same canonical form in JavaScript; null and absent are the same (Lua has no null)
function canon(v) {
  if (typeof v === 'string') {
    return `"${v.replace(/["\\\u0000-\u001f\u007f]/g, (c) => (c === '"' || c === '\\' ? `\\${c}` : `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`))}"`;
  }
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return v.length ? `[${v.map(canon).join(',')}]` : '[]';
  const keys = Object.keys(v).filter((k) => v[k] !== null).sort();
  return keys.length ? `{${keys.map((k) => `${canon(k)}:${canon(v[k])}`).join(',')}}` : '[]';
}

const encode = (payload) => deflateSync(JSON.stringify(payload)).toString('base64');

// Equal canonical forms, reported by their first difference instead of two 100 KB strings
function assertSame(actual, payload) {
  const expected = canon(payload);
  if (actual === expected) return;
  let i = 0;
  while (actual[i] === expected[i]) i++;
  assert.fail(`differs at ${i}: got ${JSON.stringify(actual.slice(Math.max(0, i - 40), i + 40))}, `
    + `expected ${JSON.stringify(expected.slice(Math.max(0, i - 40), i + 40))}`);
}
const names = (prefix) => Array.from({ length: 40 }, (_, i) => (i % 7 === 6 ? '' : `${prefix}${i + 1}`));

function night() {
  const note = Array.from({ length: 60 }, (_, i) =>
    `{rt${(i % 8) + 1}} |cffc79c6eÄldreth|r tanks pack ${i} {spell:12345}\tZoë 😀 "quoted" \\ back\u0001`).join('\n');
  return {
    protocol: 1,
    generatedAt: 1790000100,
    url: 'https://unity-pyrewood.eu/raiding/raid-plans/1234567890',
    event: { id: '1234567890', title: 'BWL + MC night', startsAt: null, raids: [{ slug: 'molten-core', name: 'Molten Core' }] },
    layouts: { default: names('Raider'), 'Twins swap': names('Swap') },
    encounters: Array.from({ length: 20 }, (_, i) => ({
      key: i === 0 ? 'x:1' : `molten-core:boss${i}`,
      label: `Boss ${i}`,
      ...(i === 0 ? {} : { raid: 'molten-core' }),
      note: i === 1 ? '' : note,
      layout: i === 5 ? 'Twins swap' : 'default',
    })),
    gargul: { string: Buffer.from(Array.from({ length: 30000 }, (_, i) => (i * 7919) % 251)).toString('base64'), generatedAt: 1790000100 },
    futureKey: { ignored: true },
  };
}

test('the example string of the format doc decodes', () => {
  const decoded = run(DOC_EXAMPLE);
  assert.match(decoded, /"label":"Lucifron"/);
  assert.match(decoded, /"note":"Tank: \|cffc79c6eAldreth\|r"/);
  assert.match(decoded, /"protocol":1/);
});

test('a full night decodes losslessly, with unicode, escapes and markup', () => {
  const payload = night();
  const text = encode(payload);
  assert.ok(text.length < 60000, `fixture is ${text.length} characters`);
  assertSame(run(text), payload);
});

test('surrounding whitespace and line breaks in the pasted text are ignored', () => {
  const payload = night();
  const text = encode(payload).replace(/(.{76})/g, '$1\r\n');
  assert.equal(run(`  \n${text}\n `), canon(payload));
});

test('\\u escapes, surrogate pairs and other escapes decode to UTF-8', () => {
  const json = `{"protocol":1,"event":{"title":"a\\u00e4\\ud83d\\ude00\\/\\n"},"layouts":{"default":${JSON.stringify(names('X'))}},"encounters":[]}`;
  const decoded = run(deflateSync(json).toString('base64'));
  assert.match(decoded, /"title":"aä😀\/\\u000a"/);
});

test('an unsupported protocol is reported before the shape is checked', () => {
  assert.equal(run(encode({ protocol: 2, whatever: true })), 'PROTOCOL:2');
});

test('broken strings give an error code, not a Lua error', () => {
  const text = encode(night());
  assert.equal(run(''), 'ERR:empty');
  assert.equal(run('hello world!!'), 'ERR:base64');
  assert.equal(run(text.slice(0, Math.floor(text.length / 2))), 'ERR:zlib');
  assert.equal(run(deflateSync('{"protocol":1,').toString('base64')), 'ERR:json');
  assert.equal(run(encode({ foo: 1 })), 'ERR:notPlan');
  assert.equal(run(encode([1, 2])), 'ERR:notPlan');
});

test('a plan with a broken shape names the first problem', () => {
  const short = night();
  short.layouts.default = short.layouts.default.slice(0, 39);
  assert.equal(run(encode(short)), 'CHECK:layouts.default');

  const missing = night();
  missing.encounters[3].layout = 'Nope';
  assert.equal(run(encode(missing)), 'CHECK:encounters[4].layout');

  const noDefault = night();
  delete noDefault.layouts.default;
  assert.equal(run(encode(noDefault)), 'CHECK:layouts.default');

  const badGargul = night();
  badGargul.gargul = { string: 5 };
  assert.equal(run(encode(badGargul)), 'CHECK:gargul');
});

test('a plan without a Gargul string is fine', () => {
  const payload = night();
  delete payload.gargul;
  assertSame(run(encode(payload)), payload);
});

test('the checksum is djb2 over the bytes, as 8 hex digits', () => {
  const djb2 = (text) => {
    let h = 5381;
    for (const b of Buffer.from(text, 'utf8')) h = (h * 33 + b) % 4294967296;
    return h.toString(16).padStart(8, '0');
  };
  const luaChecksum = (text) => {
    lua.lua_getglobal(L, to_luastring('checksum'));
    lua.lua_pushstring(L, to_luastring(text));
    if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
    const out = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);
    return out;
  };
  const gargul = night().gargul.string;
  for (const text of ['', 'a', 'Zoë 😀', gargul]) assert.equal(luaChecksum(text), djb2(text));
  assert.notEqual(luaChecksum(gargul), luaChecksum(gargul.slice(0, -1) + 'A'));
});

test('the decoder is not accidentally quadratic', () => {
  const text = encode(night());
  const started = performance.now();
  run(text);
  assert.ok(performance.now() - started < 15000, 'decoding a full night took over 15 s in fengari');
});

// Keep the doc example in sync with the file it came from when the wiki is checked out next to this repo
test('the doc example matches UnityWiki when it is checked out next to this repo', (t) => {
  let doc;
  try {
    doc = readFileSync(join(root, '..', '..', 'UnityWiki', 'docs', 'addon-export.md'), 'utf8');
  } catch {
    t.skip('UnityWiki not found next to this repo');
    return;
  }
  if (!doc.includes(DOC_EXAMPLE)) t.diagnostic('docs/addon-export.md has a different example now: update DOC_EXAMPLE');
});
