import json, os, re, sys, time, html, subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

CONF, TOKEN, SHIP_SITE, HUB_VERSION, SHIP_APK, SELF = sys.argv[1:7]
PORT = 0
def page_src():
    """the page as it is in the script on disk right now, so a rebuild shows on the next refresh without a restart"""
    try:
        m = re.search(r'PAGE_B64 = "([A-Za-z0-9+/=]+)"', open(SELF).read())
        return _b64.b64decode(m.group(1)).decode("utf-8") if m else PAGE
    except Exception: return PAGE
def page_hash():
    import hashlib; return hashlib.md5(page_src().encode()).hexdigest()[:12]
def sh(args, cwd=None):
    try: return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=3).stdout.strip()
    except Exception: return ""
def commits(folder):   # the last few commit titles, for the notes step
    if not folder or not os.path.isdir(os.path.join(folder, ".git")): return []
    return [l for l in sh(["git", "log", "-5", "--format=%s"], folder).splitlines() if l]
def pkg_version(folder):
    try: return json.load(open(os.path.join(folder, "package.json"))).get("version", "")
    except Exception: return ""
def pubspec_version(folder):
    try:
        for l in open(os.path.join(folder, "pubspec.yaml")):
            if l.startswith("version:"): return l.split(":", 1)[1].strip()
    except Exception: pass
    return ""
def tool_version(path):
    v = sh([path, "--version"]) if path else ""
    return v.split()[-1] if v else ""
def start(body):
    """one ship-site run with every answer given up front; returns the run id or an error"""
    if not SHIP_SITE: return {"error": "ship-site is not installed on this computer"}
    pid, folder = str(body.get("id", "")), str(body.get("folder", ""))
    target, version, notes, mail = body.get("target"), str(body.get("version", "keep")), str(body.get("notes", "-")), bool(body.get("mail"))
    if not pid or target not in ("main", "test"): return {"error": "which project, and main or test?"}
    if version not in ("keep", "next") and not re.match(r"^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$", version): return {"error": "a version like 1.2.3, or keep or next"}
    if target == "test": version = "keep"
    args = [SHIP_SITE, "--project", pid, "--prod" if target == "main" else "--preview", "--version=" + version,
            "--notes", notes or "-", "--mail" if mail else "--no-mail", "--yes"] + (["--dry-run"] if body.get("dry") else []) + ([folder] if folder else [])
    return run(args, kind="publish", id=pid, dry=bool(body.get("dry")))
def last_apk(root):
    """the newest release APK inside a Flutter project, as 'date · size', or ''"""
    try:
        import glob
        fs = glob.glob(os.path.join(root, "build", "app", "outputs", "**", "*release*.apk"), recursive=True)
        if not fs: return ""
        f = max(fs, key=os.path.getmtime); st = os.stat(f)
        return time.strftime("%d %b %H:%M", time.localtime(st.st_mtime)) + " · %d MB" % (st.st_size // 1048576)
    except Exception: return ""
def start_app(body):
    """one ship-apk run with every answer given up front"""
    if not SHIP_APK: return {"error": "ship-apk is not installed on this computer"}
    key, version, notes, mail = str(body.get("key", "")), str(body.get("version", "keep")), str(body.get("notes", "-")), bool(body.get("mail"))
    if not key: return {"error": "which app?"}
    if version not in ("keep", "next") and not re.match(r"^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$", version): return {"error": "a version like 1.2.3+4, or keep or next"}
    args = [SHIP_APK, "--app", key, "--version=" + version, "--fresh" if body.get("fresh", True) else "--last-build",
            "--notes", notes or "-", "--mail" if mail else "--no-mail", "--yes"] + (["--dry-run"] if body.get("dry") else [])
    return run(args, kind="ship", id=key, dry=bool(body.get("dry")))
def start_domain(body):
    """connect or check a site's domain through ship-site, streamed like a publish"""
    if not SHIP_SITE: return {"error": "ship-site is not installed on this computer"}
    pid, op, dom = str(body.get("id", "")), body.get("op"), str(body.get("domain", "")).strip().lower()
    if not pid or op not in ("connect", "check"): return {"error": "which project, and connect or check?"}
    if op == "connect" and not re.match(r"^([a-z0-9-]+\.)+[a-z]{2,}$", dom): return {"error": "that is not a domain; something like example.com or admin.example.com"}
    args = [SHIP_SITE, "--project", pid] + (["--domain", dom] if op == "connect" else ["--domain-check"]) + ["--yes"]
    return run(args, kind="domain", id=pid, op=op)
def people_edit(body):
    """add or remove a recipient, or set the subject, for a site (ship-site config, mail[id]) or an app (ship-apk config, projects[key])"""
    kind, pid, op = body.get("kind"), str(body.get("id", "")), body.get("op")
    role, email, name, subject = body.get("role", "to"), str(body.get("email", "")).strip(), str(body.get("name", "")).strip(), body.get("subject")
    if kind not in ("site", "app") or not pid or op not in ("add", "remove", "subject"): return {"error": "which project, and add, remove or subject?"}
    if role not in ("to", "cc", "bcc"): return {"error": "role is to, cc or bcc"}
    if op in ("add", "remove") and not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email): return {"error": "that is not an email address"}
    path = os.path.join(CONF, "ship-site" if kind == "site" else "ship-apk", "config.json")
    d = load("ship-site" if kind == "site" else "ship-apk", "config.json")
    if kind == "site":
        m = d.setdefault("mail", {}).setdefault(pid, {"to": [], "cc": [], "bcc": []})
    else:
        if pid not in d.get("projects", {}): return {"error": "no such app"}
        m = d["projects"][pid]
    if op == "subject": m["subject"] = str(subject or "")
    else:
        if op == "add":
            have = next((k for k in ("to", "cc", "bcc") if any(r.get("email", "").lower() == email.lower() for r in m.get(k, []))), None)
            if have: return {"error": "%s is already listed as %s" % (email, have.upper())}
            m.setdefault(role, []).append({"name": name or email.split("@")[0], "email": email})
        else: m[role] = [r for r in m.get(role, []) if r.get("email") != email]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
    return {"ok": True}
