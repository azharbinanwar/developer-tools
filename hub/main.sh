# needs: platform ui keys
# developer-tools: the hub. Run any tool online, or install, update and remove them.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/developer-tools)
#
# Each tool is also a standalone command (ship-apk, ship-site). Running one from
# here uses the installed copy if there is one, otherwise the latest release
# straight from GitHub, so the hub works with nothing installed.
#
# License: MIT.

VERSION="2.1.0"
# ── channel ───────────────────────────────────────────────────────────────
# stable: GitHub's "latest" release, which never includes a pre-release. beta: the newest release of all,
# pre-releases included. The choice is saved once in ~/.config/developer-tools/channel and used by every
# install, update and online run from this hub. The tools themselves are the same files either way.
REPO="azharbinanwar/developer-tools"
CHANNEL_FILE="$HOME/.config/developer-tools/channel"
channel(){ local c; c="$(cat "$CHANNEL_FILE" 2>/dev/null)"; [ "$c" = beta ] && echo beta || echo stable; }
set_channel(){ mkdir -p "${CHANNEL_FILE%/*}" && printf '%s\n' "$1" > "$CHANNEL_FILE"; }
newest_tag(){ # -> the newest release tag, pre-releases included; empty when GitHub cannot be reached
  curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=1" 2>/dev/null | py -c 'import json,sys
r = json.load(sys.stdin); print(r[0]["tag_name"] if r else "")' 2>/dev/null || true   # unreachable → empty, never an error
}
resolve_base(){ # -> BASE for this run: the stable latest, or the newest tag on the beta channel
  [ -n "${DEVTOOLS_BASE:-}" ] && { BASE="$DEVTOOLS_BASE"; return; }   # DEVTOOLS_BASE=file:///dir to test locally
  BASE="https://github.com/$REPO/releases/latest/download"
  if [ "$(channel)" = beta ]; then
    local t; t="$(newest_tag)"
    [ -n "$t" ] && BASE="https://github.com/$REPO/releases/download/$t" || warn "could not reach GitHub for the beta list — using the stable release"
  fi
}
BASE=""
# where tools go: /usr/local/bin (with sudo when it is not writable); on Windows Git Bash, ~/bin, which Git Bash puts on PATH
if [ "$OS" = windows ]; then BIN="$HOME/bin"; else BIN="/usr/local/bin"; fi
SUDO=""; { [ -w "$BIN" ] || [ "$OS" = windows ]; } || SUDO=sudo
TOOLS=(ship-apk ship-site)
NOTES=("build a Flutter APK, upload it to appho.st, mail the link"
       "build a Vite site, publish dist/ to Vercel, copy the link")

