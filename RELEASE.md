# Release runbook

When the user says "help me release", follow this top to bottom. Everything here can be run by the assistant except pasting a token.

Key facts:
- Releases live on this repo: https://github.com/azharbinanwar/developer-tools/releases
- Homebrew tap: `azharbinanwar/homebrew-tap`, formulas under `Formula/`, updated by the release workflow
- Install links point at `releases/latest`, so between tags the previous release keeps serving
- All three scripts (`ship-apk`, `ship-site`, `developer-tools`) must carry the same `VERSION`; the workflow refuses a tag that does not match

## 1. Decide the version

Patch for fixes, minor for a new option or tool, major if settings or flags change in a way that breaks a user. First release is `1.0.0`.

## 2. Bump

`VERSION="X.Y.Z"` in `ship-apk/ship-apk`, `ship-site/ship-site` and `developer-tools`. Update the example tag in README.md if it still shows an older number.

## 3. Rehearse on this Mac

```sh
./test-release.sh
```

It runs `test.sh`, checks all versions match, renders the formulas from the local scripts, installs them through a throwaway tap, checks `--version`, uninstalls. Fix anything red before going on. If brew complains about Command Line Tools, run `softwareupdate --install -a` and retry.

## 4. Commit and push

Commit title should say what changed for users, it becomes the release notes. `/git-ops:commit-and-push`.

## 5. Tag

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

The release workflow then: tests, checks the tag, publishes the GitHub release with `ship-apk`, `ship-site` and `developer-tools` attached, writes the notes from commit titles since the previous tag (so write titles a user would want to read), and pushes the filled-in formulas to the tap.

## 6. Verify

```sh
gh run watch --repo azharbinanwar/developer-tools
curl -sIL -o /dev/null -w "%{http_code}\n" https://github.com/azharbinanwar/developer-tools/releases/latest/download/ship-apk   # 200
brew update && brew info azharbinanwar/tap/ship-apk | head -1                                                                   # shows X.Y.Z
```

On a machine with it installed: `brew upgrade ship-apk`, or run the install one-liner again.

## One-time setup (already done)

- Repo secret `TAP_TOKEN`: a fine-grained token with Contents read and write on `homebrew-tap`. The release workflow uses it to push formulas.

## Notes

- A failed release workflow leaves no half state: the GitHub release is only created after the tests and version check pass, and the tap push is a separate job that can be re-run from the Actions tab.
- Deleting a release: `gh release delete vX.Y.Z --yes --cleanup-tag`. `releases/latest` then falls back to the previous one, so installs keep working.
- Adding a tool: new folder with the script, a line in the README table, its name and note in `developer-tools`, a `depends_on` in `homebrew/developer-tools.rb`, a template in `homebrew/`, and its name in `homebrew/render`, `test-release.sh` and the release workflow's version check.
