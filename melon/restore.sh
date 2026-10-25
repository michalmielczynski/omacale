#!/usr/bin/env bash
#
# melon-local: przywracanie stanu po lokalnych zmianach Omacale (2026-09-30).
#
# Co zostało zmienione po stronie Omarchy:
#   * pigułka hostowanych widgetów jest wyłączona (bar.plugins.enabled = false),
#   * osiem widgetów, które w niej siedziały, zostało WYŁĄCZONYCH przez
#     `omarchy plugin disable` — a to zabiera je z `bar.layout` w shell.json:
#       melon.rekuperacja, melon.lights, promaa.clock, melon.sony, melon.audio,
#       harshith.system-monitor, io.github.serg3k.omarchy-plugin-wwan,
#       omarchy-display
#     (melon.eye zostaje WŁĄCZONY: pasek melon.bar ma go w swoim layoucie, a jego
#      overlay rysuje pierścienie kliknięć).
#
# Użycie:
#   ./restore.sh plugins [--dry-run]  przywraca dokładny bar.layout ze snapshotu
#                                     (kolejność i sekcje widgetów też)
#   ./restore.sh melon                pasek → melon.bar + restart shella
#   ./restore.sh omacale              pasek → omacale.bar; jeśli plugin został
#                                     odinstalowany, instaluje go z tego checkoutu
#                                     w trybie --dev (symlink) i ustawia pasek
#   ./restore.sh all                  plugins + melon
#
# Snapshot sprzed instalacji Omacale (bajt w bajt):
#   ~/.local/state/omacale/pre-install/shell.json
# Kopia robocza robiona przez ten skrypt:
#   ~/.config/omarchy/shell.json.bak.restore.<epoch>
#
# Pełne cofnięcie (usuwa też plugin Omacale, zostawia ustawienia):
#   ~/Projects/omacale/uninstall.sh --keep-settings
#
set -Eeuo pipefail

cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
shell_json="$cfg_home/omarchy/shell.json"
snapshot="${XDG_STATE_HOME:-$HOME/.local/state}/omacale/pre-install/shell.json"

dry_run=0
cmd=""
# --dry-run w dowolnym miejscu: pierwsza wersja czytała go tylko jako $1, więc
# `restore.sh plugins --dry-run` wykonało się naprawdę (2026-09-30).
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    -h|--help) cmd="--help" ;;
    "") ;;
    *) if [[ -z $cmd ]]; then cmd="$arg"; else echo "nieznany argument: $arg" >&2; exit 1; fi ;;
  esac
done
action=""

need() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }
need jq

backup() {
  local b="$shell_json.bak.restore.$(date +%s)"
  if (( dry_run )); then echo "[dry-run] kopia: $b"; return 0; fi
  cp --preserve=mode -- "$shell_json" "$b"
  echo "kopia: $b"
}

restore_plugins() {
  [[ -f $snapshot ]] || { echo "brak snapshotu: $snapshot" >&2; exit 1; }
  [[ -f $shell_json ]] || { echo "brak $shell_json" >&2; exit 1; }
  jq -e . "$shell_json" >/dev/null || { echo "$shell_json nie jest poprawnym JSON-em" >&2; exit 1; }

  local want cur
  want="$(jq -c --argjson snap "$(cat "$snapshot")" '$snap.bar.layout' "$shell_json")"
  cur="$(jq -c '.bar.layout' "$shell_json")"
  if [[ $want == "$cur" ]]; then
    echo "bar.layout już jest taki jak w snapshocie — nic do zrobienia"
    return 0
  fi
  echo "przywracam bar.layout ze snapshotu:"
  echo "  teraz: $cur"
  echo "  ma być: $want"
  backup
  if (( dry_run )); then
    echo "[dry-run] nie zmieniam pliku"
    return 0
  fi
  jq --argjson layout "$want" '.bar.layout = $layout' "$shell_json" >"$shell_json.tmp" \
    && chmod --reference="$shell_json" "$shell_json.tmp" \
    && mv -f -- "$shell_json.tmp" "$shell_json"
  echo "gotowe — widgety wróciły do sekcji i kolejności ze snapshotu"
  omarchy-shell -q shell reloadConfig || true
  echo "restartuję shell…"
  omarchy restart shell >/dev/null 2>&1 || echo "restart nie wyszedł; uruchom: omarchy restart shell"
}

install_omacale() {
  local repo plugin state
  repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  plugin="$cfg_home/omarchy/plugins/omacale.bar"
  state="${XDG_STATE_HOME:-$HOME/.local/state}/omacale/state.json"
  if [[ -L $plugin ]]; then
    echo "plugin Omacale już jest (dev symlink) — tylko przełączam pasek"
  else
    # A stale install record sends install.sh down the upgrade path, which never
    # creates the dev symlink: drop it first, so this is a fresh --dev install.
    if [[ -f $state ]]; then
      (( dry_run )) && echo "[dry-run] usunąłbym stary rekord instalacji: $state" || { rm -f -- "$state"; echo "usunięty stary rekord instalacji: $state"; }
    fi
    echo "instaluję Omacale z checkoutu (--dev, symlink): $repo"
    if (( dry_run )); then
      echo "[dry-run] $repo/scripts/omacale install --dev --yes --no-notif-popups --no-lock-screen --no-cava"
    else
      ( cd -- "$repo" && ./scripts/omacale install --dev --yes --no-notif-popups --no-lock-screen --no-cava ) \
        || { echo "instalacja Omacale nie wyszła" >&2; return 1; }
    fi
  fi
  set_bar omacale.bar
}

set_bar() {
  local id="$1"
  [[ -f $shell_json ]] || { echo "brak $shell_json" >&2; exit 1; }
  local cur; cur="$(jq -r '.bar.id // "unset"' "$shell_json")"
  if [[ $cur == "$id" ]]; then
    echo "bar.id już ustawione na $id"
  else
    echo "bar.id: $cur → $id"
    backup
    if (( dry_run )); then
      echo "[dry-run] nie zmieniam pliku"
      return 0
    fi
    jq --arg id "$id" '.bar.id = $id' "$shell_json" >"$shell_json.tmp" \
      && chmod --reference="$shell_json" "$shell_json.tmp" \
      && mv -f -- "$shell_json.tmp" "$shell_json"
  fi
  if (( dry_run )); then
    echo "[dry-run] nie restartuję shella"
    return 0
  fi
  omarchy restart shell >/dev/null 2>&1 || echo "restart nie wyszedł; uruchom: omarchy restart shell"
  echo "gotowe"
}

case "$cmd" in
  plugins) restore_plugins ;;
  melon)   set_bar melon.bar ;;
  omacale) install_omacale ;;
  all)     restore_plugins; set_bar melon.bar ;;
  ""|--help|-h)
    sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) echo "nieznana komenda: $cmd (użyj: plugins | melon | omacale | all)" >&2; exit 1 ;;
esac
