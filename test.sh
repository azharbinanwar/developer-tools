#!/usr/bin/env bash
# Tests for everything that runs without a terminal, a Flutter SDK or a Vercel login.
# Menus are driven by feeding keystrokes on stdin. Runs in CI on every push.
set -euo pipefail
cd "$(dirname "$0")"
check(){ # $1 name, then a command; one line per check, stops at the first failure
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s\n' "$name"; "$@" || true
       [ -n "${out:-}" ] && { printf '    --- output of the flow under test (last 30 lines) ---\n'; printf '%s\n' "$out" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -30; }
       exit 1; fi
}
is(){ [ "$1" = "$2" ] || { printf '    got:  %s\n    want: %s\n' "$1" "$2"; return 1; }; }
not(){ ! "$@"; }
in_dir(){ local d="$1"; shift; ( cd "$d" && "$@" ); }
up=$'\e[A'; down=$'\e[B'; enter=$'\n'

echo "── lint"
for f in ship-apk/ship-apk ship-site/ship-site developer-tools homebrew/render test-release.sh; do check "syntax $f" bash -n "$f"; done
# bash 3.2 reads “$var” as a variable named var” → unbound; always write ${var}”
if command -v shellcheck >/dev/null; then for f in ship-apk/ship-apk ship-site/ship-site developer-tools; do check "shellcheck (errors) $f" shellcheck -S error -s bash "$f"; done; fi
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
( source ./ship-apk/ship-apk
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
  MENU_ITEMS=("build a fresh one" "use the last build" "← back to apps"); MENU_NOTES=("" "" "")
  check "keys: f is fresh build"              is "$(menu_pick t 2 0 <<<"f" 2>/dev/null)" 0
  check "keys: Esc skips"                     is "$(printf '\e' | menu_pick t 2 0 2>/dev/null)" 2
  check "menu: end of input takes the skip"   is "$(menu_pick t 2 0 </dev/null 2>/dev/null)" 2
  check "keys: an option with a quote resolves" is "$(act_of "set up this app's email")" "mail.setup_app e"
  check "ask_secret: typed value"             is "$(printf 'abc\n' | ask_secret p "" 2>/dev/null)" abc
  check "ask_secret: backspace removes a char" is "$(printf 'ab\177c\n' | ask_secret p "" 2>/dev/null)" ac
  check "ask_secret: Enter keeps saved value"  is "$(printf '\n' | ask_secret p old 2>/dev/null)" old
  check "ask_secret: shows a star per char"    is "$(printf 'xyz\n' | ask_secret p "" 2>&1 >/dev/null | tr -cd '*')" "***"

  cfg proj_set demo app "Demo App"; cfg proj_set demo app_id abc123
  cfg person_add demo Sam sam@example.com; cfg person_add demo QA qa@example.com bcc
  check "cfg: get back what was set"          is "$(cfg proj_get demo app)" "Demo App"
  check "cfg: To has one person"              is "$(cfg people demo | grep -c .)" 1
  cfg person_add blank "" nameless@example.com
  check "cfg: a blank name still lists the address" is "$(cfg people blank)" $'nameless\tnameless@example.com'
  cfg proj_del blank
  cfg person_add demo Samuel sam@example.com
  check "cfg: re-adding an email replaces it" is "$(cfg people demo | grep -c .)" 1
  check "cfg: file is 0600"                   is "$(fmode "$HOME/.config/ship-apk/config.json")" 600
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
  cfg proj_set stat path /tmp/stat; cfg stat_add stat; cfg stat_add stat; cfg stat_add stat
  check "stats: count and last date on the app row" is "$(cfg projects | grep '^stat' | cut -d$'\x1f' -f6,7 | tr $'\x1f' ' ')" "3 today"
  cfg proj_del stat
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
  MENU_NOKEY="0 1"; menu_keys 2>/dev/null
  check "app list: apps get numbers only"       is "${MK[*]}" "1 2"
  check "app list: no recipients reads no mail" grep -q "no mail" <<<"${MENU_NOTES[0]}"
  check "app list: missing folder is flagged"   grep -q "folder missing" <<<"${MENU_NOTES[1]}"
  cfg proj_del demo; cfg proj_del other

  # guided mailbox setup, answers piped: address, password, host, port, from name, no test mail
  printf 'me@gmail.com\nsecret\n\n\nMe\nn\n' | setup_mailbox >/dev/null 2>&1 || true
  check "mailbox setup: address saved"        is "$(cfg smtp_get user)" me@gmail.com
  check "mailbox setup: gmail host guessed"   is "$(cfg smtp_get host)" smtp.gmail.com
  check "mailbox setup: gmail port guessed"   is "$(cfg smtp_get port)" 465
  check "mailbox setup: password saved"       is "$(cfg smtp_get password)" secret
  check "mailbox setup: ready afterwards"     is "$(cfg smtp_ready)" yes
  printf 'me@gmail.com\n\n\n\n\nn\n' | setup_mailbox >/dev/null 2>&1 || true
  check "mailbox setup: Enter keeps the password" is "$(cfg smtp_get password)" secret

  # fvm detection and a fake flutter that really writes an apk
  fb="$(mktemp -d)"; p="$(mktemp -d)"; printf 'name: x\nversion: 2.0.0+7\n' > "$p/pubspec.yaml"
  cat > "$fb/flutter" <<'FAKE'
#!/bin/sh
echo "Running Gradle task 'assembleRelease'..."
mkdir -p build/app/outputs/flutter-apk && printf 'apk' > build/app/outputs/flutter-apk/app-release.apk
FAKE
  printf '#!/bin/sh\nshift; exec "$(dirname "$0")/flutter" "$@"\n' > "$fb/fvm"; chmod +x "$fb/flutter" "$fb/fvm"
  : > "$p/.fvmrc"
  check "flutter_cmd: fvm pinned but missing → flutter" is "$(PATH=/usr/bin:/bin flutter_cmd "$p" 2>/dev/null)" flutter
  check "flutter_cmd: fvm pinned and present"  is "$(PATH="$fb:$PATH" flutter_cmd "$p")" "fvm flutter"
  apk="$(PATH="$fb:$PATH" VERBOSE=yes build_apk "$p" 2>/dev/null)"
  check "build_apk: returns the apk it built"  is "$apk" "$p/build/app/outputs/flutter-apk/app-release.apk"
  apk="$(PATH="$fb:$PATH" VERBOSE=no build_apk "$p" 2>/dev/null)"
  check "build_apk: quiet mode writes a log"   test -s "$HOME/.config/ship-apk/logs/$(basename "$p")-build.log"
  rm -f "$fb/flutter"; printf '#!/bin/sh\necho "FAILURE: Gradle broke"; exit 1\n' > "$fb/flutter"; chmod +x "$fb/flutter"
  check "build_apk: a failing build returns 1" not bash -c "PATH='$fb:$PATH' VERBOSE=no build_apk '$p' >/dev/null 2>&1"

  # upload against a fake appho.st: curl answers the three calls, pbcopy swallows the link
  cat > "$fb/curl" <<'FAKE'
#!/bin/sh
case "$*" in
  *get_upload_url*)     echo "https://storage.fake/put/here" ;;
  *-T*)                 printf '200' ;;
  *get_current_version*) echo '{"url":"https://appho.st/d/fake1","version":"2.0.0+7"}' ;;