def cli_token(email):
    """the Firebase CLI's access token for that Google account; one harmless CLI call renews an expired one"""
    cs = os.path.join(os.path.expanduser("~"), ".config", "configstore", "firebase-tools.json")
    def read():
        try: c = json.load(open(cs))
        except Exception: return ""
        accts = [(c.get("user", {}).get("email"), c.get("tokens", {}))] + [(x.get("user", {}).get("email"), x.get("tokens", {})) for x in c.get("additionalAccounts", [])]
        tok = next((t for e, t in accts if e == email), {})
        return tok.get("access_token", "") if tok.get("expires_at", 0) / 1000 > time.time() + 60 else ""
    t = read()
    if not t: sh(["firebase", "projects:list", "--account", email]); t = read()
    return t
def fb_call(token, ep, method="GET", body=None):
    import urllib.request, urllib.error
    req = urllib.request.Request("https://firebasehosting.googleapis.com/v1beta1/" + ep, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r: raw = r.read(); return json.loads(raw) if raw else {}, None
    except urllib.error.HTTPError as e:
        try: msg = json.loads(e.read()).get("error", {}).get("message", str(e))
        except Exception: msg = str(e)
        return {}, (409 if e.code == 409 else 404 if e.code == 404 else msg)
    except Exception as e: return {}, "cannot reach Firebase: %s" % e
def dom_state(cd):
    if cd.get("hostState") != "HOST_ACTIVE": return "dns"
    return "live" if (cd.get("cert") or {}).get("state") == "CERT_ACTIVE" else "cert"
def records_of(cd, dom):
    base = ".".join(dom.split(".")[-2:])
    recs = [r for g in (cd.get("requiredDnsUpdates") or {}).get("desired", []) for r in g.get("records", [])]
    recs += [r for g in ((cd.get("cert") or {}).get("verification") or {}).get("dns", {}).get("desired", []) for r in g.get("records", [])]
    out = []
    for r in recs:
        if r.get("requiredAction") != "ADD": continue
        h = r["domainName"]; h = "@" if h == base else h[:-len(base) - 1] if h.endswith("." + base) else h
        out.append(dict(type=r["type"], host=h, value=r["rdata"], full=r["domainName"]))
    return out
def choose_folder(prompt):
    """a native folder picker; "" when cancelled"""
    try:
        if sys.platform == "darwin":
            r = subprocess.run(["osascript", "-e", 'tell application "System Events" to activate', "-e", 'POSIX path of (choose folder with prompt "%s")' % prompt], capture_output=True, text=True, timeout=600)
        else:
            r = subprocess.run(["zenity", "--file-selection", "--directory", "--title", prompt], capture_output=True, text=True, timeout=600)
        return r.stdout.strip().rstrip("/") if r.returncode == 0 else ""
    except Exception: return ""
def web_folder(f):
    return os.path.isfile(os.path.join(f, "package.json")) or any(os.path.isfile(os.path.join(f, d, "index.html")) for d in (".", "site", "public", "www", "docs", "static"))
def folder_says(f):
    """what the folder's own config names: Firebase project and site, Vercel project id"""
    rc, site, vid = "", "", ""
    try: rc = json.load(open(os.path.join(f, ".firebaserc"))).get("projects", {}).get("default", "")
    except Exception: pass
    try:
        h = json.load(open(os.path.join(f, "firebase.json"))).get("hosting", {})
        h = h[0] if isinstance(h, list) and h else h
        site = h.get("site", "") if isinstance(h, dict) else ""
    except Exception: pass
    try: vid = json.load(open(os.path.join(f, ".vercel", "project.json"))).get("projectId", "")
    except Exception: pass
    return rc, site, vid
def link_folder(body):
    """pick a folder in the Finder and link it to a project: the given one, or the one the folder's config names"""
    pid, op = str(body.get("id", "")), body.get("op", "pick")
    if body.get("kind") == "app":   # an app's folder: the Flutter project ship-apk builds; no key = a new app from its folder, like the terminal's add_app
        d = load("ship-apk", "config.json"); path = os.path.join(CONF, "ship-apk", "config.json")
        if not pid:
            f = choose_folder("The Flutter project to add (pubspec.yaml)")
            if not f: return {"cancelled": True}
            if not os.path.isfile(os.path.join(f, "pubspec.yaml")): return {"error": "no pubspec.yaml in " + f.replace(os.path.expanduser("~"), "~")}
            key = os.path.basename(f)
            if key in d.get("projects", {}): return {"error": "%s is already in the list" % key}
            name = next((l.split(":", 1)[1].strip() for l in open(os.path.join(f, "pubspec.yaml")) if l.startswith("name:")), key)
            d.setdefault("projects", {})[key] = {"path": f, "app": name.replace("_", " ").title(), "app_id": "", "user_id": "", "key": "", "to": [], "cc": [], "bcc": []}
            json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
            return {"ok": True, "id": key, "folder": f, "new": True}
        if pid not in d.get("projects", {}): return {"error": "no such app"}
        if op == "unlink":
            d["projects"][pid]["path"] = ""; json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600); return {"ok": True}
        f = choose_folder("The Flutter project of " + (d["projects"][pid].get("app") or pid) + " (pubspec.yaml)")
        if not f: return {"cancelled": True}
        if not os.path.isfile(os.path.join(f, "pubspec.yaml")): return {"error": "no pubspec.yaml in " + f.replace(os.path.expanduser("~"), "~")}
        d["projects"][pid]["path"] = f
        json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
        return {"ok": True, "id": pid, "folder": f}
    d = load("ship-site", "config.json"); path = os.path.join(CONF, "ship-site", "config.json")
    row = next((c for c in d.get("cache", []) if c["id"] == pid), None) if pid else None
    if pid and not row: return {"error": "no such project"}
    if op == "unlink":
        for f in [f for f, pr in d.get("projects", {}).items() if pr.get("id") == pid]: d["projects"].pop(f, None)
        json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600); return {"ok": True}
    f = choose_folder("The folder of " + (row["name"] if row else "the web project") + " (package.json or index.html)")
    if not f: return {"cancelled": True}
    if not web_folder(f): return {"error": "no package.json and no index.html in " + f.replace(os.path.expanduser("~"), "~")}
    if not row:
        rc, site, vid = folder_says(f)
        hits = [c for c in d.get("cache", []) if (vid and c["id"] == vid) or (rc and c["id"].startswith(rc + "/") and (not site or c["id"].endswith("/" + site)))]
        if len(hits) != 1:
            what = " · ".join(x for x in ("Firebase " + rc if rc else "", "site " + site if site else "", "Vercel " + vid if vid else "") if x)
            return {"error": ("this folder's config names %s, which is not in your list" % what) if what else "no .firebaserc or .vercel/project.json in that folder; publish it once from the terminal, which creates the project"}
        row = hits[0]
    d.setdefault("projects", {})[f] = dict(d["projects"].get(f, {}), account=row["account"], id=row["id"], name=row["name"], host=row.get("host", "vercel"))
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
    return {"ok": True, "id": row["id"], "folder": f}
