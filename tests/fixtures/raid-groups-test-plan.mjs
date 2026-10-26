// A protocol 1 raid plan export for testing the raid groups in game with two characters, Bogartlover and
// Bartababbi. Every encounter is one variation; its MRT note says what to expect. Step through it in order with ▶,
// starting with both characters in group 1 (as when the raid is formed).
//
//   node tests/fixtures/raid-groups-test-plan.mjs        prints the string to paste into /utrm import
//
// tests/raid-groups-scenario.test.mjs decodes it with the addon's decoder and checks every expected status.
import { deflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const BOG = 'Bogartlover';
export const BAR = 'Bartababbi';

// 40 slots from { group: [names] }
function layout(groups) {
  const slots = Array(40).fill('');
  for (const [group, names] of Object.entries(groups)) {
    names.forEach((name, i) => { slots[(Number(group) - 1) * 5 + i] = name; });
  }
  return slots;
}

// One step of the test: the layout it uses, what the window's status should say afterwards (the groups part,
// assuming lead or assist, nobody in combat and the previous step finished), and the groups the two end up in
export const STEPS = [
  { key: 'molten-core:lucifron', label: '1. Both in group 1', layout: 'default',
    groups: { 1: [BOG, BAR] }, expect: 'Groups already match', after: { [BOG]: 1, [BAR]: 1 } },
  { key: 'molten-core:magmadar', label: '2. Split 1 / 2', layout: 'Split',
    groups: { 1: [BOG], 2: [BAR] }, expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 1, [BAR]: 2 } },
  { key: 'molten-core:gehennas', label: '3. Split again', layout: 'Split',
    groups: { 1: [BOG], 2: [BAR] }, expect: 'Groups already match', after: { [BOG]: 1, [BAR]: 2 } },
  { key: 'molten-core:garr', label: '4. Swapped 2 / 1', layout: 'Swapped',
    groups: { 1: [BAR], 2: [BOG] }, expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 2, [BAR]: 1 } },
  { key: 'molten-core:shazzrah', label: '5. Both in group 8', layout: 'Group 8',
    groups: { 8: [BOG, BAR] }, expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 8, [BAR]: 8 } },
  { key: 'molten-core:baron-geddon', label: '6. Lower case and realm', layout: 'Case and realm',
    groups: { 1: ['bogartlover', 'Bartababbi-Pyrewood Village'] },
    expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 1, [BAR]: 1 } },
  { key: 'molten-core:golemagg', label: '7. One missing', layout: 'Missing',
    groups: { 2: ['Ghostplayer', BOG, BAR] },
    expect: 'Sorting groups... (1 missing) → Groups sorted (1 missing)', after: { [BOG]: 2, [BAR]: 2 } },
  { key: 'molten-core:sulfuron', label: '8. One not in the plan', layout: 'Not planned',
    groups: { 3: [BOG] },
    expect: 'Sorting groups... (1 not in the plan) → Groups sorted (1 not in the plan)', after: { [BOG]: 3, [BAR]: 2 } },
  { key: 'molten-core:majordomo', label: '9. Nobody planned', layout: 'Empty',
    groups: {}, expect: 'Groups already match (2 not in the plan)', after: { [BOG]: 3, [BAR]: 2 } },
  { key: 'molten-core:ragnaros', label: '10. Planned twice', layout: 'Twice',
    groups: { 1: [BOG], 4: [BOG, BAR] }, expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 1, [BAR]: 4 } },
  { key: 'x:1', label: '11. Order inside a group', layout: 'Order',
    groups: { 1: [BAR, BOG] }, expect: 'Sorting groups... → Groups sorted', after: { [BOG]: 1, [BAR]: 1 } },
  { key: 'x:2', label: '12. Order reversed', layout: 'default',
    groups: { 1: [BOG, BAR] }, expect: 'Groups already match (positions inside a group are not checked)',
    after: { [BOG]: 1, [BAR]: 1 } },
  { key: 'x:3', label: '13. No note', layout: 'default', noNote: true,
    groups: { 1: [BOG, BAR] }, expect: 'Groups already match, and the note part says Note cleared',
    after: { [BOG]: 1, [BAR]: 1 } },
];

function note(step, index) {
  if (step.noNote) return '';
  const where = Object.entries(step.groups).map(([g, names]) => `group ${g}: ${names.join(', ')}`).join('\n');
  return [
    `{rt${(index % 8) + 1}} |cffffd100Test ${index + 1}/${STEPS.length}: ${step.label.replace(/^\d+\. /, '')}|r`,
    where || 'nobody planned',
    `Expect: ${step.expect}`,
    '',
    'Also try: as a member without assist (red: need lead or assist),',
    'in combat (red: someone is in combat), out of a raid (not in a raid).',
  ].join('\n');
}

export function payload() {
  const layouts = {};
  for (const step of STEPS) layouts[step.layout] ??= layout(step.groups);
  return {
    protocol: 1,
    generatedAt: 1793030400,
    url: 'https://unity-pyrewood.eu/raiding/raid-plans/test-raid-groups',
    event: {
      id: 'test-raid-groups',
      title: 'Raid groups test',
      startsAt: null,
      raids: [{ slug: 'molten-core', name: 'Molten Core' }],
    },
    layouts,
    encounters: STEPS.map((step, i) => ({
      key: step.key,
      label: step.label,
      ...(step.key.startsWith('x:') ? {} : { raid: 'molten-core' }),
      note: note(step, i),
      layout: step.layout,
    })),
    // A minimal Gargul (TMB) string: one placeholder entry, so a Gargul import would finish without data
    gargul: {
      string: deflateSync(JSON.stringify({ wishlists: { 0: ['nobody|1|1|0'] }, groups: { 1: 'UNITY' }, loot: '', notes: {}, tiers: {} }))
        .toString('base64'),
      generatedAt: 1793030400,
    },
  };
}

export const encode = (data) => deflateSync(JSON.stringify(data)).toString('base64');

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log(encode(payload()));
}
