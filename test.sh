#!/usr/bin/env bash
# Tests for everything that runs without a terminal, a Flutter SDK or a Vercel login.
# Menus are driven by feeding keystrokes on stdin. Runs in CI on every push.
set -euo pipefail
cd "$(dirname "$0")"
check(){ # $1 name, then a command; one line per check, stops at the first failure
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s\n' "$name"; "$@" || true; exit 1; fi
}
is(){ [ "$1" = "$2" ] || { printf '    got:  %s\n    want: %s\n' "$1" "$2"; return 1; }; }
not(){ ! "$@"; }
in_dir(){ local d="$1"; shift; ( cd "$d" && "$@" ); }
up=$'\e[A'; down=$'\e[B'; enter=$'\n'

echo "── lint"
for f in ship-apk/ship-apk ship-site/ship-site developer-tools homebrew/render test-release.sh; do check "syntax $f" bash -n "$f"; done
# bash 3.2 reads “$var” as a variable named var” → unbound; always write ${var}”
check "no bare \$var before a curly quote" bash -c '! grep -nE '"'"'\$[A-Za-z_][A-Za-z_0-9]*”'"'"' ship-apk/ship-apk ship-site/ship-site developer-tools'
v="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' ship-apk/ship-apk)"
for f in ship-site/ship-site developer-tools; do check "VERSION $f = $v" grep -q "^VERSION=\"$v\"" "$f"; done
for f in ship-apk/ship-apk ship-site/ship-site developer-tools; do
  check "--help $f" bash "$f" --help
  check "--version $f" is "$(bash "$f" --version | awk '{print $2}')" "$v"
done
for f in ship-apk/ship-apk ship-site/ship-site; do check "-n is listed in --help $f" bash -c "bash $f --help 2>&1 | grep -q -- '(also -n)'"; done
check "refuses piped stdin" bash -c 'bash ship-apk/ship-apk </dev/null 2>&1 | grep -q "needs a terminal"'
check "hub rejects an unknown tool" bash -c 'bash developer-tools nope 2>&1 | grep -q "no tool called"'

export HOME; HOME="$(mktemp -d)"; trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.config"

