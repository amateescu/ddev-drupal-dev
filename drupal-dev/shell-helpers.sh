# #ddev-generated
# DDEV Drupal Dev shell helpers
# Source this file in your ~/.bashrc or ~/.zshrc:
#   source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
#
# These functions delegate composer, dr, drush, php, phpunit, phpstan, phpcs and
# cspell to DDEV when you're inside a DDEV project directory, and fall back to
# the host binary otherwise.

# Double-underscore prefix avoids zsh compinit treating these as completion
# function autoload stubs (single _ prefix is the completion-function convention).
__ddev_in_project() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/.ddev/config.yaml" ] && return 0
    dir="$(dirname "$dir")"
  done
  return 1
}

__ddev_delegate() {
  if __ddev_in_project; then
    ddev "$@"
  else
    command "$@"
  fi
}

function composer { __ddev_delegate composer "$@"; }
function dr       { __ddev_delegate dr "$@"; }
function drush    { __ddev_delegate drush "$@"; }
function php      { __ddev_delegate php "$@"; }
function phpunit  { __ddev_delegate phpunit "$@"; }
function phpstan  { __ddev_delegate phpstan "$@"; }
function phpcs    { __ddev_delegate phpcs "$@"; }
function cspell   { __ddev_delegate cspell "$@"; }
