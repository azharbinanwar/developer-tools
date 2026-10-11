# ── platform ─────────────────────────────────────────────────────────────
# ── platform ──────────────────────────────────────────────────────────────
# macOS, Linux and Windows (Git Bash or WSL) differ in a few commands; everything platform-specific goes through these.
case "$(uname -s 2>/dev/null)" in Darwin) OS=mac ;; MINGW*|MSYS*|CYGWIN*) OS=windows ;; *) OS=linux ;; esac
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
py(){ "$PY" "$@"; }
# every store starts with exec(os.environ["DT_LOAD"]) and d = load_json(path): a hand-edited file that no longer parses is
# recovered when only its tail is damaged, otherwise copied to <file>.broken-<time> and started again, with one line on stderr
export DT_LOAD='
def load_json(path):
    import json, os, sys, time, shutil
    if not os.path.exists(path): return {}
    raw = open(path, errors="replace").read()
    try: return json.loads(raw)
    except Exception: pass
    cut = raw.rfind("}")
    while cut > 0:   # cut back to a brace and close what is still open: a file cut off mid-way comes back minus its tail
        for tail in ("", "}", "}}", "}}}"):
            try:
                d = json.loads(raw[:cut + 1] + tail); sys.stderr.write("     ! %s was not valid JSON; recovered up to the damage\n" % path); return d
            except Exception: pass
        cut = raw.rfind("}", 0, cut)
    bak = "%s.broken-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
    try: shutil.copy(path, bak)
    except Exception: pass
    sys.stderr.write("     ! %s could not be read; it is kept as %s and a fresh one starts\n" % (path, os.path.basename(bak)))
    return {}
'
clip(){ # stdin -> the clipboard, whichever tool this machine has; false when there is none
  if command -v pbcopy >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then wl-copy
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
  elif command -v xsel >/dev/null 2>&1; then xsel --clipboard --input
  elif command -v clip.exe >/dev/null 2>&1; then clip.exe
  else cat >/dev/null; return 1; fi
}
open_it(){ # $1 file, folder or url -> opens it with the desktop; false when nothing can
  if [ "$OS" = mac ]; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1
  elif command -v wslview >/dev/null 2>&1; then wslview "$1"
  elif command -v cmd.exe >/dev/null 2>&1; then cmd.exe /c start "" "$1" >/dev/null 2>&1
  else return 1; fi
}
edit_file(){ # $1 file -> opens it in $VISUAL/$EDITOR, else the desktop's text editor; waits only for a terminal editor
  if [ -n "${VISUAL:-${EDITOR:-}}" ]; then
    if [ -t 2 ]; then ${VISUAL:-$EDITOR} "$1" </dev/tty >/dev/tty; else ${VISUAL:-$EDITOR} "$1" >&2; fi; return 0
  fi
  if [ "$OS" = mac ]; then open -t "$1"; else open_it "$1"; fi || return 1
  printf "     ${A}Opened in your editor — save it, then press Enter here${R} ${A}›${R} " >&2; read -r _
}
# BSD (macOS) and GNU (Linux, Git Bash) stat and date take different flags, and GNU accepts the BSD ones with other
# meanings (stat -f is file-system info), so these branch on OS rather than on failure
fsize(){ if [ "$OS" = mac ]; then stat -f %z "$1"; else stat -c %s "$1"; fi; }        # bytes
fmtime(){ if [ "$OS" = mac ]; then stat -f %m "$1"; else stat -c %Y "$1"; fi; }       # seconds since the epoch
fmode(){ if [ "$OS" = mac ]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }       # permission bits, e.g. 600
fdate(){ if [ "$OS" = mac ]; then date -r "$1" "$2"; else date -d "@$1" "$2"; fi; }   # $1 epoch seconds  $2 format
sed_i(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
tmpf(){ mktemp "${TMPDIR:-/tmp}/${1:-tmp}.XXXXXX"; }              # a temp file; portable, no -t
tmpd(){ mktemp -d "${TMPDIR:-/tmp}/${1:-tmp}.XXXXXX"; }           # a temp folder
RULE="────────────────────────────────────────────"
