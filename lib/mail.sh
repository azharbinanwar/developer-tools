# ── mail ──────────────────────────────────────────────────────────────────
# One ordinary email: To is in the headers, BCC only goes to the envelope. Needs the tool's cfg store: smtp_*, people, template.
send_mail(){ # $1 project key  $2 app label  $3 version  $4 link  $5 notes  $6 dry("yes" prints instead of sending)
py - "$CONFIG" "$@" <<'PY'
import json, smtplib, ssl, sys
from email.message import EmailMessage
from email.utils import formataddr

cfgp, key, app, version, link, notes = sys.argv[1:7]
dry = (len(sys.argv) > 7 and sys.argv[7] == "yes")
d = json.load(open(cfgp))
s = d["smtp"]
tpl = d["template"]
p = d["projects"].get(key, {})
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
  t="$(cfg people "$1" to | grep -c .)"; c="$(cfg people "$1" cc | grep -c .)"; b="$(cfg people "$1" bcc | grep -c .)"
  out="$t $([ "$t" = 1 ] && echo person || echo people)"
  [ "$c" -gt 0 ] && out="$out + $c CC"
  [ "$b" -gt 0 ] && out="$out + $b BCC"
  printf '%s' "$out"
}

smtp_login_check(){ # logs in to the mailbox and out again, sends nothing -> "OK" or "FAIL<TAB>reason"
py - "$CONFIG" <<'PY2'
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
  [ "$(cfg smtp_ready)" = yes ] || { warn "fill in address, password and host first"; return; }
  to="$(ask "Send the test to" "$(cfg smtp_get user)")"
  [ -n "$to" ] || return
  cfg proj_set "__test" app "Test"
  cfg person_add "__test" "you" "$to"
  step "Sending test"
  result="$(send_mail "__test" "ship-apk" "0.0.0" "https://appho.st" "- this is a test")"
  cfg proj_del "__test"
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
    done < <(cfg people "$key" "$list")
    MENU_ITEMS+=("+ add to $label"); MENU_NOTES+=("  ${D}name and address${R}")
    MENU_ITEMS+=("← back");         MENU_NOTES+=("")
    step "$label for “${key}”"
    case "$list" in to) sub "who the email is addressed to" ;; cc) sub "copied openly — everyone on the email sees these" ;; *) sub "hidden copy — nobody on the email can see these" ;; esac
    MENU_NOKEY="$(nokey_rows "${#mails[@]}")"
    idx="$(menu_pick "Who" $(( ${#MENU_ITEMS[@]} - 1 )) 0)"; MENU_NOKEY=""
    [ "$idx" -eq $(( ${#MENU_ITEMS[@]} - 1 )) ] && return
    if [ "$idx" -eq $(( ${#MENU_ITEMS[@]} - 2 )) ]; then
      n="$(ask "Their name" "")"; e="$(ask "Their address" "")"
      case "$e" in ?*@?*.?*) cfg person_add "$key" "$n" "$e" "$list"; ok "added ${e}" ;;
                   "") ;; *) warn "“${e}” is not an email address" ;; esac
      continue
    fi
    MENU_ITEMS=("rename" "change address" "remove" "← back"); MENU_NOTES=("" "" "" "")
    step "${names[$idx]:-${mails[$idx]}}"
    i="$(menu_pick "What to do" 3 0)"
    case "$i" in
      0) cfg person_add "$key" "$(ask "Name" "${names[$idx]}")" "${mails[$idx]}" "$list"; ok "renamed" ;;
      1) e="$(ask "Address" "${mails[$idx]}")"
         case "$e" in ?*@?*.?*) ;; *) warn "“${e}” is not an email address"; continue ;; esac
         { cfg person_del "$key" "${mails[$idx]}" "$list"; cfg person_add "$key" "${names[$idx]}" "$e" "$list"; ok "updated"; } ;;
      2) [ "$(ask_yn "Remove ${mails[$idx]}" false)" = true ] && { cfg person_del "$key" "${mails[$idx]}" "$list"; ok "removed"; } ;;
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
  sub "the account ship-apk sends from, used by every app"
  user="$(ask "Email address" "$(cfg smtp_get user)")"
  case "$user" in ?*@?*.?*) ;; *) warn "“${user}” is not an email address"; return ;; esac
  cfg smtp_set user "$user"
  case "$user" in *@gmail.com|*@googlemail.com) sub "Gmail needs an app password: myaccount.google.com/apppasswords" ;; esac
  cfg smtp_set password "$(ask_secret "Password" "$(cfg smtp_get password)")"
  hp="$(smtp_guess "$user")"
  host="$(ask "SMTP host" "$(cfg smtp_get host | grep . || echo "${hp% *}")")"; cfg smtp_set host "$host"
  port="$(ask "Port (465 SSL, 587 STARTTLS)" "${hp#* }")"; cfg smtp_set port "$port"
  cfg smtp_set from_name "$(ask "Name people see it from" "$(cfg smtp_get from_name | grep . || echo "${user%@*}")")"
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
    while IFS=$'\t' read -r n e; do [ -n "$e" ] && row "$label" "${n:+$n  }${D}${e}${R}"; done < <(cfg people "$key" "$f")
    while :; do
      e="$(ask "$label address (blank when done)" "")"; [ -n "$e" ] || break
      case "$e" in ?*@?*.?*) ;; *) warn "“${e}” is not an email address"; continue ;; esac
      n="$(ask "Their name" "${e%@*}")"
      cfg person_add "$key" "$n" "$e" "$f"; ok "added ${e} to ${label}"
    done
  done
  cfg proj_set "$key" subject "$(ask "Subject" "$(cfg proj_get "$key" subject | grep . || cfg tpl_get subject)")"
  ok "email for “$2” saved"
}

smtp_menu(){
  local idx
  while :; do
    MENU_ITEMS=("$(printf '%-16s' 'address')"  "$(printf '%-16s' 'password')"
                "$(printf '%-16s' 'smtp host')" "$(printf '%-16s' 'port')"
                "$(printf '%-16s' 'from name')" "send a test to myself" "edit the mail template" "← back")
    MENU_NOTES=("  ${D}$(cfg smtp_get user)${R}"
                "  ${D}$([ -n "$(cfg smtp_get password)" ] && echo 'set' || echo 'not set yet')${R}"
                "  ${D}$(cfg smtp_get host)${R}"
                "  ${D}$(cfg smtp_get port)  · 465 for SSL, 587 for STARTTLS${R}"
                "  ${D}$(cfg smtp_get from_name)  · the sender name people see${R}"
                "  ${D}proves the settings work before a real send${R}"
                "  ${D}opens config.json · {name} {app} {version} {link} {notes} {sender}${R}" "")
    step "Mailbox"
    idx="$(menu_pick "What to change" 7 0)"
    case "$idx" in
      0) cfg smtp_set user      "$(ask "Address" "$(cfg smtp_get user)")" ;;
      1) cfg smtp_set password  "$(ask_secret "Password" "$(cfg smtp_get password)")" ; ok "saved" ;;
      2) cfg smtp_set host      "$(ask "SMTP host" "$(cfg smtp_get host)")" ;;
      3) cfg smtp_set port      "$(ask "Port" "$(cfg smtp_get port)")" ;;
      4) cfg smtp_set from_name "$(ask "From name" "$(cfg smtp_get from_name)")" ;;
      5) smtp_test ;;
      6) edit_file "$CONFIG" || warn "open $CONFIG yourself" ;;
      7) return ;;
    esac
  done
}
