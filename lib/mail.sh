# ── mail ──────────────────────────────────────────────────────────────────
# One mailbox for every tool, in ~/.config/developer-tools/mail.json: the account mail goes out from, and a template
# per kind of tool (apk, site). Who gets it is per app or project and lives in the tool's own store, reached through
# mail_store, which each tool defines: people, person_add, person_del, subject_get, subject_set, sha_get, sha_set, mail_json.
# One ordinary email: To is in the headers, BCC only goes to the envelope.
MAILBOX="$HOME/.config/developer-tools/mail.json"
MAIL_KIND="${MAIL_KIND:-apk}"   # which template a tool sends with
mbox(){ # smtp_get key | smtp_set key value | smtp_ready | tpl_get kind key | tpl_set kind key value
py - "$MAILBOX" "$@" <<'PY'
import json, os, sys
path, op = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
try: d = json.load(open(path))
except Exception:
    d = {}
    # a mailbox set up by ship-apk 2.0 moves over as it is, nothing to type again
    old = os.path.join(os.path.dirname(os.path.dirname(path)), "ship-apk", "config.json")
    try:
        o = json.load(open(old))
        if (o.get("smtp") or {}).get("user"): d = {"smtp": o["smtp"], "template_apk": o.get("template") or {}}
    except Exception: pass
d.setdefault("smtp", {"host": "", "port": 465, "user": "", "password": "", "from_name": ""})
d.setdefault("template_apk", {
    "subject": "{app} {version} — new test build",
    "body": ("Hi {name},\n\n"
             "A new build of {app} is ready to install.\n\n"
             "    {link}\n\n"
             "Version {version}{notes}\n\n"
             "Open the link on the device you want to install it on.\n\n"
             "— {sender}"),
})
d.setdefault("template_site", {
    "subject": "{app} {version} is live",
    "body": ("Hi {name},\n\n"
             "{app} {version} is published.\n\n"
             "    {link}\n\n"
             "Version {version}{notes}\n\n"
             "— {sender}"),
})
def save():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(d, open(path, "w"), indent=2); os.chmod(path, 0o600)   # it holds a mail password
if not os.path.exists(path): save()
if   op == "smtp_get":   print(d["smtp"].get(a[0], ""))
elif op == "smtp_set":   d["smtp"][a[0]] = a[1]; save()
elif op == "smtp_ready": s = d["smtp"]; print("yes" if s.get("host") and s.get("user") and s.get("password") else "no")
elif op == "tpl_get":    print(d.get("template_" + a[0], {}).get(a[1], ""))
elif op == "tpl_set":    d.setdefault("template_" + a[0], {})[a[1]] = a[2]; save()
elif op == "dump":       print(json.dumps({"smtp": d["smtp"], "template": d.get("template_" + a[0], {})}))
else: sys.exit(2)
PY
}

send_mail(){ # $1 project key  $2 app label  $3 version  $4 link  $5 notes  $6 dry("yes" prints instead of sending)
  # MAIL_REC, when set, is the recipients JSON to use instead of the project's (the test mail)
  local rec; rec="${MAIL_REC:-$(mail_store mail_json "$1")}"
py - "$(mbox dump "$MAIL_KIND")" "$rec" "${@:2}" <<'PY'
import json, smtplib, ssl, sys
from email.message import EmailMessage
from email.utils import formataddr

box, rec, app, version, link, notes = sys.argv[1:7]
dry = (len(sys.argv) > 7 and sys.argv[7] == "yes")
d = json.loads(box)
s = d["smtp"]
tpl = d["template"]
p = json.loads(rec or "{}")
def people(f):
    return [r for r in p.get(f, []) if r.get("email", "").strip()]
to = people("to")
seen = {t["email"].strip() for t in to}
cc = [r for r in people("cc") if r["email"].strip() not in seen]
seen |= {r["email"].strip() for r in cc}
bcc = [r["email"].strip() for r in people("bcc") if r["email"].strip() not in seen]

if not to:
    print("NO_RECIPIENTS"); sys.exit(0)

names = [r.get("name") or r["email"].split("@")[0] for r in to]
sender_name = s.get("from_name") or s["user"]
fields = dict(name=" and ".join([", ".join(names[:-1]), names[-1]]) if len(names) > 1 else names[0],
              app=app, version=version, link=link, sender=sender_name,
              notes=("\n\nWhat changed:\n" + notes) if notes.strip() else "")
m = EmailMessage()
m["Subject"] = (p.get("subject") or tpl["subject"]).format(**fields)
m["From"] = formataddr((sender_name, s.get("user", "")))
m["To"] = ", ".join(formataddr((r.get("name", ""), r["email"].strip())) for r in to)
if cc: m["Cc"] = ", ".join(formataddr((r.get("name", ""), r["email"].strip())) for r in cc)
m.set_content(tpl["body"].format(**fields))

if dry:
    print("-" * 60)
    print("From:    " + m["From"])
    print("To:      " + m["To"])
    if cc:  print("CC:      " + m["Cc"])
    if bcc: print("BCC:     " + ", ".join(bcc) + "   (hidden — nobody sees these)")
    print("Subject: " + m["Subject"])
    print()
    print(m.get_content())
    print("-" * 60)
    print("DRY\t%d" % (len(to) + len(cc) + len(bcc)))
    sys.exit(0)

port = int(s.get("port") or 465)
try:
    if port == 465:
        server = smtplib.SMTP_SSL(s["host"], port, context=ssl.create_default_context(), timeout=30)
    else:
        server = smtplib.SMTP(s["host"], port, timeout=30)
        server.starttls(context=ssl.create_default_context())
    server.login(s["user"], s["password"])
    refused = server.send_message(m, to_addrs=[r["email"].strip() for r in to + cc] + bcc)
    server.quit()
except Exception as e:
    print("FAIL\t" + str(e).replace("\n", " ")); sys.exit(1)
print("OK\t%d\t%s" % (len(to) + len(cc) + len(bcc) - len(refused), "; ".join(refused)))
PY
}

