#!/bin/zsh

###############################################################################
# Script Name: remove-iwork-apps.sh
# Author: GTsolution
# Description:
#   Removes Pages, Numbers, and Keynote from macOS if installed.
#
#   The script exits with status 1 if any target app is currently running so the
#   management policy can be re-run later without interrupting the user.
#
# Notes:
#   - Safe for Jamf or other policy runners.
#   - Removes app bundles only; it does NOT delete user-created documents.
#   - Intended to run as root.
###############################################################################

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

typeset -a APPS=("Pages" "Numbers" "Keynote")
typeset -a SEARCH_PATHS=(
  "/Applications"
  "/System/Applications"
)

timestamp() {
  /bin/date '+%Y-%m-%d %H:%M:%S'
}

log() {
  print -- "[$(timestamp)] $*"
}

fail() {
  print -- "[$(timestamp)] ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
    fail "This script must be run as root."
  fi
}

is_running() {
  local app_name="$1"

  # Match the actual process name exactly.
  if /usr/bin/pgrep -x -- "$app_name" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

remove_app_bundle() {
  local bundle_path="$1"

  if [[ -e "$bundle_path" ]]; then
    log "Removing: $bundle_path"
    /bin/rm -rf -- "$bundle_path"
    return 0
  fi

  return 1
}

remove_installed_app_everywhere() {
  local app_name="$1"
  local removed=0
  local path=""
  local user_apps=""

  # Standard system-wide locations
  for path in "${SEARCH_PATHS[@]}"; do
    if remove_app_bundle "${path}/${app_name}.app"; then
      removed=1
    fi
  done

  # Per-user Applications folders
  for user_apps in /Users/*/Applications(N); do
    [[ -d "$user_apps" ]] || continue

    if remove_app_bundle "${user_apps}/${app_name}.app"; then
      removed=1
    fi
  done

  if (( removed )); then
    log "${app_name} cleanup completed."
  else
    log "${app_name} not found; nothing to remove."
  fi
}

main() {
  require_root

  log "Checking whether Pages, Numbers, or Keynote are running..."

  local app=""
  for app in "${APPS[@]}"; do
    if is_running "$app"; then
      fail "${app} is currently running. Exiting with status 1 so the policy can be re-run later."
    fi
  done

  log "No target apps are running. Proceeding with cleanup..."

  for app in "${APPS[@]}"; do
    remove_installed_app_everywhere "$app"
  done

  log "Cleanup finished successfully."
}

main "$@"