# pick:  one item, Enter picks            -> echoes the index
# tick:  many items, space toggles, Enter -> echoes the ticked indexes, space separated
ACTIONS=""
IFS= read -r -d '' ACTIONS <<'ACTS' || true   # a heredoc, so option texts may hold quotes
run a tool|run|r
install or update|install|i
remove|remove|d
channel|channel|c
quit|quit|q
back|back|esc
ACTS
_keys(){ # shared key loop; $1 mode (pick|tick), rest items. Uses SEL and TICK arrays.
  local mode="$1"; shift
  local items=("$@") n=$# k rest i saved hint
  [ "$mode" = tick ] && hint="↑↓ move · space toggles · Enter continues · q quits" || hint="↑↓ move · Enter picks · q quits"
  saved="$(stty -g 2>/dev/null || true)"
  printf '\033[?7l' >&2   # no wrapping while the menu is up: a long row is cut, not wrapped, so the redraw stays aligned
  [ -n "$saved" ] && { stty -echo -icanon 2>/dev/null; trap 'stty "$saved" 2>/dev/null; printf "\033[?7h" >&2; exit 130' INT; }
  MK=(); [ "$mode" = pick ] && { MENU_ITEMS=("${items[@]}"); menu_keys; hint="↑↓ move · Enter or a [key] picks · Esc back · q quits"; }
  printf "     ${D}%s${R}\n" "$hint" >&2
  for ((i=0;i<n;i++)); do printf '\n' >&2; done
  local w hit; w=$(( $(term_size | cut -d" " -f2) - 12 ))
  for ((i=0;i<n;i++)); do items[$i]="$(fit "$( [ "$mode" = pick ] && pfx "$i")${items[$i]}" "$w")"; done
  while :; do
    printf "\033[%dA" "$n" >&2
    for ((i=0;i<n;i++)); do
      local box=""
      [ "$mode" = tick ] && { [ "${TICK[$i]}" = 1 ] && box="${G}[x]${R} " || box="${D}[ ]${R} "; }
      [ "$i" -eq "$SEL" ] && printf "\r\033[K     ${A}❯${R} %s${B}%s${R}\n" "$box" "${items[$i]}" >&2 \
                           || printf "\r\033[K       %s${D}%s${R}\n" "$box" "${items[$i]}" >&2
    done
    IFS= read -rsn1 k 2>/dev/null || { [ "$mode" = pick ] && hit="$(back_hit)" && SEL=$hit; break; }
    [ "$mode" = pick ] && hit="$(key_hit "$k")" && { SEL=$hit; break; }
    case "$k" in
      '')    break ;;
      ' ')   [ "$mode" = tick ] && { [ "${TICK[$SEL]}" = 1 ] && TICK[$SEL]=0 || TICK[$SEL]=1; } ;;
      $'\e') IFS= read -rsn2 -t 1 rest 2>/dev/null || rest=""
             [ -z "$rest" ] && [ "$mode" = pick ] && { hit="$(back_hit)" && { SEL=$hit; break; }; }
             case "$rest" in "[A") SEL=$(((SEL-1+n)%n)) ;; "[B") SEL=$(((SEL+1)%n)) ;; esac ;;
      k|K)   SEL=$(((SEL-1+n)%n)) ;;
      j|J)   SEL=$(((SEL+1)%n)) ;;
      q|Q)   [ -n "$saved" ] && stty "$saved" 2>/dev/null; printf '\033[?7h\n' >&2; exit 0 ;;
    esac
  done
  printf '\033[?7h' >&2
  [ -n "$saved" ] && { trap - INT; stty "$saved" 2>/dev/null; }
}
pick(){ SEL=0; _keys pick "$@"; printf '%s' "$SEL"; }
tick(){ # all ticked by default
  local i; TICK=(); for ((i=0;i<$#;i++)); do TICK+=(1); done
  SEL=0; _keys tick "$@"
  for ((i=0;i<$#;i++)); do [ "${TICK[$i]}" = 1 ] && printf '%s ' "$i"; done
}

# ── tools ─────────────────────────────────────────────────────────────────
status(){ # $1 tool -> "installed 2.0.0-beta.1 (beta)" or "not installed"
  local v; command -v "$1" >/dev/null 2>&1 || { printf 'not installed'; return; }
  local tag=""; v="$("$1" --version 2>/dev/null | awk '{print $2}')"
  case "$v" in *-*) tag=" (beta)" ;; esac   # bash 3.2 cannot parse a case inside $( ), so not inline
  printf 'installed %s%s' "$v" "$tag"
}
label(){ printf '%-11s %-56s %s' "${TOOLS[$1]}" "${NOTES[$1]}" "$(status "${TOOLS[$1]}")"; }

install_tool(){ # $1 tool -> downloads the latest release into BIN
  local t="$1" tmp
  tmp="$(tmpf "$t")"
  curl -fsSL "$BASE/$t" -o "$tmp" || { rm -f "$tmp"; die "could not download $t — is there a release yet?"; }
  bash -n "$tmp" || { rm -f "$tmp"; die "$t downloaded broken, not installing it"; }
  $SUDO mkdir -p "$BIN" && $SUDO install -m 755 "$tmp" "$BIN/$t" || { rm -f "$tmp"; die "could not write $BIN/$t"; }
  rm -f "$tmp"
  ok "$t $("$BIN/$t" --version 2>/dev/null | awk '{print $2}')  ${D}→ $BIN/$t${R}"
}
install_picked(){ # $@ indexes
  local i
  [ $# -gt 0 ] || { printf "     ${D}nothing ticked, nothing installed${R}\n" >&2; return; }
  step "Installing to $BIN$([ -n "$SUDO" ] && printf "  ${D}(asks for your password once)${R}")"
  for i in "$@"; do install_tool "${TOOLS[$i]}"; done
  install_tool developer-tools   # the hub itself, so `developer-tools` works next time
  case ":$PATH:" in *":$BIN:"*) ;; *) printf "     ${Y}!${R} add %s to your PATH to run them by name\n" "$BIN" >&2 ;; esac
}
run_tool(){ # $1 tool -> installed copy if any, otherwise the latest release from GitHub
  printf "\n" >&2
  command -v "$1" >/dev/null 2>&1 && exec "$1"
  exec bash <(curl -fsSL "$BASE/$1")
}

main(){
  case "${1:-}" in
    --version|-V|-v) echo "developer-tools $VERSION"; exit 0 ;;
    -h|--help)
      printf "\n  ${B}developer-tools${R} ${D}%s${R}\n\n" "$VERSION"
      printf "    ${A}developer-tools${R}              menu: run a tool, install, update or remove tools\n"
      printf "    ${A}developer-tools install${R}      install or update every tool, no questions\n"
      printf "    ${A}developer-tools beta install${R} switch this Mac to the beta channel and install the newest beta\n"
      printf "    ${A}developer-tools stable install${R} back to the stable release\n"
      printf "    ${A}developer-tools <tool>${R}       run one tool (ship-apk, ship-site)\n\n"
      printf "  ${D}Tools install to %s and keep their settings in ~/.config/<tool>/${R}\n\n" "$BIN"
      exit 0 ;;
    install) banner "developer-tools $VERSION" "installing everything  · $(channel) channel"
             resolve_base; install_picked $(seq 0 $(( ${#TOOLS[@]} - 1 ))); printf "\n" >&2; exit 0 ;;
    beta|stable) set_channel "$1"
             if [ "${2:-}" = install ]; then banner "developer-tools $VERSION" "installing everything · $1 channel"; resolve_base; install_picked $(seq 0 $(( ${#TOOLS[@]} - 1 ))); printf "\n" >&2
             else ok "channel set to $1 — run developer-tools install to update"; fi
             exit 0 ;;
    "") ;;
    *) resolve_base; for t in "${TOOLS[@]}"; do [ "$1" = "$t" ] && run_tool "$t"; done
       die "no tool called “$1” — try: developer-tools --help" ;;
  esac
  [ -t 0 ] || die "developer-tools needs a terminal — run it, do not pipe into it"

  banner "developer-tools $VERSION" "$([ "$(channel)" = beta ] && printf "${Y}beta channel${R}")"
  resolve_base
  local items i c installed
  while :; do
    step "What do you want to do"
    c="$(pick "run a tool            ${D}without installing anything${R}" \
               "install or update     ${D}put tools in $BIN${R}" \
               "remove                ${D}take tools out of $BIN${R}" \
               "channel               ${D}$(channel) · $([ "$(channel)" = beta ] && echo 'switch back to stable' || echo 'switch to beta to try new versions first')${R}" \
               "quit")"
    case "$c" in
      0) step "Run"
         items=(); for ((i=0;i<${#TOOLS[@]};i++)); do items+=("$(label $i)"); done; items+=("← back")
         c="$(pick "${items[@]}")"; [ "$c" -lt ${#TOOLS[@]} ] && run_tool "${TOOLS[$c]}" ;;
      1) step "Install or update  ${D}everything is ticked, untick what you do not want${R}"
         items=(); for ((i=0;i<${#TOOLS[@]};i++)); do items+=("$(label $i)"); done
         install_picked $(tick "${items[@]}") ;;
      2) installed=(); items=()
         for ((i=0;i<${#TOOLS[@]};i++)); do command -v "${TOOLS[$i]}" >/dev/null 2>&1 && { installed+=("$i"); items+=("$(label $i)"); }; done
         [ ${#installed[@]} -gt 0 ] || { printf "     ${D}nothing is installed${R}\n" >&2; continue; }
         step "Remove  ${D}everything is ticked, untick what you want to keep${R}"
         for i in $(tick "${items[@]}"); do
           $SUDO rm -f "$BIN/${TOOLS[${installed[$i]}]}" && ok "removed ${TOOLS[${installed[$i]}]}  ${D}(settings in ~/.config are kept)${R}"
         done ;;
      3) if [ "$(channel)" = beta ]; then set_channel stable; ok "stable channel — install or update now gives the stable release"
         else set_channel beta; ok "beta channel — install or update now gives the newest release, betas included"; fi
         resolve_base ;;
      4) printf "\n" >&2; exit 0 ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