echo "── ship-apk"
( source ship-apk/ship-apk
  MENU_ITEMS=(a b c); MENU_NOTES=("" "" "")
  check "menu: Enter picks the start index"   is "$(menu_pick t 1 1 <<<"$enter" 2>/dev/null)" 1
  check "menu: down then Enter"               is "$(menu_pick t -1 0 <<<"${down}${enter}" 2>/dev/null)" 1
  check "menu: up wraps to the last item"     is "$(menu_pick t -1 0 <<<"${up}${enter}" 2>/dev/null)" 2
  check "menu: q jumps to the skip index"     is "$(menu_pick t 2 0 <<<"q" 2>/dev/null)" 2
  check "menu: j/k keys move too"             is "$(menu_pick t -1 0 <<<"jj${enter}" 2>/dev/null)" 2
  check "fit: short coloured row left alone"  is "$(fit $'\e[2mabc\e[0m' 10)" $'\e[2mabc\e[0m'
  check "fit: long row cut with …"            is "$(fit "send the link to 1 person + 1 CC" 12)" "send the li…"
  check "fit: colour codes do not count"      is "$(fit $'\e[36mabcdef\e[0m' 6)" $'\e[36mabcdef\e[0m'
  check "ask: Enter keeps the default"        is "$(ask x dflt <<<"" 2>/dev/null)" dflt
  check "ask: typed value wins"               is "$(ask x dflt <<<"typed" 2>/dev/null)" typed
  check "ask_yn: n → false"                   is "$(ask_yn x true <<<"n" 2>/dev/null)" false
  check "ask_secret: typed value"             is "$(printf 'abc\n' | ask_secret p "" 2>/dev/null)" abc
  check "ask_secret: backspace removes a char" is "$(printf 'ab\177c\n' | ask_secret p "" 2>/dev/null)" ac
  check "ask_secret: Enter keeps saved value"  is "$(printf '\n' | ask_secret p old 2>/dev/null)" old
  check "ask_secret: shows a star per char"    is "$(printf 'xyz\n' | ask_secret p "" 2>&1 >/dev/null | tr -cd '*')" "***"

  cfg proj_set demo app "Demo App"; cfg proj_set demo app_id abc123
  cfg person_add demo Sam sam@example.com; cfg person_add demo QA qa@example.com bcc
  check "cfg: get back what was set"          is "$(cfg proj_get demo app)" "Demo App"
  check "cfg: To has one person"              is "$(cfg people demo | grep -c .)" 1
  cfg person_add demo Samuel sam@example.com
  check "cfg: re-adding an email replaces it" is "$(cfg people demo | grep -c .)" 1
  check "cfg: file is 0600"                   is "$(stat -f '%Lp' "$HOME/.config/ship-apk/config.json")" 600
  cfg proj_get ghost app >/dev/null
  check "cfg: reading an unknown project creates nothing" not grep -q ghost <<<"$(cfg projects)"
  mail="$(send_mail demo "Demo App" 1.2.3 https://appho.st/x "- fixed login" yes)"
  check "mail: To line"                       grep -q "To:      Samuel <sam@example.com>" <<<"$mail"
  check "mail: BCC hidden line"               grep -q "BCC:     qa@example.com" <<<"$mail"
  check "mail: subject from template"         grep -q "Subject: Demo App 1.2.3" <<<"$mail"
  check "mail: notes included"                grep -q "fixed login" <<<"$mail"
  check "mail: counts To+BCC"                 grep -q $'^DRY\t2$' <<<"$mail"
  cfg person_add demo "Lee" lee@example.com cc
  mail="$(send_mail demo "Demo App" 1.2.3 https://appho.st/x "" yes)"
  check "mail: CC line"                       grep -q "CC:      Lee <lee@example.com>" <<<"$mail"
  check "mail: counts To+CC+BCC"              grep -q $'^DRY\t3$' <<<"$mail"
  cfg person_del demo lee@example.com cc
  check "smtp_guess: gmail"                   is "$(smtp_guess me@gmail.com)" "smtp.gmail.com 465"
  check "smtp_guess: outlook uses 587"        is "$(smtp_guess me@Outlook.com)" "smtp-mail.outlook.com 587"
  check "smtp_guess: own domain"              is "$(smtp_guess me@acme.io)" "smtp.acme.io 465"
  # guided setup, answers piped in: To (address, name, blank), CC (blank), BCC (blank), subject
  setup_app_mail fresh Fresh >/dev/null 2>&1 <<'ANS'
amy@example.com
Amy



{app} is ready
ANS
  check "setup_app_mail: To saved"            is "$(cfg people fresh to)" "Amy	amy@example.com"
  check "setup_app_mail: skipped CC is empty" is "$(cfg people fresh cc)" ""
  check "setup_app_mail: subject saved"       is "$(cfg proj_get fresh subject)" "{app} is ready"
  cfg proj_del fresh
  cfg proj_set empty app E
  check "mail: no recipients → NO_RECIPIENTS" is "$(send_mail empty E 1 l n yes)" NO_RECIPIENTS
  cfg proj_del demo; cfg proj_del empty
  check "cfg: delete"                         is "$(cfg projects)" ""

  p="$(mktemp -d)"; mkdir -p "$p/lib/sub"; printf 'name: x\nversion: 1.2.3+45\n' > "$p/pubspec.yaml"
  check "find_root walks up to pubspec"       is "$(cd "$p/lib/sub" && find_root)" "$p"
  check "find_root fails outside a project"   not in_dir /tmp find_root
  check "proj_version from pubspec"           is "$(proj_version "$p")" "1.2.3+45"
  check "proj_version falls back to a date"   grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-' <<<"$(proj_version /tmp)"
  check "flutter_cmd: plain by default"       is "$(flutter_cmd "$p")" flutter
  check "last_build: none yet"                is "$(last_build "$p")" ""
  mkdir -p "$p/build/app/outputs/flutter-apk"; : > "$p/build/app/outputs/flutter-apk/app-release.apk"
  check "last_build: finds the release apk"   is "$(last_build "$p")" "$p/build/app/outputs/flutter-apk/app-release.apk"
  ( cd "$p" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m first && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m second )
  check "git_notes: last commits as bullets"  is "$(git_notes "$p" demo)" $'- second\n- first'
  cfg proj_set demo last_sha "$(cd "$p" && git rev-parse HEAD~1)"
  check "git_notes: only since the last send" is "$(git_notes "$p" demo)" "- second"
  check "git_notes: not a repo → empty"       is "$(git_notes /tmp demo)" ""
  check "bump: build"                         is "$(bump_version 1.0.0+3 build)" 1.0.0+4
  check "bump: patch also raises build"       is "$(bump_version 1.0.0+3 patch)" 1.0.1+4
  check "bump: minor resets patch"            is "$(bump_version 1.2.5+9 minor)" 1.3.0+10
  check "bump: major resets the rest"         is "$(bump_version 1.2.5+9 major)" 2.0.0+10
  check "bump: no build number → +1"          is "$(bump_version 1.0.0 build)" 1.0.0+1
  check "bump: no build number, patch"        is "$(bump_version 1.0.0 patch)" 1.0.1
  check "bump: pre-release tag dropped"       is "$(bump_version 1.0.0-beta.1 patch)" 1.0.1
  check "bump: pre-release with build"        is "$(bump_version 2.1.0-rc.2+30 build)" 2.1.0+31
  nov="$(mktemp -d)"; printf 'name: x\n' > "$nov/pubspec.yaml"; cfg proj_set demo last_version 2026.10.08-1047
  check "version_guard: date stamp not bumped" is "$(version_guard demo "$nov" 2026.10.08-1047 </dev/null 2>/dev/null)" 2026.10.08-1047
  rm -rf "$nov"
  check "version_guard: Enter ships as is"   is "$(version_guard demo "$p" 1.2.3+45 <<<"" 2>/dev/null)" 1.2.3+45
  check "version_guard: bump, Enter takes hint" is "$(printf '\e[B\n\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null)" 1.2.3+46
  check "version_guard: pubspec rewritten"    is "$(proj_version "$p")" 1.2.3+46
  printf 'name: x\nversion: 1.2.3+45\n' > "$p/pubspec.yaml"
  check "version_guard: bump, typed version"  is "$(printf '\e[B\n2.0.0+50\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null)" 2.0.0+50
  printf 'name: x\nversion: 1.2.3+45\n' > "$p/pubspec.yaml"
  check "version_guard: bad input asks again" is "$(printf '\e[B\nabc\n1.3.0+46\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null)" 1.3.0+46
  printf 'name: x\nversion: 1.2.3+45\n' > "$p/pubspec.yaml"
  cfg proj_set demo last_version 1.2.3+45
  check "version_guard: repeat preselects bump" is "$(printf '\n\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null)" 1.2.3+46
  printf 'name: x\nversion: 1.2.3+45\n' > "$p/pubspec.yaml"
  check "version_guard: repeat, up keeps it"  is "$(printf '\e[A\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null)" 1.2.3+45
  check "version_guard: pubspec untouched"    is "$(proj_version "$p")" 1.2.3+45
  cfg proj_set demo last_version ""
  DRY=yes
  check "dry run: version change not written" is "$(printf '\e[B\n\n' | version_guard demo "$p" 1.2.3+45 2>/dev/null; proj_version "$p")" "1.2.3+461.2.3+45"
  cfg proj_set demo app_id A1; cfg proj_set demo user_id U1; cfg proj_set demo key K1
  out="$(dry_ship demo "$p" Demo 1.2.3+45 yes "" no "" <<<"q" 2>&1 || true)"
  check "dry run: checks the app id"          grep -q "appho.st app id is set" <<<"$out"
  check "dry run: shows the build command"    grep -q "build apk --release" <<<"$out"
  check "dry run: shows the upload target"    grep -q "appho.st app A1" <<<"$out"
  check "dry run: says nothing was changed"   grep -q "nothing was built, uploaded, mailed or written" <<<"$out"
  check "dry run: no last version saved"      is "$(cfg proj_get demo last_version)" ""
  DRY=no
  check "pick_notes: Enter uses the commits"   is "$(pick_notes "$p" demo <<<"$enter" 2>/dev/null)" "- second"
  check "pick_notes: no notes gives nothing"  is "$(pick_notes "$p" demo <<<"${down}${down}${enter}" 2>/dev/null)" ""
  ed="$(mktemp)"; printf '#!/bin/sh\nprintf "Fixed login\\n# hint\\n" > "$1"\n' > "$ed"; chmod +x "$ed"
  check "pick_notes: own text, # lines drop"  is "$(VISUAL="$ed" pick_notes "$p" demo <<<"${down}${enter}" 2>/dev/null)" "Fixed login"
  printf '#!/bin/sh\nprintf "App\\n•\\nNew splash\\n◦\\nfaster\\n" > "$1"\n' > "$ed"; chmod +x "$ed"
  check "pick_notes: pasted bullets joined"   is "$(VISUAL="$ed" pick_notes "$p" demo <<<"${down}${enter}" 2>/dev/null)" $'App\n- New splash\n  - faster'
  rm -f "$ed"
  cfg person_add demo Sam sam@example.com; cfg person_add demo Al al@example.com; cfg person_add demo Lee lee@example.com cc; cfg person_add demo Q q@example.com bcc
  check "recipients: To + CC + BCC spelled out" is "$(recipients demo)" "2 people + 1 CC + 1 BCC"
  cfg person_del demo lee@example.com cc; cfg person_del demo q@example.com bcc; cfg person_del demo sam@example.com; cfg person_del demo al@example.com
  cfg proj_set demo path "$p"; cfg proj_set other path /gone/away
  load_projects /tmp; check "app list: no match outside an app"     is "$HIT" -1
  load_projects "$p"; check "app list: this folder's app is found"  is "$HIT" 0
  check "app list: rows reach the menu"         is "${#MENU_ITEMS[@]}" 2
  check "app list: no recipients reads no mail" grep -q "no mail" <<<"${MENU_NOTES[0]}"
  check "app list: missing folder is flagged"   grep -q "folder missing" <<<"${MENU_NOTES[1]}"
  cfg proj_del demo; cfg proj_del other; rm -rf "$p"
)

