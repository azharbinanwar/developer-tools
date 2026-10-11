# ── web ───────────────────────────────────────────────────────────────────
# developer-tools ui: one local page over the same config files the tools use. Read-only: projects, apps, labels,
# domains, counts, history, recipients and the mailbox, every link copyable. Python's stdlib serves it on 127.0.0.1
# with a random token in the URL, so no other page in the browser can read it; the password never leaves the file.
stop_ui(){ # $1 pid of the wrapper -> the server runs inside it; both go, so the port is freed
  pkill -TERM -P "$1" 2>/dev/null; kill "$1" 2>/dev/null; wait "$1" 2>/dev/null
}
ui_serve(){ # [--no-open] -> runs until q or Ctrl-C
  local tok url pid open=yes line out
  [ "${1:-}" = --no-open ] && open=no
  tok="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  out="$(tmpf devtools-ui)"
  step "Web page"
  # the ship-site that publishes from the page: the one next to this hub (the repo), else the installed one
  local here site_bin=""; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  if [ -x "$here/ship-site/ship-site" ]; then site_bin="$here/ship-site/ship-site"; else site_bin="$(command -v ship-site || true)"; fi
  py - "$HOME/.config" "$tok" "$site_bin" "$VERSION" "$(command -v ship-apk || true)" "${BASH_SOURCE[0]}" <<'PY' >"$out" 2>&1 &
@@SERVER_PY@@
PY
  pid=$!; disown "$pid" 2>/dev/null || true   # ours to stop later; bash must not report it when we do
  # the server prints one line, where it listens; wait for it, then hand the link over
  for _ in $(seq 1 25); do [ -s "$out" ] && break; sleep 0.2; done
  url="$(sed -n 's/^URL	//p' "$out" 2>/dev/null)"
  [ -n "$url" ] || { kill "$pid" 2>/dev/null; die "the local server did not start (python3 http.server) — see $out"; }
  row "page" "${B}${A}${url}${R}"
  sub "projects, apps, domains, history, mail; open a site to publish it · this computer only · the link holds a one-time key"
  [ -n "$site_bin" ] || warn "ship-site is not installed, so the page shows everything but cannot publish"
  [ "$open" = yes ] && { open_it "$url" || sub "open that link in your browser"; }
  printf "     ${D}q or Ctrl-C stops it${R}\n" >&2
  trap 'stop_ui "$pid"; printf "\n" >&2; exit 0' INT TERM
  if [ -t 0 ]; then while IFS= read -rsn1 line; do [ "$line" = q ] || [ "$line" = Q ] && break; done
  else while kill -0 "$pid" 2>/dev/null; do sleep 1; done; fi   # no terminal: run until the server goes (a disowned job cannot be waited on)
  stop_ui "$pid"; trap - INT TERM; rm -f "$out"
  ok "stopped"
}
