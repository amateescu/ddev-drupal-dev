# #ddev-generated
# Shared functions for the tab completion scripts of the drupal-dev host
# commands. Sourced with:
#   . "$(dirname "$0")/../../../drupal-dev/completion-helpers.sh"

# DDEV turns everything a completion script prints into suggestions, stderr
# included, so an error from git would be offered as words to pick from.
exec 2>/dev/null

# DDEV runs host completion scripts without the DDEV_* variables it gives host
# commands (https://github.com/ddev/ddev/issues/8867), so the project root is
# worked out from the script's location in .ddev/commands/host/autocomplete/.
DDEV_APPROOT=${DDEV_APPROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}

. "$DDEV_APPROOT/.ddev/drupal-dev/command-helpers.sh"

# Reads the words DDEV passes to a completion script: the command name, the
# words already typed, then the word being completed. Sets CUR to the word
# being completed and POSITIONAL to the typed words after the leading flags,
# which is how the commands parse them too. DDEV passes an empty word as the
# two characters '', so that counts as empty.
read_completion_words() {
  local word
  shift
  CUR="${!#}"
  [ "$CUR" = "''" ] && CUR=""
  POSITIONAL=()
  for word in "${@:1:$#-1}"; do
    if [ ${#POSITIONAL[@]} -eq 0 ] && [[ "$word" == --* ]]; then
      continue
    fi
    POSITIONAL+=("$word")
  done
}

# Echoes the directories of the modules cloned with add-module, one per line.
# add-module registers each one as a path repository in composer.local.json.
# Composer writes repositories either as an object keyed by name or as a list,
# and both forms have a "url" line, so only those lines are read. Anything
# that is not a git checkout of a module with a valid name is skipped.
module_dirs() {
  local url dir name
  while read -r url; do
    dir="$DDEV_APPROOT/${url%/}"
    name="${dir##*/}"
    if is_git_checkout "$dir" && [ -f "$dir/$name.info.yml" ] && validate_module_name "$name" >/dev/null; then
      echo "$dir"
    fi
  done < <(grep -o '"url" *: *"[^"]*"' "$DDEV_APPROOT/composer.local.json" | sed 's/.*"\([^"]*\)"$/\1/')
}

# Echoes the names of the modules cloned with add-module, one per line.
list_modules() {
  module_dirs | sed 's|.*/||' | sort -u
}

# Echoes the checkout directory of a project: the project root for 'core', the
# module's directory otherwise. Returns 1 when there is no such checkout.
project_dir() {
  local project="$1" dir
  if [ "$project" = "core" ]; then
    is_git_checkout "$DDEV_APPROOT" || return 1
    echo "$DDEV_APPROOT"
    return
  fi
  while read -r dir; do
    if [ "${dir##*/}" = "$project" ]; then
      echo "$dir"
      return
    fi
  done < <(module_dirs)
  return 1
}

# Echoes the branches a project can be switched to: its local branches and the
# branches of every remote it has fetched. Only reads refs, so it never waits
# on the network.
list_branches() {
  local dir
  dir=$(project_dir "$1") || return 0
  {
    git -C "$dir" for-each-ref --format='%(refname:lstrip=2)' refs/heads
    git -C "$dir" for-each-ref --format='%(refname:lstrip=3)' refs/remotes | grep -vx HEAD
  } | sort -u
}
