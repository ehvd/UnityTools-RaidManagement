# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

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
  priorities, and the planned players are in the raid; its tooltip lists every check

[Unreleased]: https://github.com/ehvd/UnityTools-RaidManagement/commits/develop
