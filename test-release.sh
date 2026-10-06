#!/usr/bin/env bash
# Rehearse a release on this Mac, no tag, no GitHub:
#   1. the version check the workflow does
#   2. render the Homebrew formulas exactly as the workflow will, from local files
#   3. brew install them from those files, check --version, brew uninstall
#   4. if TAP_TOKEN is set, prove it can push to homebrew-tap (dry run, nothing pushed)
set -euo pipefail
cd "$(dirname "$0")"
./test.sh

v="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' ship-apk/ship-apk)"
for f in ship-site/ship-site developer-tools; do [ "$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$f")" = "$v" ] || { echo "VERSION in $f differs from ship-apk"; exit 1; }; done
echo "version $v"

rel="$(mktemp -d)"; trap 'rm -rf "$rel"; brew untap -q azharbinanwar/rehearsal 2>/dev/null' EXIT
mkdir -p "$rel/assets"; cp ship-apk/ship-apk ship-site/ship-site developer-tools "$rel/assets/"
homebrew/render "$v" "file://$rel/assets" "$rel/Formula"
grep -q "sha256 \"$(shasum -a 256 ship-apk/ship-apk | cut -d' ' -f1)\"" "$rel/Formula/ship-apk.rb"
grep -q "version \"$v\"" "$rel/Formula/ship-site.rb"
echo "formulas render"

if command -v brew >/dev/null; then
  # brew only installs from a tap, so make a throwaway one and drop the formulas in
  tap="azharbinanwar/rehearsal"
  brew untap -q "$tap" 2>/dev/null || true
  brew tap-new -q --no-git "$tap" >/dev/null
  cp "$rel"/Formula/*.rb "$(brew --repository "$tap")/Formula/"
  for t in ship-apk ship-site developer-tools; do
    brew uninstall --formula -q "$t" >/dev/null 2>&1 || true
    sed -i "" "s#azharbinanwar/tap/#$tap/#" "$(brew --repository "$tap")/Formula/developer-tools.rb"
    brew install -q "$tap/$t" >/dev/null || { echo "brew could not install $t — read the error above (outdated Command Line Tools is the usual cause: softwareupdate --install -a)"; exit 1; }
    [ "$("$(brew --prefix)/bin/$t" --version)" = "$t $v" ]
    brew test -q "$tap/$t" >/dev/null
    echo "brew install $t works"
  done
  brew uninstall --formula -q developer-tools ship-apk ship-site >/dev/null
else
  echo "no brew here, skipped the install"
fi

if [ -n "${TAP_TOKEN:-}" ]; then
  git clone -q "https://x-access-token:$TAP_TOKEN@github.com/azharbinanwar/homebrew-tap" "$rel/tap"
  ( cd "$rel/tap" && cp ../Formula/*.rb Formula/ && git add Formula && git -c user.name=t -c user.email=t@t commit -qm test && git push --dry-run -q origin HEAD )
  echo "TAP_TOKEN can push to homebrew-tap"
else
  echo "TAP_TOKEN not set, skipped the push check (export TAP_TOKEN=... to include it)"
fi
echo "release rehearsal passed"
