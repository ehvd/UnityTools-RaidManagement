# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-11-03

### Added

- New plan (its own section of the Raid Plan window, also opened by the plan window's New plan button when no plan is
  loaded) makes a raid plan in game without the UnityWiki planner: a title (the raids and today's date unless you type
  one) and one or more raids. The plan has, per raid, Trash and then the bosses in kill order with their encounter
  IDs, empty notes, and the raid as it is arranged now as the night's groups (empty outside a raid). It replaces the
  current plan after the same confirmation as an import, and syncs like one. The bosses come from a built-in table
  that mirrors UnityWiki's (fights with several bosses, such as the Bug Trio, are one encounter); Assignments says
  such a plan's notes have no assignment slots
- Encounters (the Raid Plan window) changes the plan's encounter list in game. It lists every encounter in plan order:
  rename one in its row (the label only: the sync and the note after a kill still match), move it up or down with the
  arrow buttons, or remove it after a confirmation. Below the list, add a boss from the built-in boss table (it sets
  the label and encounter ID) or a custom encounter with only a name; it starts with an empty note on the night's
  groups. Removing the active encounter makes the next one active, removing the note after a kill sets that back to
  none, and an encounter's own groups go with it when no other encounter uses them. Every change syncs to the raid
  like other plan edits
- Groups (the Raid Plan window) shares one group layout between several encounters. The dropdown lists the layouts
  first: Default (the night's groups, before "Night's groups") and every named layout such as "MC Default", each with
  how many encounters use it; below them the encounters, each with its layout on the right (overrides highlighted). A
  named layout's groups are edited for every encounter on it; Delete override removes it after a confirmation naming
  its encounters, which go back to Default (Default can't be deleted). An encounter picks the layout it uses in its
  Groups box, or gets a new one with New override (a name, starting as a copy of its current layout); its groups are
  its layout's, and editing them edits that layout. All of it is part of the section's unsaved changes (Save / Undo
  changes) and syncs like other group edits; Save sorts the raid when the active encounter's groups changed
- Groups (the Raid Plan window) adds players to the raid plan by hand: type a name, choose the class and Add, and the
  player is on the bench in their class colour, from where they go into a group like anyone else. A name already in
  the plan or the raid, or an empty one, is refused with a message. The × on a bench player takes them out of the plan
  and out of every group layout, after a confirmation when other encounters' groups or assignments use them
  (assignments stay as they are). Both are part of the section's unsaved changes: Save stores them (and syncs them
  like other group edits), Undo changes drops them
- Default assignments: Default, at the top of the Assignments section's Encounter dropdown, changes a job (TANK1,
  HEALER1 …) on every encounter that follows the default and rebuilds their notes. On an encounter, a job with other
  players than the default is an override: its name is cyan, its menu has Use default, and the Encounter dropdown
  shows how many overrides each encounter has. An imported plan takes each job's most common players as its default,
  so its exceptions show as overrides at once. The defaults are kept in the plan and sync with it; the export still
  writes each encounter's own players
- The Raid Plan window's Gargul section has a Paste string box: Save puts a Gargul import string (loot priorities from
  anywhere that makes one) into the plan, replacing the imported one or giving a plan without one its own. It syncs
  like other edits; Import into Gargul and the readiness check then use it. A string Gargul's importer would not take,
  or one that imports nothing, is refused with a message before saving
- Export, a new section of the Raid Plan window, gives the raid plan as one string, selected for Ctrl+C, to import on
  another client or bring back to the UnityWiki raid planner. It is the planner's own export format (protocol 2), with
  the plan as edited in game: hand-edited notes, current assignments, edited groups, and the classes of people added
  in game when the raid roster shows them. The active encounter, the fallback note and the edit history are not in it
  yet
- Export raid (a button in Groups of the Raid Plan window, or `/utrm roster`) gives the raid's members and groups as
  one string, selected for Ctrl+C, for pasting into a raid planner: it matches the plan's names (from the signups)
  with the characters really in the raid. Each member goes with their realm, class, level, group, rank, whether they
  are online and their zone (UnityWiki's roster protocol 1). It works without a plan; outside a raid the dialog says
  so, and Refresh makes the string again

### Changed

- The addon's texts no longer name UnityWiki or its raid planner: the import asks for a raid plan string, and an
  encounter whose note has no assignment slots says to write the names in the note
- Groups no longer shows the info line and the hint above the groups, and an encounter's groups are never read-only:
  the window is 46 px shorter

### Fixed

- The Raid Plan window's Notes section: the note box fills the section instead of leaving empty space under it

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

[Unreleased]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.3.0...develop
[0.3.0]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ehvd/UnityTools-RaidManagement/releases/tag/v0.1.0
