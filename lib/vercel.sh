# ── vercel ─────────────────────────────────────────────────────────────────
# Vercel through its REST API (token) and the Vercel CLI; each account keeps its own CLI session folder.
need_vercel(){ need "the Vercel CLI" vercel "npm i -g vercel"; }

acct_token(){ # $1 name -> echoes the token
  local dir="$ACCTS/$1"
  [ -f "$dir/token" ] && { cat "$dir/token"; return; }
  [ -f "$dir/auth.json" ] && py -c 'import json,sys;print(json.load(open(sys.argv[1])).get("token",""))' "$dir/auth.json"
}

AUTH=()
acct_cli(){ # $1 name -> fills AUTH with the vercel cli flags, as an array so a space in the name survives
  local dir="$ACCTS/$1"
  [ -f "$dir/token" ] && AUTH=(--token "$(cat "$dir/token")") || AUTH=(--global-config "$dir")
}

add_account(){ # -> echoes the new account name
  local name dir token user teams idx r
  step "Add a Vercel account"
  name="$(ask "A name for it (your name, or the team)" "")"; [ -n "$name" ] || return 1
  case "$name" in */*|.*) warn "no slashes or leading dots"; return 1 ;; esac
  [ -z "$(vc acct_get "$name" org_id)" ] || { warn "“${name}” exists already — pick it from the list"; return 1; }
  dir="$ACCTS/$name"; mkdir -p "$dir"; chmod 700 "$ACCTS" "$dir"
  MENU_ITEMS=("sign in with Vercel in the browser" "paste a token" "← back")
  MENU_NOTES=("  ${D}opens vercel.com, nothing to copy${R}" "  ${D}from vercel.com/account/tokens${R}" "")
  idx="$(menu_pick "How" 0)"
  [ "$idx" = 2 ] && { rm -rf "$dir"; return 1; }
  if [ "$idx" = 0 ]; then
    cmd "vercel login --global-config $dir"
    vercel login --global-config "$dir" >&2 || { rm -rf "$dir"; warn "sign-in did not finish"; return 1; }
    rm -f "$dir/token"
  else
    sub "create one at https://vercel.com/account/tokens, then paste it here (hidden)"
    token="$(ask_secret "Token")"; [ -n "$token" ] || { rm -rf "$dir"; return 1; }
    printf '%s\n' "$token" > "$dir/token"; chmod 600 "$dir/token"
  fi
  token="$(acct_token "$name")"; [ -n "$token" ] || { rm -rf "$dir"; warn "no token came back"; return 1; }
  user="$(vc user "$token")" || { rm -rf "$dir"; warn "${user#ERR	}"; return 1; }
  ok "signed in as ${user#*	}"

  # scope: personal, or one of the teams the account belongs to
  teams="$(vc teams "$token")" || die "${teams#ERR	}"
  vc acct_set "$name" scope "${user#*	}"; vc acct_set "$name" org_id "${user%%	*}"; vc acct_set "$name" team_id ""
  if [ -n "$teams" ]; then
    MENU_ITEMS=("personal  ${user#*	}"); MENU_NOTES=("")
    while IFS=$'\t' read -r id slug tname; do MENU_ITEMS+=("team      $tname"); MENU_NOTES+=("  ${D}$slug${R}"); done <<<"$teams"
    step "Which scope does “${name}” deploy to"
    idx="$(menu_pick "Scope" 0)"
    if [ "$idx" -gt 0 ]; then
      r="$(sed -n "${idx}p" <<<"$teams")"
      vc acct_set "$name" team_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" org_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" scope "$(cut -f2 <<<"$r")"
    fi
  fi
  ok "saved “${name}”  ${D}→ $(vc acct_get "$name" scope)${R}"
  printf '%s' "$name"
}

pick_account(){ # -> echoes an account name
  local names=() n idx
  while :; do
    names=(); MENU_ITEMS=(); MENU_NOTES=()
    while IFS= read -r n; do [ -n "$n" ] && { names+=("$n"); MENU_ITEMS+=("$(printf '%-16s' "$n")"); MENU_NOTES+=("  ${D}$(vc acct_get "$n" scope)${R}"); }; done < <(vc accounts)
    MENU_ITEMS+=("+ add a Vercel account" "← back"); MENU_NOTES+=("  ${D}browser sign-in or a token${R}" "")
    step "Vercel account"
    idx="$(menu_pick "Which account" 0)"
    if   [ "$idx" -eq $(( ${#names[@]} + 1 )) ]; then return 1
    elif [ "$idx" -eq ${#names[@]} ]; then n="$(add_account)" && { printf '%s' "$n"; return; }
    else printf '%s' "${names[$idx]}"; return; fi
  done
}

wake_logins(){ # browser logins expire; any vercel cli call renews them, so nudge the expired ones first
  local n
  while IFS= read -r n; do
    [ -n "$n" ] && vercel whoami --global-config "$ACCTS/$n" >/dev/null 2>&1
  done < <(py - "$ACCTS" <<'PY2'
import json, os, sys, time
for n in sorted(os.listdir(sys.argv[1])) if os.path.isdir(sys.argv[1]) else []:
    f = os.path.join(sys.argv[1], n, "auth.json")
    try:
        if json.load(open(f)).get("expiresAt", 0) < time.time() + 120: print(n)
    except Exception: pass
PY2
)
}

vercel_json_project(){ # $1 folder -> the Vercel project id its .vercel/project.json names, if any
  [ -f "$1/.vercel/project.json" ] && py -c 'import json,sys;print(json.load(open(sys.argv[1])).get("projectId",""))' "$1/.vercel/project.json" 2>/dev/null
}

stage_dist(){ # $1 root  $2 stage dir  $3 project id  $4 org id  $5 project name
  cp -R "$1/$(outdir "$1")/." "$2/" || return 1; clean_stage "$2"
  [ -f "$1/vercel.json" ] && cp "$1/vercel.json" "$2/vercel.json"
  # an app gets the single-page rewrite so deep links work; a static site keeps its real pages, with /privacy serving privacy/index.html
  [ -f "$2/vercel.json" ] || { [ -n "$STATIC" ] && printf '{"cleanUrls":true}' || printf '{"rewrites":[{"source":"/(.*)","destination":"/index.html"}]}'; } > "$2/vercel.json"
  mkdir -p "$2/.vercel"
  printf '{"projectId":"%s","orgId":"%s","projectName":"%s"}' "$3" "$4" "$5" > "$2/.vercel/project.json"
}

dry_deploy(){ # $1 account $2 project id $3 project name $4 folder $5 package manager -> checks, then what would run; changes nothing
  local acct="$1" pid="$2" pname="$3" root="$4" pm="$5" token team r bad=0
  token="$(acct_token "$acct")"; team="$(vc acct_get "$acct" team_id)"
  step "Dry run · checks"
  dry_source "$root" "$pm" || bad=1
  have vercel && ok "Vercel CLI is installed  ${D}$(vercel --version 2>/dev/null | head -1)${R}" || { warn "✗ the Vercel CLI is not installed  ${D}npm i -g vercel${R}"; bad=1; }
  r="$(vc user "$token" 2>/dev/null)" && ok "Vercel login works  ${D}${r#*	} · ${acct}${R}" || { warn "✗ Vercel login failed for “${acct}”: ${r#ERR	}"; bad=1; }
  r="$(vc domain "$token" "${team:--}" "$pid" 2>/dev/null)" && ok "project “${pname}” is reachable" || { warn "✗ cannot reach project “${pname}”: ${r#ERR	}"; bad=1; }

  step "Dry run · would run"
  [ -n "$STATIC" ] || cmd "cd $root && $pm run build"
  acct_cli "$acct"
  cmd "vercel deploy --yes $([ "$PROD" = yes ] && echo --prod) $([ "${AUTH[0]}" = --token ] && echo '--token ••••' || printf '%s "%s"' "${AUTH[0]}" "${AUTH[1]}")  ${D}(from a temp copy of dist/)${R}"
  row "target" "$([ "$PROD" = yes ] && echo 'main website' || echo 'test version')"
  printf "\n" >&2
  [ "$bad" = 0 ] && ok "dry run passed — nothing was built, deployed or written" \
                 || warn "dry run found problems above — nothing was built, deployed or written"
  printf "\n" >&2
}
