# ── firebase ───────────────────────────────────────────────────────────────
# Firebase Hosting through the Firebase CLI and its own Google logins (--account), plus the Hosting API for custom domains.
need_firebase(){ need "the Firebase CLI" firebase "npm i -g firebase-tools"; }

fb_logins(){ # -> the Google accounts signed in to the Firebase CLI right now, one per line
  have firebase && firebase login:list 2>/dev/null | grep -Eo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' | sort -u
}

add_fb_account(){ # signs one more Google account into the Firebase CLI; the CLI keeps them side by side
  need_firebase
  step "Add a Firebase account"
  sub "signs in with Google in the browser — nothing to copy"
  if firebase login:list 2>/dev/null | grep -E '[A-Za-z0-9._%+-]+@' >/dev/null; then
    cmd "firebase login:add"; firebase login:add >&2 || { warn "sign-in did not finish"; return 1; }
  else
    cmd "firebase login"; firebase login >&2 || { warn "sign-in did not finish"; return 1; }
  fi
  ok "signed in"
}

fb_ensure_site(){ # $1 account $2 project id -> echoes the project's hosting site, creating the default one when it has none
  local acct="$1" pid="$2" site
  site="$(firebase hosting:sites:list --project "$pid" --account "$acct" --json 2>/dev/null \
    | py -c 'import json,sys;s=(json.load(sys.stdin).get("result") or {}).get("sites") or [];print(s[0]["name"].rsplit("/",1)[-1] if s else "")' 2>/dev/null)"
  [ -n "$site" ] && { printf '%s' "$site"; return; }
  cmd "firebase hosting:sites:create $pid --project $pid --account $acct"
  firebase hosting:sites:create "$pid" --project "$pid" --account "$acct" --non-interactive >&2 || return 1
  printf '%s' "$pid"
}

fb_create_project(){ # $1 account $2 suggested name -> echoes "projectId<TAB>site" of a brand-new Firebase project
  local acct="$1" name id r site
  step "New Firebase project in ${acct}"
  sub "free plan, Hosting only — no billing needed"
  name="$(ask "Project name" "$2")"; [ -n "$name" ] || return 1
  while :; do
    # project ids are global across all of Google Cloud, so a short random tail avoids clashes
    id="$(ask "Project id (6–30 letters, digits, dashes; unique worldwide)" "$(slugify "$name" | cut -c1-24)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')")"
    [ -n "$id" ] || return 1
    echo "$id" | grep -Eq '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' && break
    warn "“${id}” is not a valid project id — lowercase letters, digits and dashes, 6–30 long, starting with a letter"
  done
  [ "$DRY" = yes ] && { ok "would create Firebase project “${name}” (${id}) with its site ${id}.web.app  ${D}(dry run, not created)${R}"; return 1; }
  cmd "firebase projects:create $id --display-name \"$name\" --account $acct"
  if ! r="$(firebase projects:create "$id" --display-name "$name" --account "$acct" --non-interactive 2>&1)"; then
    printf '%s\n' "$r" | grep -i error | tail -3 | while IFS= read -r l; do sub "$l"; done
    if printf '%s' "$r" | grep -qi 'terms of service\|tos'; then
      warn "this Google account has not accepted the Google Cloud terms yet — opening them; accept, then try again"
      open_it "https://console.cloud.google.com/"
    fi
    return 1
  fi
  ok "created project “${name}” (${id})"
  site="$(fb_ensure_site "$acct" "$id")" || { warn "the project was created but its Hosting site was not — open console.firebase.google.com › Hosting › Get started"; return 1; }
  printf '%s\t%s' "$id" "$site"
}

new_site_here(){ # $1 account $2 Firebase project $3 folder -> creates one more <name>.web.app site in that project; echoes its name
  local acct="$1" proj="$2" n r g
  need_firebase
  g="$(guess_label "$3")"; n="$(slugify "${g:+$g-}$proj")"
  step "New site in ${proj}  ${D}${acct}${R}"
  sub "its own <name>.web.app in the same project — admin-${proj}, website-${proj}"
  while :; do
    n="$(confirm_name "Site name (becomes <name>.web.app)" "$n" "NAME.web.app  in ${proj}")" || return 1
    [ "$DRY" = yes ] && { ok "would create site “${n}” in ${proj}  ${D}(dry run, not created)${R}"; return 1; }
    cmd "firebase hosting:sites:create $n --project $proj --account $acct"
    r="$(firebase hosting:sites:create "$n" --project "$proj" --account "$acct" --non-interactive 2>&1)" && break
    warn "$(printf '%s' "$r" | grep -i error | tail -1 | sed 's/^Error: //')"
  done
  ok "created site “${n}” → ${n}.web.app"
  vc cache_add "$acct" "$proj/$n" "$n" "$n.web.app" firebase "$proj"
  printf '%s' "$n"
}

