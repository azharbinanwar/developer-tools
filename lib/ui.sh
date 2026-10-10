# ── looks ─────────────────────────────────────────────────────────────────
# ── looks ─────────────────────────────────────────────────────────────────
if [ -t 2 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  B=$(tput bold); D=$(tput dim); R=$(tput sgr0)
  A=$(tput setaf 6); G=$(tput setaf 2); Y=$(tput setaf 3); E=$(tput setaf 1)
else B=; D=; R=; A=; G=; Y=; E=; fi
banner(){ printf "\n  ${A}${B}◆  %s${R}  ${D}%s${R}\n" "$1" "${2:-}" >&2; }
step(){ printf "\n  ${A}${B}▸${R} ${B}%s${R}\n" "$1" >&2; }
sub(){ printf "     ${D}%s${R}\n" "$1" >&2; }
ok(){ printf "     ${G}✓${R} %s\n" "$1" >&2; }
warn(){ printf "     ${Y}!${R} %s\n" "$1" >&2; }
die(){ printf "\n  ${E}${B}✗ %s${R}\n" "$1" >&2; exit 1; }
row(){ printf "     ${D}%-11s${R} %s\n" "$1" "$2" >&2; }
cmd(){ printf "     ${D}\$${R} %s\n" "$1" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
fail(){ # $1 message  $2 log file -> repeats the error lines from the log, then dies
  local l; printf "\n" >&2
  warn "$1"
  grep -i 'error\|fail\|denied\|not found\|cannot' "$2" 2>/dev/null | tail -6 | while IFS= read -r l; do sub "$l"; done
  die "stopped — full output is above"
}


fit(){ # $1 text (may carry colour codes)  $2 width -> the text as is, or cut with … when it would wrap
  local plain
  plain="$(printf '%s' "$1" | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' -e $'s/\x1b(B//g')"
  [ "${#plain}" -le "$2" ] && { printf '%s' "$1"; return; }
  printf '%s…' "${plain:0:$(( $2 - 1 ))}"
}
term_size(){ # -> "rows cols" of the real terminal; works inside $( ), where tput only sees a pipe and guesses 24x80
  local s; s="$({ stty size </dev/tty; } 2>/dev/null)"
  [ -n "$s" ] && { printf '%s' "$s"; return; }
  printf '%s %s' "$(tput lines 2>/dev/null || echo 24)" "$(tput cols 2>/dev/null || echo 80)"
}
MENU_ITEMS=(); MENU_NOTES=(); MENU_FIXED=0
menu_pick(){ # $1 title  [$2 skip index]  $3 start index -> echoes chosen index
  # items starting with \x01 are headings, never picked; the last MENU_FIXED items stay on screen while the rest scrolls.
  # With a skip index, Esc, q and end of input pick that row (a "skip" or "back" row); without one, Esc and end of input
  # pick the "← back" row when there is one, and q quits.
  local title="$1" skip=-1 n=${#MENU_ITEMS[@]} sel k rest i saved step nf ns vs top=0 last L ctxl=0 lines cols w g ctx more
  if [ $# -ge 3 ]; then skip="$2"; sel="$3"; else sel="$2"; fi
  nf=${MENU_FIXED:-0}; MENU_FIXED=0; ns=$((n - nf))
  read -r lines cols <<<"$(term_size)"
  vs=$(( lines - 9 - nf )); [ "$vs" -lt 3 ] && vs=3; [ "$vs" -gt "$ns" ] && vs=$ns
  [ "$ns" -gt "$vs" ] && ctxl=1      # a scrolling list gets one line on top for its group heading
  L=$((ctxl + vs + nf))
  saved="$(stty -g 2>/dev/null || true)"
  printf '\033[?7l' >&2   # no wrapping while the menu is up: a long row is cut, not wrapped, so the redraw stays aligned
  [ -n "$saved" ] && { stty -echo -icanon 2>/dev/null; trap 'stty "$saved" 2>/dev/null; printf "\033[?7h" >&2; exit 130' INT; }
  menu_keys
  printf "     ${D}%s  · ↑↓ move · Enter or a [key] picks · Esc back · q quits${R}\n" "$title" >&2
  for ((i=0;i<L;i++)); do printf '\n' >&2; done
  # rows are cut to the window width up front: a wrapped row would throw off the cursor-up redraw
  local rows=() hit; w=$(( cols - 20 ))
  for ((i=0;i<n;i++)); do
    if [ "${MENU_ITEMS[$i]:0:1}" = $'\x01' ]; then rows+=("$(fit "${MENU_ITEMS[$i]}" "$w")")
    else rows+=("$(fit "$(pfx "$i")${MENU_ITEMS[$i]}${MENU_NOTES[$i]:-}" "$w")"); fi
  done
  is_head(){ [ "${MENU_ITEMS[$1]:0:1}" = $'\x01' ]; }
  while is_head "$sel"; do sel=$(((sel+1)%n)); done
  while :; do
    if [ "$sel" -lt "$ns" ]; then
      [ "$sel" -lt "$top" ] && top=$sel
      [ "$sel" -ge $((top + vs)) ] && top=$((sel - vs + 1))
      [ "$top" -gt 0 ] && is_head $((top - 1)) && [ "$sel" -lt $((top + vs - 1)) ] && top=$((top - 1))
    fi
    last=$((top + vs - 1))
    printf "\033[%dA" "$L" >&2
    if [ "$ctxl" = 1 ]; then
      # the heading of the group in view, pinned when it has scrolled off the top
      ctx=""; g=$([ "$sel" -lt "$ns" ] && echo "$sel" || echo "$top")
      while [ "$g" -ge 0 ] && { ! is_head "$g" || [ "${MENU_ITEMS[$g]:1:1}" = " " ]; }; do g=$((g - 1)); done
      [ "$g" -ge 0 ] && [ "$g" -lt "$top" ] && ctx="${rows[$g]:1}"
      printf "\r\033[K     ${B}%s${R}%s\n" "$ctx" "$([ "$top" -gt 0 ] && printf "  ${D}▲ %s more${R}" "$top")" >&2
    fi
    for ((i=top;i<=last && i<ns;i++)); do
      more=""; [ "$i" -eq "$last" ] && [ "$last" -lt $((ns - 1)) ] && more="  ${D}▼ $((ns - 1 - last)) more${R}"
      if   is_head "$i";           then printf "\r\033[K     ${B}%s${R}%s\n" "${rows[$i]:1}" "$more" >&2
      elif [ "$i" -eq "$sel" ];    then printf "\r\033[K     ${A}❯ %s${R}%s\n" "${rows[$i]}" "$more" >&2
      else                              printf "\r\033[K       ${D}%s${R}%s\n" "${rows[$i]}" "$more" >&2; fi
    done
    for ((i=ns;i<n;i++)); do
      if   is_head "$i";           then printf "\r\033[K     ${B}%s${R}\n" "${rows[$i]:1}" >&2
      elif [ "$i" -eq "$sel" ];    then printf "\r\033[K     ${A}❯ %s${R}\n" "${rows[$i]}" >&2
      else                              printf "\r\033[K       ${D}%s${R}\n" "${rows[$i]}" >&2; fi
    done
    IFS= read -rsn1 k 2>/dev/null || { if [ "$skip" -ge 0 ]; then sel="$skip"; else hit="$(back_hit)" && sel=$hit; fi; break; }   # end of input: back out
    step=0
    hit="$(key_hit "$k")" && { sel=$hit; break; }
    case "$k" in
      '')    break ;;
      $'\e') IFS= read -rsn2 -t 1 rest 2>/dev/null || rest=""
             if [ -z "$rest" ]; then
               if [ "$skip" -ge 0 ]; then sel="$skip"; break; fi
               hit="$(back_hit)" && { sel=$hit; break; }
             fi
             case "$rest" in "[A") step=-1 ;; "[B") step=1 ;; esac ;;
      k|K)   step=-1 ;;
      j|J)   step=1 ;;
      q|Q)   [ "$skip" -ge 0 ] && { sel="$skip"; break; }
             [ -n "$saved" ] && stty "$saved" 2>/dev/null; printf '\033[?7h\n' >&2; exit 0 ;;
    esac
    [ "$step" -ne 0 ] && { sel=$(((sel+step+n)%n)); while is_head "$sel"; do sel=$(((sel+step+n)%n)); done; }
  done
  printf '\033[?7h' >&2
  [ -n "$saved" ] && { trap - INT; stty "$saved" 2>/dev/null; }
  printf '%s' "$sel"
}
ask(){ local r; printf "     ${A}%s${R}%s ${A}›${R} " "$1" "${2:+ ${D}[$2]${R}}" >&2; read -r r; printf '%s' "${r:-$2}"; }
ask_secret(){ # $1 label  $2 saved value -> one * per character typed; Enter on nothing keeps the saved value
  local r="" c
  printf "     ${A}%s${R} ${D}[%s]${R} ${A}›${R} " "$1" "$([ -n "${2:-}" ] && echo 'saved · Enter keeps it' || echo 'none')" >&2
  while IFS= read -rsn1 c; do
    case "$c" in
      '')            break ;;
      $'\177'|$'\b') [ -n "$r" ] && { r="${r%?}"; printf '\b \b' >&2; } ;;
      *)             r="$r$c"; printf '*' >&2 ;;
    esac
  done
  printf '\n' >&2
  printf '%s' "${r:-${2:-}}"
}

ask_yn(){ local r d; [ "$2" = true ] && d="yes" || d="no"
  printf "     ${A}%s${R} ${D}(y/n) [%s]${R} ${A}›${R} " "$1" "$d" >&2
  read -r r; case "$r" in [yY]*) echo true ;; [nN]*) echo false ;; *) echo "$2" ;; esac; }
need(){ # $1 what  $2 how to check  $3 install command -> asks, installs, or dies with the command
  have "$2" && return
  printf "     ${Y}!${R} %s is not installed\n     ${A}Install it now with  %s${R} ${D}(y/n) [yes]${R} ${A}›${R} " "$1" "$3" >&2
  read -r a; case "$a" in [nN]*) die "install it yourself, then run again:  $3" ;; esac
  $3 >&2 || die "that failed — run it yourself and try again:  $3"
  have "$2" || die "$1 still not found — open a new terminal and run again"
}
need_vercel(){ need "the Vercel CLI" vercel "npm i -g vercel"; }
need_firebase(){ need "the Firebase CLI" firebase "npm i -g firebase-tools"; }