esac
FAKE
  printf '#!/bin/sh\ncat >/dev/null\n' > "$fb/pbcopy"; chmod +x "$fb/curl" "$fb/pbcopy"
  cfg proj_set up app_id A1; cfg proj_set up user_id U1; cfg proj_set up key K1
  printf 'apk' > "$p/x.apk"
  out="$(PATH="$fb:$PATH" bash -c 'source ./ship-apk/ship-apk; do_upload "$1" up Up 2.0.0+7 && printf "%s" "$UPLOAD_LINK"' _ "$p/x.apk" 2>/dev/null)"
  check "upload: link returned"               is "$out" "https://appho.st/d/fake1"
  printf '#!/bin/sh\ncase "$*" in *get_upload_url*) echo "bad key";; esac\n' > "$fb/curl"
  check "upload: appho.st refusal is a failure" not bash -c "PATH='$fb:$PATH'; source ./ship-apk/ship-apk; do_upload '$p/x.apk' up Up 1 >/dev/null 2>&1"
  printf '#!/bin/sh\ncase "$*" in *get_upload_url*) echo "https://s/x";; *-T*) exit 56;; esac\n' > "$fb/curl"
  out="$(PATH="$fb:$PATH" bash -c 'source ./ship-apk/ship-apk; do_upload "$1" up Up 1' _ "$p/x.apk" 2>&1 || true)"
  check "upload: a dropped connection says so" grep -q "upload interrupted" <<<"$out"
  cfg proj_del up

  # a whole dry ship: pick fresh build, skip mail, then quit from the done menu
  cfg proj_set e2e path "$p"; cfg proj_set e2e app E2E; cfg proj_set e2e app_id A2; cfg proj_set e2e user_id U; cfg proj_set e2e key K
  printf '#!/bin/sh\nmkdir -p build/app/outputs/flutter-apk && printf apk > build/app/outputs/flutter-apk/app-release.apk\n' > "$fb/flutter"
  out="$(printf 's' | PATH="$fb:$PATH" DRY=yes bash -c 'source ./ship-apk/ship-apk; DRY=yes; printf "sfxq" | ship e2e "$1"' _ "$p" 2>&1 || true)"
  check "ship dry run: version shown"         grep -q "Version  2.0.0+7" <<<"$out"
  check "ship dry run: checks ran"            grep -q "appho.st app id is set" <<<"$out"
  check "ship dry run: build command shown"   grep -q "build apk --release" <<<"$out"
  check "ship dry run: mail skipped"          grep -q "none — skipped" <<<"$out"
  check "ship dry run: nothing changed"       grep -q "nothing was built, uploaded, mailed or written" <<<"$out"
  check "ship dry run: no last version saved" is "$(cfg proj_get e2e last_version)" ""

  # edit an app: remove it with its key and a y
  out="$(printf 'dy' | edit_app e2e 2>&1 || true)"
  check "edit app: remove needs y, then gone"  is "$(cfg proj_get e2e app)" ""
  # people: add one by key, then back
  printf 'aAmy\namy@x.com\nq' | people_menu pp to >/dev/null 2>&1 || true
  check "people: added through the menu"      is "$(cfg people pp to)" $'Amy\tamy@x.com'
  cfg proj_del pp
  log_send e2e 2.0.0+7 https://x 2
  check "log_send: writes the send log"       grep -q $'2.0.0+7\t2\thttps://x' "$HOME/.config/ship-apk/logs/e2e.log"
  rm -rf "$p" "$fb"
)

