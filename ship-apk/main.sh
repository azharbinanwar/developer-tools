# needs: platform ui keys mail
# ship-apk: build a Flutter APK, ship it to appho.st, mail the link.
#
# One file. Settings and send logs live in ~/.config/ship-apk, never in
# your project repos, so no email address or API key can ever be committed.
#
# Needs curl and python3 (built in on macOS and Linux) plus flutter or fvm to build; works on macOS, Linux and Windows (Git Bash or WSL).
# qrencode is used if present and skipped if not.
#
# License: MIT.

VERSION="2.1.0"
CONF="$HOME/.config/ship-apk"
CONFIG="$CONF/config.json"
LOGS="$CONF/logs"
MAIL_KIND=apk; MAIL_VERB="uploads"; MAIL_THING="app"   # how lib/mail.sh talks about this tool
mail_store(){ cfg "$@"; }                                # where this tool keeps who gets the mail
API="https://appho.st/api"
DRY=no; VERBOSE=no
MAX_MB=100          # appho.st free tier rejects builds bigger than this

# ── config ────────────────────────────────────────────────────────────────
# One python block owns the file; bash only ever asks it for lines.
cfg(){
py - "$CONFIG" "$@" <<'PY'
import json, os, sys

path, op = sys.argv[1], sys.argv[2]
a = sys.argv[3:]

try:
    d = json.load(open(path))
except Exception:
    d = {}

d.setdefault("smtp", {"host": "", "port": 465, "user": "", "password": "", "from_name": ""})
d.setdefault("projects", {})
d.setdefault("template", {
    "subject": "{app} {version} — new test build",
    "body": ("Hi {name},\n\n"
             "A new build of {app} is ready to install.\n\n"
             "    {link}\n\n"
             "Version {version}{notes}\n\n"
             "Open the link on the device you want to install it on.\n\n"
             "— {sender}"),
})

def save():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
    os.chmod(path, 0o600)          # it holds API keys and a mail password

if not os.path.exists(path):
    save()

def proj(key):
    return d["projects"].setdefault(key, {"path": "", "app": "", "app_id": "", "user_id": "", "key": "", "to": [], "bcc": []})

def ago(t):  # epoch -> "today", "3d ago", "2mo ago"; "" for none
    import time
    if not t: return ""
    d_ = (int(time.time()) - int(t)) // 86400
    if d_ < 1: return "today"
    if d_ < 7: return "%dd ago" % d_
    if d_ < 30: return "%dw ago" % (d_ // 7)
    if d_ < 365: return "%dmo ago" % (d_ // 30)
    return "%dy ago" % (d_ // 365)

if op == "projects":   # key path app app_id people count last
    for k in sorted(d["projects"]):
        p = d["projects"][k]
        print("\x1f".join([k, p.get("path", ""), p.get("app", ""), p.get("app_id", ""), str(len(p.get("to", []))),
                           str(p.get("count", "") or ""), ago(p.get("last"))]))
elif op == "stat_add":   # key -> one more build shipped, now
    import time
    p = proj(a[0]); p["count"] = p.get("count", 0) + 1; p["last"] = int(time.time()); save()
elif op == "proj_get":   print(d["projects"].get(a[0], {}).get(a[1], ""))
elif op == "proj_set":   proj(a[0])[a[1]] = a[2]; save()
elif op == "proj_del":   d["projects"].pop(a[0], None); save()
elif op == "people":          # key [to|bcc]
    for r in proj(a[0]).get(a[1] if len(a) > 1 else "to", []):
        # never an empty name: bash reads these tab-separated, and an empty first field would swallow the address
        print("%s\t%s" % (r.get("name") or r.get("email", "").split("@")[0], r.get("email", "")))
elif op == "person_add":      # key name email [to|bcc]
    p = proj(a[0]); f = a[3] if len(a) > 3 else "to"
    p[f] = [r for r in p.get(f, []) if r.get("email") != a[2]]
    p[f].append({"name": a[1], "email": a[2]}); save()
elif op == "person_del":      # key email [to|bcc]
    p = proj(a[0]); f = a[2] if len(a) > 2 else "to"
    p[f] = [r for r in p.get(f, []) if r.get("email") != a[1]]; save()
elif op == "subject_get":      print(d["projects"].get(a[0], {}).get("subject", ""))
elif op == "subject_set":      proj(a[0])["subject"] = a[1]; save()
elif op == "sha_get":          print(d["projects"].get(a[0], {}).get("last_sha", ""))
elif op == "sha_set":          proj(a[0])["last_sha"] = a[1]; save()
elif op == "mail_default_get": print(d["projects"].get(a[0], {}).get("mail_default", ""))
elif op == "mail_default_set": proj(a[0])["mail_default"] = a[1]; save()
elif op == "mail_json":        # key -> {"to": [...], "cc": [...], "bcc": [...], "subject": ""} for send_mail
    p = d["projects"].get(a[0], {})
    print(json.dumps({f: p.get(f, []) for f in ("to", "cc", "bcc")} | {"subject": p.get("subject", "")}))
else: sys.exit(2)
PY
}

ACTIONS=""
IFS= read -r -d '' ACTIONS <<'ACTS' || true   # a heredoc, so option texts may hold quotes
add this app|app.add|a
add app|app.add|a
edit an app|app.edit|e
mailbox|mailbox|m
quit|quit|q
ship as|version.keep|s
bump|version.bump|b
build a fresh one|build.fresh|f
use the last build|build.last|l
back to apps|apps|a
send the link|mail.send|s
skip mail this time|mail.skip|x
change to, cc, bcc or subject|mail.change|c
set up mailbox|mail.setup_box|m
set up this app's email|mail.setup_app|e
use these|notes.use|u
write my own|notes.write|w
no notes|notes.none|x
open the apk folder|done.folder|o
open the link in the browser|done.link|l
retry the upload|upload.retry|r
to|edit.to|t
cc|edit.cc|c
bcc|edit.bcc|b
subject|edit.subject|s
app name|edit.name|a
app id|edit.id|i
folder|edit.folder|f
credentials|edit.credentials|r
remove this app|edit.remove|d
address|box.address|a
password|box.password|p
smtp host|box.host|h
port|box.port|o
from name|box.from|f
send a test to myself|box.test|t
edit the mail template|box.template|e
add to|people.add|a
rename|person.rename|r
change address|person.address|c
remove|person.remove|d
back|back|esc
ACTS

PROJ_KEYS=(); PROJ_PATHS=()
HIT=-1
load_projects(){ # $1 current folder (optional) -> fills the app rows; HIT = row of that folder's app, or -1
  local here="${1:-}" note mail k path app id n cnt last st
  HIT=-1
  PROJ_KEYS=(); PROJ_PATHS=(); MENU_ITEMS=(); MENU_NOTES=()
  while IFS=$'\x1f' read -r k path app id n cnt last; do   # \x1f, not a tab: bash collapses empty tab fields
    [ -n "$k" ] || continue
    PROJ_KEYS+=("$k"); PROJ_PATHS+=("$path")
    if   [ -n "$here" ] && [ "$path" = "$here" ]; then note="  ${G}● this folder${R}"; HIT=$(( ${#PROJ_KEYS[@]} - 1 ))
    elif [ ! -d "$path" ]; then note="  ${Y}folder missing${R}"
    else note="  ${D}$(sed "s|^$HOME|~|" <<<"$path")${R}"; fi
    [ "$n" -gt 0 ] && mail="$n $([ "$n" = 1 ] && echo person || echo people)" || mail="no mail"
    st=""; [ -n "$cnt" ] && st="${cnt}× · ${last}"
    MENU_ITEMS+=("$(printf '%-22s' "${app:-$k}")")
    MENU_NOTES+=("  ${D}$(printf '%-12s %-11s %-13s' "${id:0:10}" "$mail" "$st")${R}$note")
  done < <(cfg projects)
}

# ── project detection ─────────────────────────────────────────────────────
# Walks up from the working directory; a pubspec.yaml is what makes it a project.
find_root(){
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/pubspec.yaml" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}
proj_version(){ # $1 root -> "1.0.0+104" from pubspec, or a date stamp
  local v; v="$(sed -n 's/^version: *//p' "$1/pubspec.yaml" 2>/dev/null | head -1 | tr -d ' \r')"
  printf '%s' "${v:-$(date '+%Y.%m.%d-%H%M')}"
}
# fvm pins a Flutter version per project; use it when the project says to.
flutter_cmd(){ # $1 root
  if [ -f "$1/.fvmrc" ] || [ -d "$1/.fvm" ]; then
    have fvm && { printf 'fvm flutter'; return; }
    warn "this project pins Flutter with fvm but fvm is not installed — using plain flutter" >&2
  fi
  printf 'flutter'
}

# ── build ─────────────────────────────────────────────────────────────────
last_build(){ # $1 root -> newest release apk inside that project, if any
  ls -t "$1"/build/app/outputs/flutter-apk/app-release.apk \
        "$1"/build/app/outputs/apk/release/app-release.apk 2>/dev/null | head -1
}
build_apk(){ # $1 root -> echoes the apk path on stdout, nothing else
  local root="$1" fl out log pid started elapsed last
  fl="$(flutter_cmd "$root")"
  log="$LOGS/$(basename "$root")-build.log"; mkdir -p "$LOGS"
  step "Building"
  row "project" "$(basename "$root")"
  row "flutter" "$fl"
  row "version" "$(proj_version "$root")"
  row "log" "${D}$log${R}"

  if [ "$VERBOSE" = yes ]; then
    printf "\n" >&2
    ( cd "$root" && $fl build apk --release ) >&2 2>&1 || { warn "the build failed"; return 1; }
  else
    ( cd "$root" && $fl build apk --release ) >"$log" 2>&1 &
    pid=$!
    started=$(date +%s)
    # one line, rewritten in place: elapsed time plus whatever gradle last said
    while kill -0 "$pid" 2>/dev/null; do
      elapsed=$(( $(date +%s) - started ))
      last="$(tr -d '\r' < "$log" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-52)"
      printf "\r\033[K     ${A}▪${R} ${D}%3ds${R}  %s" "$elapsed" "$last" >&2
      sleep 1
    done
    if ! wait "$pid"; then
      printf "\r\033[K" >&2
      warn "the build failed — last lines of $log:"
      tr -d '\r' < "$log" | tail -15 | while IFS= read -r l; do sub "$l"; done
      return 1
    fi
    printf "\r\033[K" >&2
    ok "built in $(( $(date +%s) - started ))s  ${D}(run with -v to watch it)${R}"
  fi

  out="$(last_build "$root")"
  [ -n "$out" ] || { warn "the build reported success but no apk was found"; return 1; }
  printf '%s' "$out"
}

# ── notes ─────────────────────────────────────────────────────────────────
# What changed since the last time this project was shipped, so the mail says
# something. Empty if the folder is not a git repo.
# ── upload ────────────────────────────────────────────────────────────────
UPLOAD_LINK=""
do_upload(){ # $1 apk  $2 project key  $3 app name  $4 version -> sets UPLOAD_LINK
  local apk="$1" key="$2" name="$3" version="$4"
  local user_id apikey app_id url link code copied err rc try bytes
  UPLOAD_LINK=""
  user_id="$(cfg proj_get "$key" user_id)"; apikey="$(cfg proj_get "$key" key)"; app_id="$(cfg proj_get "$key" app_id)"

  bytes="$(fsize "$apk")"
  if [ "$bytes" -gt $((MAX_MB * 1048576)) ]; then
    warn "$((bytes / 1048576)) MB is over the ${MAX_MB} MB free-tier limit — appho.st will probably reject it"
    [ "$(ask_yn "Try the upload anyway" true)" = true ] || return 1
  fi

  # drop arrow keys typed during the menus — only on a real terminal: at end of a closed stdin, Linux reports
  # "input available" forever and the old unconditional loop never ended
  if [ -t 0 ]; then while read -rst 0 _ 2>/dev/null; do IFS= read -rsn 1000 -t 1 _ 2>/dev/null || break; done; fi
  step "Uploading"
  row "build" "$(basename "$apk")  ${D}$((bytes / 1048576)) MB${R}"
  row "app" "$name"
  row "version" "$version"
  printf "\n" >&2

  # no -f: appho.st reports problems as a 4xx with the reason in the body.
  err="$(tmpf shipapk)"
  url="$(curl -sSG "$API/get_upload_url" \
    --data-urlencode "user_id=$user_id" --data-urlencode "app_id=$app_id" \
    --data-urlencode "key=$apikey" --data-urlencode "platform=android" \
    --data-urlencode "version=$version" 2>"$err")"
  rc=$?
  case "$url" in
    https://*) rm -f "$err" ;;
    "") warn "appho.st sent nothing back (curl exit $rc)"
        [ -s "$err" ] && sub "$(tr -d '\r' < "$err" | head -3)"
        rm -f "$err"; return 1 ;;
    *)  warn "appho.st refused: $url"
        sub "the three values come from the app page › Private API › download config"
        rm -f "$err"; return 1 ;;
  esac

  # curl exits 0 on a 4xx from storage, so the status code is the real verdict
  code="$(curl -H 'Content-Type: application/octet-stream' -T "$apk" "$url" -o /dev/null -w '%{http_code}' --progress-bar)"; rc=$?
  [ "$rc" -eq 0 ] || { warn "upload interrupted — the network dropped or appho.st was unreachable (curl exit $rc)"; return 1; }
  case "$code" in 2??) ;; *) warn "appho.st storage rejected the build (HTTP $code)"; return 1 ;; esac

  # the link appears a moment after the PUT lands, so give it a few tries
  for try in 1 2 3 4 5; do
    link="$(curl -sG "$API/get_current_version/" \
      --data-urlencode "u=$user_id" --data-urlencode "a=$app_id" --data-urlencode "platform=android" \
      | py -c 'import json,sys;print(json.load(sys.stdin).get("url",""))' 2>/dev/null)"
    [ -n "$link" ] && break
    sleep 2
  done

  step "Uploaded"
  row "app" "$name"
  row "version" "$version"
  row "when" "$(date '+%d %b %Y, %H:%M')"
  if [ -n "$link" ]; then
    printf %s "$link" | clip 2>/dev/null && copied="  ${D}copied${R}"
    row "link" "${B}${A}${link}${R}$copied"
    have qrencode && { printf "\n" >&2; qrencode -t ANSIUTF8 -m 2 "$link" >&2; }
    UPLOAD_LINK="$link"
  else
    warn "no link returned yet — it usually appears on the dashboard within a minute"
    return 1
  fi
}


bump_version(){ # $1 version like 1.4.2+17  $2 build|patch|minor|major -> next version; the +build always goes up when present
  local name="${1%%+*}" build="" ma mi pa
  name="${name%%-*}"   # a pre-release tag (1.0.0-beta.1) is dropped: bumping moves past it
  case "$1" in *+*) build="${1#*+}" ;; esac
  IFS=. read -r ma mi pa <<<"$name"; ma="${ma:-0}"; mi="${mi:-0}"; pa="${pa:-0}"
  case "$2" in
    patch) pa=$((pa + 1)) ;;
    minor) mi=$((mi + 1)); pa=0 ;;
    major) ma=$((ma + 1)); mi=0; pa=0 ;;
  esac
  case "$build" in ''|*[!0-9]*) [ "$2" = build ] && build=1 ;; *) build=$((build + 1)) ;; esac
  printf '%s%s' "$ma.$mi.$pa" "${build:++$build}"
}

