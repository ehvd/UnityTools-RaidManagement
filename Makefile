# UnityTools-RaidManagement development tasks. Run `make` for the list of targets.
#
# Needs GNU make plus a POSIX sh with git, cp, sed and awk (Git for Windows provides them).
# Personal settings (WoW location, luacheck path) go into the untracked local.mk, e.g.
#   WOW_DIR  = D:/Games/World of Warcraft
#   LUACHECK = C:/Users/me/bin/luacheck.exe
-include local.mk

ADDON     := UnityTools-RaidManagement
WOW_DIR   ?= C:/Program Files (x86)/Blizzard/World of Warcraft
ADDON_DIR ?= $(WOW_DIR)/_classic_era_/Interface/AddOns
LUACHECK  ?= luacheck
# make install LOCALE=deDE shows the addon in another language on any client (see Locales/)
LOCALE    ?=
VERSION   ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

DEST          := $(ADDON_DIR)/$(ADDON)
# Everything the game needs (no docs, CI files, tests)
INSTALL_FILES := $(ADDON).toc embeds.xml Core.lua LICENSE Locales Media Modules UI Libs

# PowerShell snippets (the path comes in through the T / S environment variables to survive spaces)
PS_EXIT_IF_LINK  = if ((Test-Path -LiteralPath $$env:T) -and ((Get-Item -LiteralPath $$env:T -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { exit 1 }
PS_EXIT_IF_EXIST = if (Test-Path -LiteralPath $$env:T) { exit 1 }
PS_MAKE_LINK     = New-Item -ItemType Junction -Path $$env:T -Target (Resolve-Path -LiteralPath $$env:S).Path | Out-Null
PS_REMOVE        = if (Test-Path -LiteralPath $$env:T) { $$i = Get-Item -LiteralPath $$env:T -Force; if ($$i.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($$i.FullName) } else { Remove-Item -LiteralPath $$i.FullName -Recurse -Force } }

.DEFAULT_GOAL := help
.PHONY: help libs lint locales install link uninstall description clean check-addon-dir

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "AddOns folder: $(ADDON_DIR)"

libs: Libs/.fetched ## Fetch the embedded libraries into Libs/ (needs git)

# Mirrors the externals of .pkgmeta from GitHub (the packager uses wowace SVN in CI).
# Keep the list of libraries in sync with .pkgmeta and embeds.xml; delete what the addon does not use.
Libs/.fetched: Makefile
	@echo "Fetching libraries into Libs/ ..."
	@rm -rf Libs .libs-tmp
	@mkdir -p Libs .libs-tmp
	@git clone --quiet --depth 1 https://github.com/WoWUIDev/Ace3.git .libs-tmp/ace3
	@for lib in LibStub CallbackHandler-1.0 AceAddon-3.0 AceDB-3.0 AceConsole-3.0 AceEvent-3.0 AceTimer-3.0 \
	           AceLocale-3.0 AceGUI-3.0; do \
	  cp -r ".libs-tmp/ace3/$$lib" "Libs/$$lib" || exit 1; \
	done
	@rm -rf .libs-tmp
	@touch $@
	@echo "Libraries written to Libs/"

lint: ## Run luacheck
	$(LUACHECK) .

check-addon-dir:
	@test -d "$(ADDON_DIR)" || { \
	  echo "AddOns folder not found: $(ADDON_DIR)"; \
	  echo "Set WOW_DIR (or ADDON_DIR) on the command line or in local.mk."; \
	  exit 1; }

install: libs check-addon-dir ## Copy the addon into the WoW AddOns folder
	@T="$(DEST)" powershell -NoProfile -Command '$(PS_EXIT_IF_LINK)' || { \
	  echo "$(DEST) is a link created by 'make link'. Run 'make uninstall' first."; exit 1; }
	@rm -rf "$(DEST)"
	@mkdir -p "$(DEST)"
	@cp -r $(INSTALL_FILES) "$(DEST)/"
	@sed -i "s/@project-version@/$(VERSION)/" "$(DEST)/$(ADDON).toc"
	@if [ -n "$(LOCALE)" ]; then \
	  echo 'UTRM_LOCALE_OVERRIDE = "$(LOCALE)"' > "$(DEST)/GameLocale.lua"; \
	  sed -i '/^embeds\.xml/i GameLocale.lua' "$(DEST)/$(ADDON).toc"; \
	  echo "Language override: $(LOCALE). Install again without LOCALE= to switch back."; \
	  fi
	@echo "Installed $(ADDON) $(VERSION) to $(DEST). Use /reload (or restart) in game."

link: libs check-addon-dir ## Junction the repo into AddOns for live development (/reload picks up edits)
	@T="$(DEST)" powershell -NoProfile -Command '$(PS_EXIT_IF_EXIST)' || { \
	  echo "$(DEST) already exists. Run 'make uninstall' first."; exit 1; }
	@T="$(DEST)" S="$(CURDIR)" powershell -NoProfile -Command '$(PS_MAKE_LINK)'
	@echo "Linked $(DEST) -> $(CURDIR). Use /reload in game after editing."

uninstall: check-addon-dir ## Remove the installed addon or the link (never touches the repo)
	@T="$(DEST)" powershell -NoProfile -Command '$(PS_REMOVE)'
	@echo "Removed $(DEST)"

description: ## Copy the CurseForge description (docs/curseforge.md) to the clipboard
	@powershell -NoProfile -Command 'Get-Content -Raw -Encoding UTF8 docs/curseforge.md | Set-Clipboard'
	@echo "Copied docs/curseforge.md to the clipboard. Paste it into the project description: https://authors.curseforge.com/#/projects/1766854/description"

clean: ## Remove the fetched libraries
	rm -rf Libs .libs-tmp

# Translation check. Locales/enUS.lua is the source, one entry per line:
#   L["English text"] = true   (enUS)   and   L["English text"] = "translation"   (other languages)
# Checks the translations in Locales/ against Locales/enUS.lua. Entries are `L["English text"] = "translation"`,
# one per line. Errors (exit status 1): a key that is not in enUS.lua, a duplicate, a different list of %s / %d
# format specifiers or of {placeholders}. Missing keys are only listed (make locales STRICT=1 fails on them too).
define CHECK_LOCALES
function specs(s,   out, i, c, rest, idx, n, max, k, arr) {
  n = 0; max = 0; i = 1
  while (i <= length(s)) {
    if (substr(s, i, 1) == "%") {
      if (substr(s, i + 1, 1) == "%") { i += 2; continue }
      rest = substr(s, i + 1)
      if (match(rest, /^[0-9]+\$$[sd]/)) {
        idx = substr(rest, 1, index(rest, "$$") - 1) + 0
        arr[idx] = substr(rest, RLENGTH, 1)
        if (idx > max) max = idx
        i += RLENGTH + 1
        continue
      } else if (match(rest, /^[sd]/)) {
        n++; arr[n] = substr(rest, 1, 1)
        if (n > max) max = n
        i += 2
        continue
      }
    }
    i++
  }
  out = ""
  for (k = 1; k <= max; k++) out = out (k > 1 ? "," : "") arr[k]
  return out
}
function braces(s,   out, n, i, j, tmp, arr) {
  n = 0
  while (match(s, /\{[a-z]+\}/)) { arr[++n] = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) }
  for (i = 2; i <= n; i++) { tmp = arr[i]; for (j = i - 1; j >= 1 && arr[j] > tmp; j--) arr[j + 1] = arr[j]; arr[j + 1] = tmp }
  out = ""
  for (i = 1; i <= n; i++) out = out arr[i] " "
  return out
}
FNR == 1 { if (FILENAME != base) { nfiles++; files[nfiles] = FILENAME } }
/^L\["/ {
  p = index($$0, "\"] = ")
  if (!p) next
  key = substr($$0, 4, p - 4)
  val = substr($$0, p + 5)
  if (FILENAME == base) { src[key] = 1; nsrc++; order[nsrc] = key; next }
  if ((FILENAME, key) in seen) { printf "ERROR %s: duplicate entry %s\n", FILENAME, key; errors++; next }
  seen[FILENAME, key] = 1
  count[FILENAME]++
  if (!(key in src)) { printf "ERROR %s: key not in enUS.lua: %s\n", FILENAME, key; errors++; next }
  if (key ~ /^[A-Z_]+$$/) next      # language specific defaults (phrase lists, templates): no source text to compare
  if (specs(key) != specs(val)) { printf "ERROR %s: format specifiers differ (%s vs %s): %s\n", FILENAME, specs(key), specs(val), key; errors++ }
  if (braces(key) != braces(val)) { printf "ERROR %s: {placeholders} differ (%s vs %s): %s\n", FILENAME, braces(key), braces(val), key; errors++ }
}
END {
  if (nfiles == 0) { print "No translations found next to enUS.lua"; exit 0 }
  for (f = 1; f <= nfiles; f++) {
    file = files[f]; miss = 0
    for (i = 1; i <= nsrc; i++) if (!((file, order[i]) in seen)) { miss++; if (miss <= 10) printf "  missing in %s: %s\n", file, order[i] }
    if (miss > 10) printf "  ... and %d more missing in %s\n", miss - 10, file
    printf "%s: %d of %d entries translated\n", file, count[file] + 0, nsrc
    missing += miss
  }
  if (errors > 0) { printf "%d error(s)\n", errors; exit 1 }
  if (strict == "1" && missing > 0) { printf "%d missing translation(s)\n", missing; exit 1 }
}
endef
export CHECK_LOCALES

locales: ## Check the translations in Locales/ against enUS.lua (STRICT=1 also fails on missing ones)
	@awk -v base=Locales/enUS.lua -v strict="$(STRICT)" "$$CHECK_LOCALES" Locales/enUS.lua $(filter-out Locales/enUS.lua,$(wildcard Locales/*.lua))
	@# Every L["..."] used by the code must exist in enUS.lua (AceLocale raises an error for missing keys)
	@grep -rhoE 'L\["([^"\]|\.)*"\]' --include=*.lua $(wildcard Core.lua Modules UI) | sed -E 's/^L\["//; s/"\]$$//' | sort -u > .used-keys.tmp
	@grep -hoE '^L\["([^"\]|\.)*"\]' Locales/enUS.lua | sed -E 's/^L\["//; s/"\]$$//' | sort -u > .defined-keys.tmp
	@missing=$$(comm -23 .used-keys.tmp .defined-keys.tmp); rm -f .used-keys.tmp .defined-keys.tmp; \
	if [ -n "$$missing" ]; then echo "Keys used in code but missing from Locales/enUS.lua:"; echo "$$missing" | sed 's/^/  /'; exit 1; fi