def app_edit(body):
    """an app's name, appho.st app id and credentials, in ship-apk's own config; a blank key keeps the saved one"""
    key = str(body.get("key", ""))
    d = load("ship-apk", "config.json"); path = os.path.join(CONF, "ship-apk", "config.json")
    if key not in d.get("projects", {}): return {"error": "no such app"}
    p = d["projects"][key]
    for f in ("app", "app_id", "user_id"):
        if f in body: p[f] = str(body[f]).strip()
    if "api_key" in body: p["key"] = str(body["api_key"]).strip()
    if "account" in body and p.get("user_id"): d.setdefault("accounts", {})[p["user_id"]] = str(body["account"]).strip()
    if not p.get("app_id"): return {"error": "the appho.st app id cannot be blank"}
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
    return {"ok": True}
def label_edit(body):
    pid, label = str(body.get("id", "")), str(body.get("label", "")).strip()[:40]
    d = load("ship-site", "config.json"); path = os.path.join(CONF, "ship-site", "config.json")
    if not any(c["id"] == pid for c in d.get("cache", [])): return {"error": "no such project"}
    labels = d.setdefault("labels", {})
    if label: labels[pid] = label
    else: labels.pop(pid, None)
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
    return {"ok": True, "label": label}
def domain_edit(body):
    """save a domain for a project; on Firebase also connect it and return the records to add, or its state"""
    pid, dom, op = str(body.get("id", "")), str(body.get("domain", "")).strip().lower(), body.get("op", "save")
    dom = re.sub(r"^https?://", "", dom).split("/")[0]; dom = re.sub(r"^www\.", "", dom)
    d = load("ship-site", "config.json"); path = os.path.join(CONF, "ship-site", "config.json")
    row = next((c for c in d.get("cache", []) if c["id"] == pid), None)
    if not row: return {"error": "no such project"}
    if op in ("remove", "disconnect"):
        dom = d.get("domains", {}).get(pid, "")
        if op == "disconnect" and row.get("host") == "firebase" and dom:
            tok = cli_token(row["account"])
            if not tok: return {"error": "no Firebase login for %s on this computer" % row["account"]}
            proj, site = pid.split("/", 1)
            _, err = fb_call(tok, "projects/%s/sites/%s/customDomains/%s" % (proj, site, dom), "DELETE")
            if err and err != 404: return {"error": str(err)}
            if row.get("url") == dom: row["url"] = site + ".web.app"
        d.get("domains", {}).pop(pid, None); d.get("domain_state", {}).pop(pid, None)
        json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600); return {"ok": True}
    if op == "check": dom = d.get("domains", {}).get(pid, "")
    if not re.match(r"^([a-z0-9-]+\.)+[a-z]{2,}$", dom or ""): return {"error": "that is not a domain; something like example.com or admin.example.com"}
    d.setdefault("domains", {})[pid] = dom
    res = {"ok": True, "domain": dom, "host": row.get("host", "vercel")}
    if row.get("host") == "firebase":
        proj, site = pid.split("/", 1)
        tok = cli_token(row["account"])
        if not tok: res["error"] = "no Firebase login for %s on this computer" % row["account"]
        else:
            ep = "projects/%s/sites/%s/customDomains" % (proj, site)
            if op == "save": fb_call(tok, ep + "?customDomainId=" + dom, "POST", {})
            cd, err = None, None
            for _ in range(4 if op == "save" else 1):
                cd, err = fb_call(tok, ep + "/" + dom)
                if err or cd.get("requiredDnsUpdates") or dom_state(cd) == "live": break
                time.sleep(1)
            if err == 404: res["state"] = "new"; res["note"] = "not connected on Firebase yet"
            elif err: res["error"] = str(err)
            else:
                st = dom_state(cd); res["state"] = st; res["records"] = records_of(cd, dom); res["cert"] = (cd.get("cert") or {}).get("type", "")
                d.setdefault("domain_state", {})[pid] = st
                if st == "live": row["url"] = dom
    else: res["state"] = "reminder"; res["note"] = "Vercel domains are added on vercel.com, which shows its records; the name is kept here as a reminder"
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)
    return res