version_guard(){ # $1 key  $2 root  $3 version -> shows the version, bumps only if asked; echoes the version to ship
  local key="$1" root="$2" v="$3" nv repeat=no
  # only a real pubspec version is offered for a bump; the date stamp used when pubspec has none is not
  grep -q '^version: *[0-9]' "$root/pubspec.yaml" 2>/dev/null || { printf '%s' "$v"; return; }
  [ "$v" = "$(cfg proj_get "$key" last_version)" ] && repeat=yes
  step "Version  ${B}$v${R}$([ "$repeat" = yes ] && printf "  ${Y}shipped last time${R}")"
  MENU_ITEMS=("ship as $v" "bump"); MENU_NOTES=("" "  ${D}next build is $(bump_version "$v" build), or type your own${R}")
  [ "$(menu_pick "Version" -1 "$([ "$repeat" = yes ] && echo 1 || echo 0)")" = 0 ] && { printf '%s' "$v"; return; }
  while :; do
    nv="$(ask "New version" "$(bump_version "$v" build)")"
    echo "$nv" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$' && break
    warn "“${nv}” is not a version like 1.0.0+4"
  done
  [ "$nv" = "$v" ] && { printf '%s' "$v"; return; }
  if [ "$DRY" = yes ]; then row "pubspec" "would become version: ${D}$v${R} → ${B}$nv${R}  ${D}(dry run, not written)${R}"; printf '%s' "$nv"; return; fi
  sed_i "s/^version:.*/version: $nv/" "$root/pubspec.yaml" || { warn "could not write pubspec.yaml"; printf '%s' "$v"; return; }
  row "pubspec" "version: ${D}$v${R} → ${B}$nv${R}"
  printf '%s' "$nv"
}


