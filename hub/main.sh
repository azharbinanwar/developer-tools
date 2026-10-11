# needs: platform ui keys mail web
# developer-tools: the hub. Run any tool online, or install, update and remove them.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/developer-tools)
#
# Each tool is also a standalone command (ship-apk, ship-site). Running one from
# here uses the installed copy if there is one, otherwise the latest release
# straight from GitHub, so the hub works with nothing installed.
#
# License: MIT.

VERSION="2.2.0-beta.1"
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
latest_tag(){ # -> the newest release tag on the current channel: the stable "latest", or the newest of all on beta; empty offline
  if [ "$(channel)" = beta ]; then newest_tag
  else curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null | sed -n 's|.*/tag/||p'; fi
}
releases(){ # -> the last 20 releases, newest first: tag<TAB>beta|stable<TAB>date<TAB>notes (newlines as \\n); empty offline
  curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=20" 2>/dev/null | py -c 'import json,sys
for r in json.load(sys.stdin):
    print("\t".join([r["tag_name"], "beta" if r.get("prerelease") else "stable", (r.get("published_at") or "")[:10], (r.get("body") or "").replace("\r","").replace("\n","\\n")]))' 2>/dev/null || true
}
versions(){ # -> one line per tool: name<TAB>installed version (or -), then channel and latest; what the web page's Updates view shows
  local t v
  for t in "${TOOLS[@]}" developer-tools; do
    v=""; command -v "$t" >/dev/null 2>&1 && v="$("$t" --version 2>/dev/null | awk '{print $2}')"
    printf '%s\t%s\n' "$t" "${v:--}"
  done
  printf 'channel\t%s\nlatest\t%s\n' "$(channel)" "$(latest_tag | sed 's/^v//')"
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

as_admin(){ # runs a command line with the rights BIN needs: plain when writable, sudo in a terminal, the macOS password dialog when there is none (the web page)
  local line; line="$(printf '%q ' "$@" | sed 's/ \\&\\& / \&\& /g')"
  if [ -z "$SUDO" ]; then eval "$line"
  elif [ -t 0 ]; then eval "sudo $line"
  elif [ "$OS" = mac ]; then
    sub "macOS asks for your password in a dialog"
    osascript -e "do shell script \"$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')\" with administrator privileges" >/dev/null
  else die "writing to $BIN needs sudo, which needs a terminal — run: sudo developer-tools install"; fi
}
fetch_tool(){ # $1 tool -> downloads and checks the latest release; echoes the temp file
  local t="$1" tmp
  tmp="$(tmpf "$t")"
  curl -fsSL "$BASE/$t" -o "$tmp" || { rm -f "$tmp"; die "could not download $t — is there a release yet?"; }
  bash -n "$tmp" || { rm -f "$tmp"; die "$t downloaded broken, not installing it"; }
  printf '%s' "$tmp"
}
install_picked(){ # $@ indexes -> downloads every tool first, then one privileged step puts them all in place: one password, once
  local i t tmp names=() files=() line=()
  [ $# -gt 0 ] || { printf "     ${D}nothing ticked, nothing installed${R}\n" >&2; return; }
  step "Installing to $BIN$([ -n "$SUDO" ] && printf "  ${D}(asks for your password once)${R}")"
  for i in "$@"; do names+=("${TOOLS[$i]}"); done
  names+=(developer-tools)   # the hub itself, so `developer-tools` works next time
  for t in "${names[@]}"; do files+=("$(fetch_tool "$t")"); done
  line=(mkdir -p "$BIN"); for i in "${!names[@]}"; do line+=("&&" install -m 755 "${files[$i]}" "$BIN/${names[$i]}"); done
  as_admin "${line[@]}" || { rm -f "${files[@]}"; die "could not write to $BIN"; }
  rm -f "${files[@]}"
  for t in "${names[@]}"; do ok "$t $("$BIN/$t" --version 2>/dev/null | awk '{print $2}')  ${D}→ $BIN/$t${R}"; done
  case ":$PATH:" in *":$BIN:"*) ;; *) printf "     ${Y}!${R} add %s to your PATH to run them by name\n" "$BIN" >&2 ;; esac
}
run_tool(){ # $1 tool -> installed copy if any, otherwise the latest release from GitHub
  printf "\n" >&2
  command -v "$1" >/dev/null 2>&1 && exec "$1"
  exec bash <(curl -fsSL "$BASE/$1")
}

main(){
  case "${1:-}" in
    --version|-V) echo "developer-tools $VERSION"; exit 0 ;;
    -h|--help)
      printf "\n  ${B}developer-tools${R} ${D}%s${R}\n\n" "$VERSION"
      printf "    ${A}developer-tools${R}              menu: run a tool, install, update or remove tools\n"
      printf "    ${A}developer-tools install${R}      install or update every tool, no questions\n"
      printf "    ${A}developer-tools beta install${R} switch this Mac to the beta channel and install the newest beta\n"
      printf "    ${A}developer-tools stable install${R} back to the stable release\n"
      printf "    ${A}developer-tools <tool>${R}       run one tool (ship-apk, ship-site)\n"
      printf "    ${A}developer-tools ui${R}           a local web page over both tools: publish a site, its domain, history, mail, folders\n"
      printf "    ${A}developer-tools mailbox${R}      the account the links are mailed from; ${A}mailbox test <address>${R} sends a test there\n"
      printf "    ${A}developer-tools versions${R}     what is installed, the channel, and the newest release on it\n"
      printf "    ${A}developer-tools releases${R}     the releases on GitHub, newest first; ${A}install <version>${R} puts that one in place\n\n"
      printf "  ${D}Tools install to %s and keep their settings in ~/.config/<tool>/${R}\n\n" "$BIN"
      exit 0 ;;
    ui)      banner "developer-tools $VERSION" "web page"; ui_serve "${2:-}"; exit 0 ;;
    mailbox) banner "developer-tools $VERSION" "mailbox"
             if [ "${2:-}" = test ]; then smtp_test "${3:-}"; exit $?; fi
             [ -t 0 ] || die "needs a terminal; or: developer-tools mailbox test <address>"
             { [ "$(mbox smtp_ready)" = yes ] && smtp_menu || setup_mailbox; }; exit 0 ;;
    versions) versions; exit 0 ;;
    releases) releases; exit 0 ;;
    install) if [ -n "${2:-}" ]; then   # install <version>: that release, whatever the channel
               banner "developer-tools $VERSION" "installing ${2#v}"; BASE="https://github.com/$REPO/releases/download/v${2#v}"
             else banner "developer-tools $VERSION" "installing everything  · $(channel) channel"; resolve_base; fi
             install_picked $(seq 0 $(( ${#TOOLS[@]} - 1 ))); printf "\n" >&2; exit 0 ;;
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
               "web page              ${D}a local read-only page over both tools: projects, domains, history, mail${R}" \
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
      4) ui_serve ;;
      5) printf "\n" >&2; exit 0 ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
