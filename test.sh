#!/usr/bin/env bash
# Smoke test: syntax, help, and the ship-apk config + mail paths in a throwaway HOME.
set -euo pipefail
cd "$(dirname "$0")"
bash -n ship-apk/ship-apk
bash -n ship-site/ship-site
bash -n developer-tools
bash -n homebrew/render
bash -n test-release.sh
bash ship-apk/ship-apk --help >/dev/null
bash ship-site/ship-site --help >/dev/null
bash developer-tools --help >/dev/null
[ "$(bash developer-tools --version)" = "developer-tools $(sed -n 's/^VERSION="\(.*\)"$/\1/p' ship-apk/ship-apk)" ]

export HOME; HOME="$(mktemp -d)"
source ship-apk/ship-apk
cfg proj_set demo app "Demo App"
cfg proj_set demo app_id "abc123"
cfg person_add demo "Sam" "sam@example.com"
cfg person_add demo "QA" "qa@example.com" bcc
[ "$(cfg proj_get demo app)" = "Demo App" ]
[ "$(cfg people demo | grep -c .)" = 1 ]
[ "$(stat -f '%Lp' "$HOME/.config/ship-apk/config.json")" = 600 ]
mail="$(send_mail demo "Demo App" "1.2.3" "https://appho.st/x" "- fixed login" yes)"
grep -q "To:      Sam <sam@example.com>" <<<"$mail"
grep -q "BCC:     qa@example.com" <<<"$mail"
grep -q "Subject: Demo App 1.2.3" <<<"$mail"
grep -q "fixed login" <<<"$mail"
grep -q $'^DRY\t2$' <<<"$mail"
cfg proj_del demo
[ -z "$(cfg projects)" ]

# ship-site config store, same throwaway HOME
( source ship-site/ship-site
  vc acct_set me scope azhar; vc acct_set me org_id u1; vc proj_set /tmp/x name demo
  [ "$(vc accounts)" = me ]; [ "$(vc proj_get /tmp/x name)" = demo ]
  [ "$(stat -f '%Lp' "$HOME/.config/ship-site/config.json")" = 600 ]
  vc acct_del me; [ -z "$(vc accounts)" ] )
rm -rf "$HOME"
echo "all good"