dry_ship(){ # $1 key $2 root $3 name $4 version $5 fresh $6 last apk $7 want_mail $8 notes -> checks, then what would happen; changes nothing
  local key="$1" root="$2" name="$3" version="$4" fresh="$5" apk="$6" want_mail="$7" notes="$8" fl bin r bad=0 idx
  step "Dry run · checks"
  fl="$(flutter_cmd "$root" 2>/dev/null)"; bin="${fl%% *}"
  have "$bin" && ok "$fl is installed" || { warn "✗ $bin is not installed"; bad=1; }
  grep -q '^version: *[0-9]' "$root/pubspec.yaml" && ok "pubspec.yaml has a version" || { warn "✗ pubspec.yaml has no version line — a date stamp would be used"; }
  [ -n "$(cfg proj_get "$key" app_id)" ] && ok "appho.st app id is set" || { warn "✗ no appho.st app id"; bad=1; }
  { [ -n "$(cfg proj_get "$key" user_id)" ] && [ -n "$(cfg proj_get "$key" key)" ]; } && ok "appho.st user_id and API key are set" || { warn "✗ appho.st user_id or API key missing"; bad=1; }
  MAIL="$want_mail"
  [ "$want_mail" = yes ] && { r="$(smtp_login_check)"; case "$r" in OK) ok "mailbox login works  ${D}$(mbox smtp_get user)${R}" ;; *) warn "✗ mailbox login failed: ${r#FAIL	}"; bad=1 ;; esac; }

  step "Dry run · would run"
  if [ "$fresh" = yes ]; then cmd "cd $root && $fl build apk --release"
  else row "build" "use the last build  ${D}$(sed "s|^$HOME|~|" <<<"$apk")${R}"; fi
  row "upload" "→ appho.st app $(cfg proj_get "$key" app_id)  ${D}as $name $version${R}"
  if [ "$want_mail" = yes ]; then
    step "Dry run · the mail that would go out"
    send_mail "$key" "$name" "$version" "https://appho.st/d/…" "$notes" yes | grep -v '^DRY' >&2
  else
    row "mail" "none — skipped"
  fi
  printf "\n" >&2
  [ "$bad" = 0 ] && ok "dry run passed — nothing was built, uploaded, mailed or written" \
                 || warn "dry run found problems above — nothing was built, uploaded, mailed or written"

  MENU_ITEMS=(); MENU_NOTES=()
  [ -n "$apk" ] && { MENU_ITEMS+=("open the APK folder"); MENU_NOTES+=("  ${D}$(sed "s|^$HOME|~|" <<<"$(dirname "$apk")")${R}"); }
  MENU_ITEMS+=("back to apps" "quit"); MENU_NOTES+=("" "")
  while :; do
    idx="$(menu_pick "What next" $(( ${#MENU_ITEMS[@]} - 1 )) $(( ${#MENU_ITEMS[@]} - 2 )))"
    case "${MENU_ITEMS[$idx]}" in
      "open the APK folder") open_it "$(dirname "$apk")" ;;
      "back to apps") return 0 ;;
      quit) return 1 ;;
    esac
  done
}

