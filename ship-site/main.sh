# needs: platform ui keys mail firebase vercel
# ship-site: build a web app, publish only its build folder to Vercel or Firebase Hosting, copy the link.
#
# One file. Accounts are named and signed in either with a token or through
# the Vercel browser login; each keeps its own CLI session under
# ~/.config/ship-site/accounts/<name>. Projects are listed from the account and
# picked or created by name, never guessed. The deploy runs from a temp copy of
# dist/ outside your git repo, so no commit info is attached, and the copy is
# removed afterwards.
#
# Firebase accounts are the Firebase CLI's own Google logins (firebase login:add);
# every command names its --account, so several accounts never mix.
#
# Needs node and python3, plus the Vercel or Firebase CLI for whichever host a
# project uses; it asks before installing any of them.
#
# License: MIT.

VERSION="2.1.0"
CONF="$HOME/.config/ship-site"
LOGS="$CONF/logs"
MAIL_KIND=site; MAIL_VERB="publishes"; MAIL_THING="project"   # how lib/mail.sh talks about this tool
mail_store(){ vc "$@"; }                                        # where this tool keeps who gets the mail: per project, under "mail"
CONFIG="$CONF/config.json"
ACCTS="$CONF/accounts"

# ── config + vercel api ───────────────────────────────────────────────────
# One python block owns config.json and talks to api.vercel.com; bash only asks it for lines.
vc(){
py - "$CONFIG" "$@" <<'PY'
import json, os, sys, urllib.request, urllib.error, urllib.parse

path, op = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
try: d = json.load(open(path))
except Exception: d = {}
d.setdefault("accounts", {}); d.setdefault("projects", {})

def save():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)

class ApiErr(Exception): pass
sys.excepthook = lambda t, v, tb: print("ERR\t" + str(v)) if t is ApiErr else sys.__excepthook__(t, v, tb)

