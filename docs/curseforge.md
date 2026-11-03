<!-- CurseForge project page. Paste the "Description" section into the project description editor (make description
copies just that section). Keep "## Description" the last section: it runs to the end of the file. -->

## Project settings

| Field | Value |
|---|---|
| Name | Unity Tools - Raid Management |
| Game / version | World of Warcraft, Classic (1.15.x) |
| Main category | **Guild** |
| Additional categories | Boss Encounters, Chat & Communication |
| Logo | `icon.png` (400x400) |
| License | MIT |
| Source / issues | https://github.com/ehvd/UnityTools-RaidManagement |

## Summary (max 250 characters)

Raid leader toolkit for WoW Classic Era: organise your raid and post raid notes to Method Raid Tools from one place.

## Description

# Unity Tools - Raid Management

Raid management tools for raid leaders and officers: the night's raid plan, Method Raid Tools notes, raid groups,
Gargul loot priorities and readiness checks, from one small window.

Works with [Method Raid Tools](https://www.curseforge.com/wow/addons/method-raid-tools) (notes and raid groups) and
[Gargul](https://www.curseforge.com/wow/addons/gargul) (loot priorities); both are optional.

## Features

- Make the night's raid plan in game: pick the raids, and every boss comes in kill order with the raid's current
  groups. Or import a raid plan string
- Switch the Method Raid Tools note with one click per encounter, from a small window (`/utrm plan`); the raid is
  sorted into the planned groups at the same time
- Change the whole plan in game in one Raid Plan window (`/utrm edit`):
  - the encounters: add a boss or your own entry, rename, reorder, remove
  - the groups: one layout for the whole night, or layouts shared by several encounters (say one for Molten Core);
    add players by name and class, take them out again
  - the assignments: a default for the night, with exceptions per encounter shown in colour
  - each encounter's note (and back to the plan's note with one click), and the note after a boss kill
- After a boss kill, the note switches by itself to the one you chose (for example the night's trash note)
- Export the plan as one string, to give it to another raid leader or keep a copy, and export who is really in the
  raid and their groups (`/utrm roster`), to match signup names with the raid's characters
- Loads loot priorities into [Gargul](https://www.curseforge.com/wow/addons/gargul) with one click (paste a Gargul
  import string into the plan) and shows whether Gargul has the current ones
- A readiness icon: Master Loot on, the planned players in the raid, Method Raid Tools and Gargul ready
- The raid leader and assistants share the plan and the active encounter with the whole raid automatically
- A minimap button for the Raid Plan window and the small plan window
- Write the raid note and send it to [Method Raid Tools](https://www.curseforge.com/wow/addons/method-raid-tools)
  (`/utrm note`), or send a one-line note from a macro (`/utrm note {rt1} Tanks on the left\nHealers in the middle`)
- Available in English, German, French, Spanish and Italian

## Links

- Source and bug reports: https://github.com/ehvd/UnityTools-RaidManagement