recipients(){ # $1 key -> "2 people + 1 CC + 1 BCC"
  local t c b out
  t="$(mail_store people "$1" to | grep -c .)"; c="$(mail_store people "$1" cc | grep -c .)"; b="$(mail_store people "$1" bcc | grep -c .)"
  out="$t $([ "$t" = 1 ] && echo person || echo people)"
  [ "$c" -gt 0 ] && out="$out + $c CC"
  [ "$b" -gt 0 ] && out="$out + $b BCC"
  printf '%s' "$out"
}

smtp_login_check(){ # logs in to the mailbox and out again, sends nothing -> "OK" or "FAIL<TAB>reason"
py - "$MAILBOX" <<'PY2'
import json, smtplib, ssl, sys
s = json.load(open(sys.argv[1]))["smtp"]
port = int(s.get("port") or 465)
try:
    if port == 465: c = smtplib.SMTP_SSL(s["host"], port, context=ssl.create_default_context(), timeout=20)
    else:
        c = smtplib.SMTP(s["host"], port, timeout=20); c.starttls(context=ssl.create_default_context())
    c.login(s["user"], s["password"]); c.quit(); print("OK")
except Exception as e:
    print("FAIL\t" + str(e).replace("\n", " "))
PY2
}

log_send(){ # project · version · link · how many were mailed
  mkdir -p "$LOGS"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$2" "$4" "$3" >> "$LOGS/$1.log"
}

smtp_test(){
  local to result
  [ "$(mbox smtp_ready)" = yes ] || { warn "fill in address, password and host first"; return; }
  to="$(ask "Send the test to" "$(mbox smtp_get user)")"
  [ -n "$to" ] || return
  step "Sending test"
  result="$(MAIL_REC="{\"to\":[{\"name\":\"you\",\"email\":\"$to\"}]}" send_mail - "developer-tools" "0.0.0" "https://github.com/azharbinanwar/developer-tools" "- this is a test")"
  case "$result" in
    OK*) ok "delivered — check $to (and its spam folder)" ;;
    FAIL*) warn "$(printf '%s' "$result" | cut -f2)" ;;
    *) warn "no recipients" ;;
  esac
}

