# #ddev-generated
# Shared functions for the drupal-dev host commands. Sourced with:
#   . "$DDEV_APPROOT/.ddev/drupal-dev/command-helpers.sh"

# Checks a module machine name. Prints an error and returns 1 if invalid.
validate_module_name() {
  local module="$1"
  if [[ ! "$module" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "Error: Invalid module name '$module'."
    echo "Must start with a lowercase letter, contain only lowercase letters, numbers, and underscores."
    return 1
  fi
}

# Checks whether a directory is a git checkout. .git is a directory in a
# normal clone and a file in a git worktree; accept both.
is_git_checkout() {
  [ -e "$1/.git" ]
}

# Echoes the install dir for a module, read from Composer's installer-paths
# config. Falls back to modules/contrib/<name>.
get_module_dir() {
  local module="$1" dir
  dir=$(ddev exec -- bash <<'EOF' | sed "s/{\\\$name}/$module/"
composer config extra.installer-paths --json 2>/dev/null \
  | jq -r 'to_entries[] | select(.value[] == "type:drupal-module") | .key' 2>/dev/null
EOF
)
  if [ -z "$dir" ]; then
    dir="modules/contrib/$module"
  fi
  echo "$dir"
}

# Echoes the Composer dev version from the canonical Drupal repo that matches
# a git branch, or '*' when no match is found.
find_composer_dev_version() {
  local module="$1" branch="$2" versions version="" stripped
  versions=$(ddev exec -- bash <<EOF | grep -E '\-dev$|^dev-' || true
composer show --all "drupal/$module" --format=json 2>/dev/null | jq -r '.versions[]' 2>/dev/null
EOF
)
  # Try direct match: 2.0.x → 2.0.x-dev
  if echo "$versions" | grep -qx "${branch}-dev"; then
    version="${branch}-dev"
  # Try dev- prefix: main → dev-main
  elif echo "$versions" | grep -qx "dev-${branch}"; then
    version="dev-${branch}"
  # Try legacy Drupal format: 8.x-1.x → strip prefix → 1.x-dev
  elif [[ "$branch" =~ ^[0-9]+\.x-(.+)$ ]]; then
    stripped="${BASH_REMATCH[1]}"
    if echo "$versions" | grep -qx "${stripped}-dev"; then
      version="${stripped}-dev"
    elif echo "$versions" | grep -qx "dev-${stripped}"; then
      version="dev-${stripped}"
    fi
  fi
  echo "${version:-*}"
}

# A branch switch or fresh clone can change thousands of files. Let Mutagen
# settle so the container sees them before Composer runs. No-op when Mutagen
# is not in use.
sync_container() {
  ddev mutagen sync >/dev/null 2>&1 || true
}
