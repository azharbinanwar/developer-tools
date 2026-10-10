# Contributing

Bug reports and fixes are welcome. A few rules keep the one-liners working.

## The rules

- **One file per tool.** `bash <(curl …)` only works because each tool is a single script. No helper files, no imports, no `lib/`.
- **No dependencies beyond what the tool drives.** bash 3.2+, python3 and curl, plus flutter for ship-apk, node and the Vercel or Firebase CLI for ship-site. If you need something else, the script asks the user before installing it, never silently.
- **Stay portable.** macOS, Linux and Windows (Git Bash or WSL) all run these. Anything that differs between them goes through the platform helpers in `lib/platform.sh` (`clip`, `open_it`, `edit_file`, `fsize`, `fmtime`, `fmode`, `fdate`, `sed_i`, `tmpf`, `tmpd`, `py`); never call `pbcopy`, `open`, `stat -f`, `sed -i ''` or `mktemp -t` directly. CI runs the suite on macOS and Linux.
- **Settings go in `~/.config/<tool>/`**, never next to the script and never in the user's project.
- **Ask before anything irreversible.** Uploads, emails, production deploys and installs all confirm first unless a flag like `--prod` says otherwise.
- **Short over clever.** If a feature can be covered by the thing we drive (the Vercel dashboard, Finder, an editor), leave it out and say so in the README.

## How the repo is laid out

```
lib/platform.sh             macOS, Linux, Windows: clipboard, opener, stat, sed, temp files
lib/ui.sh                   colours, step/row/ok/warn/die, the arrow-key menu, prompts
lib/keys.sh                 the shortcut-key engine and keys.json overrides
lib/mail.sh                 mailbox setup, recipients, template, SMTP send
lib/firebase.sh             Firebase Hosting: CLI logins, sites, deploys, custom domains
lib/vercel.sh               Vercel: accounts, projects, deploys
ship-apk/main.sh            the ship-apk flow; its first line names the lib parts it needs
ship-site/main.sh           the ship-site flow
hub/main.sh                 the hub: menu to run, install, update or remove tools
build                       glues lib parts + main.sh into the one file per tool below
ship-apk/ship-apk           built — what is released, run online and installed    ship-apk/README.md
ship-site/ship-site         built                                                 ship-site/README.md
developer-tools             built
test.sh                     smoke test, runs in CI on every push; checks the built files are current
test-release.sh             release rehearsal, runs on a maintainer's Mac before tagging
homebrew/<tool>.rb          formula templates, filled in by homebrew/render on release
.github/workflows/test.yml  runs test.sh
.github/workflows/release.yml  on a v* tag: test, GitHub release, push formulas to the tap
RELEASE.md                  the maintainer's release runbook
```

## Making a change

1. Fork and branch.
2. Edit `lib/*.sh` or the tool's `main.sh`, never the built file. Keep the existing look: `step`, `row`, `ok`, `warn`, `die` helpers and the arrow-key menus. Something two tools need goes in `lib/`.
3. Run `./build`, then `./test.sh`. Add a line to it if your change touches the config store or mail rendering.
4. Try it for real in a project. The smoke test cannot build a Flutter app or deploy to Vercel.
5. Open a pull request. Say what a user will notice, that sentence becomes the release note.

## How a release works

You do not need this to contribute, it is here so the pipeline is not a mystery.

1. A maintainer bumps `VERSION` in the three `main.sh` files, runs `./build` and `./test-release.sh`, which installs the tools through a throwaway Homebrew tap on their Mac to prove the formulas are right.
2. They push a beta tag like `v1.2.0-beta.1`. It is published as a pre-release that only Macs on the beta channel (`developer-tools beta`) pick up; stable users and Homebrew are untouched. Once it holds up, the plain tag `v1.2.0` goes out to everyone.
3. The `release` workflow runs `test.sh`, refuses the tag if it does not match `VERSION`, creates the GitHub release with the three scripts attached, and generates the notes from commit titles since the previous tag, one bullet per commit.
4. A second job renders the Homebrew formulas with the release sha256 and pushes them to `azharbinanwar/homebrew-tap`, using a repo secret with write access to that tap.
5. `brew upgrade`, the install one-liner and the picker all pick up the new version from `releases/latest`. The try-it-online line always serves `main`.

Details for maintainers are in [RELEASE.md](RELEASE.md).

## Adding a tool

A new folder with the script and a README, plus its name in: the README table, `developer-tools` (name and one-line note), `homebrew/` (a template, and a `depends_on` line in `developer-tools.rb`), `homebrew/render`, `test-release.sh`, and the version check in `release.yml`. All greppable by an existing tool's name.