echo "── ship-site"
( source ship-site/ship-site
  MENU_ITEMS=(a b c); MENU_NOTES=("" "" "")
  check "menu: down twice then Enter"         is "$(menu_pick t 0 <<<"${down}${down}${enter}" 2>/dev/null)" 2
  check "menu: starts on the given index"     is "$(menu_pick t 2 <<<"$enter" 2>/dev/null)" 2
  vc acct_set me scope azhar; vc acct_set me org_id u1; vc acct_set me team_id ""; vc proj_set /tmp/x name demo
  check "vc: accounts listed"                 is "$(vc accounts)" me
  check "vc: project memory per folder"       is "$(vc proj_get /tmp/x name)" demo
  check "vc: unknown key is empty"            is "$(vc acct_get me nothing)" ""
  check "vc: file is 0600"                    is "$(stat -f '%Lp' "$HOME/.config/ship-site/config.json")" 600
  check "vc: bad token → ERR line"            grep -q "^ERR" <<<"$(vc user not-a-token 2>/dev/null || true)"
  check "vc: bad token exits non-zero"        not vc user not-a-token
  vc cache_add me prj_9 site-a site-a.vercel.app; vc proj_set /tmp/site-a id prj_9
  check "landing: cached row with its folder" is "$(vc landing)" "me	prj_9	site-a	site-a.vercel.app	/tmp/site-a"
  vc acct_del me
  check "vc: delete"                          is "$(vc accounts)" ""
  check "landing: hides removed accounts"     is "$(vc landing)" ""
  mkdir -p "$HOME/.config/ship-site/accounts/tok" "$HOME/.config/ship-site/accounts/web"
  printf 'abc\n' > "$HOME/.config/ship-site/accounts/tok/token"; printf '{"token":"xyz"}' > "$HOME/.config/ship-site/accounts/web/auth.json"
  check "acct_token: pasted token"            is "$(acct_token tok)" abc
  check "acct_token: browser login auth.json" is "$(acct_token web)" xyz
  acct_cli tok;  check "acct_cli: token flag"                is "${AUTH[*]}" "--token abc"
  acct_cli web;  check "acct_cli: global-config for logins"  is "${AUTH[*]}" "--global-config $HOME/.config/ship-site/accounts/web"
  mkdir -p "$HOME/.config/ship-site/accounts/Mohsin Dev"
  acct_cli "Mohsin Dev"
  check "acct_cli: a space in the name stays one argument" is "${#AUTH[@]}" 2
  check "slugify"                             is "$(slugify "My Site_v2!")" my-site-v2
  p="$(mktemp -d)"; mkdir -p "$p/src/deep" "$p/dist"; : > "$p/package.json"; : > "$p/dist/index.html"
  check "find_root walks up to package.json"  is "$(cd "$p/src/deep" && find_root)" "$p"
  check "detect_pm: npm by default"           is "$(detect_pm "$p")" npm
  : > "$p/pnpm-lock.yaml"
  check "detect_pm: pnpm lockfile"            is "$(detect_pm "$p")" pnpm
  st="$(mktemp -d)"; stage_dist "$p" "$st" prj_1 org_1 demo
  check "stage: dist copied"                  test -f "$st/index.html"
  check "stage: SPA rewrite added"            grep -q '"/index.html"' "$st/vercel.json"
  check "stage: project link written"         grep -q '"projectId":"prj_1","orgId":"org_1"' "$st/.vercel/project.json"
  check "stage: no .git inside the copy"      test ! -e "$st/.git"
  printf '{"headers":[]}' > "$p/vercel.json"; st2="$(mktemp -d)"; stage_dist "$p" "$st2" a b c
  check "stage: project vercel.json wins"     is "$(cat "$st2/vercel.json")" '{"headers":[]}'
  ROOT=/somewhere; check "choose_folder: inside a project uses it"  is "$(choose_folder "")" /somewhere
  check "choose_folder: missing saved folder → current one"        is "$(choose_folder /gone/away)" /somewhere
  ROOT="";         check "choose_folder: outside, saved folder used" is "$(choose_folder "$p")" "$p"
  printf '{"name":"x","version":"1.0.0","scripts":{"build":"vite build"}}' > "$p/package.json"
  mkdir -p "$HOME/.config/ship-site/accounts/dryacct"; printf 'bad-token\n' > "$HOME/.config/ship-site/accounts/dryacct/token"
  out="$(DRY=yes PROD=no dry_deploy dryacct prj_x site "$p" npm 2>&1)"
  check "dry deploy: build script checked"    grep -q "has a build script" <<<"$out"
  check "dry deploy: bad login reported"      grep -q "Vercel login failed" <<<"$out"
  check "dry deploy: deploy command shown"    grep -q "vercel deploy --yes" <<<"$out"
  check "dry deploy: says nothing changed"    grep -q "nothing was built, deployed or written" <<<"$out"
  check "dry deploy: package.json untouched"  grep -q '"version":"1.0.0"' "$p/package.json"
  rm -rf "$p" "$st" "$st2"
)

echo "── developer-tools"
( source developer-tools
  check "pick: down then Enter"               is "$(pick a b c <<<"${down}${enter}" 2>/dev/null)" 1
  check "tick: Enter keeps everything"        is "$(tick a b c <<<"$enter" 2>/dev/null)" "0 1 2 "
  check "tick: space unticks the first"       is "$(tick a b c <<<" ${enter}" 2>/dev/null)" "1 2 "
  check "tick: move down, untick the second"  is "$(tick a b c <<<"${down} ${enter}" 2>/dev/null)" "0 2 "
  check "tick: untick then tick again"        is "$(tick a b <<<"  ${enter}" 2>/dev/null)" "0 1 "
  check "status: not installed"               is "$(PATH=/nonexistent status ship-apk)" "not installed"
)
echo "all good"