# ── ship ──────────────────────────────────────────────────────────────────
# The flow is: pick the build, settle mail (send, set it up, or skip), then
# build, upload and mail unattended, then a done menu. Nothing asks mid-run.
ship(){ # $1 project key  $2 root -> returns 1 when the user picked quit
  local key="$1" root="$2" apk name version notes="" idx result count fails want_mail n ready apkdir   # notes="" — on bash 5 a bare local is unset under set -u
  [ -f "$root/pubspec.yaml" ] || { warn "“${key}” points at ${root}, which has no pubspec.yaml — fix the folder under edit an app"; return 0; }
  version="$(proj_version "$root")"
  name="$(cfg proj_get "$key" app)"; [ -n "$name" ] || name="$key"
  [ -n "$(cfg proj_get "$key" app_id)" ] || cfg proj_set "$key" app_id "$(ask "appho.st app id for “${name}”" "")"
  [ -n "$(cfg proj_get "$key" app_id)" ] || { warn "no app id, nothing to upload to"; return 0; }
  { [ -n "$(cfg proj_get "$key" user_id)" ] && [ -n "$(cfg proj_get "$key" key)" ]; } || credentials "$key"

  printf "\n  ${D}%s${R}\n  ${B}%s${R}  ${D}%s${R}\n" "$RULE" "$name" "$version" >&2

  # 0. same version as last time? bump it (fresh build forced) or ship it again knowingly
  local was="$version"
  version="$(version_guard "$key" "$root" "$version")"

  # 1. which build
  apk="$(last_build "$root")"
  [ "$version" != "$was" ] && apk=""   # the last APK carries the old version
  MENU_ITEMS=("build a fresh one"); MENU_NOTES=("  ${D}$(flutter_cmd "$root") build apk --release${R}")
  if [ -n "$apk" ]; then
    MENU_ITEMS+=("use the last build")
    MENU_NOTES+=("  ${D}$(fdate "$(fmtime "$apk")" '+%d %b %H:%M')  $(( $(fsize "$apk") / 1048576 )) MB${R}")
  fi
  MENU_ITEMS+=("← back to apps"); MENU_NOTES+=("")
  step "Build"
  idx="$(menu_pick "Which build" $(( ${#MENU_ITEMS[@]} - 1 )) 0)"
  [ "$idx" -eq $(( ${#MENU_ITEMS[@]} - 1 )) ] && return 0
  local fresh=no; [ "$idx" -eq 0 ] && fresh=yes

  # 2. mail: send, set up what is missing (mailbox, then this app's email), or skip
  mail_step "$key" "$name"; want_mail="$MAIL"
  [ "$want_mail" = yes ] && notes="$(pick_notes "$root" "$key")"

  [ "$DRY" = yes ] && { dry_ship "$key" "$root" "$name" "$version" "$fresh" "$apk" "$want_mail" "$notes"; return; }

  # 3. nothing below asks anything — walk away
  if [ "$fresh" = yes ]; then apk="$(build_apk "$root")" || return 0; fi
  [ -n "$apk" ] || return 0
  until do_upload "$apk" "$key" "$name" "$version"; do
    MENU_ITEMS=("retry the upload" "back to apps" "quit"); MENU_NOTES=("  ${D}same APK, no rebuild${R}" "" "")
    case "$(menu_pick "Upload did not finish" 2 0)" in 1) return 0 ;; 2) return 1 ;; esac
  done
  cfg proj_set "$key" last_version "$version"; cfg proj_set "$key" last_date "$(date '+%d %b %H:%M')"; cfg stat_add "$key"

  MAIL="$want_mail"; mail_after "$key" "$name" "$version" "$UPLOAD_LINK" "$notes" "$root"; want_mail="$MAIL"

  # 4. done — what next; when no mail went out, opening the APK folder comes first
  apkdir="$(dirname "$apk")"
  [ "$want_mail" = no ] && idx=0 || idx=2
  while :; do
    MENU_ITEMS=("open the APK folder" "open the link in the browser" "back to apps" "quit")
    MENU_NOTES=("  ${D}$(sed "s|^$HOME|~|" <<<"$apkdir")${R}" "  ${D}${UPLOAD_LINK}${R}" "" "")
    step "Done"
    case "$(menu_pick "What next" 3 "$idx")" in
      0) open_it "$apkdir" || warn "open $apkdir yourself"; idx=2 ;;
      1) open_it "$UPLOAD_LINK" || warn "open $UPLOAD_LINK yourself"; idx=2 ;;
      2) return 0 ;;
      3) return 1 ;;
    esac
  done
}


