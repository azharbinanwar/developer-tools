# developer-tools

[![test](https://github.com/azharbinanwar/developer-tools/actions/workflows/test.yml/badge.svg)](https://github.com/azharbinanwar/developer-tools/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Small terminal tools for macOS, Linux and Windows (Git Bash or WSL). Each one is a single file with no dependencies beyond what it drives. Use them one by one, or through the `developer-tools` hub that runs, installs and updates all of them from one menu.

| Tool | What it does | Needs |
| --- | --- | --- |
| [ship-apk](ship-apk/README.md) | Build a Flutter APK, upload it to appho.st, mail the link to testers | flutter or fvm |
| [ship-site](ship-site/README.md) | Build a web app, publish it to Vercel or Firebase Hosting, copy the link | node, plus the Vercel or Firebase CLI |

---

## 1. Try it, nothing installed

Open Terminal in your project folder and paste the line for the tool you want, or the hub to pick from a menu:

```sh
# ship-apk, inside a Flutter project
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-apk/ship-apk)

# ship-site, inside a web project
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-site/ship-site)

# the hub, from anywhere
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/developer-tools)
```

Nothing lands on your Mac except your settings (see [Where settings live](#where-settings-live)). You always get the newest code.

Not sure yet? Add `--dry-run` (or `-n`) to either tool. It walks the whole flow, checks your setup, shows exactly what it would build, upload, mail or deploy, and changes nothing.

---

## 2. Install it

After installing you just type `ship-apk` or `ship-site` from any folder.

### Option A: the hub

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/developer-tools)
```

```
◆  developer-tools

  ▸ What do you want to do
     ↑↓ move · Enter picks · q quits
   ❯ run a tool            without installing anything
     install or update     put tools in /usr/local/bin
     remove                take tools out of /usr/local/bin
     quit
```

**Run a tool** lists them and runs the one you pick, fetching the latest release if it is not installed. **Install or update** shows every tool ticked: press Enter for all, or untick with space first. It also installs the hub itself, so `developer-tools` works from then on. **Remove** works the same way. Or install the hub with Homebrew:

```sh
brew trust azharbinanwar/tap                        # once, Homebrew 7 asks this of every third-party tap
brew install azharbinanwar/tap/developer-tools      # hub plus every tool
```

### Option B: Homebrew, one tool

```sh
brew trust azharbinanwar/tap                        # once
brew install azharbinanwar/tap/ship-apk
brew install azharbinanwar/tap/ship-site
```

`brew upgrade` updates, `brew uninstall` removes.

### Option C: one tool, one line

```sh
sudo curl -fsSL https://github.com/azharbinanwar/developer-tools/releases/latest/download/ship-apk -o /usr/local/bin/ship-apk && sudo chmod +x /usr/local/bin/ship-apk
```

Swap `ship-apk` for `ship-site` to get the other one. Run again to update, `sudo rm /usr/local/bin/ship-apk` to remove.

### Beta channel

New versions go out as a beta first, for anyone who wants them early. Stable users never see a beta: the one-liners, the hub and Homebrew keep serving the latest stable release until the beta becomes one.

One command installs the newest beta of every tool and switches this Mac to the beta channel:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/developer-tools) beta install
```

From then on `developer-tools install` keeps you on the newest beta. Back to stable, any time:

```sh
developer-tools stable install
```

`ship-site -v` shows a beta as `2.0.0-beta.6`. The tools are the same files on both channels; only which release you get differs.

### Which one?

All three install the same files. Want everything: the hub. Want one tool: Homebrew or the one-liner. Each tool works on its own, the hub is a convenience.

---

## Keys

Every menu works the same in all three tools:

| Key | Does |
| --- | --- |
| `↑` `↓` | move |
| `Enter` | pick the highlighted option |
| a letter shown as `[m]` | pick that option straight away |
| `1`–`9` | pick an app or project by its place on screen |
| `Esc` | back |
| `q` | quit |
| `y` | confirm sending mail or publishing to the main website when you picked it with a single key |

The same option keeps the same key, so a run becomes a short sequence you remember, like `Enter` `m` `p` in ship-site. Each tool's README lists its keys.

**Set your own** in `~/.config/developer-tools/keys.json`, shared by all three tools:

```json
{ "site.main": "w", "mail.skip": "z" }
```

A key that is already used on the same screen is refused with a warning, and the default stays.

---

## Platforms

| | macOS | Linux | Windows |
| --- | --- | --- | --- |
| runs in | Terminal | any terminal | Git Bash, or WSL |
| needs | bash, python3, curl (all built in) | bash, python3, curl | Git for Windows (bash, curl) and Python |
| copies the link with | `pbcopy` | `wl-copy`, `xclip` or `xsel`, whichever is installed | `clip.exe` |
| opens links and folders with | `open` | `xdg-open` | `cmd.exe /c start`, or `wslview` under WSL |
| install folder | `/usr/local/bin` | `/usr/local/bin` (asks for sudo once) | `~/bin` |

The test suite runs on macOS and Linux in GitHub Actions on every push.

---

## Where settings live

| Tool | Settings |
| --- | --- |
| ship-apk | `~/.config/ship-apk/config.json` plus build and send logs in `logs/` |
| ship-site | `~/.config/ship-site/config.json` plus each Vercel account's sign-in in `accounts/`; Firebase sign-ins stay in the Firebase CLI |
| your keys | `~/.config/developer-tools/keys.json`, shared by all three tools |

Trying it online and installing it share the same settings, so you can start one way and switch later. The only thing either tool changes in your project is the version (`pubspec.yaml` or `package.json`), and only when you pick **bump**. Credentials are stored with mode 0600; keep that folder private.

---

## Test

```sh
./test.sh
```

Syntax-checks every script, drives the menus with fed keystrokes, and exercises the config stores, mail rendering, version bumps and dry runs in a throwaway home folder. The same test runs in GitHub Actions on every push.

## Releases

Rehearse first, on your Mac, with no tag and nothing pushed:

```sh
./test-release.sh
```

It renders the Homebrew formulas from the local scripts, really installs them with `brew`, checks `--version`, uninstalls, and with `TAP_TOKEN` exported also proves the token can push to the tap. Then:

1. Bump `VERSION` in all three scripts and commit.
2. Beta first: `git tag v2.0.0-beta.1 && git push origin v2.0.0-beta.1`. It is published as a pre-release, which only the beta channel picks up.
3. When it is right: `git tag v2.0.0 && git push origin v2.0.0`. Everyone gets it.

The release workflow runs the tests, refuses a tag that does not match `VERSION`, attaches the three scripts, writes the release notes from the commits since the last tag, and, for stable tags only, pushes updated formulas to the Homebrew tap. The full runbook is in [RELEASE.md](RELEASE.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the rules and the repo layout, and [RELEASE.md](RELEASE.md) for how a release is cut.

## License

MIT. See [LICENSE](LICENSE).