firebaserc_project(){ # $1 folder -> the default Firebase project its .firebaserc names, if any
  [ -f "$1/.firebaserc" ] && py -c 'import json,sys;print((json.load(open(sys.argv[1])).get("projects") or {}).get("default",""))' "$1/.firebaserc" 2>/dev/null
}

firebase_json_site(){ # $1 folder -> the hosting site its firebase.json names, if any
  [ -f "$1/firebase.json" ] && py -c '
import json, sys
h = json.load(open(sys.argv[1])).get("hosting", {})
h = h[0] if isinstance(h, list) and h else h
print(h.get("site", "") if isinstance(h, dict) else "")' "$1/firebase.json" 2>/dev/null
}

stage_firebase(){ # $1 root  $2 stage dir  $3 site -> build output in <stage>/public plus a firebase.json for it
  mkdir -p "$2/public" && cp -R "$1/$(outdir "$1")/." "$2/public/" || return 1; clean_stage "$2/public"
  py - "$1/firebase.json" "$2/firebase.json" "$3" "$STATIC" <<'PY2'
import json, os, sys
src, dst, site, static = sys.argv[1:5]
h = {}
if os.path.exists(src):
    try:
        hs = json.load(open(src)).get("hosting", {})
        h = next((x for x in hs if x.get("site") == site), hs[0] if hs else {}) if isinstance(hs, list) else hs
    except Exception: h = {}
# the project's own redirects, headers and rewrites come along; where the files are and which site is ours
out = {k: v for k, v in h.items() if k in ("rewrites", "redirects", "headers", "cleanUrls", "trailingSlash", "i18n", "appAssociation")}
# dotfiles stay, .well-known above all (app links live there); the copy was cleaned of .git and the like already
out.update(site=site, public="public", ignore=["firebase.json", "**/.DS_Store", "**/.htaccess"])
if static: out.setdefault("cleanUrls", True)                 # real pages: /privacy serves privacy/index.html
else: out.setdefault("rewrites", [{"source": "**", "destination": "/index.html"}])   # an app: deep links open index.html
json.dump({"hosting": out}, open(dst, "w"), indent=2)
PY2
}

dry_deploy_firebase(){ # $1 account $2 project/site $3 folder $4 package manager -> checks, then what would run; changes nothing
  local acct="$1" proj="${2%%/*}" site="${2#*/}" root="$3" pm="$4" bad=0
  step "Dry run · checks"
  dry_source "$root" "$pm" || bad=1
  if have firebase; then
    ok "Firebase CLI is installed  ${D}$(firebase --version 2>/dev/null)${R}"
    firebase login:list 2>/dev/null | grep -F "$acct" >/dev/null && ok "signed in as $acct" || { warn "✗ $acct is not signed in to the Firebase CLI"; bad=1; }
    firebase hosting:sites:list --project "$proj" --account "$acct" --json 2>/dev/null | grep "sites/$site\"" >/dev/null \
      && ok "site “${site}” in project ${proj} is reachable" || { warn "✗ cannot reach site “${site}” in project ${proj}"; bad=1; }
  else
    warn "✗ the Firebase CLI is not installed  ${D}npm i -g firebase-tools${R}"; bad=1
  fi

  step "Dry run · would run"
  [ -n "$STATIC" ] || cmd "cd $root && $pm run build"
  if [ "$PROD" = yes ]; then cmd "firebase deploy --only hosting --project $proj --account $acct  ${D}(from a temp copy of the $([ -n "$STATIC" ] && echo files || echo build))${R}"
  else cmd "firebase hosting:channel:deploy preview --expires 7d --project $proj --account $acct"; fi
  row "target" "$([ "$PROD" = yes ] && echo "main website  ${D}${site}.web.app${R}" || echo 'test version  a preview URL for 7 days')"
  printf "\n" >&2
  [ "$bad" = 0 ] && ok "dry run passed — nothing was built, deployed or written" \
                 || warn "dry run found problems above — nothing was built, deployed or written"
  printf "\n" >&2
}