people_menu(){ # $1 project key  $2 to | bcc
  local key="$1" list="${2:-to}" idx n e names=() mails=() i label
  case "$list" in to) label=To ;; cc) label=CC ;; *) label=BCC ;; esac
  while :; do
    names=(); mails=(); MENU_ITEMS=(); MENU_NOTES=()
    while IFS=$'\t' read -r n e; do
      [ -n "$e" ] || continue
      names+=("$n"); mails+=("$e")
      MENU_ITEMS+=("$(printf '%-22s' "${n:-—}")"); MENU_NOTES+=("  ${D}${e}${R}")
    done < <(mail_store people "$key" "$list")
    MENU_ITEMS+=("+ add to $label"); MENU_NOTES+=("  ${D}name and address${R}")
    MENU_ITEMS+=("← back");         MENU_NOTES+=("")
    step "$label for “${key}”"
    case "$list" in to) sub "who the email is addressed to" ;; cc) sub "copied openly — everyone on the email sees these" ;; *) sub "hidden copy — nobody on the email can see these" ;; esac
    MENU_NOKEY="$(nokey_rows "${#mails[@]}")"
    idx="$(menu_pick "Who" $(( ${#MENU_ITEMS[@]} - 1 )) 0)"; MENU_NOKEY=""
    [ "$idx" -eq $(( ${#MENU_ITEMS[@]} - 1 )) ] && return
    if [ "$idx" -eq $(( ${#MENU_ITEMS[@]} - 2 )) ]; then
      n="$(ask "Their name" "")"; e="$(ask "Their address" "")"
      case "$e" in ?*@?*.?*) mail_store person_add "$key" "$n" "$e" "$list"; ok "added ${e}" ;;
                   "") ;; *) warn "“${e}” is not an email address" ;; esac
      continue
    fi
    MENU_ITEMS=("rename" "change address" "remove" "← back"); MENU_NOTES=("" "" "" "")
    step "${names[$idx]:-${mails[$idx]}}"
    i="$(menu_pick "What to do" 3 0)"
    case "$i" in
      0) mail_store person_add "$key" "$(ask "Name" "${names[$idx]}")" "${mails[$idx]}" "$list"; ok "renamed" ;;
      1) e="$(ask "Address" "${mails[$idx]}")"
         case "$e" in ?*@?*.?*) ;; *) warn "“${e}” is not an email address"; continue ;; esac
         { mail_store person_del "$key" "${mails[$idx]}" "$list"; mail_store person_add "$key" "${names[$idx]}" "$e" "$list"; ok "updated"; } ;;
      2) [ "$(ask_yn "Remove ${mails[$idx]}" false)" = true ] && { mail_store person_del "$key" "${mails[$idx]}" "$list"; ok "removed"; } ;;
    esac
  done
}

smtp_guess(){ # $1 address -> "host port" for the common providers, smtp.<domain> 465 otherwise
  case "$(printf '%s' "${1##*@}" | tr 'A-Z' 'a-z')" in
    gmail.com|googlemail.com)        echo "smtp.gmail.com 465" ;;
    outlook.com|hotmail.com|live.com) echo "smtp-mail.outlook.com 587" ;;
    icloud.com|me.com|mac.com)       echo "smtp.mail.me.com 587" ;;
    yahoo.com)                       echo "smtp.mail.yahoo.com 465" ;;
    zoho.com)                        echo "smtp.zoho.com 465" ;;
    *)                               echo "smtp.${1##*@} 465" ;;
  esac
}

setup_mailbox(){ # guided, one question at a time; the mailbox menu is for later edits
  local user hp host port
  step "Set up mailbox"
  sub "the account the link is sent from — once, shared by ship-apk and ship-site"
  user="$(ask "Email address" "$(mbox smtp_get user)")"
  case "$user" in ?*@?*.?*) ;; *) warn "“${user}” is not an email address"; return ;; esac
  mbox smtp_set user "$user"
  case "$user" in *@gmail.com|*@googlemail.com) sub "Gmail needs an app password: myaccount.google.com/apppasswords" ;; esac
  mbox smtp_set password "$(ask_secret "Password" "$(mbox smtp_get password)")"
  hp="$(smtp_guess "$user")"
  host="$(ask "SMTP host" "$(mbox smtp_get host | grep . || echo "${hp% *}")")"; mbox smtp_set host "$host"
  port="$(ask "Port (465 SSL, 587 STARTTLS)" "${hp#* }")"; mbox smtp_set port "$port"
  mbox smtp_set from_name "$(ask "Name people see it from" "$(mbox smtp_get from_name | grep . || echo "${user%@*}")")"
  ok "mailbox saved"
  [ "$(ask_yn "Send a test to yourself now" true)" = true ] && smtp_test
}

setup_app_mail(){ # $1 key  $2 app name -> guided To, CC, BCC, subject
  local key="$1" f label hint n e
  step "Email for “$2”"
  for f in to cc bcc; do
    case "$f" in
      to)  label=To;  hint="who the link is addressed to" ;;
      cc)  label=CC;  hint="copied openly, everyone sees them — blank to skip" ;;
      bcc) label=BCC; hint="hidden copy, nobody sees them — blank to skip" ;;
    esac
    sub "${label}: ${hint}"
    while IFS=$'\t' read -r n e; do [ -n "$e" ] && row "$label" "${n:+$n  }${D}${e}${R}"; done < <(mail_store people "$key" "$f")
    while :; do
      e="$(ask "$label address (blank when done)" "")"; [ -n "$e" ] || break
      case "$e" in ?*@?*.?*) ;; *) warn "“${e}” is not an email address"; continue ;; esac
      n="$(ask "Their name" "${e%@*}")"
      mail_store person_add "$key" "$n" "$e" "$f"; ok "added ${e} to ${label}"
    done
  done
  mail_store subject_set "$key" "$(ask "Subject" "$(mail_store subject_get "$key" | grep . || mbox tpl_get "$MAIL_KIND" subject)")"
  ok "email for “$2” saved"
}