echo "── ship-site"
( source ./ship-site/ship-site
  MENU_ITEMS=(a b c); MENU_NOTES=("" "" "")
  check "menu: down twice then Enter"         is "$(menu_pick t 0 <<<"${down}${down}${enter}" 2>/dev/null)" 2
  check "menu: starts on the given index"     is "$(menu_pick t 2 <<<"$enter" 2>/dev/null)" 2
  MENU_ITEMS=($'\x01Group A' a1 $'\x01Group B' b1 b2); MENU_NOTES=("" "" "" "" "")
  check "menu: a heading is never picked"     is "$(menu_pick t 0 <<<"$enter" 2>/dev/null)" 1
  check "menu: down jumps over a heading"     is "$(menu_pick t 1 <<<"${down}${enter}" 2>/dev/null)" 3
  check "menu: up jumps over headings, wraps" is "$(menu_pick t 1 <<<"${up}${enter}" 2>/dev/null)" 4
  MENU_ITEMS=(); MENU_NOTES=(); for i in $(seq 0 59); do MENU_ITEMS+=("item $i"); MENU_NOTES+=(""); done
  keys=""; for i in $(seq 1 50); do keys="$keys$down"; done
  check "menu: long list scrolls to the pick" is "$(menu_pick t 0 <<<"$keys$enter" 2>/dev/null)" 50
  MENU_ITEMS=(); MENU_NOTES=(); for i in $(seq 0 39); do MENU_ITEMS+=("p$i"); MENU_NOTES+=(""); done; MENU_ITEMS+=(new quit); MENU_NOTES+=("" "")
  MENU_FIXED=2; check "menu: fixed footer item is picked" is "$(menu_pick t 0 <<<"${up}${enter}" 2>/dev/null)" 41
  # settings handed to one menu must not leak into the next one (menu_pick runs in a subshell)
  MENU_ITEMS=(p0 p1 p2 p3 p4 p5 p6 x y); MENU_NOTES=("" "" "" "" "" "" "" "" ""); MENU_FIXED=2; MENU_NOKEY="0 1"
  menu_pick t 0 <<<"" >/dev/null 2>&1; MENU_FIXED=0; MENU_NOKEY=""
  MENU_ITEMS=("main website" "test version" "← back"); MENU_NOTES=("" "" "")
  check "menu: a small menu after a fixed one still works" is "$(menu_pick t 0 <<<"t" 2>/dev/null)" 1
  MENU_ITEMS=("main website" "test version"); MENU_NOTES=("" "")
  check "keys: a letter picks its option"     is "$(menu_pick t 0 <<<"t" 2>/dev/null)" 1
  check "keys: the pick is known as a key"    bash -c 'source ship-site/ship-site; MENU_ITEMS=("main website" "test version"); MENU_NOTES=("" ""); menu_pick t 0 <<<"m" >/dev/null 2>&1; picked_by_key'
  check "keys: Enter is not a key pick"       bash -c 'source ship-site/ship-site; MENU_ITEMS=("main website" "test version"); MENU_NOTES=("" ""); menu_pick t 0 <<<"" >/dev/null 2>&1; ! picked_by_key'
  MENU_ITEMS=(alpha beta gamma); MENU_NOTES=("" "" "")
  check "keys: plain rows get 1–9"            is "$(menu_pick t 0 <<<"3" 2>/dev/null)" 2
  MENU_ITEMS=(alpha "← back"); MENU_NOTES=("" "")
  check "keys: Esc picks ← back"              is "$(printf '\e' | menu_pick t 0 2>/dev/null)" 1
  mkdir -p "$HOME/.config/developer-tools"; printf '{"site.main":"w"}' > "$HOME/.config/developer-tools/keys.json"
  MENU_ITEMS=("main website" "test version"); MENU_NOTES=("" "")
  check "keys.json: your key wins"            is "$(menu_pick t 0 <<<"w" 2>/dev/null)" 0
  printf '{"site.main":"t"}' > "$HOME/.config/developer-tools/keys.json"
  check "keys.json: a clashing key is refused" is "$(menu_pick t 1 <<<"m" 2>/dev/null)" 0
  rm -f "$HOME/.config/developer-tools/keys.json"
  MENU_ITEMS=("accounts" "refresh" "  + new project"); MENU_NOTES=("" "" "")
  MENU_NOKEY="0 1"; menu_keys 2>/dev/null
  check "nokey: data rows get numbers, not action keys" is "${MK[*]}" "1 2 n"
  check "nokey_rows: three rows"              is "$(nokey_rows 3)" "0 1 2"
  check "nokey_rows: none stays empty"        is "$(nokey_rows 0)" ""
  MENU_ITEMS=("+ new project" "← back"); MENU_NOTES=("" ""); MENU_NOKEY="$(nokey_rows 0)"; menu_keys 2>/dev/null
  check "nokey: an empty list keeps the action key" is "${MK[*]}" "n esc"
  MENU_ITEMS=(alpha "← back"); MENU_NOTES=("" "")
  check "menu: end of input backs out"        is "$(menu_pick t 0 </dev/null 2>/dev/null)" 1
  check "pick file: lives in ~/.config/developer-tools" test -f "$HOME/.config/developer-tools/.lastpick"
  vc stamp
  check "cache: fresh right after a refresh"  test "$(vc age)" -lt 600
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["refreshed_at"]=0; json.dump(d,open(p,"w"))' "$HOME/.config/ship-site/config.json"
  check "cache: stale once the stamp is old"  test "$(vc age)" -gt 600
  check "confirm: y goes"                     confirm_y "go?" <<<"y"
  check "confirm: anything else cancels"      not confirm_y "go?" <<<"x"
  MENU_ITEMS=(a b c); MENU_NOTES=("" "" "")
  vc acct_set me scope azhar; vc acct_set me org_id u1; vc acct_set me team_id ""; vc proj_set /tmp/x name demo
  check "vc: accounts listed"                 is "$(vc accounts)" me
  check "vc: project memory per folder"       is "$(vc proj_get /tmp/x name)" demo
  check "vc: unknown key is empty"            is "$(vc acct_get me nothing)" ""
  check "vc: file is 0600"                    is "$(fmode "$HOME/.config/ship-site/config.json")" 600
  check "vc: bad token → ERR line"            grep -q "^ERR" <<<"$(vc user not-a-token 2>/dev/null || true)"
  check "vc: bad token exits non-zero"        not vc user not-a-token
  vc cache_add me prj_9 site-a site-a.vercel.app; vc proj_set /tmp/site-a id prj_9
  check "landing: cached row with its folder" is "$(vc landing)" $'me\x1fprj_9\x1fsite-a\x1fsite-a.vercel.app\x1f/tmp/site-a\x1fvercel\x1f\x1f\x1f\x1f\x1f'
  vc stat_add prj_9; vc stat_add prj_9
  check "stats: count and last date on the row" is "$(vc landing | cut -d$'\x1f' -f9,10 | tr $'\x1f' ' ')" "2 today"
  check "stats: stat_get"                       is "$(vc stat_get prj_9 | tr '\t' ' ')" "2 today"
  check "stats: none is blank"                  is "$(vc stat_get nothing | tr '\t' ' ')" "0 "
  check "url_get: the cached url"               is "$(vc url_get prj_9)" site-a.vercel.app
  vc domain_set prj_9 site-a.com
  check "domain: saved per project"             is "$(vc domain_get prj_9)" site-a.com
  check "domain: on the landing row"            is "$(vc landing | cut -d$'\x1f' -f11)" site-a.com
  vc domain_set prj_9 ""
  check "domain: blank removes it"              is "$(vc domain_get prj_9)" ""
  check "fb_token: nothing without a CLI login" is "$(vc fb_token a@x.com)" ""
  mkdir -p "$HOME/.config/configstore"; printf '{"user":{"email":"a@x.com"},"tokens":{"access_token":"tokA","expires_at":%s},"additionalAccounts":[{"user":{"email":"b@x.com"},"tokens":{"access_token":"tokB","expires_at":%s}}]}' "$(( ($(date +%s) + 3600) * 1000 ))" "$(( ($(date +%s) - 10) * 1000 ))" > "$HOME/.config/configstore/firebase-tools.json"
  check "fb_token: the default account's token" is "$(vc fb_token a@x.com)" tokA
  check "fb_token: an expired token is nothing" is "$(vc fb_token b@x.com)" ""
  rm -f "$HOME/.config/configstore/firebase-tools.json"
  vc label_set prj_9 "site-a.com"
  check "label: saved and shown on the row"   is "$(vc landing | cut -d$'\x1f' -f7)" site-a.com
  vc label_set prj_9 ""
  check "label: blank removes it"             is "$(vc label_get prj_9)" ""
  vc acct_del me
  check "vc: delete"                          is "$(vc accounts)" ""
  check "landing: hides removed accounts"     is "$(vc landing)" ""
  a=x id=p/s nm=s f="" h=firebase; rowstr="$a"$'\x1f'"$id"$'\x1f'"$nm"$'\x1f'"$f"$'\x1f'"$h"
  IFS=$'\x1f' read -r a id nm f h <<<"$rowstr"
  check "landing row: empty folder keeps the host" is "$h" firebase
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
  out2="$(PATH=/usr/bin:/bin DRY=yes PROD=no dry_deploy dryacct prj_x site "$p" npm 2>&1)"
  check "dry deploy: missing Vercel CLI reported" grep -q "the Vercel CLI is not installed" <<<"$out2"
  out2="$(PATH=/usr/bin:/bin DRY=yes PROD=no dry_deploy_firebase a@x.com shop-1/shop-1 "$p" npm 2>&1)"
  check "dry deploy: missing Firebase CLI reported" grep -q "the Firebase CLI is not installed" <<<"$out2"
  check "dry deploy: deploy command shown"    grep -q "vercel deploy --yes" <<<"$out"
  check "dry deploy: says nothing changed"    grep -q "nothing was built, deployed or written" <<<"$out"
  check "dry deploy: package.json untouched"  grep -q '"version":"1.0.0"' "$p/package.json"
  # ── Firebase, with a fake firebase command so this runs anywhere ──
  fbin="$(mktemp -d)"; cat > "$fbin/firebase" <<'FAKE'
#!/bin/sh
case "$1" in
  login:list) printf 'Logged in as a@x.com\n\nOther accounts:\n  b@y.com\n' ;;
  --version)  echo 15.0.0 ;;
  projects:list)
    case "$*" in
      *a@x.com*) echo '{"status":"success","result":[{"projectId":"shop-1","displayName":"Shop","resources":{"hostingSite":"shop-1"}},{"projectId":"api-2","displayName":"API","resources":{}}]}' ;;
      *) echo '{"status":"error","error":"Authentication Error"}' ;;
    esac ;;
  hosting:sites:list) echo '{"status":"success","result":{"sites":[{"name":"projects/shop-1/sites/shop-1","defaultUrl":"https://shop-1.web.app"}]}}' ;;
