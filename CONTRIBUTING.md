# Contributing

## Git flow

| Branch | Purpose |
|---|---|
| `main` | Released code only. Every commit on `main` is a tagged release. |
| `develop` | Integration branch (GitHub default). |
| `feature/<issue>-<slug>` | From `develop`, merged back via PR. |
| `release/x.y.z` | From `develop`; merged to `main`, tagged `vx.y.z`, merged back to `develop`. |
| `hotfix/x.y.z` | From `main`; same as release. |

With the `git flow` CLI (`git flow init -d` has been run on the project):

```bash
git flow feature start 12-mrt-notes             # branch feature/12-mrt-notes
git push -u origin feature/12-mrt-notes         # open a PR into develop

git flow release start 0.1.0
# bump CHANGELOG.md, then:
git flow release finish -m "v0.1.0" 0.1.0        # merges to main, tags v0.1.0, merges back
git push origin main develop --tags
```

Without the CLI: `git checkout -b feature/12-x develop`; for releases
`git checkout -b release/0.1.0 develop`, then merge `--no-ff` into `main`, tag `v0.1.0`,
and merge `--no-ff` back into `develop`.

`main` and `develop` are protected: changes go through a PR with passing CI. No force pushes.

## Rules

- One issue → one feature branch → one PR into `develop` with `Closes #N`.
- Update `[Unreleased]` in `CHANGELOG.md` in every PR.
- `make lint` (`luacheck .`) and `make test` must pass locally before pushing; `make install` or `make link` put the addon into your AddOns folder (see the README).
- Never commit `Libs/` or any secret.

## Commit conventions

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`;
optional scope, e.g. `feat(notes): post a note to Method Raid Tools`. PRs are squash-merged with the title
`feat(scope): ... (#issue) (#pr)`.

## Release tags

`v1.2.3` → release, `v1.2.3-beta.1` → beta, `v1.2.3-alpha.1` → alpha (CurseForge + GitHub Release).

## Releasing

1. Cut `release/x.y.z` from `develop`: turn `[Unreleased]` in `CHANGELOG.md` into a dated section and fix the compare links at the bottom.
2. PR into `develop`, wait for the `luacheck` check, squash-merge.
3. Fast-forward `main` to the merged `develop` commit and tag `vx.y.z`; the Release workflow uploads the file to CurseForge and GitHub.
4. Review `docs/curseforge.md` (the CurseForge project description) in the release PR. CurseForge has no API to edit a description, so it cannot be published automatically.
5. For full releases the workflow attaches the description as `curseforge-description.md` to the GitHub release and prints it in the job summary. If `docs/curseforge.md` changed since the previous release it opens an issue assigned to the repository owner (older open reminders are closed as superseded).
6. Paste it into the [project description editor on CurseForge](https://authors.curseforge.com/#/projects/1766854/description): run `make description` (clipboard) or copy it from the issue, then close the issue.

## In-game testing

Nobody can run the game in CI: every PR lists the in-game checks it needs (`make link` once, then `/reload` after each
change; install [BugSack](https://www.curseforge.com/wow/addons/bugsack) to see Lua errors).

## Translations

Every user-visible string goes through `L["English text"]` (AceLocale); `Locales/enUS.lua` lists them all and the other languages (`frFR`, `deDE`, `esES`, `itIT`) are one file each with `L["English text"] = "translation"`, one entry per line. Keep `%s` / `%d` in the same order (or use `%1$s`) and keep the `{name}` style placeholders unchanged. Strings left out fall back to English.

- `make locales` lists missing entries and fails on broken `%s` / `{placeholders}`, entries that are not in `enUS.lua` and duplicates (CI runs it; add `STRICT=1` to fail on missing entries too)
- `make install LOCALE=deDE` installs with a language override so a translation can be checked on any client
- Defaults that depend on the language are `DEFAULT_*` keys (upper case); `make locales` does not compare their placeholders
- Text the addon sends to chat must stay under 255 bytes in every language (accented letters take two bytes)
