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
  # The script goes in over stdin, which 'ddev exec --raw' does not forward, so
  # this stays a plain exec.
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

# Echoes the result of a git.drupalcode.org API request, passed through a jq
# filter. Runs in the container, so the host needs neither curl nor jq. Echoes
# nothing when the request fails, which is how a missing project or merge
# request shows up.
#   drupalcode_api "projects/project%2Fdrupal/merge_requests/16853" '.source_branch'
drupalcode_api() {
  # --raw passes the arguments through untouched, so the path and the filter
  # reach the container as data. Splicing them into the command instead would
  # run whatever a pasted URL or an API field happened to contain.
  ddev exec --raw -- bash -c \
    'curl -fs --max-time 20 "https://git.drupalcode.org/api/v4/$1" | jq -r "$2" 2>/dev/null' \
    drupalcode_api "$1" "$2"
}

# Echoes the drupalcode.org project path a checkout came from, like
# "project/drupal". Reads the remote URLs, so it works for whichever project
# is at the root, not just core. Returns 1 when no remote points at drupalcode.
drupalcode_project_path() {
  local dir="$1" remote url
  while read -r remote; do
    url=$(git -C "$dir" remote get-url "$remote" 2>/dev/null) || continue
    if [[ "$url" =~ git\.drupal[a-z]*\.org[:/](project/[a-z0-9_]+)(\.git)?/?$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  done < <(git -C "$dir" remote 2>/dev/null)
  return 1
}

# Echoes the remotes that have a branch, one per line.
remotes_with_branch() {
  local dir="$1" branch="$2" remote
  while read -r remote; do
    if git -C "$dir" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
      echo "$remote"
    fi
  done < <(git -C "$dir" remote)
}

# Echoes the remote that a new local branch should track. Returns 1 when no
# remote has the branch and 2 when several do and none of them stands out.
#
# Drupal issue forks carry the same branch names as the canonical project repo,
# so git's own guess ("git switch 11.x" with no local branch) fails as soon as
# one fork remote is fetched. Forks live under issue/<project>-<nid>, the
# canonical repo under project/<project>, which is what tells them apart.
canonical_remote() {
  local dir="$1" project="$2" branch="$3" candidates remote preferred
  candidates=$(remotes_with_branch "$dir" "$branch")

  if [ -z "$candidates" ]; then
    return 1
  fi

  while read -r remote; do
    if [[ "$(git -C "$dir" remote get-url "$remote")" =~ [:/]project/$project(\.git)?/?$ ]]; then
      echo "$remote"
      return 0
    fi
  done <<< "$candidates"

  # No canonical remote, so fall back to the user's own preference, then origin.
  for preferred in "$(git -C "$dir" config --get checkout.defaultRemote || true)" origin; do
    if [ -n "$preferred" ] && echo "$candidates" | grep -qxF "$preferred"; then
      echo "$preferred"
      return 0
    fi
  done

  # A single candidate is unambiguous, whatever it is called.
  if [ "$(echo "$candidates" | wc -l)" -eq 1 ]; then
    echo "$candidates"
    return 0
  fi

  return 2
}

# Switches a repo to a branch, creating it from the canonical remote when there
# is no local branch of that name yet.
switch_to_branch() {
  local dir="$1" project="$2" branch="$3" remote status git_cmd

  # Nothing to resolve when the branch is already local.
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$dir" switch "$branch"
    return
  fi

  git_cmd="git"
  [ "$dir" = "." ] || git_cmd="git -C $dir"

  remote=$(canonical_remote "$dir" "$project" "$branch") && status=0 || status=$?

  if [ "$status" -eq 1 ]; then
    echo "Error: branch '$branch' is not in this checkout, neither locally nor on"
    echo "any remote you have fetched. If it exists on drupal.org, fetch it first:"
    echo "  $git_cmd fetch --all"
    return 1
  fi

  if [ "$status" -eq 2 ]; then
    echo "Error: several remotes have a branch called '$branch', and none of them"
    echo "looks like the drupal.org repository for '$project':"
    remotes_with_branch "$dir" "$branch" | sed 's/^/  /'
    echo "Pick the one you want:"
    echo "  $git_cmd switch --track <remote>/$branch"
    echo "Or make that choice stick for every ambiguous branch:"
    echo "  $git_cmd config checkout.defaultRemote <remote>"
    return 1
  fi

  git -C "$dir" switch --track "$remote/$branch"
}

# A branch switch or fresh clone can change thousands of files. Let Mutagen
# settle so the container sees them before Composer runs. No-op when Mutagen
# is not in use.
sync_container() {
  ddev mutagen sync >/dev/null 2>&1 || true
}