esac
FAKE
  chmod +x "$fbin/firebase"
  PATH="$fbin:$PATH" vc fb_refresh 2>"$fbin/err"
  check "firebase: every CLI login is an account" is "$(vc fb_accounts | tr '\n' ' ')" "a@x.com b@y.com "
  check "firebase: site row in the landing list"  is "$(vc landing | grep firebase | cut -d$'\x1f' -f1-4,6)" $'a@x.com\x1fshop-1/shop-1\x1fshop-1\x1fshop-1.web.app\x1ffirebase'
  check "firebase: project without Hosting left out" not grep -q api-2 <<<"$(vc landing)"
  check "firebase: failing account reported"      grep -q "b@y.com" "$fbin/err"
  check "firebase: projects for new sites"        is "$(vc fb_projects a@x.com)" $'shop-1\tShop'
  PATH="$fbin:$PATH" vc refresh 2>/dev/null
  check "firebase: Vercel refresh keeps Firebase rows" grep -q firebase <<<"$(vc landing)"
  out="$(PATH="$fbin:$PATH" DRY=yes PROD=yes dry_deploy_firebase a@x.com shop-1/shop-1 "$p" npm 2>&1)"
  check "firebase dry run: signed-in account found" grep -q "signed in as a@x.com" <<<"$out"
  check "firebase dry run: site reachable"        grep -q "site “shop-1” in project shop-1 is reachable" <<<"$out"
  check "firebase dry run: deploy command shown"  grep -q "firebase deploy --only hosting --project shop-1 --account a@x.com" <<<"$out"
  check "firebase dry run: passed"                grep -q "dry run passed" <<<"$out"
  out="$(PATH="$fbin:$PATH" DRY=yes PROD=no dry_deploy_firebase a@x.com shop-1/shop-1 "$p" npm 2>&1)"
  check "firebase dry run: preview channel shown" grep -q "hosting:channel:deploy preview --expires 7d" <<<"$out"
  # create a project: the fake CLI records what it was asked to do
  cat > "$fbin/firebase2" <<'FAKE'
#!/bin/sh
echo "$*" >> "$(dirname "$0")/calls"
case "$1" in
  projects:create)      echo "✔ Your Firebase project is ready!" ;;
  hosting:sites:list)   case "$*" in *new-shop*) echo '{"status":"success","result":{"sites":[]}}' ;; *) echo '{"status":"success","result":{"sites":[{"name":"projects/x/sites/x"}]}}' ;; esac ;;
  hosting:sites:create) echo "site created" ;;
esac
FAKE
  chmod +x "$fbin/firebase2"; mv "$fbin/firebase2" "$fbin/firebase"
  r="$(printf 'New Shop\nnew-shop-1234\n' | PATH="$fbin:$PATH" fb_create_project a@x.com shop 2>/dev/null)"
  check "create project: id and site returned"    is "$r" $'new-shop-1234\tnew-shop-1234'
  check "create project: projects:create ran"      grep -q "projects:create new-shop-1234 --display-name New Shop --account a@x.com" "$fbin/calls"
  check "create project: missing site created"     grep -q "hosting:sites:create new-shop-1234 --project new-shop-1234" "$fbin/calls"
  : > "$fbin/calls"
  r="$(printf 'X\nBad_ID\nok-proj-12\n' | PATH="$fbin:$PATH" DRY=yes fb_create_project a@x.com shop 2>/dev/null || true)"
  check "create project: bad id asks again, dry run creates nothing" is "$(cat "$fbin/calls")" ""
  rm -rf "$fbin"
  printf '{"projects":{"default":"shop-1"}}' > "$p/.firebaserc"
  check "firebaserc: default project read"         is "$(firebaserc_project "$p")" shop-1
  check "firebaserc: none when missing"            is "$(firebaserc_project /tmp)" ""
  printf '{"hosting":{"site":"shop-1"}}' > "$p/firebase.json"
  check "firebase.json: hosting site read"         is "$(firebase_json_site "$p")" shop-1
  mkdir -p "$p/.vercel"; printf '{"projectId":"prj_v1"}' > "$p/.vercel/project.json"
  check ".vercel link: project id read"            is "$(vercel_json_project "$p")" prj_v1
  US=$'\x1f'
  landing="m${US}prj_v1${US}web${US}web.vercel.app${US}${US}vercel${US}