publish_firebase(){ # $1 account $2 project/site $3 folder $4 package manager
  local acct="$1" proj="${2%%/*}" site="${2#*/}" root="$3" pm="$4" stage log url out also=""
  stage="$(tmpd shipsite)"; trap "rm -rf '$stage' '$stage'-*.log" EXIT
  build_or_files "$root" "$pm" "$stage"
  # published from a copy with its own firebase.json: nothing is added to your repo
  stage_firebase "$root" "$stage" "$site" || die "could not copy the build output"

  step "Publishing"
  row "site" "$site  ${D}${proj}${R}"
  row "target" "$([ "$PROD" = yes ] && echo 'main website' || echo 'test version · 7 days')"
  log="$stage-deploy.log"
  if [ "$PROD" = yes ]; then
    cmd "firebase deploy --only hosting --project $proj --account $acct"
    ( cd "$stage" && firebase deploy --only hosting --project "$proj" --account "$acct" --non-interactive ) > >(tee "$log" >&2) 2>&1 \
      || fail "Firebase rejected the deploy — nothing was published" "$log"
    url="https://$(vc url_get "${proj}/${site}")"; [ "$url" = "https://" ] && url="https://${site}.web.app"
    [ "$url" != "https://${site}.web.app" ] && also="https://${site}.web.app"
    vc stat_add "${proj}/${site}"
    vc proj_set "$root" last_prod_version "$(node -p "require('$root/package.json').version||''" 2>/dev/null)"
    vc proj_set "$root" last_prod_date "$(date '+%d %b %H:%M')"
  else
    cmd "firebase hosting:channel:deploy preview --expires 7d --project $proj --account $acct"
    out="$(cd "$stage" && firebase hosting:channel:deploy preview --expires 7d --project "$proj" --account "$acct" --json 2> >(tee "$log" >&2))" \
      || { printf '%s\n' "$out" >>"$log"; fail "Firebase rejected the preview — nothing was published" "$log"; }
    url="$(printf '%s' "$out" | py -c 'import json,sys;r=json.load(sys.stdin).get("result",{});print(next((v.get("url","") for v in r.values() if isinstance(v,dict)),""))' 2>/dev/null)"
    [ -n "$url" ] || { printf '%s\n' "$out" >>"$log"; fail "Firebase finished but returned no preview URL" "$log"; }
    vc stat_add "${proj}/${site}"
  fi
  printf %s "$url" | clip 2>/dev/null
  step "Published"
  row "link" "${B}${A}${url}${R}  ${D}copied${R}"
  [ -n "$also" ] && row "also" "${also}  ${D}stays as is${R}"
  URL="$url"; ALSO="$also"
  domain_status "$acct" "${proj}/${site}" || true
}

custom_domain(){ # $1 host  $2 account  $3 project id (Firebase: project/site)  $4 name -> saves the domain; on Firebase connects it and prints the DNS records to add
  local host="$1" acct="$2" proj="${3%%/*}" site="${3#*/}" dom tok out t h v text=""
  step "Custom domain for ${4}  ${D}$([ "$host" = firebase ] && echo "${site}.web.app" || echo "${4}.vercel.app")${R}"
  sub "a domain you own, or a subdomain of one — example.com, admin.example.com, with its ending"
  dom="$(ask "Domain" "$(vc domain_get "$3")")"; [ -n "$dom" ] || return 1
  dom="$(printf '%s' "$dom" | tr 'A-Z' 'a-z' | sed 's|^https\{0,1\}://||; s|/.*||; s/^www\.//')"
  echo "$dom" | grep -Eq '^([a-z0-9-]+\.)+[a-z]{2,}$' || { warn "“${dom}” is not a domain — something like example.com or admin.example.com"; return 1; }
  case ".${dom##*.}." in
    .com.|.net.|.org.|.io.|.app.|.dev.|.co.|.uk.|.pk.|.in.|.me.|.ai.|.xyz.|.site.|.online.|.store.|.tech.|.info.|.biz.|.us.|.ca.|.de.|.fr.|.au.|.nz.|.eu.|.pro.|.cloud.|.shop.|.ae.|.sa.) ;;
    *) warn "“${dom}” ends in .${dom##*.}, which is not a usual ending — admin.sukungarden needs its .com"
       confirm_y "Use “${dom}” as typed?" || return 1 ;;
  esac
  [ "$DRY" = yes ] && { ok "would remember ${dom} for ${4}$([ "$host" = firebase ] && echo ", connect it and show the DNS records to add")  ${D}(dry run, nothing saved)${R}"; return 0; }
  vc domain_set "$3" "$dom"; ok "remembered ${dom} for ${4} — it shows on its row$([ "$host" = firebase ] && echo ' as waiting for DNS until it answers')"
  [ "$host" = firebase ] || { sub "add it on vercel.com › ${4} › Domains, which shows the records to add"; return 0; }
  MENU_ITEMS=("connect it now" "just keep it as a reminder"); MENU_NOTES=("  ${D}on Firebase, then the DNS records to add at your registrar; connected already: shows them again${R}" "  ${D}connect it another time from the list: custom domain${R}")
  [ "$(menu_pick "Firebase" 0)" = 0 ] || return 0
  need_firebase
  tok="$(fb_token_for "$acct")"
  [ -n "$tok" ] || { warn "no Firebase login for ${acct} on this Mac — sign in again under accounts"; return 1; }
  cmd "firebasehosting.googleapis.com … sites/${site}/customDomains/${dom}"
  out="$(vc fb_domain "$tok" "$proj" "$site" "$dom")" || { warn "${out#ERR	}"; return 1; }
  show_records "$proj" "$site" "$dom" "$out"
}