def api(token, team, method, ep, body=None):
    if team and team != "-": ep += ("&" if "?" in ep else "?") + urllib.parse.urlencode({"teamId": team})
    req = urllib.request.Request("https://api.vercel.com" + ep, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read(); return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        try: msg = json.loads(e.read()).get("error", {}).get("message", str(e))
        except Exception: msg = str(e)
        raise ApiErr(msg)
    except urllib.error.URLError as e:
        raise ApiErr("cannot reach Vercel: %s" % e.reason)

def ago(t):  # epoch -> "today", "3d ago", "2mo ago"; "" for none
    import time
    if not t: return ""
    d_ = (int(time.time()) - int(t)) // 86400
    if d_ < 1: return "today"
    if d_ < 7: return "%dd ago" % d_
    if d_ < 30: return "%dw ago" % (d_ // 7)
    if d_ < 365: return "%dmo ago" % (d_ // 30)
    return "%dy ago" % (d_ // 365)

def cli_token(email):  # the Firebase CLI's current access token for that Google account, or "" when it has expired
    import time
    cs = os.path.join(os.path.expanduser("~"), ".config", "configstore", "firebase-tools.json")
    try: c = json.load(open(cs))
    except Exception: c = {}
    accts = [(c.get("user", {}).get("email"), c.get("tokens", {}))] + [(x.get("user", {}).get("email"), x.get("tokens", {})) for x in c.get("additionalAccounts", [])]
    tok = next((t for e, t in accts if e == email), {})
    return tok.get("access_token", "") if tok.get("expires_at", 0) / 1000 > time.time() + 60 else ""

def fb_get(token, ep):  # one Hosting API read; {} on any trouble
    req = urllib.request.Request("https://firebasehosting.googleapis.com/v1beta1/" + ep, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=20) as r: raw = r.read(); return json.loads(raw) if raw else {}
    except Exception: return {}

def dom_state(cd):  # a customDomain -> dns (records not seen yet), cert (answers on http, HTTPS on its way), live
    if cd.get("hostState") != "HOST_ACTIVE": return "dns"
    c = cd.get("cert") or {}
    return "live" if c.get("state") == "CERT_ACTIVE" and c.get("type") != "TEMPORARY" else "cert"

def fb_domain_of(token, pid, site):  # the site's connected custom domain and its state, "" when none; the shortest when several
    ds = fb_get(token, "projects/%s/sites/%s/customDomains" % (pid, site)).get("customDomains", [])
    ds = sorted(ds, key=lambda d_: (dom_state(d_) != "live", len(d_["name"])))
    return (ds[0]["name"].rsplit("/", 1)[-1], dom_state(ds[0])) if ds else ("", "")

def pages(token, team, ep, key):
    out, until = [], None
    while True:
        r = api(token, team, "GET", ep + ("&until=%s" % until if until else ""))
        out += r.get(key, [])
        until = r.get("pagination", {}).get("next")
        if not until: return out

def mail(pid): return d.setdefault("mail", {}).setdefault(pid, {"to": [], "cc": [], "bcc": []})

# config
if   op == "accounts":  [print(n) for n in sorted(d["accounts"])]
elif op == "acct_get":  print(d["accounts"].get(a[0], {}).get(a[1], ""))
elif op == "acct_set":  d["accounts"].setdefault(a[0], {})[a[1]] = a[2]; save()
elif op == "acct_del":  d["accounts"].pop(a[0], None); save()
elif op == "proj_get":  print(d["projects"].get(a[0], {}).get(a[1], ""))
elif op == "proj_set":  d["projects"].setdefault(a[0], {})[a[1]] = a[2]; save()
# vercel
elif op == "user":      u = api(a[0], "-", "GET", "/v2/user")["user"]; print("%s\t%s" % (u["id"], u.get("username") or u.get("name", "")))
elif op == "teams":     [print("%s\t%s\t%s" % (t["id"], t["slug"], t.get("name", t["slug"]))) for t in pages(a[0], "-", "/v2/teams?limit=100", "teams")]
elif op == "refresh":   # every account's projects into the cache; a failing account keeps its last known rows
    base, old = os.path.join(os.path.dirname(path), "accounts"), d.get("cache", [])
    new = [c for c in old if c.get("host") == "firebase"]
    for n in sorted(d["accounts"]):
        try:
            tf, af, tok = os.path.join(base, n, "token"), os.path.join(base, n, "auth.json"), ""
            if os.path.exists(tf): tok = open(tf).read().strip()
            elif os.path.exists(af): tok = json.load(open(af)).get("token", "")
            if not tok: raise ApiErr("not signed in")
            for p in pages(tok, d["accounts"][n].get("team_id") or "-", "/v9/projects?limit=100", "projects"):
                al = p.get("targets", {}).get("production", {}).get("alias") or []
                url = next((x for x in al if not x.endswith(".vercel.app")), None) or (al[0] if al else p["name"] + ".vercel.app")
                new.append({"host": "vercel", "account": n, "id": p["id"], "name": p["name"], "url": url})
        except Exception as e:
            sys.stderr.write("%s\t%s\n" % (n, e))
            new += [c for c in old if c.get("account") == n and c.get("host") != "firebase"]
    d["cache"] = sorted(new, key=lambda c: (c["name"], c["account"])); save()
elif op == "fb_refresh":  # every Firebase CLI login's projects with a hosting site; one CLI call per account
    import re, subprocess
    def fb(*args): return subprocess.run(["firebase", *args], capture_output=True, text=True, timeout=180)
    try: logins = fb("login:list").stdout
    except Exception: logins = ""   # no Firebase CLI on this Mac: no Firebase rows
    emails = sorted(set(re.findall(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+", logins)))
    old = d.get("cache", [])
    new = [c for c in old if c.get("host") != "firebase"]
    for e in emails:
        try:
            r = fb("projects:list", "--json", "--account", e)
            res = json.loads(r.stdout or "{}")
            if res.get("status") != "success":
                raise ApiErr(res.get("error") or ((r.stderr or "").strip().splitlines() or ["could not list projects"])[-1])
            for pr in res.get("result", []):
                site = (pr.get("resources") or {}).get("hostingSite")
                if site:
                    new.append({"host": "firebase", "account": e, "id": pr["projectId"] + "/" + site, "name": site,
                                "url": site + ".web.app", "project": pr.get("displayName") or pr["projectId"]})
            new += [c for c in old if c.get("host") == "firebase" and c.get("account") == e and c.get("extra")]
            tok = cli_token(e)   # projects:list just renewed it
            if tok and os.environ.get("SHIP_SITE_NO_DOMAINS") != "1":
                from concurrent.futures import ThreadPoolExecutor
                mine = [c for c in new if c.get("host") == "firebase" and c["account"] == e]
                for c, (dom, state) in zip(mine, ThreadPoolExecutor(16).map(lambda c: fb_domain_of(tok, *c["id"].split("/", 1)), mine)):
                    c["url"] = dom if state == "live" else c["name"] + ".web.app"
                    if dom: d.setdefault("domains", {})[c["id"]] = dom; d.setdefault("domain_state", {})[c["id"]] = state
        except Exception as x:
            sys.stderr.write("%s\t%s\n" % (e, x))
            new += [c for c in old if c.get("host") == "firebase" and c.get("account") == e]
    d["fb_accounts"] = emails
    d["cache"] = sorted(new, key=lambda c: (c["name"], c["account"])); save()
elif op == "cache_add":  # account id name url [host] [project name]
    row = {"host": a[4] if len(a) > 4 else "vercel", "account": a[0], "id": a[1], "name": a[2], "url": a[3]}
    if len(a) > 5: row.update(project=a[5], extra=True)
    d.setdefault("cache", []).append(row); save()
elif op == "landing":   # cached projects: account id name url folder host label project count last, \x1f-separated (empty fields survive)
    folders, labels, stats, doms = {}, d.get("labels", {}), d.get("stats", {}), d.get("domains", {})
    for f, pr in d["projects"].items(): folders.setdefault(pr.get("id"), f)
    # projects already built from a folder on this Mac come first, then the rest by name
    for c in sorted(d.get("cache", []), key=lambda c: (c["id"] not in folders, c["name"])):
        h, st = c.get("host", "vercel"), stats.get(c["id"], {})
        if (h == "vercel" and c["account"] in d["accounts"]) or (h == "firebase" and c["account"] in d.get("fb_accounts", [])):
            print("\x1f".join([c["account"], c["id"], c["name"], c["url"], folders.get(c["id"], ""), h, labels.get(c["id"], ""),
                               c.get("project", ""), str(st.get("count", "") or ""), ago(st.get("last")), doms.get(c["id"], ""),
                               d.get("domain_state", {}).get(c["id"], "")]))
elif op == "stat_add":  # id -> one more publish, now
    import time
    st = d.setdefault("stats", {}).setdefault(a[0], {}); st["count"] = st.get("count", 0) + 1; st["last"] = int(time.time()); save()
elif op == "stat_get":  st = d.get("stats", {}).get(a[0], {}); print("%s\t%s" % (st.get("count", 0), ago(st.get("last"))))
elif op == "fb_token":  print(cli_token(a[0]))
elif op == "url_get":   print(next((c["url"] for c in d.get("cache", []) if c["id"] == a[0]), ""))
elif op in ("fb_domain", "fb_records"):  # token project site domain -> the DNS records to add, type<TAB>host<TAB>value; fb_domain connects it first
    import time
    base = "https://firebasehosting.googleapis.com/v1beta1/projects/%s/sites/%s/customDomains" % (a[1], a[2])
    def call(ep, method="GET", body=None):
        req = urllib.request.Request(base + ep, method=method, data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": "Bearer " + a[0], "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r: raw = r.read(); return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            try: msg = json.loads(e.read()).get("error", {}).get("message", str(e))
            except Exception: msg = str(e)
            if e.code == 409: return {}   # connected already: just read its records
            if e.code == 404: raise ApiErr("not connected on Firebase yet")
            raise ApiErr(msg)
        except urllib.error.URLError as e: raise ApiErr("cannot reach Firebase: %s" % e.reason)
    if op == "fb_domain": call("?customDomainId=" + a[3], "POST", {})
    for _ in range(15 if op == "fb_domain" else 1):
        cd = call("/" + a[3])
        recs = [r for g in (cd.get("requiredDnsUpdates") or {}).get("desired", []) for r in g.get("records", [])]
        recs += [r for g in ((cd.get("cert") or {}).get("verification") or {}).get("dns", {}).get("desired", []) for r in g.get("records", [])]
        if recs or cd.get("hostState") == "HOST_ACTIVE": break
        time.sleep(2)
    if dom_state(cd) == "live" or not recs: print("%s\t%s\t%s" % (dom_state(cd), cd.get("hostState", ""), (cd.get("cert") or {}).get("state", ""))); sys.exit(0)
    for r in recs:   # records already in place come back too, marked with no action; only the ones to add are shown
        if r.get("requiredAction") == "ADD": print("%s\t%s\t%s" % (r["type"], r["domainName"], r["rdata"]))
elif op == "label_set":
    labels = d.setdefault("labels", {})
    if a[1]: labels[a[0]] = a[1]
    else: labels.pop(a[0], None)
    save()
elif op == "label_get": print(d.get("labels", {}).get(a[0], ""))
elif op == "domain_set":  # id domain -> remembered at once, shown as pending until the refresh sees it answer
    doms = d.setdefault("domains", {})
    if a[1]: doms[a[0]] = a[1]
    else: doms.pop(a[0], None)
    d.get("domain_state", {}).pop(a[0], None)
    save()
elif op == "domain_get": print(d.get("domains", {}).get(a[0], ""))
elif op == "domain_state": print(d.get("domain_state", {}).get(a[0], ""))   # dns, cert or live, from the last refresh; "" when never seen
# mail: who gets the link for a project, by project id; the mailbox itself is lib/mail.sh's mail.json
elif op == "people":           # id [to|cc|bcc]
    for r in mail(a[0]).get(a[1] if len(a) > 1 else "to", []):
        print("%s\t%s" % (r.get("name") or r.get("email", "").split("@")[0], r.get("email", "")))
elif op == "person_add":       # id name email [to|cc|bcc]
    m = mail(a[0]); f = a[3] if len(a) > 3 else "to"
    m[f] = [r for r in m.get(f, []) if r.get("email") != a[2]]; m[f].append({"name": a[1], "email": a[2]}); save()
elif op == "person_del":       # id email [to|cc|bcc]
    m = mail(a[0]); f = a[2] if len(a) > 2 else "to"
    m[f] = [r for r in m.get(f, []) if r.get("email") != a[1]]; save()
elif op == "subject_get":      print(d.get("mail", {}).get(a[0], {}).get("subject", ""))
elif op == "subject_set":      mail(a[0])["subject"] = a[1]; save()
elif op == "sha_get":          print(d.get("mail", {}).get(a[0], {}).get("last_sha", ""))
elif op == "sha_set":          mail(a[0])["last_sha"] = a[1]; save()
elif op == "mail_default_get": print(d.get("mail", {}).get(a[0], {}).get("default", ""))
elif op == "mail_default_set": mail(a[0])["default"] = a[1]; save()
elif op == "mail_json":
    m = d.get("mail", {}).get(a[0], {})
    print(json.dumps({f: m.get(f, []) for f in ("to", "cc", "bcc")} | {"subject": m.get("subject", "")}))
elif op == "folder_of":  print(next((f for f, pr in sorted(d["projects"].items()) if pr.get("id") == a[0]), ""))
elif op == "fb_accounts": [print(e) for e in d.get("fb_accounts", [])]
elif op == "stamp":     import time; d["refreshed_at"] = int(time.time()); save()
elif op == "age":       import time; print(int(time.time()) - int(d.get("refreshed_at") or 0))
elif op == "fb_projects":  # account -> projectId<TAB>display name, from the cache
    seen = set()
    for c in d.get("cache", []):
        if c.get("host") == "firebase" and c["account"] == a[0]:
            pid = c["id"].split("/")[0]
            if pid not in seen: seen.add(pid); print(pid + "\t" + c.get("project", pid))
elif op == "create":    p = api(a[0], a[1], "POST", "/v10/projects", {"name": a[2], "framework": None}); print("%s\t%s" % (p["id"], p["name"]))
elif op == "domain":    # the stable production domain of a project, if any
    ds = [x["name"] for x in pages(a[0], a[1], "/v9/projects/%s/domains?limit=100" % a[2], "domains") if not x.get("gitBranch") and not x.get("redirect")]
    print(next((x for x in ds if not x.endswith(".vercel.app")), ds[0] if ds else ""))
else: sys.exit(2)
PY
}

ACTIONS=""
IFS= read -r -d '' ACTIONS <<'ACTS' || true   # a heredoc, so option texts may hold quotes
new site here|site.new|s
new project here|-|
new project|project.new|n
label a project|project.label|l
custom domain|project.domain|d
create a new firebase project|new.firebase_project|c
create|new.create|c
change the name|new.rename|e
accounts|accounts|a
refresh|refresh|r
quit|quit|q
connect it now|domain.connect|c
just keep it as a reminder|domain.remember|r
main website|site.main|m
test version|site.test|t
publish as|version.keep|p
bump|version.bump|b
vercel project|new.vercel|v
firebase site|new.firebase|f
add a firebase account|account.add_firebase|f
add a vercel account|account.add_vercel|v
sign in with vercel in the browser|signin.browser|b
paste a token|signin.token|t
vercel|host.vercel|v
firebase|host.firebase|f
this folder|folder.this|t
the folder it was built from last time|folder.last|l
remove it|account.remove|d
sign it out|account.signout|d
personal|scope.personal|p
mailbox|mailbox|m
email for this project|project.mail|e
send the link|mail.send|s
skip mail this time|mail.skip|x
change to, cc, bcc or subject|mail.change|c
set up mailbox|mail.setup_box|m
set up this project's email|mail.setup_app|e
use these|notes.use|u
write my own|notes.write|w
no notes|notes.none|x
open the link in the browser|done.link|o
check the domain again|domain.check|c
label this project|done.label|l
back to projects|projects|p
back|back|esc
ACTS

# ── accounts ──────────────────────────────────────────────────────────────
# Every account ends up with a token on disk: pasted ones in accounts/<name>/token,
# browser logins in the CLI's own accounts/<name>/auth.json. Same API path after that.


add_any_account(){ # -> asks which host and adds an account there; asks again until one is added or the user quits
  while :; do
    MENU_ITEMS=("Vercel" "Firebase" "quit"); MENU_NOTES=("  ${D}browser sign-in or a token${R}" "  ${D}Google sign-in in the browser${R}" "")
    step "Add an account"
    case "$(menu_pick "Where" 0)" in
      0) need_vercel; add_account >/dev/null && return 0 ;;
      1) add_fb_account && return 0 ;;
      *) return 1 ;;
    esac
  done
}

accounts_menu(){
  local names=() kinds=() n idx
  while :; do
    names=(); kinds=(); MENU_ITEMS=(); MENU_NOTES=()
    while IFS= read -r n; do [ -n "$n" ] && { names+=("$n"); kinds+=(vercel); MENU_ITEMS+=("$(printf '%-28s' "$n")"); MENU_NOTES+=("  ${D}Vercel   · $(vc acct_get "$n" scope) · $([ -f "$ACCTS/$n/token" ] && echo token || echo 'browser sign-in')${R}"); }; done < <(vc accounts)
    while IFS= read -r n; do [ -n "$n" ] && { names+=("$n"); kinds+=(firebase); MENU_ITEMS+=("$(printf '%-28s' "$n")"); MENU_NOTES+=("  ${D}Firebase · Google sign-in${R}"); }; done < <(fb_logins)
    MENU_ITEMS+=("+ add a Vercel account" "+ add a Firebase account" "← back"); MENU_NOTES+=("" "" "")
    step "Accounts"
    idx="$(menu_pick "Which account" 0)"
    case $(( idx - ${#names[@]} )) in
      0) need_vercel; add_account >/dev/null; continue ;;
      1) add_fb_account; vc fb_refresh 2>/dev/null; continue ;;
      2) return ;;
    esac
    n="${names[$idx]}"
    if [ "${kinds[$idx]}" = firebase ]; then
      MENU_ITEMS=("sign it out" "← back"); MENU_NOTES=("  ${D}firebase logout ${n} — nothing changes on Firebase${R}" "")
      step "$n"
      [ "$(menu_pick "What to do" 1)" = 0 ] && { cmd "firebase logout $n"; firebase logout "$n" >&2; vc fb_refresh 2>/dev/null; ok "signed out “${n}”"; }
    else
      MENU_ITEMS=("remove it" "← back"); MENU_NOTES=("  ${D}forgets the sign-in on this Mac, nothing changes on Vercel${R}" "")
      step "$n"
      [ "$(menu_pick "What to do" 1)" = 0 ] && { vc acct_del "$n"; rm -rf "$ACCTS/$n"; ok "removed “${n}”"; }
    fi
  done
}

# ── projects ──────────────────────────────────────────────────────────────

refresh(){ # pulls every account's projects into the cache behind a spinner; "fresh" skips it when the cache is under 10 minutes old
  local out pid i=0 f='|/-\' n e
  [ "${1:-}" = fresh ] && [ -n "$(vc landing)" ] && [ "$(vc age)" -lt 600 ] && return 0
  out="$(tmpf shipsite-refresh)"
  { wake_logins; vc refresh; vc fb_refresh; } 2>"$out" & pid=$!
  if [ -t 2 ]; then
    while kill -0 "$pid" 2>/dev/null; do printf "\r     ${A}%s${R} ${D}refreshing projects from Vercel and Firebase…${R}" "${f:$((i++ % 4)):1}" >&2; sleep 0.15; done
    printf "\r\033[K" >&2
  fi
  wait "$pid"; vc stamp
  while IFS=$'\t' read -r n e; do [ -n "$n" ] && warn "“${n}”: ${e} — showing its last known projects"; done <"$out"
  rm -f "$out"
}

choose_folder(){ # $1 folder this project was last built from -> echoes the folder to build now
  local saved="$1" p
  [ -n "$ROOT" ] && { printf '%s' "$ROOT"; return; }   # you are in a project: that is the one; another folder on the same site is warned about later
  [ -n "$saved" ] && is_project "$saved" && { printf '%s' "$saved"; return; }
  step "Which folder to build"
  while :; do
    p="$(ask "Project folder" "")"; [ -n "$p" ] || return 1; p="${p/#\~/$HOME}"
    is_project "$p" && { ( cd "$p" && pwd ); return; }
    warn "no package.json and no index.html in $p"
  done
}


new_project(){ # $1 host  $2 account (both optional: given from a group's own row) -> echoes "host<TAB>account<TAB>id<TAB>name"
  local names=() fbs=() n acct="${2:-}" token team pname r host="${1:-}" idx pid site
  while IFS= read -r n; do [ -n "$n" ] && names+=("$n"); done < <(vc accounts)
  while IFS= read -r n; do [ -n "$n" ] && fbs+=("$n"); done < <(vc fb_accounts)
  if [ -z "$host" ]; then
    MENU_ITEMS=("Vercel project" "Firebase site" "← back")
    MENU_NOTES=("  ${D}$([ ${#names[@]} -gt 0 ] && echo "in ${names[0]}$([ ${#names[@]} -gt 1 ] && echo ' or another account')" || echo 'signs in to Vercel first')${R}"
                "  ${D}$([ ${#fbs[@]} -gt 0 ] && echo 'in an existing or a new Firebase project' || echo 'signs in with Google first')${R}" "")
    step "New project"
    case "$(menu_pick "Where" 0)" in 0) host=vercel ;; 1) host=firebase ;; *) return 1 ;; esac
  fi
  n=""; [ -n "$ROOT" ] && n="$(slugify "$(node -p "require('$ROOT/package.json').name||''" 2>/dev/null || basename "$ROOT")")"

  if [ "$host" = firebase ]; then
    need_firebase
    while [ -z "$acct" ]; do
      MENU_ITEMS=(); MENU_NOTES=()
      for n2 in "${fbs[@]}"; do MENU_ITEMS+=("$n2"); MENU_NOTES+=(""); done
      MENU_ITEMS+=("+ add a Firebase account" "← back"); MENU_NOTES+=("  ${D}another Google account, signed in through the browser${R}" "")
      step "Firebase account"
      idx="$(menu_pick "Which account" 0)"
      if   [ "$idx" -eq $(( ${#fbs[@]} + 1 )) ]; then return 1
      elif [ "$idx" -eq ${#fbs[@]} ]; then
        add_fb_account && vc fb_refresh 2>/dev/null
        fbs=(); while IFS= read -r n2; do [ -n "$n2" ] && fbs+=("$n2"); done < <(vc fb_accounts)
      else acct="${fbs[$idx]}"; fi
    done
    local pids=(); MENU_ITEMS=("+ create a new Firebase project"); MENU_NOTES=("  ${D}just a name — free plan, Hosting only${R}")
    while IFS=$'\t' read -r pid pname; do [ -n "$pid" ] && { pids+=("$pid"); MENU_ITEMS+=("$(printf '%-30s' "$pname")"); MENU_NOTES+=("  ${D}${pid}${R}"); }; done < <(vc fb_projects "$acct")
    MENU_ITEMS+=("← back"); MENU_NOTES+=("")
    step "Which Firebase project  ${D}${acct}${R}"
    idx="$(menu_pick "Project" 0)"
    [ "$idx" -eq $(( ${#pids[@]} + 1 )) ] && return 1
    if [ "$idx" -eq 0 ]; then
      r="$(fb_create_project "$acct" "${n:-my-site}")" || return 1
      pid="${r%%	*}"; site="${r#*	}"
      vc cache_add "$acct" "$pid/$site" "$site" "$site.web.app" firebase "$pid"
      printf 'firebase\t%s\t%s\t%s' "$acct" "$pid/$site" "$site"; return
    fi
    pid="${pids[$((idx - 1))]}"
    while :; do
      pname="$(confirm_name "Site name (becomes <name>.web.app)" "$n" "NAME.web.app  in ${pid}")" || return 1
      [ "$DRY" = yes ] && { ok "would create site “${pname}” in ${pid}  ${D}(dry run, not created)${R}"; return 1; }
      cmd "firebase hosting:sites:create $pname --project $pid --account $acct"
      r="$(firebase hosting:sites:create "$pname" --project "$pid" --account "$acct" --non-interactive 2>&1)" && break
      warn "$(printf '%s' "$r" | grep -i error | tail -1 | sed 's/^Error: //')"; n="$pname"
    done
    ok "created site “${pname}” → ${pname}.web.app"
    vc cache_add "$acct" "$pid/$pname" "$pname" "$pname.web.app" firebase "$pid"
    printf 'firebase\t%s\t%s\t%s' "$acct" "$pid/$pname" "$pname"; return
  fi

  need_vercel
  if [ -n "$acct" ]; then :; elif [ ${#names[@]} -eq 1 ]; then acct="${names[0]}"; elif [ ${#names[@]} -eq 0 ]; then acct="$(add_account)" || return 1; else acct="$(pick_account)" || return 1; fi
  token="$(acct_token "$acct")"; team="$(vc acct_get "$acct" team_id)"
  step "New Vercel project in “${acct}”  ${D}$(vc acct_get "$acct" scope)${R}"
  while :; do
    pname="$(confirm_name "Project name" "$n" "NAME  on Vercel in “${acct}”")" || return 1
    [ "$DRY" = yes ] && { ok "would create “${pname}” in “${acct}”  ${D}(dry run, not created)${R}"; return 1; }
    r="$(vc create "$token" "${team:--}" "$pname")" && break
    warn "${r#ERR	}"; n="$pname"
  done
  ok "created “${r#*	}”"
  vc cache_add "$acct" "${r%%	*}" "${r#*	}" "${r#*	}.vercel.app"
  printf 'vercel\t%s\t%s' "$acct" "$r"
}


rank_rows(){ # stdin: landing rows; $1 folder $2 .firebaserc project $3 firebase.json site $4 .vercel project $5 names
  # -> the rows grouped by account and host, each with its rank (0 path, 1 config, 2 name, 3 similar name, 9 none) and why
  py -c '
import sys
root, rc, fbsite, vid = sys.argv[1:5]
names = set(n for n in sys.argv[5].split() if n)
rows = [(l.rstrip("\n").split("\x1f") + [""] * 12)[:12] for l in sys.stdin if l.strip()]
def rank(r):
    a, i, n, u, f, h, lb = r[:7]
    if root and f == root: return 0, "this folder"
    if f and f != root: return 9, ""
    like = lambda x: x and any(len(x) > 3 and len(m) > 3 and (m.startswith(x) or x.startswith(m)) for m in names)
    if h == "firebase":
        pid, site = (i.split("/") + [""])[:2]
        if (rc and pid == rc) or (fbsite and site == fbsite): return 1, "this folder’s firebase config"
        if pid in names or site in names or n.lower() in names: return 2, "same name as this folder"
        if like(site) or like(n.lower()): return 3, "named like this folder"
    else:
        if vid and i == vid: return 1, "this folder’s .vercel link"
        if n.lower() in names: return 2, "same name as this folder"
        if like(n.lower()): return 3, "named like this folder"
    return 9, ""
groups = {}
for r in rows: groups.setdefault((r[5], r[0]), []).append(r)
best = lambda g: min(rank(r)[0] for r in groups[g])
pid = lambda r: r[1].split("/")[0] if r[5] == "firebase" else r[1]
for g in sorted(groups, key=lambda g: (best(g), g[0] != "vercel", g[1].lower())):
    first = {}
    for r in groups[g]: first.setdefault(pid(r), len(first))
    sites = {}
    for r in groups[g]: sites[pid(r)] = sites.get(pid(r), 0) + 1
    for r in sorted(groups[g], key=lambda r: first[pid(r)]):
        k, why = rank(r)
        print("\x1f".join(r + [str(k), why, str(sites[pid(r)])]))
' "$@"
}

find_root(){ local d="$PWD"; while [ "$d" != "/" ]; do is_project "$d" && { printf '%s' "$d"; return; }; d="$(dirname "$d")"; done; return 1; }
is_project(){ [ -f "$1/package.json" ] || [ -n "$(web_root "$1")" ]; }   # something to build, or plain files to publish
has_build(){ [ -n "$(node -p "(require('$1/package.json').scripts||{}).build||''" 2>/dev/null)" ]; }
web_root(){ # $1 root -> the folder of a static site, the one holding index.html: here, site/, public/, www/, docs/, static/
  local d; for d in . site public www docs static; do [ -f "$1/$d/index.html" ] && { printf '%s' "$d"; return; }; done
}
nfiles(){ local n; n="$(find "$1" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.idea/*' -not -name .DS_Store | wc -l | tr -d ' ')"; printf '%s file%s' "$n" "$([ "$n" = 1 ] || echo s)"; }
clean_stage(){ # $1 folder -> what never belongs on a website: the repo, modules, editor files, secrets
  rm -rf "$1/.git" "$1/node_modules" "$1/.idea" "$1/.vscode"; rm -f "$1"/.env "$1"/.env.*; find "$1" -name .DS_Store -delete 2>/dev/null; :
}
detect_pm(){ # $1 root -> the package manager whose lockfile is there, npm otherwise
  if   [ -f "$1/pnpm-lock.yaml" ]; then echo pnpm
  elif [ -f "$1/yarn.lock" ];      then echo yarn
  elif [ -f "$1/bun.lock" ] || [ -f "$1/bun.lockb" ]; then echo bun
  else echo npm; fi
}
slugify(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'; }
confirm_name(){ # $1 prompt  $2 suggested  $3 what it becomes, with NAME standing for the name -> echoes the cleaned name once it is confirmed
  local typed name
  while :; do
    typed="$(ask "$1" "$2")"; [ -n "$typed" ] || return 1
    name="$(slugify "$typed")"; [ -n "$name" ] || { warn "nothing usable in “${typed}” — letters, digits and dashes"; continue; }
    [ "$name" != "$typed" ] && sub "cleaned to ${B}${name}${R} — only lowercase letters, digits and dashes are allowed"
    MENU_ITEMS=("create  ${3//NAME/$name}" "change the name" "← back"); MENU_NOTES=("" "" "")
    case "$(menu_pick "Create it" 0)" in 0) printf '%s' "$name"; return ;; 1) set -- "$1" "$name" "$3" ;; *) return 1 ;; esac
  done
}
guess_label(){ # $1 folder -> a label guessed from its name: admin, dashboard, landing, api, docs; nothing when it says nothing
  local n; n="$(basename "$1" | tr 'A-Z' 'a-z')"
  case "$n" in
    *admin*)                        echo admin ;;
    *dashboard*|*panel*)            echo dashboard ;;
    *landing*|*website*|*-web|*web|*site|*www*|*home*) echo landing ;;
    *api*)                          echo api ;;
    *docs*)                         echo docs ;;
  esac
}

outdir(){ # $1 root -> the folder to publish: the build output (dist for Vite, build for Create React App, out for a Next.js export, _site for Eleventy or Jekyll), else a static site's web root
  local d; for d in dist build out _site; do [ -f "$1/$d/index.html" ] && { printf '%s' "$d"; return; }; done
  has_build "$1" || web_root "$1"
}
STATIC=""   # set by deploy when the project has no build: its files are published as they are
build_or_files(){ # $1 root $2 package manager $3 stage -> runs the build, or for a static site names the files that go up as they are
  local root="$1" pm="$2" log="$3-build.log"
  if [ -n "$STATIC" ]; then
    step "Files"
    row "folder" "${root}/${STATIC#./}  ${D}no build — published as they are, $(nfiles "$root/$STATIC")${R}"
    return
  fi
  step "Building"
  cmd "cd $root && $pm run build"
  ( cd "$root" && $pm run build ) > >(tee "$log" >&2) 2>&1 || { fail "the build failed — nothing was published" "$log"; }
  [ -n "$(outdir "$root")" ] || die "no index.html in dist/, build/, out/ or _site/ after the build — where does your build put its files?"
}


bump_version(){ # $1 version like 1.4.2+17  $2 build|patch|minor|major -> next version
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

web_version_guard(){ # $1 root -> on a main-website publish, shows the version and bumps package.json only if asked
  local root="$1" v nv repeat=no
  v="$(node -p "require('$root/package.json').version||''" 2>/dev/null)"
  # package.json is plain semver (1.0.0, maybe 1.0.0-beta.1); anything else is left alone
  echo "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || return 0
  [ "$v" = "$(vc proj_get "$root" last_prod_version)" ] && repeat=yes
  step "Version  ${B}$v${R}$([ "$repeat" = yes ] && printf "  ${Y}live already${R}")"
  MENU_ITEMS=("publish as $v" "bump"); MENU_NOTES=("" "  ${D}next is $(bump_version "$v" patch), or type your own${R}")
  [ "$(menu_pick "Version" "$([ "$repeat" = yes ] && echo 1 || echo 0)")" = 0 ] && return 0
  while :; do
    nv="$(ask "New version" "$(bump_version "$v" patch)")"
    echo "$nv" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' && break
    warn "“${nv}” is not a version like 1.0.1"
  done
  [ "$nv" = "$v" ] && return 0
  [ "$DRY" = yes ] && { row "package" "would become version: ${D}$v${R} → ${B}$nv${R}  ${D}(dry run, not written)${R}"; return 0; }
  cmd "npm version $nv --no-git-tag-version"
  ( cd "$root" && npm version "$nv" --no-git-tag-version >/dev/null ) || { warn "could not bump package.json — publishing $v"; return 0; }
  row "package" "version: ${D}$v${R} → ${B}$nv${R}"
}

dry_source(){ # $1 root $2 package manager -> says whether a build runs or files go up as they are; false when neither can
  if [ -n "$STATIC" ]; then ok "static site: ${STATIC#./}/ with $(nfiles "$1/$STATIC") — no build, published as they are"; return 0; fi
  has_build "$1" && ok "package.json has a build script" || { warn "✗ package.json has no build script"; return 1; }
  have "$2" && ok "$2 is installed" || { warn "✗ $2 is not installed"; return 1; }
}


# ── deploy ────────────────────────────────────────────────────────────────
deploy(){ # $1 account  $2 project id (Firebase: project/site)  $3 name  $4 folder  $5 host (vercel|firebase)
  local acct="$1" pid="$2" pname="$3" root="$4" host="${5:-vercel}" pm token team stage url flag domain log label also idx site notes="" ver
  pm="$(detect_pm "$root")"; STATIC=""
  if ! has_build "$root"; then
    STATIC="$(web_root "$root")"
    [ -n "$STATIC" ] || die "nothing to publish in $root — no build script in package.json, and no index.html here or in site/, public/, www/, docs/ or static/"
  fi
  [ "$DRY" = yes ] || { [ "$host" = firebase ] && need_firebase || need_vercel; }   # before any question or write
  while :; do
    label="$(vc label_get "$pid")"; domain="$(vc domain_get "$pid")"
    step "${label:-$pname}$([ -n "$label" ] && printf "  ${D}%s${R}" "$pname")"
    if [ "$host" = firebase ]; then
      row "host" "Firebase  ${D}${acct}${R}"
      row "project" "${pid%%/*}"
    else
      row "host" "Vercel  ${D}${acct} · $(vc acct_get "$acct" scope)${R}"
    fi
    row "folder" "$root"
    if [ -n "$domain" ]; then
      [ "$host" = firebase ] && [ "$(vc url_get "$pid")" != "$domain" ] && row "domain" "${domain}  ${Y}$(dom_note "$(vc domain_state "$pid")")${R}  ${D}also ${pid#*/}.web.app, which stays as is${R}" \
                                                                        || row "domain" "${domain}  ${D}also ${pid#*/}.$([ "$host" = firebase ] && echo web.app || echo vercel.app), which stays as is${R}"
    else row "domain" "${D}none yet${R}"; fi
    [ -n "$PROD" ] && break
    MENU_ITEMS=("main website" "test version")
    if [ "$host" = firebase ]; then MENU_NOTES=("   ${D}updates ${pid#*/}.web.app$([ -n "$domain" ] && echo " and ${domain} once live")${R}" "   ${D}a preview URL for 7 days, the main website untouched${R}")
    else MENU_NOTES=("   ${D}updates production${R}" "   ${D}a new preview URL, production untouched${R}"); fi
    [ "$host" = firebase ] && { MENU_ITEMS+=("new site here"); MENU_NOTES+=("   ${D}another <name>.web.app in ${pid%%/*}; this folder publishes there instead${R}"); }
    MENU_ITEMS+=("custom domain" "← back")
    MENU_NOTES+=("   ${D}${domain:-your own domain or subdomain}, saved as a reminder; connect it now or later${R}" "   ${D}another project or site${R}")
    idx="$(menu_pick "Publish to" 0)"
    [ "$host" = firebase ] || [ "$idx" -lt 2 ] || idx=$((idx + 1))   # no "new site here" on Vercel: the rows after it shift up by one
    case "$idx" in
      0) PROD=yes
         # a single stray key must not replace the live site
         if picked_by_key && [ "$DRY" != yes ] && ! confirm_y "Publish to the main website?"; then warn "cancelled — nothing was published"; exit 0; fi
         break ;;
      1) PROD=no; break ;;
      2) if site="$(new_site_here "$acct" "${pid%%/*}" "$root")"; then pid="${pid%%/*}/$site"; pname="$site"; fi; continue ;;
      3) custom_domain "$host" "$acct" "$pid" "$pname" || true; continue ;;
      *) return 1 ;;
    esac
  done
  DONE_ID="$pid"; DONE_NAME="$pname"   # the done screen needs the site actually published to, which "new site here" may have changed
  # another folder already publishes here: say so before anything is built, and let the user back out
  domain="$(vc folder_of "$pid")"
  if [ -n "$domain" ] && [ "$domain" != "$root" ]; then
    warn "${label:-$pname} is published from $(sed "s|^$HOME|~|" <<<"$domain")"
    confirm_y "Publish $(sed "s|^$HOME|~|" <<<"$root") there instead, replacing what is live?" || { ok "nothing changed — back to projects"; return 1; }
  fi
  # remember which project this folder publishes to — not in a dry run, which writes nothing
  if [ "$DRY" != yes ] && [ "$(vc proj_get "$root" id)" != "$pid" ]; then
    vc proj_set "$root" account "$acct"; vc proj_set "$root" id "$pid"; vc proj_set "$root" name "$pname"; vc proj_set "$root" host "$host"
  fi
  [ "$PROD" = yes ] && web_version_guard "$root"
  ver="$(node -p "require('$root/package.json').version||''" 2>/dev/null)"
  mail_step "$pid" "${label:-$pname}"
  [ "$MAIL" = yes ] && notes="$(pick_notes "$root" "$pid")"

  if [ "$host" = firebase ]; then
    [ "$DRY" = yes ] && { dry_deploy_firebase "$acct" "$pid" "$root" "$pm"; dry_mail "$pid" "${label:-$pname}" "${ver:-—}" "https://${pid#*/}.web.app" "$notes" || true; exit 0; }
    publish_firebase "$acct" "$pid" "$root" "$pm"
    mail_after "$pid" "${label:-$pname}" "${ver:-—}" "$URL" "$notes" "$root"; return
  fi

  token="$(acct_token "$acct")"; team="$(vc acct_get "$acct" team_id)"
  [ "$DRY" = yes ] && { dry_deploy "$acct" "$pid" "$pname" "$root" "$pm"; dry_mail "$pid" "${label:-$pname}" "${ver:-—}" "https://${pname}.vercel.app" "$notes" || true; exit 0; }

  stage="$(tmpd shipsite)"; trap "rm -rf '$stage' '$stage'-*.log" EXIT
  build_or_files "$root" "$pm" "$stage"

  # publish from a copy outside the repo: no .git above it, so Vercel attaches no commit
  stage_dist "$root" "$stage" "$pid" "$(vc acct_get "$acct" org_id)" "$pname" || die "could not copy dist/"

  step "Publishing"
  row "project" "$pname"
  row "target" "$([ "$PROD" = yes ] && echo 'main website' || echo 'test version')"
  [ "$PROD" = yes ] && flag="--prod" || flag=""
  acct_cli "$acct"
  cmd "vercel deploy --yes $flag $([ "${AUTH[0]}" = --token ] && echo '--token ••••' || printf '%s "%s"' "${AUTH[0]}" "${AUTH[1]}")  ${D}(from a temp copy of dist/)${R}"
  log="$stage-deploy.log"
  url="$(cd "$stage" && vercel deploy --yes $flag "${AUTH[@]}" 2> >(tee "$log" >&2))" || fail "Vercel rejected the deploy — nothing was published" "$log"
  [ -n "$url" ] || fail "Vercel finished but returned no URL" "$log"
  vc stat_add "$pid"
  if [ "$PROD" = yes ]; then
    domain="$(vc domain "$token" "${team:--}" "$pid" 2>/dev/null)"; [ -n "$domain" ] && [ "${domain#ERR}" = "$domain" ] && url="https://$domain"
  fi
  also=""; [ "$PROD" = yes ] && [ "$url" != "https://${pname}.vercel.app" ] && also="https://${pname}.vercel.app"
  if [ "$PROD" = yes ]; then
    vc proj_set "$root" last_prod_version "$(node -p "require('$root/package.json').version||''" 2>/dev/null)"
    vc proj_set "$root" last_prod_date "$(date '+%d %b %H:%M')"
  fi
  printf %s "$url" | clip 2>/dev/null
  step "Published"
  row "link" "${B}${A}${url}${R}  ${D}copied${R}"
  [ -n "$also" ] && row "also" "${also}  ${D}stays as is${R}"
  URL="$url"; ALSO="$also"
  mail_after "$pid" "${label:-$pname}" "${ver:-—}" "$URL" "$notes" "$root"
}

URL=""; ALSO=""; DONE_ID=""; DONE_NAME=""
done_menu(){ # $1 host $2 account $3 project id $4 name $5 folder -> after a publish: the details to copy, then what next
  local host="$1" acct="$2" pid="$3" pname="$4" root="$5" l dom pend idx
  [ "$host" = firebase ] && row "console" "https://console.firebase.google.com/project/${pid%%/*}/hosting/sites/${pid#*/}" \
                         || row "console" "https://vercel.com/$(vc acct_get "$acct" scope)/${pname}"
  [ -n "$MAILED" ] && row "mail" "sent to $MAILED address$([ "$MAILED" = 1 ] || echo es)"
  while :; do
    l="$(vc label_get "$pid")"
    MENU_ITEMS=("open the link in the browser" "label this project" "custom domain" "email for this project")
    MENU_NOTES=("  ${D}${URL}${R}" "  ${D}${l:-$pname} — admin, landing, the domain it serves; change it any time${R}" "  ${D}$(vc domain_get "$pid")${R}"
                "  ${D}$([ "$(vc people "$pid" to | grep -c .)" -gt 0 ] && recipients "$pid" || echo 'nobody yet — who gets the link next time')${R}")
    dom="$(vc domain_get "$pid")"; pend=""
    if [ "$host" = firebase ] && [ -n "$dom" ] && [ "$(vc url_get "$pid")" != "$dom" ]; then
      pend=yes; MENU_ITEMS+=("check the domain again"); MENU_NOTES+=("  ${D}asks Firebase whether ${dom} is live yet${R}")
    fi
    MENU_ITEMS+=("back to projects" "quit"); MENU_NOTES+=("" "")
    printf "\n" >&2
    idx="$(menu_pick "Next" $(( ${#MENU_ITEMS[@]} - 2 )))"
    [ -n "$pend" ] || [ "$idx" -lt 4 ] || idx=$((idx + 1))   # without the check row, the rows after it shift up by one
    case "$idx" in
      0) open_it "$URL" || warn "could not open a browser — the link is copied" ;;
      1) vc label_set "$pid" "$(ask "Label for ${pname}" "${l:-$pname}")"; ok "saved" ;;
      2) custom_domain "$host" "$acct" "$pid" "$pname" ;;
      3) setup_app_mail "$pid" "${l:-$pname}" ;;
      4) domain_status "$acct" "$pid" || true ;;
      5) return 0 ;;
      *) printf "\n" >&2; exit 0 ;;
    esac
  done
}