RUNDIR = os.path.join(CONF, "developer-tools", "runs")
def run(args, **meta):
    """start a tool detached from this server, its output in RUNDIR/<id>.log and its exit code in <id>.code when it ends;
    the run is listed in /api/data until then, so a reloaded page (or a restarted server) picks it up"""
    os.makedirs(RUNDIR, exist_ok=True)
    for f in os.listdir(RUNDIR):   # a week of runs is plenty
        fp = os.path.join(RUNDIR, f)
        if time.time() - os.path.getmtime(fp) > 7 * 86400: os.remove(fp)
    rid = time.strftime("%Y%m%d-%H%M%S") + "-%04x" % (int(time.time() * 1000) % 65536)
    base = os.path.join(RUNDIR, rid)
    log = open(base + ".log", "w")
    proc = subprocess.Popen(["bash", "-c", '"$@"; echo $? > "$CODE"', "run"] + args, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                            env=dict(os.environ, TERM="dumb", CODE=base + ".code"), start_new_session=True)
    meta = dict(meta, run=rid, started=time.time(), pid=proc.pid, command=" ".join(a if a else "''" for a in args))
    json.dump(meta, open(base + ".json", "w"))
    return {"run": rid, "command": meta["command"]}
def alive(pid):
    try: os.kill(pid, 0); return True
    except Exception: return False