fb_token_for(){ # $1 account -> the CLI's token, renewing it with one harmless CLI call when it has expired
  local tok; tok="$(vc fb_token "$1")"
  [ -n "$tok" ] || { firebase projects:list --account "$1" >/dev/null 2>&1; tok="$(vc fb_token "$1")"; }
  printf '%s' "$tok"
}

dom_note(){ # $1 state from the last refresh -> the short note next to a domain that is not fully live
  case "$1" in cert) echo "(up on http, HTTPS soon)" ;; *) echo "(waiting for DNS)" ;; esac
}

show_records(){ # $1 project $2 site $3 domain $4 records (type<TAB>host<TAB>value lines, or "live…") -> the table, copied
  local proj="$1" site="$2" dom="$3" out="$4" t h v text="" base
  case "${out%%	*}" in
    live) ok "${dom} is live with HTTPS — nothing to add"; vc fb_refresh 2>/dev/null; return 0 ;;
    cert) ok "${dom} is up on http — DNS is through, the HTTPS certificate is on its way, nothing to add"; vc fb_refresh 2>/dev/null; return 0 ;;
  esac
  # the registrar wants the host without the domain: admin for admin.example.com, @ for example.com itself
  base="$(printf '%s' "$dom" | awk -F. '{print $(NF-1)"."$NF}')"
  step "Add these records at your registrar (Namecheap: Advanced DNS)  ${D}for ${base}${R}"
  printf "     ${D}%-6s %-34s %s${R}\n" type host value >&2
  while IFS=$'\t' read -r t h v; do
    [ -n "$t" ] || continue
    case "$h" in "$base") h="@" ;; *".$base") h="${h%.$base}" ;; esac
    printf "     ${B}%-6s${R} %-34s ${A}%s${R}\n" "$t" "$h" "$v" >&2
    text="${text}${t}  ${h}  ${v}
"
  done <<<"$out"
  printf '%s' "$text" | clip 2>/dev/null && sub "copied — host is the part before ${base}; @ is ${base} itself"
  sub "Firebase checks them on its own; the site answers on ${dom} once they are live, usually within an hour, sometimes a day"
  sub "https://console.firebase.google.com/project/${proj}/hosting/sites/${site}"
  sub "the TXT _acme-challenge row is optional: it only speeds up the HTTPS certificate"
  sub "after every publish one line says where it stands; the list shows ${dom} in place of ${site}.web.app once it is live"
  printf "\n" >&2
}

domain_status(){ # $1 account $2 project/site -> one line on a saved domain: live, or what Firebase still waits to see; true once live
  local acct="$1" proj="${2%%/*}" site="${2#*/}" dom tok out t h v base need=""
  dom="$(vc domain_get "$2")"; [ -n "$dom" ] || return 0
  [ "$(vc url_get "$2")" = "$dom" ] && { row "domain" "${dom}  ${G}live${R}"; return 0; }
  tok="$(fb_token_for "$acct")"; [ -n "$tok" ] || return 1
  out="$(vc fb_records "$tok" "$proj" "$site" "$dom")" || { warn "${dom} is saved but ${out#ERR	} — custom domain › connect it now"; return 1; }
  case "${out%%	*}" in
    live) vc fb_refresh 2>/dev/null; row "domain" "${dom}  ${G}live with HTTPS${R}  ${D}the list shows it from here on${R}"; return 0 ;;
    cert) vc fb_refresh 2>/dev/null; row "domain" "${dom}  ${G}up on http${R}  ${D}DNS is through; Firebase is issuing the HTTPS certificate, usually under an hour — nothing to do${R}"; return 1 ;;
  esac
  base="$(printf '%s' "$dom" | awk -F. '{print $(NF-1)"."$NF}')"
  while IFS=$'\t' read -r t h v; do
    [ -n "$t" ] || continue
    case "$h" in "$base") h="@" ;; *".$base") h="${h%.$base}" ;; esac
    need="${need:+$need, }${t} ${h}"
  done <<<"$out"
  row "domain" "${dom}  ${Y}waiting for DNS${R}  ${D}Firebase has not seen yet: ${need} — added already: DNS takes up to an hour; d shows the records${R}"
  return 1
}