m${US}prj_v2${US}my-app${US}my-app.vercel.app${US}${US}vercel${US}
g@x${US}shop-1/shop-1${US}shop-1${US}shop-1.web.app${US}${US}firebase${US}
g@x${US}other/other${US}other${US}other.web.app${US}/the/folder${US}firebase${US}"
  rr(){ rank_rows "$@" <<<"$landing" | cut -d"$US" -f3,12 | tr "$US" ' '; }
  check "rank: saved folder path wins"             grep -qx "other 0" <<<"$(rr /the/folder "" "" "" "")"
  check "rank: .firebaserc project is config"      grep -qx "shop-1 1" <<<"$(rr /x shop-1 "" "" "")"
  check "rank: firebase.json site is config"       grep -qx "shop-1 1" <<<"$(rr /x "" shop-1 "" "")"
  check "rank: .vercel link is config"             grep -qx "web 1" <<<"$(rr /x "" "" prj_v1 "")"
  check "rank: same name as the folder"            grep -qx "my-app 2" <<<"$(rr /x "" "" "" "my-app")"
  check "rank: nothing matches"                    is "$(rr /x "" "" "" "zzz" | cut -d' ' -f2 | sort -u)" 9
  check "rank: a site named like the folder"       grep -qx "shop-1 3" <<<"$(rr /x "" "" "" "shop-1-web shopweb")"
  check "rank: short names never match by prefix"  grep -qx "web 9" <<<"$(rr /x "" "" "" "we")"
  check "rank: a project linked to another folder never matches" grep -qx "other 9" <<<"$(rr /x other "" "" "other")"
  check "rank: the best match's group comes first" is "$(rank_rows /x shop-1 "" "" "" <<<"$landing" | head -1 | cut -d"$US" -f6)" firebase
  two="g@x${US}shop-1/shop-1${US}shop-1${US}shop-1.web.app${US}${US}firebase${US}${US}Shop
g@x${US}other/other${US}other${US}other.web.app${US}${US}firebase${US}
g@x${US}shop-1/shop-admin${US}shop-admin${US}shop-admin.web.app${US}${US}firebase${US}${US}Shop"
  check "sites: a project's sites stay together"   is "$(rank_rows /x "" "" "" "" <<<"$two" | cut -d"$US" -f3 | tr '\n' ' ')" "shop-1 shop-admin other "
  check "sites: each row knows its project's size" is "$(rank_rows /x "" "" "" "" <<<"$two" | cut -d"$US" -f14 | tr '\n' ' ')" "2 2 1 "
  check "label guess: admin from the folder"       is "$(guess_label /x/SukunGardenAdmin)" admin
  check "label guess: landing from a web folder"   is "$(guess_label /x/sukun-garden-web)" landing
  check "label guess: nothing from a plain name"   is "$(guess_label /x/thoub)" ""
  check "name: cleaned and confirmed"              is "$(confirm_name "Site" "" "NAME.web.app" <<<$'Admin.Sukun Garden\n\n')" admin-sukun-garden
  check "name: change the name asks again"         is "$(confirm_name "Site" "" "NAME.web.app" <<<$'first\nesecond\n\n')" second
  check "name: back gives nothing"                 is "$(confirm_name "Site" "" "NAME.web.app" <<<$'first\n\e')" ""
  check "name: blank backs out"                    not confirm_name "Site" "" "NAME.web.app" <<<$'\n'

  # static sites: no build, the folder holding index.html goes up as it is
  st="$(mktemp -d)"; mkdir -p "$st/site/.well-known" "$st/site/privacy" "$st/.git" "$st/node_modules/x" "$st/scripts"
  : > "$st/site/index.html"; : > "$st/site/.well-known/apple-app-site-association"; : > "$st/site/privacy/index.html"; : > "$st/site/og-image.png"
  : > "$st/site/.DS_Store"; : > "$st/.git/HEAD"; : > "$st/node_modules/x/i.js"; : > "$st/scripts/deploy.mjs"
  printf '{"name":"w","version":"1.0.0","scripts":{"dev":"serve site"}}' > "$st/package.json"
  check "static: a project without a build script"   not has_build "$st"
  check "static: the web root is site/"              is "$(web_root "$st")" site
  check "static: a folder with index.html is a project" is_project "$st"
  check "static: outdir falls back to the web root"  is "$(outdir "$st")" site
  check "static: files counted without .git and modules" is "$(nfiles "$st/site")" "4 files"
  sd="$(mktemp -d)"; STATIC=site stage_firebase "$st" "$sd" shop-1
  check "static firebase: .well-known comes along"   test -f "$sd/public/.well-known/apple-app-site-association"
  check "static firebase: cleanUrls, no SPA rewrite" bash -c 'grep -q cleanUrls "$1" && ! grep -q rewrites "$1" && ! grep -q "\*\*/\.\*" "$1"' _ "$sd/firebase.json"
  check "static firebase: .DS_Store dropped"         test ! -e "$sd/public/.DS_Store"
  sr="$(mktemp -d)"; : > "$sr/index.html"; mkdir -p "$sr/.git"; : > "$sr/.git/HEAD"
  check "static: index.html at the root, no package.json" is "$(outdir "$sr")" .
  check "static: find_root from inside it"           is "$(cd "$sr" && find_root)" "$sr"
  sd2="$(mktemp -d)"; STATIC=. stage_dist "$sr" "$sd2" prj_9 org w
  check "static vercel: the repo is not uploaded"    test ! -e "$sd2/.git"
  check "static vercel: cleanUrls instead of the rewrite" bash -c 'grep -q cleanUrls "$1" && ! grep -q rewrites "$1"' _ "$sd2/vercel.json"
  sd3="$(mktemp -d)"; mkdir -p "$p/dist"; : > "$p/dist/index.html"; rm -f "$p/vercel.json"; STATIC="" stage_dist "$p" "$sd3" prj_9 org w
  check "app vercel: the SPA rewrite stays for a build" grep -q rewrites "$sd3/vercel.json"

  # build output folder and Firebase staging
  check "outdir: dist first"                      is "$(outdir "$p")" dist
  rm -rf "$p/dist"; mkdir -p "$p/build"; : > "$p/build/index.html"
  check "outdir: build when there is no dist"     is "$(outdir "$p")" build
  printf '{"hosting":{"public":"build","headers":[{"source":"**","headers":[]}]}}' > "$p/firebase.json"
  st3="$(mktemp -d)"; stage_firebase "$p" "$st3" shop-1
  check "firebase stage: build copied to public/" test -f "$st3/public/index.html"
  check "firebase stage: our site and folder"     python3 -c 'import json,sys;h=json.load(open(sys.argv[1]))["hosting"];assert h["site"]=="shop-1" and h["public"]=="public"' "$st3/firebase.json"
  check "firebase stage: project headers kept"    python3 -c 'import json,sys;assert "headers" in json.load(open(sys.argv[1]))["hosting"]' "$st3/firebase.json"
  check "firebase stage: SPA rewrite added"       grep -q '"/index.html"' "$st3/firebase.json"
  check "firebase stage: repo firebase.json untouched" grep -q '"public":"build"' "$p/firebase.json"
  # back paths never dead-end
  check "pick_account: back returns 1"        not pick_account <<<"$(printf '\e')"
  check "new project: Esc on Where backs out" not new_project <<<"$(printf '\e')"
  check "new project: Firebase account step has back" not new_project firebase <<<"$(printf '\e')"
  fbin2="$(mktemp -d)"; printf '#!/bin/sh\necho "No authorized accounts"\n' > "$fbin2/firebase"; chmod +x "$fbin2/firebase"
  check "add account: quit backs out of first run" not bash -c "PATH='$fbin2:\$PATH'; source ./ship-site/ship-site; printf '\\e[B\\e[B\\n' | add_any_account >/dev/null 2>&1"
  # version guard on the web side
  p="$(mktemp -d)"; printf '{"name":"w","version":"1.0.0","scripts":{"build":"true"}}' > "$p/package.json"
  check "web version: Enter publishes as is"  bash -c "source ./ship-site/ship-site; web_version_guard '$p' <<<'' >/dev/null 2>&1; grep -q '\"version\": \"1.0.0\"\|\"version\":\"1.0.0\"' '$p/package.json'"
  printf '\e[B\n\n' | DRY=yes web_version_guard "$p" >/dev/null 2>&1 || true
  check "web version: dry bump leaves package.json" grep -q '"version":"1.0.0"' "$p/package.json"
  if command -v npm >/dev/null; then
    printf '\e[B\n\n' | web_version_guard "$p" >/dev/null 2>&1 || true
    check "web version: bump writes 1.0.1 via npm" grep -q '"version": *"1.0.1"' "$p/package.json"
  fi
  # a dry deploy end to end through deploy(): test version, firebase, nothing saved
  mkdir -p "$p/dist"; : > "$p/dist/index.html"
  cat > "$fbin2/firebase" <<'FAKE'