smtp_menu(){
  local idx
  while :; do
    MENU_ITEMS=("$(printf '%-16s' 'address')"  "$(printf '%-16s' 'password')"
                "$(printf '%-16s' 'smtp host')" "$(printf '%-16s' 'port')"
                "$(printf '%-16s' 'from name')" "send a test to myself" "edit the mail template" "← back")
    MENU_NOTES=("  ${D}$(mbox smtp_get user)${R}"
                "  ${D}$([ -n "$(mbox smtp_get password)" ] && echo 'set' || echo 'not set yet')${R}"
                "  ${D}$(mbox smtp_get host)${R}"
                "  ${D}$(mbox smtp_get port)  · 465 for SSL, 587 for STARTTLS${R}"
                "  ${D}$(mbox smtp_get from_name)  · the sender name people see${R}"
                "  ${D}proves the settings work before a real send${R}"
                "  ${D}opens mail.json · {name} {app} {version} {link} {notes} {sender}${R}" "")
    step "Mailbox"
    idx="$(menu_pick "What to change" 7 0)"
    case "$idx" in
      0) mbox smtp_set user      "$(ask "Address" "$(mbox smtp_get user)")" ;;
      1) mbox smtp_set password  "$(ask_secret "Password" "$(mbox smtp_get password)")" ; ok "saved" ;;
      2) mbox smtp_set host      "$(ask "SMTP host" "$(mbox smtp_get host)")" ;;
      3) mbox smtp_set port      "$(ask "Port" "$(mbox smtp_get port)")" ;;
      4) mbox smtp_set from_name "$(ask "From name" "$(mbox smtp_get from_name)")" ;;
      5) smtp_test ;;
      6) edit_file "$MAILBOX" || warn "open $MAILBOX yourself" ;;
      7) return ;;
    esac
  done
}

git_notes(){ # $1 root  $2 key -> commit titles since the last send, or the last five
  local since
  [ -d "$1/.git" ] || return 0
  since="$(mail_store sha_get "$2")"
  if [ -n "$since" ] && ( cd "$1" && git cat-file -e "$since^{commit}" 2>/dev/null ); then
    ( cd "$1" && git log --format='- %s' "$since..HEAD" 2>/dev/null | head -8 )
  else
    ( cd "$1" && git log --format='- %s' -5 2>/dev/null )
  fi
}
head_sha(){ [ -d "$1/.git" ] && ( cd "$1" && git rev-parse HEAD 2>/dev/null ); }

pick_notes(){ # $1 root  $2 key -> echoes the "What changed" text for the mail, chosen before anything runs
  local git f
  git="$(git_notes "$1" "$2")"
  step "What changed  ${D}goes into the mail as {notes}${R}"
  if [ -n "$git" ]; then
    printf '%s\n' "$git" | while IFS= read -r f; do sub "$f"; done
    MENU_ITEMS=("use these" "write my own" "no notes")
    MENU_NOTES=("  ${D}commit titles since the last send${R}" "  ${D}opens your editor with these to start from · Markdown is fine${R}" "")
  else
    sub "no commits to list — not a git repo, or nothing new since the last send"
    MENU_ITEMS=("no notes" "write my own"); MENU_NOTES=("" "  ${D}opens your editor · Markdown is fine${R}")
  fi
  case "${MENU_ITEMS[$(menu_pick "Notes" -1 0)]}" in
    "use these") printf '%s' "$git" ;;
    "no notes")  ;;
    *) f="$(tmpf notes).md"
       { printf '%s\n' "$git"; printf '\n# Write what changed. Lines starting with # are dropped. Save and close to continue.\n'; } > "$f"
       edit_file "$f" || warn "open $f yourself, save it, then press Enter"
       git="$(grep -v '^#' "$f" | awk '
         /^[[:space:]]*[•●▪–]+[[:space:]]*$/ { pre = "- "; next }
         /^[[:space:]]*[◦○]+[[:space:]]*$/   { pre = "  - "; next }
         { sub(/^[[:space:]]*[•●▪]+[[:space:]]+/, "- "); sub(/^[[:space:]]*[◦○]+[[:space:]]+/, "  - "); print pre $0; pre = "" }' \
         | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
       rm -f "$f"
       if [ -n "$git" ]; then ok "notes for the mail:"; printf '%s\n' "$git" | while IFS= read -r f; do sub "$f"; done
       else warn "the file was empty — sending without notes"; fi
       printf '%s' "$git" ;;
  esac
}