add_app(){ # $1 folder (optional) -> echoes the new project key
  local root="${1:-}" key
  step "Add an app"
  while [ ! -f "$root/pubspec.yaml" ]; do
    root="$(ask "Flutter project folder" "")"
    [ -n "$root" ] || return 1
    root="${root/#\~/$HOME}"
    [ -f "$root/pubspec.yaml" ] || warn "no pubspec.yaml in that folder"
  done
  key="$(basename "$root")"
  cfg proj_set "$key" path "$root"
  cfg proj_set "$key" app "$(ask "App name (shown in the email)" "$(cfg proj_get "$key" app | grep . || echo "$key")")"
  cfg proj_set "$key" app_id "$(ask "appho.st app id" "$(cfg proj_get "$key" app_id)")"
  credentials "$key"
  ok "saved “$(cfg proj_get "$key" app)”"
  printf '%s' "$key"
}

credentials(){ # $1 project key
  step "appho.st credentials for “$(cfg proj_get "$1" app | grep . || echo "$1")”"
  sub "both come from the app's page on appho.st › Private API › download config"
  cfg proj_set "$1" user_id "$(ask "user_id" "$(cfg proj_get "$1" user_id)")"
  cfg proj_set "$1" key     "$(ask "API key" "$(cfg proj_get "$1" key)")"
  ok "saved"
}


