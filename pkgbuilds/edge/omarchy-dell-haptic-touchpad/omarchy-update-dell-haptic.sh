#!/bin/bash

set -euo pipefail

SERVICE_NAME="dell-xps-haptic-touchpad.service"
DAEMON_PATH="/usr/bin/omarchy-haptic-touchpad-user"
CONFIG_PATH="$HOME/.config/omarchy/dell-haptic.conf"
ENV_PATH="/etc/omarchy-dell-haptic-touchpad.env"
OVERRIDE_DIR="/etc/systemd/system/${SERVICE_NAME}.d"
OVERRIDE_PATH="${OVERRIDE_DIR}/override.conf"

usage() {
  printf 'Usage: %s --intensity 0-100\n' "$(basename -- "$0")"
}

ensure_service_present() {
  if ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    printf 'Required service %s was not found.\n' "$SERVICE_NAME" >&2
    exit 1
  fi
}

reset_trackpad() {
  if ! command -v omarchy-restart-trackpad >/dev/null 2>&1; then
    return
  fi

  if ! omarchy-restart-trackpad; then
    printf 'Warning: omarchy-restart-trackpad failed; continuing with service restart.\n' >&2
  fi
}

validate_value() {
  local name=$1
  local value=$2

  if ! [[ $value =~ ^[0-9]+$ ]]; then
    printf '%s must be an integer from 0 to 100.\n' "$name" >&2
    exit 1
  fi

  if (( value < 0 || value > 100 )); then
    printf '%s must be an integer from 0 to 100.\n' "$name" >&2
    exit 1
  fi
}

write_config() {
  local intensity=$1

  install -d -m 755 "$(dirname -- "$CONFIG_PATH")"
  printf '# Dell XPS touchpad haptic intensity.\n# Valid range: 0-100.\nINTENSITY=%s\n' "$intensity" >"$CONFIG_PATH"
}

write_env_file() {
  local tmpfile
  tmpfile="$(mktemp)"

  printf 'OMARCHY_HAPTIC_HOME=%s\n' "$HOME" >"$tmpfile"
  sudo install -D -m 644 "$tmpfile" "$ENV_PATH"
  rm -f "$tmpfile"
}

write_override_file() {
  local tmpfile
  tmpfile="$(mktemp)"

  cat >"$tmpfile" <<EOF
[Service]
EnvironmentFile=-$ENV_PATH
ExecStart=
ExecStart=$DAEMON_PATH
EOF

  sudo install -D -m 644 "$tmpfile" "$OVERRIDE_PATH"
  rm -f "$tmpfile"
}

setup_is_current() {
  local unit_text env_text=""

  unit_text="$(systemctl cat "$SERVICE_NAME" 2>/dev/null || true)"
  if [[ -f $ENV_PATH ]]; then
    env_text="$(<"$ENV_PATH")"
  fi

  [[ $unit_text == *"EnvironmentFile=-$ENV_PATH"* ]] &&
    [[ $unit_text == *"ExecStart=$DAEMON_PATH"* ]] &&
    [[ $env_text == "OMARCHY_HAPTIC_HOME=$HOME" ]]
}

ensure_system_setup() {
  if setup_is_current; then
    return 1
  fi

  write_env_file
  write_override_file
  sudo systemctl daemon-reload
  reset_trackpad
  sudo systemctl restart "$SERVICE_NAME"
  return 0
}

daemon_updated_since_service_start() {
  local pid elapsed now start_epoch script_mtime

  pid=$(systemctl show -p MainPID --value "$SERVICE_NAME")
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1

  elapsed=$(ps -o etimes= -p "$pid" | tr -d '[:space:]')
  [[ $elapsed =~ ^[0-9]+$ ]] || return 1

  now=$(date +%s)
  start_epoch=$(( now - elapsed ))
  script_mtime=$(stat -c %Y "$DAEMON_PATH")

  (( script_mtime > start_epoch ))
}

intensity=""

while (( $# > 0 )); do
  case "$1" in
    --intensity)
      if (( $# < 2 )); then
        usage >&2
        exit 1
      fi
      intensity=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z $intensity ]]; then
  usage >&2
  exit 1
fi

validate_value "Haptic intensity" "$intensity"
ensure_service_present

if [[ ! -x $DAEMON_PATH ]]; then
  printf 'Installed daemon not found at %s. Reinstall the package.\n' "$DAEMON_PATH" >&2
  exit 1
fi

write_config "$intensity"

if ensure_system_setup; then
  printf 'Configured Dell haptic service and set intensity=%s.\n' "$intensity"
else
  if daemon_updated_since_service_start; then
    reset_trackpad
    sudo systemctl restart "$SERVICE_NAME"
    printf 'Updated Dell haptic intensity to %s and restarted the service to load the latest daemon code.\n' "$intensity"
  else
    printf 'Updated Dell haptic intensity to %s. The running daemon will pick it up on the next click.\n' "$intensity"
  fi
fi