#!/bin/sh
case "$1" in login:list) echo "Logged in as a@x.com" ;; --version) echo 15.0.0 ;; hosting:sites:list) echo '{"status":"success","result":{"sites":[{"name":"projects/shop-1/sites/shop-1"}]}}' ;; esac
FAKE
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=yes; PROD=""; printf "t" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "deploy dry: test version by key"     grep -q "hosting:channel:deploy preview" <<<"$out"
  check "deploy dry: passed"                  grep -q "dry run passed" <<<"$out"
  check "deploy dry: folder link not saved"   is "$(vc proj_get "$p" id)" ""
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=yes; PROD=""; printf "m\n" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "deploy dry: main website skips the y-confirm in a dry run" grep -q "firebase deploy --only hosting" <<<"$out"
  p2="$(mktemp -d)"; cp "$p/package.json" "$p2/"
  # the y-confirm guards a real main-website publish picked by a single key
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "mx" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "deploy: main website by key, then not y → cancelled" grep -q "cancelled — nothing was published" <<<"$out"
  check "deploy: a cancelled publish links nothing"          is "$(vc proj_get "$p" id)" ""
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "myp" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "deploy: no label question in the flow"              not grep -q "Label for" <<<"$out"
  check "deploy: the folder is linked"                       is "$(vc proj_get "$p" id)" shop-1/shop-1
  vc label_set shop-1/shop-1 admin
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "myp" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "deploy: the label heads the screen"                 grep -q "▸ admin" <<<"$out"
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "dadmin.shop.dev\nr\e" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p" 2>&1 || true)"
  check "publish-to: custom domain saved from that screen"   is "$(vc domain_get shop-1/shop-1)" admin.shop.dev
  check "publish-to: the screen redraws with the domain"     grep -q "DNS pending" <<<"$out"
  check "publish-to: main website names the domain"          grep -q "web.app and admin" <<<"$out"
  vc domain_set shop-1/shop-1 ""
  check "swap: another folder on the same site is warned and backs out" not bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "tn" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p2"
  out="$(bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "tn" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p2" 2>&1 || true)"
  check "swap: the warning names the other folder"           grep -q "is published from $p" <<<"$out"
  check "swap: backing out keeps the old link"               is "$(vc folder_of shop-1/shop-1)" "$p"
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "ty" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p2" 2>&1 || true)"
  check "swap: y goes on and relinks the folder"             is "$(vc proj_get "$p2" id)" shop-1/shop-1
  cat > "$fbin2/firebase" <<'FAKE'