edit_app(){ # $1 project key -> everything about one app in one place; returns 1 if it was removed
  local key="$1" v
  while :; do
    MENU_ITEMS=("$(printf '%-16s' 'To')" "$(printf '%-16s' 'CC')" "$(printf '%-16s' 'BCC')" "$(printf '%-16s' 'subject')"
                "$(printf '%-16s' 'app name')" "$(printf '%-16s' 'app id')" "$(printf '%-16s' 'folder')"
                "$(printf '%-16s' 'credentials')" "remove this app" "← back")
    MENU_NOTES=("  ${D}$(cfg people "$key" to | cut -f2 | tr '\n' ' ' | grep . || echo 'nobody yet')${R}"
                "  ${D}$(cfg people "$key" cc | cut -f2 | tr '\n' ' ' | grep . || echo '—')${R}"
                "  ${D}$(cfg people "$key" bcc | cut -f2 | tr '\n' ' ' | grep . || echo '—')${R}"
                "  ${D}$(cfg subject_get "$key" | grep . || mbox tpl_get apk subject)${R}"
                "  ${D}$(cfg proj_get "$key" app)  · used in the email${R}"
                "  ${D}$(cfg proj_get "$key" app_id)  · from the appho.st app page${R}"
                "  ${D}$(cfg proj_get "$key" path)${R}"
                "  ${D}user_id $(cfg proj_get "$key" user_id | grep . || echo 'not set')${R}" "" "")
    step "Edit “$(cfg proj_get "$key" app | grep . || echo "$key")”"
    case "$(menu_pick "What to change" 9 0)" in
      0) people_menu "$key" to ;;
      1) people_menu "$key" cc ;;
      2) people_menu "$key" bcc ;;
      3) cfg proj_set "$key" subject "$(ask "Subject (blank = default)" "$(cfg proj_get "$key" subject)")" ;;
      4) cfg proj_set "$key" app    "$(ask "App name" "$(cfg proj_get "$key" app)")" ;;
      5) cfg proj_set "$key" app_id "$(ask "App id" "$(cfg proj_get "$key" app_id)")" ;;
      6) v="$(ask "Folder" "$(cfg proj_get "$key" path)")"; v="${v/#\~/$HOME}"
         [ -f "$v/pubspec.yaml" ] && cfg proj_set "$key" path "$v" || warn "no pubspec.yaml in that folder" ;;
      7) credentials "$key" ;;
      8) [ "$(ask_yn "Remove “${key}” and its email lists" false)" = true ] && { cfg proj_del "$key"; ok "removed"; return 1; } ;;
      9) return 0 ;;
    esac
  done
}

