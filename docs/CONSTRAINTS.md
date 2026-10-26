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
- Callbacks `Note_SendText`, `Note_ReceivedText` and `Note_UpdateText` fire through MRT's callback system.

Treat these as internals that can change with an MRT update: every MRT access lives in `Modules/MRT.lua`, guarded with
`type(...)` checks, and the user gets a clear message instead of a Lua error when the shape is different.

Source: `Interface/AddOns/MRT/Note.lua` (MRT 5335)
