# ── shortcut keys ─────────────────────────────────────────────────────────
# Every option is matched by its text to an action with a default key (ACTIONS below). A key set in
# ~/.config/developer-tools/keys.json, e.g. {"site.main": "w"}, wins over the default. Options without
# an action, such as apps and projects, get 1–9 in screen order. Esc picks "← back"; q quits.
KEYS_FILE="$HOME/.config/developer-tools/keys.json"
PICK_FILE="$HOME/.config/developer-tools/.lastpick"   # how the last menu pick was made: key or enter; one file, overwritten
act_of(){ # $1 option text -> "action key" from ACTIONS, or nothing
  local t p a k
  t="$(printf '%s' "$1" | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' -e $'s/\x1b(B//g' | tr 'A-Z' 'a-z' \
       | sed -e 's/^[[:space:]]*//' -e 's/^← *//' -e 's/^+ *//' -e 's/[[:space:]]*$//')"
  while IFS='|' read -r p a k; do
    [ -n "$p" ] || continue
    case "$t" in "$p"|"$p "*) printf '%s %s' "$a" "$k"; return ;; esac
  done <<<"$ACTIONS"
}
MK=(); MENU_NOKEY=""   # MENU_NOKEY: indexes of rows that are data (apps, projects, people) — they get 1–9, never an action key
nokey_rows(){ # $1 count -> "0 1 … count-1", or nothing for 0 (seq would count down to -1)
  local i out=""; for ((i=0;i<${1:-0};i++)); do out="$out$i "; done; printf '%s' "${out% }"
}
menu_keys(){ # -> MK: the shortcut shown for each MENU_ITEMS entry (a letter, 1–9, esc, or nothing)
  local i ak a k o ov used=" j k q / ? " d=1 acts=() defs=() all=" " nokey=" $MENU_NOKEY "
  MK=(); ov=""; MENU_NOKEY=""
  [ -f "$KEYS_FILE" ] && ov="$(py -c '
import json, sys
for a, k in json.load(open(sys.argv[1])).items(): print(a + "=" + str(k)[:1].lower())' "$KEYS_FILE" 2>/dev/null)"
  # first pass: every option's action and default key, so a key from keys.json can never steal another option's default
  for ((i=0;i<${#MENU_ITEMS[@]};i++)); do
    a=""; k=""
    case "$nokey" in *" $i "*) ak="" ;; *) [ "${MENU_ITEMS[$i]:0:1}" != $'\x01' ] && ak="$(act_of "${MENU_ITEMS[$i]}")" || ak="" ;; esac
    [ -n "$ak" ] && { a="${ak%% *}"; k="${ak#* }"; }
    acts+=("$a"); defs+=("$k"); [ -n "$k" ] && [ "$k" != esc ] && all="$all$k "
  done
  for ((i=0;i<${#MENU_ITEMS[@]};i++)); do
    a="${acts[$i]}"; k="${defs[$i]}"
    if [ -n "$a" ] && [ "$a" != "-" ] && [ "$k" != esc ]; then
      o="$(printf '%s\n' "$ov" | grep -F "$a=" | head -1 | cut -d= -f2 || true)"
      if [ -n "$o" ] && [ "$o" != "$k" ]; then
        case "$used$all" in *" $o "*) warn "keys.json: “${o}” for ${a} is taken on this screen — keeping “${k}”"; o="" ;; esac
      fi
      [ -n "$o" ] && k="$o"
      case "$used" in *" $k "*) k="" ;; esac
    fi
    [ "$a" = "-" ] && k=""
    [ "$a" = quit ] && k=q          # q quits on every screen anyway; the quit option just shows it
    if [ -z "$a" ] && [ "${MENU_ITEMS[$i]:0:1}" != $'\x01' ] && [ "$d" -le 9 ]; then k="$d"; d=$((d + 1)); fi
    [ -n "$k" ] && [ "$k" != esc ] && used="$used$k "
    MK+=("$k")
  done
  mkdir -p "${PICK_FILE%/*}" 2>/dev/null; printf 'enter' > "$PICK_FILE" 2>/dev/null
}
pfx(){ local k="${MK[$1]:-}"; [ -n "$k" ] && printf '%-6s' "[$k]" || printf '      '; }
key_hit(){ # $1 key pressed -> echoes the index of the option with that shortcut
  local i; [ -n "$1" ] || return 1
  for ((i=0;i<${#MK[@]};i++)); do [ "${MK[$i]}" = "$1" ] && { printf 'key' > "$PICK_FILE" 2>/dev/null; printf '%s' "$i"; return 0; }; done
  return 1
}
back_hit(){ local i; for ((i=0;i<${#MK[@]};i++)); do [ "${MK[$i]}" = esc ] && { printf '%s' "$i"; return 0; }; done; return 1; }
picked_by_key(){ [ "$(cat "$PICK_FILE" 2>/dev/null)" = key ]; }
confirm_y(){ # $1 question -> true only on y; used where one stray key must not do something hard to undo
  local c; printf "     ${Y}%s${R} ${A}y to go, any other key cancels ›${R} " "$1" >&2
  IFS= read -rsn1 c; printf '%s\n' "$c" >&2
  [ "$c" = y ] || [ "$c" = Y ]
}
