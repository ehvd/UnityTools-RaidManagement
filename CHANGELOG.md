# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Export, a new section of the Raid Plan window, gives the raid plan as one string, selected for Ctrl+C, to import
  on another client or bring back to the UnityWiki raid planner. It is the planner's own export format (protocol 2),
  with the plan as edited in game: hand-edited notes, current assignments, edited groups, and the classes of people
  added in game when the raid roster shows them. The active encounter, the fallback note and the edit history are
  not in it yet

## [0.2.0] - 2026-11-01

### Added

- The Raid Plan window edits everything about the raid plan in one place: a list of sections on the left (Groups,
  Assignments, Notes, Gargul, Config, Import) and the section on the right. Groups, Assignments and Notes have their
  own encounter dropdown, which only picks what is edited: the active encounter changes in the plan window alone.
  Each section saves on its own; leaving a section or its encounter with unsaved changes asks first, the list marks
  such a section with *, and closing the window keeps them. Open it from the plan window's ⚙ menu (Open Raid Plan),
  the minimap button's menu or `/utrm edit`; the plan window's Import button and `/utrm import` open its Import
  section
- Clear raid plan (the Raid Plan window's Import section) removes the imported plan after a confirmation; it clears
  only your copy, and a raid leader's or assistant's plan may sync back
- The import reads export protocol 2 of the UnityWiki raid planner (note templates with assignment slots, the
  bosses' encounter IDs, the people's classes) next to protocol 1, and can rebuild a note from its template; a
  template with an unknown slot fails the import as damaged
- Notes (the Raid Plan window) changes an encounter's note in game: Save keeps it in the plan (and sends it to Method
  Raid Tools when the encounter is active), Reset to the plan's note brings back the imported one. Edited notes sync
  like other plan edits and are marked with a note icon
- Groups (the Raid Plan window) edits the night's groups or an encounter's (a dropdown, opening on the active
  encounter): click a player, then a slot, another player or a list (or drag) to move, swap or take them out; fill
  slots from the raid members not in the groups or from the bench (the plan's people who are neither in the groups
  nor in the raid). Names are in class colours, also outside a raid; planned players who are not in the
  raid are marked. An encounter on the night's groups shows them read-only until Create override gives it its own
  groups; Delete override (after a confirmation) puts it back on the night's groups. Every change is a plan edit
  that syncs, and saving the active encounter's groups sorts the raid
- Assignments (the Raid Plan window) changes who fills an encounter's assignments: the slots come in the note's
  order with the same kind together (all tanks, then all healers), and each slot's menu lists the planner's
  candidates alphabetically in class colours with their role and marks who is not in the raid; custom assignments
  take several people. A scrollable preview shows the rebuilt note with Method Raid Tools' icons, as one person sees
  it (their blocks for players, classes and their planned group) or only what everyone sees; Save is a plan edit
  that syncs, and the note goes to Method Raid Tools when the encounter is active. Protocol 1 plans and hand-edited
  notes say what to do instead
- Fallback note after a boss kill: choose an encounter in the plan window's ⚙ menu (After a kill ▸) or the Raid Plan
  window's Config section, for example the night's trash note. When a boss of the plan dies, the raid leader's
  client makes it active as if chosen in the window (note sent, groups sorted after combat, the raid follows). Not
  after a wipe; with a protocol 1 plan any kill switches. The choice is a plan edit and syncs to the raid

### Changed

- The plan window's ⚙ menu is short again: Open Raid Plan, After a kill ▸, Lock position, Scale, Close (they are
  also in Config). The minimap button's menu has Open Raid Plan and Open mini window; hiding the button moved to
  Config, the free raid note editor stays on `/utrm note`. The import window, Gargul and Force sync moved into the
  Raid Plan window
- Raid plan edits are revisions: an edit by the raid leader or an assistant reaches the raid like a newer import,
  a member's edit stays on their client; the Import section shows who edited the plan and when. The sync version
  goes to 2, so 0.1.0 and 0.2.0 clients ignore each other's sync (update everybody)

## [0.1.0] - 2026-10-26

### Added

- Addon skeleton: Ace3 core, `/utrm` slash command, localization (enUS, deDE, frFR, esES, itIT)
- Releases are uploaded to [CurseForge](https://www.curseforge.com/wow/addons/unity-tools-raid-management)
- Addon icon in the addon list and CurseForge logo (the Unity logo)
- Raid note editor (`/utrm note`) that sends the note to Method Raid Tools, and `/utrm note <text>` for macros
- Import the night's raid plan exported from the UnityWiki raid planner (`/utrm import`, protocol 1)
- Raid plan window (`/utrm plan`): pick the active encounter (previous, next or from the list) to send its note to
  Method Raid Tools; movable, resizable in width, lockable and scalable from its options button
- Activating an encounter also sorts the raid into its planned groups (with Method Raid Tools' sorter); the status
  line says when they match and its tooltip names who is missing or not in the plan
- Import the plan's loot priorities into Gargul from the raid plan window's options; the menu shows whether Gargul
  still has them
- Raid readiness icon in the raid plan window: Master Loot on, Method Raid Tools loaded, Gargul has the plan's loot
  priorities, the planned players are in the raid and in their groups; its tooltip lists every check, and a click
  offers the fixes (set Master Loot, import into Gargul, invite the missing players, sort the groups)
- Raid plan sync from the raid leader and assistants: the most recently chosen plan and the active encounter
  reach everybody in the raid (only lead and assists are sources); Force sync (options) sends yours to all, each
  recipient confirms
- Minimap button: left click shows or hides the raid plan window, right click opens the options (import, Gargul,
  Force sync, note editor, hide the button); `/utrm minimap` shows or hides it

[Unreleased]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.2.0...develop
[0.2.0]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ehvd/UnityTools-RaidManagement/releases/tag/v0.1.0
