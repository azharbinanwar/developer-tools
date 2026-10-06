Homebrew formula templates for the `azharbinanwar/tap` tap.

The release workflow fills in `url`, `version` and `sha256` and pushes the result to `homebrew-tap/Formula/` automatically on every `v*` tag. Nothing to do by hand.

One-time setup: add a repository secret named `TAP_TOKEN` to this repo, a fine-grained GitHub token with **Contents: read and write** on the `homebrew-tap` repo.