#!/bin/sh
case "$1" in login:list) echo "Logged in as a@x.com" ;; --version) echo 15.0.0 ;; hosting:sites:list) echo '{"status":"success","result":{"sites":[{"name":"projects/shop-1/sites/shop-1"}]}}' ;; hosting:sites:create) echo "created $2" ;; esac
FAKE
  p3="$(mktemp -d)/ShopAdmin"; mkdir -p "$p3/dist"; : > "$p3/dist/index.html"; cp "$p/package.json" "$p3/"
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; printf "s\n\n\e" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$p3" 2>&1 || true)"
  check "new site here: suggested from the folder and project" grep -q "create  admin-shop-1.web.app  in shop-1" <<<"$out"
  check "new site here: created in the same project"         grep -q "created site “admin-shop-1”" <<<"$out"
  check "new site here: the screen redraws as the new site"  grep -q "▸ admin-shop-1" <<<"$out"
  check "new site here: cached under the project"            grep -q "shop-1/admin-shop-1" <<<"$(vc landing)"
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=no; PROD=""; deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase < <(printf "s\n\nmyp"); echo "done=$DONE_ID"' _ "$p3" 2>&1 || true)"
  check "new site here: the done screen gets the new site"   grep -q "done=shop-1/admin-shop-1" <<<"$out"
  out="$(PATH="$fbin2:$PATH" bash -c 'source ./ship-site/ship-site; DRY=yes; PROD=""; printf "ty" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$st" 2>&1 || true)"
  check "static dry run: says files go up as they are" grep -q "static site: site/ with 4 files" <<<"$out"
  check "static dry run: no build command"           not grep -q "npm run build" <<<"$out"
  check "static dry run: passes"                     grep -q "dry run passed" <<<"$out"
  rm -rf "$st/site"
  out="$(bash -c 'source ./ship-site/ship-site; DRY=yes; PROD=""; printf "ty" | deploy a@x.com shop-1/shop-1 shop-1 "$1" firebase' _ "$st" 2>&1 || true)"
  check "static: nothing to publish is explained"    grep -q "no build script in package.json, and no index.html" <<<"$out"
  check "new site here: not offered on Vercel"               not grep -q "new site here" <<<"$(bash -c 'source ./ship-site/ship-site; DRY=yes; PROD=""; printf "\e" | deploy me prj_9 shop "$1" vercel' _ "$p" 2>&1)"
  vc proj_set "$p2" id ""
  check "done: back to projects returns"                     bash -c 'source ./ship-site/ship-site; URL=https://x; printf "p" | done_menu firebase a@x.com shop-1/shop-1 shop-1 /tmp'
  out="$(bash -c 'source ./ship-site/ship-site; URL=https://x; printf "lmine\np" | done_menu firebase a@x.com shop-1/shop-1 shop-1 /tmp' 2>&1)"
  check "done: console link shown"                           grep -q "console.firebase.google.com/project/shop-1/hosting/sites/shop-1" <<<"$out"
  check "done: label saved from the done screen"             is "$(vc label_get shop-1/shop-1)" mine
  out="$(bash -c 'source ./ship-site/ship-site; vc domain_set shop-1/shop-1 shop.example.com; URL=https://x; printf "p" | done_menu firebase a@x.com shop-1/shop-1 shop-1 /tmp' 2>&1)"
  check "done: a saved domain shows on the screen"           grep -q shop.example.com <<<"$out"
  out="$(bash -c 'source ./ship-site/ship-site; DRY=no; printf "Admin.SukunGarden.com\nr" | custom_domain firebase a@x.com shop-1/shop-1 shop-1' 2>&1)"
  check "domain: remembered without connecting"              is "$(vc domain_get shop-1/shop-1)" admin.sukungarden.com
  check "domain: says it is a reminder"                      grep -q "remembered admin.sukungarden.com" <<<"$out"
  out="$(bash -c 'source ./ship-site/ship-site; DRY=no; printf "shop.vercel.dev\n" | custom_domain vercel me prj_9 shop' 2>&1)"
  check "domain: vercel keeps a reminder and points at vercel.com" grep -q "vercel.com › shop › Domains" <<<"$out"
  check "domain: vercel reminder saved"                      is "$(vc domain_get prj_9)" shop.vercel.dev
  check "domain: a bad one is refused"                       not bash -c 'source ./ship-site/ship-site; DRY=no; printf "not a domain\n" | custom_domain firebase a@x.com shop-1/shop-1 shop-1'
  check "domain: a missing ending is questioned"             not bash -c 'source ./ship-site/ship-site; DRY=no; printf "admin.sukungarden\nn" | custom_domain firebase a@x.com shop-1/shop-1 shop-1'
  out="$(bash -c 'source ./ship-site/ship-site; DRY=no; printf "admin.sukungarden\nn" | custom_domain firebase a@x.com shop-1/shop-1 shop-1' 2>&1 || true)"
  check "domain: the question names the missing .com"        grep -q "needs its .com" <<<"$out"
  out="$(bash -c 'source ./ship-site/ship-site; show_records shop-1 shop-1 admin.example.com "$(printf "CNAME\tadmin.example.com\tshop-1.web.app\nTXT\t_acme-challenge.admin.example.com\tabc\nA\texample.com\t1.2.3.4")"' 2>&1)"
  check "records: host shown the registrar's way"           grep -q "CNAME  admin  " <<<"$out"
  check "records: _acme-challenge host kept short"           grep -q "_acme-challenge.admin" <<<"$out"
  check "records: @ for the domain itself"                   grep -q "A      @" <<<"$out"
  check "records: live means nothing to add"                 grep -q "connected and live" <<<"$(bash -c 'source ./ship-site/ship-site; show_records shop-1 shop-1 a.example.com "live	HOST_ACTIVE"' 2>&1)"
  check "pending: nothing without a saved domain"            is "$(bash -c 'source ./ship-site/ship-site; pending_records a@x.com shop-1/shop-1' 2>&1)" ""
  check "domain: y keeps an odd ending"                      bash -c 'source ./ship-site/ship-site; DRY=no; printf "admin.sukungarden\nyr" | custom_domain firebase a@x.com shop-1/shop-1 shop-1' && [ "$(vc domain_get shop-1/shop-1)" = admin.sukungarden ]
  vc domain_set shop-1/shop-1 ""; vc domain_set prj_9 ""
  # cache: a young cache skips the refresh, a stale one runs it
  vc stamp; check "refresh fresh: young cache returns at once" bash -c "source ./ship-site/ship-site; refresh fresh; [ \"\$(vc age)\" -lt 5 ]"
  # removed Firebase account disappears from the list
  vc cache_add z@y shop-9/shop-9 shop-9 shop-9.web.app firebase shop-9
  check "landing: a Firebase account not signed in is hidden" not grep -q shop-9 <<<"$(vc landing)"
  # helpers
  check "slugify: spaces and punctuation"     is "$(slugify "  My App!! v2 ")" my-app-v2
  : > "$p/yarn.lock"; check "detect_pm: yarn" is "$(detect_pm "$p")" yarn
  rm -f "$p/yarn.lock"; : > "$p/bun.lock"; check "detect_pm: bun" is "$(detect_pm "$p")" bun
  rm -rf "$p/dist" "$p/build"; mkdir -p "$p/out"; : > "$p/out/index.html"
  check "outdir: Next.js export in out/"       is "$(outdir "$p")" out
  rm -rf "$p/out"; mkdir -p "$p/_site"; : > "$p/_site/index.html"
  check "outdir: Eleventy or Jekyll in _site/" is "$(outdir "$p")" _site
  rm -rf "$p/_site"; check "outdir: nothing built → empty" is "$(outdir "$p")" ""
  printf '{"hosting":[{"site":"first"},{"site":"second"}]}' > "$p/firebase.json"
  check "firebase.json: list form reads the first site" is "$(firebase_json_site "$p")" first
  check "fit: exact width is untouched"       is "$(fit abcdef 6)" abcdef
  check "term_size: two numbers"              bash -c 'source ./ship-site/ship-site; term_size | grep -Eq "^[0-9]+ [0-9]+$"'
  check "confirm: capital Y also goes"        confirm_y "go?" <<<"Y"
  # the Linux branches of the platform helpers, driven by fake GNU stat and date (macOS has the BSD ones)
  gnu="$(mktemp -d)"
  cat > "$gnu/stat" <<'FAKE'
