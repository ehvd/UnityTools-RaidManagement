# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/ehvd/UnityTools-RaidManagement/compare/v0.1.0...develop
[0.1.0]: https://github.com/ehvd/UnityTools-RaidManagement/releases/tag/v0.1.0
