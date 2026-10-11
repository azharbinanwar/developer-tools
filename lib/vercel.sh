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

add_account(){ # [$1 label] [$2 browser|token] [$3 team slug] -> echoes the new account's id; with $2 nothing is asked (VERCEL_TOKEN carries a pasted token)
  # the account is keyed by a random id, which is also its folder; renaming only changes the label, so nothing filed under the id moves
  local label="${1:-}" how="${2:-}" want_team="${3:-}" name dir token user teams idx r
  step "Add a Vercel account"
  [ -n "$label" ] || [ -n "$how" ] || label="$(ask "A name for it (your name, or the team; blank for the Vercel username)" "")"
  name="v$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  dir="$ACCTS/$name"; mkdir -p "$dir"; chmod 700 "$ACCTS" "$dir"
  if [ -n "$how" ]; then idx=0; [ "$how" = token ] && idx=1
  else
    MENU_ITEMS=("sign in with Vercel in the browser" "paste a token" "← back")
    MENU_NOTES=("  ${D}opens vercel.com, nothing to copy${R}" "  ${D}from vercel.com/account/tokens${R}" "")
    idx="$(menu_pick "How" 0)"
    [ "$idx" = 2 ] && { rm -rf "$dir"; return 1; }
  fi
  if [ "$idx" = 0 ]; then
    cmd "vercel login --global-config $dir"
    vercel login --global-config "$dir" >&2 || { rm -rf "$dir"; warn "sign-in did not finish"; return 1; }
    rm -f "$dir/token"
  else
    if [ -n "${VERCEL_TOKEN:-}" ]; then token="$VERCEL_TOKEN"
    else sub "create one at https://vercel.com/account/tokens, then paste it here (hidden)"; token="$(ask_secret "Token")"; fi
    [ -n "$token" ] || { rm -rf "$dir"; return 1; }
    printf '%s\n' "$token" > "$dir/token"; chmod 600 "$dir/token"
  fi
  token="$(acct_token "$name")"; [ -n "$token" ] || { rm -rf "$dir"; warn "no token came back"; return 1; }
  user="$(vc user "$token")" || { rm -rf "$dir"; warn "${user#ERR	}"; return 1; }
  ok "signed in as ${user#*	}"
  vc acct_set "$name" user "${user#*	}"; vc acct_label vercel "$name" "${label:-${user#*	}}"

  # scope: personal, or one of the teams the account belongs to
  teams="$(vc teams "$token")" || die "${teams#ERR	}"
  vc acct_set "$name" scope "${user#*	}"; vc acct_set "$name" org_id "${user%%	*}"; vc acct_set "$name" team_id ""
  if [ -n "$teams" ] && [ -n "$how" ]; then   # answered up front: the team by slug, else personal
    r="$(awk -F'\t' -v t="$want_team" '$2 == t' <<<"$teams" | head -1)"
    [ -n "$want_team" ] && [ -z "$r" ] && warn "no team “${want_team}” on this account; using the personal scope"
    [ -n "$r" ] && { vc acct_set "$name" team_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" org_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" scope "$(cut -f2 <<<"$r")"; }
    [ -z "$want_team" ] && sub "teams on this account: $(cut -f2 <<<"$teams" | tr '\n' ' ')· add again with --team <slug> to deploy to one"
  elif [ -n "$teams" ]; then
    MENU_ITEMS=("personal  ${user#*	}"); MENU_NOTES=("")
    while IFS=$'\t' read -r id slug tname; do MENU_ITEMS+=("team      $tname"); MENU_NOTES+=("  ${D}$slug${R}"); done <<<"$teams"
    step "Which scope does “${name}” deploy to"
    idx="$(menu_pick "Scope" 0)"
    if [ "$idx" -gt 0 ]; then
      r="$(sed -n "${idx}p" <<<"$teams")"
      vc acct_set "$name" team_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" org_id "$(cut -f1 <<<"$r")"; vc acct_set "$name" scope "$(cut -f2 <<<"$r")"
    fi
  fi
  ok "saved “$(acct_show "$name")”  ${D}→ $(vc acct_get "$name" scope)${R}"
  printf '%s' "$name"
}
migrate_accounts(){ # accounts saved under a typed name move to a random id, like new ones: the name becomes the label, the sign-in folder follows, nothing else changes
  local n tok u id
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$n" in v[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *) id="v$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
         [ "$(vc acct_rekey "$n" "$id")" = ok ] || continue
         [ -d "$ACCTS/$n" ] && mv "$ACCTS/$n" "$ACCTS/$id"; n="$id" ;;
    esac
    if [ -z "$(vc acct_get "$n" user)" ]; then tok="$(acct_token "$n" 2>/dev/null)"; [ -n "$tok" ] && u="$(vc user "$tok" 2>/dev/null)" && [ "${u#ERR}" = "$u" ] && vc acct_set "$n" user "${u#*	}"; fi
  done < <(vc accounts)
}
acct_show(){ # $1 id -> the label of a Vercel account, else its username, else the id
  local l; l="$(vc acct_label vercel "$1")"; [ -n "$l" ] || l="$(vc acct_get "$1" user)"; printf '%s' "${l:-$1}"
}

pick_account(){ # -> echoes an account name
  local names=() n idx
  while :; do
    names=(); MENU_ITEMS=(); MENU_NOTES=()
    while IFS= read -r n; do [ -n "$n" ] && { names+=("$n"); MENU_ITEMS+=("$(printf '%-16s' "$(acct_show "$n")")"); MENU_NOTES+=("  ${D}$(vc acct_get "$n" scope)${R}"); }; done < <(vc accounts)
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