mail_step(){ # $1 key  $2 name -> MAIL=yes|no: send, set up what is missing (mailbox, then this project's email), or skip
  local key="$1" name="$2" n idx
  MAIL="$(mail_store mail_default_get "$key")"
  case "$MAIL" in false|none|no) MAIL=no ;; *) MAIL=yes ;; esac
  step "Email"
  while :; do
    n="$(mail_store people "$key" to | grep -c .)"
    if [ "$(mbox smtp_ready)" != yes ]; then
      MENU_ITEMS=("set up mailbox" "skip mail this time")
      MENU_NOTES=("  ${D}the address the link is sent from — once, for every app and site${R}" "  ${D}still ${MAIL_VERB:-publishes} and copies the link${R}")
      [ "$(menu_pick "No mailbox yet" 1 1)" = 0 ] && { setup_mailbox; continue; }
    elif [ "$n" -eq 0 ]; then
      MENU_ITEMS=("set up this ${MAIL_THING:-project}'s email" "skip mail this time")
      MENU_NOTES=("  ${D}To, CC, BCC and subject for “${name}”${R}" "  ${D}still ${MAIL_VERB:-publishes} and copies the link${R}")
      [ "$(menu_pick "Mailbox ready · nobody to send to yet" 1 1)" = 0 ] && { setup_app_mail "$key" "$name"; continue; }
    else
      MENU_ITEMS=("send the link to $(recipients "$key")" "skip mail this time" "change To, CC, BCC or subject")
      MENU_NOTES=("  ${D}To $(mail_store people "$key" to | cut -f2 | tr '\n' ' ')$(mail_store people "$key" cc | cut -f2 | tr '\n' ' ' | sed 's/^./· CC &/')$(mail_store people "$key" bcc | cut -f2 | tr '\n' ' ' | sed 's/^./· BCC &/')${R}" "" "")
      [ "$MAIL" = yes ] && idx=0 || idx=1
      case "$(menu_pick "Mail" 1 "$idx")" in
        0) # a single stray key must not mail everyone
           if picked_by_key && [ "$DRY" != yes ] && ! confirm_y "Mail the link to $(recipients "$key") afterwards?"; then continue; fi
           MAIL=yes; break ;;
        2) setup_app_mail "$key" "$name"; continue ;;
      esac
    fi
    MAIL=no; break
  done
  [ "$DRY" = yes ] || mail_store mail_default_set "$key" "$MAIL"
}
MAIL=no

mail_after(){ # $1 key $2 name $3 version $4 link $5 notes $6 root -> sends when MAIL=yes; MAILED = how many, or ""
  local result count fails
  MAILED=""
  if [ "$MAIL" = no ]; then log_send "$1" "$3" "$4" "0 (link only)"; return 0; fi
  step "Sending"
  result="$(send_mail "$1" "$2" "$3" "$4" "$5")"
  case "$result" in
    OK*) count="$(printf '%s' "$result" | cut -f2)"; fails="$(printf '%s' "$result" | cut -f3)"
         ok "sent to $count address$([ "$count" = 1 ] || echo es)"
         [ -n "$fails" ] && warn "failed: $fails"
         mail_store sha_set "$1" "$(head_sha "$6")"
         log_send "$1" "$3" "$4" "$count"; MAILED="$count" ;;
    NO_RECIPIENTS) warn "no recipients saved"; MAIL=no ;;
    FAIL*) warn "could not send: $(printf '%s' "$result" | cut -f2)"
           sub "check host, port, address and password under mailbox"; MAIL=no ;;
  esac
}
MAILED=""

dry_mail(){ # $1 key $2 name $3 version $4 link $5 notes -> the mailbox login check and the mail as it would go out
  local r
  if [ "$MAIL" = yes ]; then
    r="$(smtp_login_check)"
    case "$r" in OK) ok "mailbox login works  ${D}$(mbox smtp_get user)${R}" ;; *) warn "✗ mailbox login failed: ${r#FAIL	}"; return 1 ;; esac
    step "Dry run · the mail that would go out"
    send_mail "$1" "$2" "$3" "$4" "$5" yes | grep -v '^DRY' >&2
  else
    row "mail" "none — skipped"
  fi
}