#!/bin/sh
[ "$1" = "-c" ] || { echo "stat: illegal option" >&2; exit 1; }
case "$2" in %s) wc -c < "$3" | tr -d ' ' ;; %Y) echo 1700000000 ;; %a) echo 600 ;; esac
FAKE
  printf '#!/bin/sh\n[ "$1" = "-d" ] || { echo bad >&2; exit 1; }\necho "gnu-date $2 $3"\n' > "$gnu/date"; chmod +x "$gnu/stat" "$gnu/date"
  f="$(mktemp)"; printf 'abcde' > "$f"
  check "linux: fsize via stat -c"            is "$(OS=linux PATH="$gnu:$PATH" fsize "$f")" 5
  check "linux: fmtime via stat -c"           is "$(OS=linux PATH="$gnu:$PATH" fmtime "$f")" 1700000000
  check "linux: fmode via stat -c"            is "$(OS=linux PATH="$gnu:$PATH" fmode "$f")" 600
  check "linux: fdate via date -d"            is "$(OS=linux PATH="$gnu:$PATH" fdate 1700000000 '+%d')" "gnu-date @1700000000 +%d"
  check "linux: BSD flags never reach GNU stat" bash -c "OS=linux; PATH='$gnu:$PATH'; source ./ship-site/ship-site; OS=linux; [ \"\$(fmode '$f')\" = 600 ]"
  check "clip: no tool → false, no crash"     not bash -c 'PATH=/bin; source ./ship-site/ship-site; printf x | clip'
  check "open_it: nothing to open with → false" not bash -c 'OS=linux; PATH=/nonexistent; source ./ship-site/ship-site; OS=linux; open_it /tmp'
  check "tmpf: makes a file"                  test -f "$(tmpf abc)"
  check "tmpd: makes a folder"                test -d "$(tmpd abc)"
  check "py: python is found"                 py -c 'print(1)'
  rm -rf "$gnu" "$f"
  rm -rf "$p" "$st" "$st2" "$st3" "$fbin2"
)

echo "── developer-tools"
( source ./developer-tools
  check "pick: down then Enter"               is "$(pick a b c <<<"${down}${enter}" 2>/dev/null)" 1
  check "pick: i is install"                  is "$(pick "run a tool" "install or update" "remove" "quit" <<<"i" 2>/dev/null)" 1
  check "pick: c is channel"                  is "$(pick "run a tool" "install or update" "remove" "channel" "quit" <<<"c" 2>/dev/null)" 3
  check "tick: Enter keeps everything"        is "$(tick a b c <<<"$enter" 2>/dev/null)" "0 1 2 "
  check "tick: space unticks the first"       is "$(tick a b c <<<" ${enter}" 2>/dev/null)" "1 2 "
  check "tick: move down, untick the second"  is "$(tick a b c <<<"${down} ${enter}" 2>/dev/null)" "0 2 "
  check "tick: untick then tick again"        is "$(tick a b <<<"  ${enter}" 2>/dev/null)" "0 1 "
  check "channel: stable by default"          is "$(channel)" stable
  set_channel beta;   check "channel: switch to beta"    is "$(channel)" beta
  set_channel stable; check "channel: back to stable"    is "$(channel)" stable
  DEVTOOLS_BASE=file:///x resolve_base; check "base: DEVTOOLS_BASE wins" is "$BASE" file:///x
  unset DEVTOOLS_BASE; resolve_base;     check "base: stable → latest"   is "$BASE" "https://github.com/azharbinanwar/developer-tools/releases/latest/download"
  cb="$(mktemp -d)"; cat > "$cb/curl" <<'FAKE'
#!/bin/sh
echo '[{"tag_name":"v9.0.0-beta.3"}]'
FAKE
  chmod +x "$cb/curl"
  set_channel beta; PATH="$cb:$PATH" resolve_base
  check "base: beta → newest tag, betas included" is "$BASE" "https://github.com/azharbinanwar/developer-tools/releases/download/v9.0.0-beta.3"
  printf '#!/bin/sh\nexit 22\n' > "$cb/curl"; PATH="$cb:$PATH" resolve_base 2>/dev/null
  check "base: beta with no GitHub falls back to stable" is "$BASE" "https://github.com/azharbinanwar/developer-tools/releases/latest/download"
  set_channel stable; rm -rf "$cb"
  hb2="$(mktemp -d)"; printf '#!/bin/sh\necho "ship-site 2.0.0-beta.1"\n' > "$hb2/ship-site"; chmod +x "$hb2/ship-site"
  check "status: a beta version is marked"    is "$(PATH="$hb2:/usr/bin:/bin" status ship-site)" "installed 2.0.0-beta.1 (beta)"
  rm -rf "$hb2"
  check "status: not installed"               is "$(PATH=/nonexistent status ship-apk)" "not installed"
  hb="$(mktemp -d)"; printf '#!/bin/sh\necho "ship-apk 9.9.9"\n' > "$hb/ship-apk"; chmod +x "$hb/ship-apk"
  check "status: installed with its version"  is "$(PATH="$hb:/usr/bin:/bin" status ship-apk)" "installed 9.9.9"
  check "label: name, note and status"        grep -q "9.9.9" <<<"$(PATH="$hb:/usr/bin:/bin" label 0)"
  rm -rf "$hb"
  check "tick: q quits without ticking"       is "$(tick a b <<<"q" 2>/dev/null)" ""
  check "hub: --help lists the install mode"  bash -c 'bash ./developer-tools --help | grep -q "install or update every tool"'
  check "hub: --help shows beta install"      bash -c 'bash ./developer-tools --help | grep -q "developer-tools beta install"'
  check "hub: beta alone only sets the channel" bash -c 'bash ./developer-tools beta 2>&1 | grep -q "channel set to beta"; [ "$(cat "$HOME/.config/developer-tools/channel")" = beta ]'
  check "hub: stable alone sets it back"      bash -c 'bash ./developer-tools stable >/dev/null 2>&1; [ "$(cat "$HOME/.config/developer-tools/channel")" = stable ]'
)
echo "all good"