def run_meta(rid):
    try: return json.load(open(os.path.join(RUNDIR, rid + ".json")))
    except Exception: return None
def run_state(meta):
    """(done, code): the code file says it ended; a dead process with no code file crashed"""
    try: return True, int(open(os.path.join(RUNDIR, meta["run"] + ".code")).read().strip() or 1)
    except Exception: return (False, None) if alive(meta.get("pid", 0)) else (True, 1)
def active_runs():
    """every run still going, newest first"""
    rows = []
    try: names = sorted(f[:-5] for f in os.listdir(RUNDIR) if f.endswith(".json"))
    except Exception: names = []
    for rid in names[-20:]:
        m = run_meta(rid)
        if m and not run_state(m)[0]: rows.append(m)
    return sorted(rows, key=lambda m: -m["started"])
def status(rid):
    m = run_meta(rid) if re.match(r"^[0-9a-f-]+$", rid or "") else None
    if not m: return {"error": "no such run"}
    try: out = open(os.path.join(RUNDIR, rid + ".log"), errors="replace").read()
    except Exception: out = ""
    done, code = run_state(m)
    return {"out": out, "done": done, "code": code}
def load(*p):
    try: return json.load(open(os.path.join(CONF, *p)))
    except Exception: return {}
def ago(t):
    if not t: return ""
    d = (int(time.time()) - int(t)) // 86400
    return "today" if d < 1 else "%dd ago" % d if d < 7 else "%dw ago" % (d // 7) if d < 30 else "%dmo ago" % (d // 30) if d < 365 else "%dy ago" % (d // 365)
def when(t): return time.strftime("%d %b %Y %H:%M", time.localtime(t))
def hist(rows): return [dict(r, when=when(r["t"])) for r in reversed(rows or [])]

def data():
    s, a, m = load("ship-site", "config.json"), load("ship-apk", "config.json"), load("developer-tools", "mail.json")
    folders = {}
    for f, pr in s.get("projects", {}).items(): folders.setdefault(pr.get("id"), f)
    labels, stats, doms, dstate, mail, history = (s.get(k, {}) for k in ("labels", "stats", "domains", "domain_state", "mail", "history"))
    sites = []
    for c in s.get("cache", []):
        h = c.get("host", "vercel")
        if (h == "vercel" and c["account"] not in s.get("accounts", {})) or (h == "firebase" and c["account"] not in s.get("fb_accounts", [])): continue
        st, mm = stats.get(c["id"], {}), mail.get(c["id"], {})
        f = folders.get(c["id"], "")
        sites.append(dict(account=c["account"], host=h, id=c["id"], name=c["name"], url=c["url"], project=c.get("project", ""),
                          label=labels.get(c["id"], ""), folder=f, count=st.get("count", 0), last=ago(st.get("last")), version=pkg_version(f), commits=commits(f),
                          static=bool(f) and not (json.load(open(os.path.join(f, "package.json"))).get("scripts", {}).get("build") if os.path.exists(os.path.join(f, "package.json")) else False),
                          domain=doms.get(c["id"], ""), domain_state=dstate.get(c["id"], ""), history=hist(history.get(c["id"])),
                          mail={k: mm.get(k, []) for k in ("to", "cc", "bcc")} | {"subject": mm.get("subject", "")}))
    sites.sort(key=lambda x: (x["host"] != "vercel", x["account"].lower(), x["id"].split("/")[0], x["name"]))
    apps = []
    for k, p in sorted(a.get("projects", {}).items()):
        apps.append(dict(key=k, app=p.get("app") or k, path=p.get("path", ""), app_id=p.get("app_id", ""), count=p.get("count", 0),
                         last=ago(p.get("last")), history=hist(p.get("history")), version=pubspec_version(p.get("path", "")), commits=commits(p.get("path", "")),
                         creds=bool(p.get("user_id") and p.get("key")), user_id=p.get("user_id", ""), api_key=p.get("key", ""), account=a.get("accounts", {}).get(p.get("user_id", ""), ""), last_apk=last_apk(p.get("path", "")),
                         mail={f: p.get(f, []) for f in ("to", "cc", "bcc")} | {"subject": p.get("subject", "")}))
    smtp = m.get("smtp", {})
    box = dict(user=smtp.get("user", ""), host=smtp.get("host", ""), port=smtp.get("port", ""), from_name=smtp.get("from_name", ""),
               ready=bool(smtp.get("host") and smtp.get("user") and smtp.get("password")))
    try: channel = open(os.path.join(CONF, "developer-tools", "channel")).read().strip() or "stable"
    except Exception: channel = "stable"
    accounts = [dict(name=n, scope=a.get("scope", ""), team=a.get("team_id", ""), host="Vercel") for n, a in sorted(s.get("accounts", {}).items())]
    accounts += [dict(name=e, scope="", team="", host="Firebase") for e in s.get("fb_accounts", [])]
    tpl = dict(site=m.get("template_site", {}), apk=m.get("template_apk", {}))
    return dict(sites=sites, apps=apps, mailbox=box, templates=tpl, accounts=accounts, vercel_accounts=sorted(s.get("accounts", {})), firebase_accounts=s.get("fb_accounts", []),
                can_publish=bool(SHIP_SITE), can_ship=bool(SHIP_APK), active=active_runs(), hub_version=HUB_VERSION, port=PORT, channel=channel, page=page_hash(),
                tools=[dict(name="ship-site", what="Build a web app and publish it to Vercel or Firebase", version=tool_version(SHIP_SITE)),
                       dict(name="ship-apk", what="Build a Flutter APK, upload it to appho.st, mail the link", version=tool_version(SHIP_APK)),
                       dict(name="developer-tools", what="The hub, and this page", version=HUB_VERSION)])

import base64 as _b64
PAGE_B64 = "@@PAGE_B64@@"
PAGE = _b64.b64decode(PAGE_B64).decode("utf-8")

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype):
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urlparse(self.path)
        if parse_qs(u.query).get("t", [""])[0] != TOKEN: return self.send(403, b"not allowed", "text/plain")
        if u.path == "/": return self.send(200, page_src().encode(), "text/html; charset=utf-8")
        if u.path == "/api/data": return self.send(200, json.dumps(data()).encode(), "application/json")
        if u.path == "/api/run": return self.send(200, json.dumps(status(parse_qs(u.query).get("id", [""])[0])).encode(), "application/json")
        self.send(404, b"not found", "text/plain")
    def do_POST(self):
        u = urlparse(self.path)
        if parse_qs(u.query).get("t", [""])[0] != TOKEN: return self.send(403, b"not allowed", "text/plain")
        try: body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0")) or b"{}"))
        except Exception: body = {}
        if u.path == "/api/deploy": return self.send(200, json.dumps(start(body)).encode(), "application/json")
        if u.path == "/api/people": return self.send(200, json.dumps(people_edit(body)).encode(), "application/json")
        if u.path == "/api/domain": return self.send(200, json.dumps(domain_edit(body)).encode(), "application/json")
        if u.path == "/api/domain_run": return self.send(200, json.dumps(start_domain(body)).encode(), "application/json")
        if u.path == "/api/ship": return self.send(200, json.dumps(start_app(body)).encode(), "application/json")
        if u.path == "/api/label": return self.send(200, json.dumps(label_edit(body)).encode(), "application/json")
        if u.path == "/api/link": return self.send(200, json.dumps(link_folder(body)).encode(), "application/json")
        if u.path == "/api/app": return self.send(200, json.dumps(app_edit(body)).encode(), "application/json")
        self.send(404, b"not found", "text/plain")

UI = os.path.join(CONF, "developer-tools", "ui.json")
try: want = int(json.load(open(UI)).get("port", 0))
except Exception: want = 0
try: srv = ThreadingHTTPServer(("127.0.0.1", want), H)
except OSError: srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
PORT = srv.server_address[1]
try:
    os.makedirs(os.path.dirname(UI), exist_ok=True); json.dump({"port": PORT, "token": TOKEN}, open(UI, "w")); os.chmod(UI, 0o600)
except Exception: pass
print("URL\thttp://127.0.0.1:%d/?t=%s" % (PORT, TOKEN), flush=True)
srv.serve_forever()