# #ddev-generated
# DDEV Drupal Dev shell helpers
# Source this file in your ~/.bashrc or ~/.zshrc:
#   source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
#
# These functions delegate composer, drush, php and phpunit to DDEV when
# you're inside a DDEV project directory, and fall back to the host binary
# otherwise.

_in_ddev_project() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/.ddev/config.yaml" ] && return 0
    dir="$(dirname "$dir")"
  done
  return 1
}

_ddev_delegate() {
  if _in_ddev_project; then
    ddev "$@"
  else
    command "$@"
  fi
}

function composer { _ddev_delegate composer "$@"; }
function drush    { _ddev_delegate drush "$@"; }
function php      { _ddev_delegate php "$@"; }
function phpunit  { _ddev_delegate phpunit "$@"; }