# ── main ──────────────────────────────────────────────────────────────────
PROD=""; ROOT=""; DRY=no
main(){
  local arg rows=() a id nm u f note sel idx r folder i
  for arg in "$@"; do
    case "$arg" in
      --prod|--production) PROD=yes ;;
      --preview)           PROD=no ;;
      --dry-run|-n)        DRY=yes ;;
      accounts)            [ -t 0 ] || die "needs a terminal"; banner "ship-site $VERSION" "accounts"; accounts_menu; exit 0 ;;
      mailbox)             [ -t 0 ] || die "needs a terminal"; banner "ship-site $VERSION" "mailbox"; { [ "$(mbox smtp_ready)" = yes ] && smtp_menu || setup_mailbox; }; exit 0 ;;
      --version|-V|-v)     echo "ship-site $VERSION"; exit 0 ;;
      -h|--help)
        printf "\n  ${B}ship-site${R} ${D}%s${R}\n\n" "$VERSION"
        printf "    ${A}ship-site${R}             your Vercel projects and Firebase sites; pick one, it builds and publishes\n"
        printf "    ${A}ship-site --prod${R}      straight to the main website, no question asked\n"
        printf "    ${A}ship-site --preview${R}   a test URL: a fresh preview on Vercel, the 7-day preview channel on Firebase\n"
        printf "    ${A}ship-site --dry-run${R}   check everything and show what would happen; changes nothing (also -n)\n"
        printf "    ${A}ship-site ~/site${R}      treat that folder as the current project\n"
        printf "    ${A}ship-site accounts${R}    add or remove Vercel and Firebase accounts\n"
        printf "    ${A}ship-site mailbox${R}     the account the link is mailed from, shared with ship-apk\n\n"
        printf "  ${D}Run inside a web project and the project it publishes to is preselected. Settings live in %s${R}\n\n" "$CONF"
        exit 0 ;;
      *) ROOT="${arg/#\~/$HOME}"; is_project "$ROOT" || die "no package.json and no index.html in $ROOT" ;;
    esac
  done
  [ -t 0 ] || die "ship-site needs a terminal — run it, do not pipe into it"
  have python3 || die "python3 is required (it ships with macOS developer tools)"
  have npm || { have brew && need "node and npm" npm "brew install node"; } || have npm || die "node is required for the Vercel and Firebase CLIs — install it from https://nodejs.org then run again"
  [ -n "$ROOT" ] || ROOT="$(find_root)" || ROOT=""
  [ -n "$ROOT" ] && ROOT="$(cd "$ROOT" && pwd)"

  banner "ship-site $VERSION" "build it, publish it, copy the link"
  [ "$DRY" = yes ] && sub "${Y}dry run — checks everything, then shows what it would do; nothing is built, deployed, created or written${R}"
  refresh fresh   # the cached list comes up at once; it is refreshed when older than 10 minutes, or on "refresh"
  if [ -z "$(vc landing)" ] && [ -z "$(vc accounts)" ] && [ -z "$(vc fb_accounts)" ]; then
    step "No account on this Mac yet"
    add_any_account || { printf "\n" >&2; exit 0; }
    refresh
  fi

  local h lb rc fbsite vid names rank why best rcseen kind=() grp lines g pj cnt last dom dst pc pgrp ind st
  # what this folder says about where it deploys: its .firebaserc, firebase.json, .vercel/project.json, and its names
  rc=""; fbsite=""; vid=""; names=""
  if [ -n "$ROOT" ]; then
    rc="$(firebaserc_project "$ROOT")"; fbsite="$(firebase_json_site "$ROOT")"; vid="$(vercel_json_project "$ROOT")"
    names="$(slugify "$(node -p "require('$ROOT/package.json').name||''" 2>/dev/null)") $(slugify "$(basename "$ROOT")")"
  fi
  while :; do
    rows=(); MENU_ITEMS=(); MENU_NOTES=(); kind=(); sel=-1; best=9; rcseen=no
    # rank each project against this folder (0 path, 1 config, 2 name, 9 none), then group by account and host;
    # the group holding the best match comes first, then Vercel, then Firebase
    lines="$(vc landing | rank_rows "$ROOT" "$rc" "$fbsite" "$vid" "$names")"
    grp=""; pgrp=""; local ga="" gh=""
    while IFS=$'\x1f' read -r a id nm u f h lb pj cnt last dom dst rank why pc; do
      [ -n "$id" ] || continue
      g="$a · $([ "$h" = firebase ] && echo Firebase || echo Vercel)"
      if [ "$g" != "$grp" ]; then
        [ -n "$grp" ] && { MENU_ITEMS+=("  + new project here"); MENU_NOTES+=("  ${D}in ${grp}${R}"); kind+=("newin"$'\x1f'"$gh"$'\x1f'"$ga"); }
        MENU_ITEMS+=($'\x01'"$g"); MENU_NOTES+=(""); kind+=(head); grp="$g"; ga="$a"; gh="$h"; pgrp=""
      fi
      # a Firebase project with several sites shows them under its own line, so two sites read as one project
      ind=""
      if [ "$h" = firebase ] && [ "${pc:-1}" -gt 1 ]; then
        ind="  "
        [ "${id%%/*}" != "$pgrp" ] && { pgrp="${id%%/*}"; MENU_ITEMS+=($'\x01'"  ${pj:-$pgrp}  ${D}${pgrp} · ${pc} sites${R}"); MENU_NOTES+=(""); kind+=(head); }
      fi
      [ "$h" = firebase ] && [ -n "$rc" ] && [ "${id%%/*}" = "$rc" ] && rcseen=yes
      rows+=("$a"$'\x1f'"$id"$'\x1f'"$nm"$'\x1f'"$f"$'\x1f'"$h")
      note=""
      if [ "$rank" -lt 9 ]; then
        note="  ${G}● ${why}${R}"
        [ "$rank" -lt "$best" ] && { best=$rank; sel=${#MENU_ITEMS[@]}; }
      elif [ -n "$f" ]; then note="  ${D}$(sed "s|^$HOME|~|" <<<"$f")${R}"; fi
      st=""; [ -n "$cnt" ] && st="${cnt}× · ${last}"
      if [ -n "$dom" ] && [ "$dom" != "$u" ]; then u="$dom $(dom_note "$dst")"; fi
      case "$u" in *.web.app|*.vercel.app) ;; *) st="$st  also ${nm}.$([ "$h" = firebase ] && echo web.app || echo vercel.app)" ;; esac
      MENU_ITEMS+=("  ${ind}$(printf '%-24s' "${lb:-$nm}")"); MENU_NOTES+=("  ${D}$(printf '%-32s %-13s' "$u" "$st")${R}$note"); kind+=("row:$(( ${#rows[@]} - 1 ))")
    done <<<"$lines"
    [ -n "$grp" ] && { MENU_ITEMS+=("  + new project here"); MENU_NOTES+=("  ${D}in ${grp}${R}"); kind+=("newin"$'\x1f'"$gh"$'\x1f'"$ga"); }
    [ ${#rows[@]} -gt 0 ] && { MENU_ITEMS+=($'\x01'); MENU_NOTES+=(""); kind+=(head); }   # a blank line sets the actions apart
    MENU_ITEMS+=("  + new project" "  label a project" "  custom domain" "  mailbox" "  accounts" "  refresh" "  quit")
    MENU_NOTES+=("  ${D}a Vercel project or a Firebase site, by name${R}" "  ${D}your own name for one: admin, landing, the domain it serves${R}"
                 "  ${D}connect your own domain to a Firebase site; shows the DNS records to add${R}"
                 "  ${D}$([ "$(mbox smtp_ready)" = yes ] && mbox smtp_get user || echo 'not set up yet') · the link can be mailed after a publish · shared with ship-apk${R}"
                 "  ${D}Vercel and Firebase: add, remove, sign in again${R}" "  ${D}fetch the project list again${R}" "")
    kind+=(new label domain mailbox accounts refresh quit)
    [ "$sel" -ge 0 ] || sel=0
    step "Projects"
    [ -n "$ROOT" ] && sub "you are in $(sed "s|^$HOME|~|" <<<"$ROOT")"
    [ -n "$rc" ] && [ "$rcseen" = no ] && sub "${Y}this folder's .firebaserc names Firebase project “${rc}”, which none of your signed-in accounts can see — add its Google account under accounts${R}"
    MENU_FIXED=$([ ${#rows[@]} -gt 0 ] && echo 8 || echo 7)   # the actions stay on screen; only the projects scroll
    MENU_NOKEY=""; for i in "${!kind[@]}"; do case "${kind[$i]}" in row:*) MENU_NOKEY="$MENU_NOKEY $i" ;; esac; done
    idx="$(menu_pick "Pick one to publish" "$sel")"; MENU_FIXED=0; MENU_NOKEY=""   # set for that menu only; it ran in a subshell
    case "${kind[$idx]}" in
      new|newin*)
         if [ "${kind[$idx]}" = new ]; then r="$(new_project)" || continue
         else IFS=$'\x1f' read -r _ h a <<<"${kind[$idx]}"; r="$(new_project "$h" "$a")" || continue; fi
         folder="$(choose_folder "")" || continue
         IFS=$'\t' read -r h a id nm <<<"$r"
         deploy "$a" "$id" "$nm" "$folder" "$h" || continue; done_menu "$h" "$a" "$DONE_ID" "$DONE_NAME" "$folder"; continue ;;
      label|domain)
         [ ${#rows[@]} -gt 0 ] || { warn "no projects yet"; continue; }
         local k; MENU_ITEMS=(); MENU_NOTES=()
         for k in "${rows[@]}"; do IFS=$'\x1f' read -r a id nm f h <<<"$k"; MENU_ITEMS+=("$(printf '%-28s' "$nm")"); MENU_NOTES+=("  ${D}$(vc label_get "$id")${R}"); done
         MENU_ITEMS+=("← back"); MENU_NOTES+=("")
         step "$([ "${kind[$idx]}" = label ] && echo 'Label which project' || echo 'Custom domain for which site')"
         MENU_NOKEY="$(nokey_rows "${#rows[@]}")"
         r="${kind[$idx]}"; idx="$(menu_pick "Project" 0)"; MENU_NOKEY=""
         [ "$idx" -lt ${#rows[@]} ] || continue
         IFS=$'\x1f' read -r a id nm f h <<<"${rows[$idx]}"
         if [ "$r" = domain ]; then
           custom_domain "$h" "$a" "$id" "$nm"; continue
         fi
         vc label_set "$id" "$(ask "Label for ${nm} (blank removes it)" "$(vc label_get "$id")")"
         ok "saved — only a name for you, nothing changes on $([ "$h" = firebase ] && echo Firebase || echo Vercel)"
         continue ;;
      mailbox)  [ "$(mbox smtp_ready)" = yes ] && smtp_menu || setup_mailbox; continue ;;
      accounts) accounts_menu; refresh; continue ;;
      refresh)  refresh; continue ;;
      quit)     printf "\n" >&2; exit 0 ;;
    esac
    idx="${kind[$idx]#row:}"
    IFS=$'\x1f' read -r a id nm f h <<<"${rows[$idx]}"
    folder="$(choose_folder "$f")" || continue
    deploy "$a" "$id" "$nm" "$folder" "$h" || continue; done_menu "$h" "$a" "$DONE_ID" "$DONE_NAME" "$folder"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