# ── main ──────────────────────────────────────────────────────────────────
main(){
  DRY=no; VERBOSE=no
  local arg ROOT="" HERE="" idx sel n napps
  for arg in "$@"; do
    case "$arg" in
      --dry-run|-n) DRY=yes ;;
      --verbose)    VERBOSE=yes ;;
      --version|-V|-v) echo "ship-apk $VERSION"; exit 0 ;;
      config|-c)    banner "ship-apk $VERSION" "mail account"; smtp_menu; exit 0 ;;
      -h|--help)
        printf "\n  ${B}ship-apk${R} ${D}%s${R}\n\n" "$VERSION"
        printf "    ${A}ship-apk${R}             your apps; pick one, it builds, uploads and mails the link\n"
        printf "    ${A}ship-apk --dry-run${R}   check everything and show what would happen; changes nothing (also -n)\n"
        printf "    ${A}ship-apk --verbose${R}   stream the full build log instead of one line\n"
        printf "    ${A}ship-apk config${R}      mail account and template\n\n"
        printf "  ${D}Run it inside a Flutter project and that app is preselected, or offered to add.\n"
        printf "  Settings and logs live in %s${R}\n\n" "$CONF"
        exit 0 ;;
    esac
  done

  [ -t 0 ] || die "ship-apk needs a terminal — run it, do not pipe into it"
  have python3 || die "python3 is required (it ships with macOS developer tools)."
  cfg projects >/dev/null   # creates config.json on first run
  banner "ship-apk $VERSION" "build it, ship it, mail the link"
  [ "$DRY" = yes ] && sub "${Y}dry run — checks everything, then shows what it would do; nothing is built, uploaded, mailed or written${R}"
  ROOT="$(find_root)" || ROOT=""

  while :; do
    load_projects "$ROOT"; HERE=$HIT
    napps=${#PROJ_KEYS[@]}
    # this folder is a Flutter project nobody saved yet → "+ add app" starts selected, with it filled in
    if [ -n "$ROOT" ] && [ "$HERE" -lt 0 ]; then
      MENU_ITEMS+=("+ add this app");  MENU_NOTES+=("  ${G}● $(sed "s|^$HOME|~|" <<<"$ROOT")${R}"); sel=$napps
    else
      MENU_ITEMS+=("+ add app");       MENU_NOTES+=("  ${D}a Flutter folder, an app id, credentials${R}"); sel=$(( HERE < 0 ? 0 : HERE ))
    fi
    MENU_ITEMS+=("edit an app" "mailbox" "quit")
    MENU_NOTES+=("  ${D}To, CC, BCC, subject, credentials, folder, remove${R}"
                 "  ${D}$([ "$(mbox smtp_ready)" = yes ] && mbox smtp_get user || echo 'not set up yet') · shared with ship-site · template${R}" "")
    step "Apps"
    [ "$napps" -gt 0 ] || sub "no apps yet — add one to get started"
    MENU_NOKEY="$(nokey_rows "$napps")"
    idx="$(menu_pick "Pick an app to build and upload" $(( napps + 3 )) "$sel")"; MENU_NOKEY=""   # set for that menu only; it ran in a subshell
    case $(( idx - napps )) in
      0) n="$(add_app "$([ "$HERE" -lt 0 ] && printf '%s' "$ROOT")")" || continue
         [ -n "$ROOT" ] && [ "$(cfg proj_get "$n" path)" = "$ROOT" ] && { ship "$n" "$ROOT" || exit 0; } ;;
      1) [ "$napps" -gt 0 ] || { warn "no apps yet"; continue; }
         load_projects "$ROOT"; MENU_ITEMS+=("← back"); MENU_NOTES+=("")
         step "Edit which app"
         MENU_NOKEY="$(nokey_rows "$napps")"
         idx="$(menu_pick "App" "$napps" "$(( HERE < 0 ? 0 : HERE ))")"; MENU_NOKEY=""
         [ "$idx" -lt "$napps" ] && edit_app "${PROJ_KEYS[$idx]}" ;;
      2) [ "$(mbox smtp_ready)" = yes ] && smtp_menu || setup_mailbox ;;
      3) printf "\n" >&2; exit 0 ;;
      *) ship "${PROJ_KEYS[$idx]}" "${PROJ_PATHS[$idx]}" || { printf "\n" >&2; exit 0; } ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
