# Platform constraints

Blizzard restricts what addons may automate. UnityTools-RaidManagement is designed around these limits and never tries
to bypass them. Verified against warcraft.wiki.gg (Classic Era 1.15.x, Interface `11509`) and the Method Raid Tools
source (MRT 5335) on 2026-10-26.

<!-- Each section: the rule, the design decision that follows from it, implementation notes, and the source link.
     Add a section whenever a feature runs into a new limit. -->

## 1. Raid chat and raid warnings

`SendChatMessage` to `RAID`, `PARTY` and `WHISPER` is not hardware-event restricted. `RAID_WARNING` needs raid leader
or assistant. Public `CHANNEL` messages (and `SAY` / `YELL` outdoors) do need a hardware event: a timer or event handler
may only prepare them, the user's click sends them. Messages are cut at 255 bytes (not characters).

Source: <https://warcraft.wiki.gg/wiki/API_SendChatMessage>

## 2. Raid management actions need permissions

Promoting, setting loot method, moving players between subgroups (`SetRaidSubgroup` / `SwapRaidSubgroup`) and raid
markers need raid leader or assistant; several of them are blocked in combat. Check `UnitIsGroupLeader("player")` /
`UnitIsGroupAssistant("player")` and `InCombatLockdown()` first and tell the user why an action was skipped.

Source: <https://warcraft.wiki.gg/wiki/API_SetRaidSubgroup>

## 3. Addon messages and throttling

`C_ChatInfo.SendAddonMessage` (through AceComm) is not hardware-event restricted but is throttled by the server;
send through ChatThrottleLib (bundled with AceComm). An addon whisper to an offline player prints a
"Player is offline." system message, so skip offline peers.

Source: <https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage>

## 4. Method Raid Tools notes

MRT is an optional dependency (`## OptionalDeps: MRT`); every feature that uses it checks that it is loaded and keeps
working without it. MRT has no documented API for setting a note, only for reading it (`GMRT.F:GetNote()`). From its
source (`Note.lua`):

- The current note is `VMRT.Note.Text1`; `GMRT.A.Note.frame:Save()` stores it in the history and sends it to the
  group as `multiline` chunks of 220 characters on the `EXRTADD` addon prefix, followed by a `multiline_add` message.
  Outside a group MRT whispers it to the player, which updates the note locally (useful for testing alone).
- `GMRT.F:GetNote()` strips colour codes (it passes `GMRT.F` as `removeColors`), so the editor reads
  `VMRT.Note.Text1` directly to keep the markup.
- Receivers with "only from promoted players" enabled ignore notes from senders who are not raid leader / assistant.
- Raid groups: `GMRT.A.RaidGroups:ApplyGroups(list)` (`RaidGroups.lua`) takes 40 names in raid-groups order (group 1
  slots 1-5, group 2 ...), the same order the UnityWiki export uses. It does nothing outside a raid, refuses (with
  its own chat error) while any raid member is in combat, matches names exactly (only a realm suffix is stripped),
  and moves people with `SetRaidSubgroup` / `SwapRaidSubgroup` over several `GROUP_ROSTER_UPDATE`s, swapping
  unplanned members aside when a group is full. In Classic it ignores positions inside a group unless its "keep
  position in group" option is on. `Modules/RaidGroups.lua` therefore checks raid / lead or assist / combat itself,
  passes the raid's own spelling of each planned name (matched case-insensitively, realm ignored:
  `Modules/GroupPlan.lua`), and watches the roster until the groups match or 15 s pass.
- Callbacks `Note_SendText`, `Note_ReceivedText` and `Note_UpdateText` fire through MRT's callback system.

Treat these as internals that can change with an MRT update: every MRT access lives in `Modules/MRT.lua`, guarded with
`type(...)` checks, and the user gets a clear message instead of a Lua error when the shape is different.

Source: `Interface/AddOns/MRT/Note.lua` (MRT 5335)

## 5. Pasting long strings

A raid plan export is up to ~60,000 characters. A multi-line edit box that holds that much text freezes the client
while it lays the text out. The import window caps the edit box with `SetMaxBytes(2500)` and collects the paste in
`OnChar`, which still fires for every pasted character, joining it on the next frame: the technique the import of
WeakAuras uses. The edit box is an AceGUI widget from a pool shared with other addons, so the window removes its
`OnChar` / `OnUpdate` scripts and the byte limit before releasing it.

Source: `UI/ImportWindow.lua`; the format of the export: UnityWiki `docs/addon-export.md`
