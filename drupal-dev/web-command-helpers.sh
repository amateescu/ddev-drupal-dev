# #ddev-generated
# Shared functions for the drupal-dev container commands. Sourced with:
#   . /mnt/ddev_config/drupal-dev/web-command-helpers.sh

# Rewrites the arguments in ARGS with each glob replaced by the paths it matches.
# Tools that take paths rather than globs need this, because a quoted glob
# reaches the command whole instead of being expanded by a shell on the way in.
# A glob that matches nothing is left alone, so the tool reports it rather than
# the run quietly widening to the whole codebase.
#   expand_globs "$@"; set -- "${ARGS[@]}"
expand_globs() {
  local arg restore
  local -a matched
  # Empty IFS keeps a pattern with a space in it in one piece; pathname
  # expansion still hands back one match per element. globstar makes "**" cross
  # directories the way people write it.
  local IFS=
  restore=$(shopt -p globstar)
  shopt -s globstar

  ARGS=()
  for arg in "$@"; do
    case "$arg" in
      -*) ARGS+=("$arg") ;;
      *[*?[]*)
        matched=($arg)
        ARGS+=("${matched[@]}")
        ;;
      *) ARGS+=("$arg") ;;
    esac
  done

  eval "$restore"
}

# Splits arguments into the FLAGS and PATHS arrays, and counts in OPERANDS the
# arguments that are neither an option nor the value of one. The first argument
# lists the options that take a separate value, so the value stays with its flag
# instead of being taken for a path.
#   split_args "-c|--configuration" "$@"
split_args() {
  local value_flags="$1"
  shift

  FLAGS=()
  PATHS=()
  OPERANDS=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*)
        FLAGS+=("$1")
        case "|$value_flags|" in
          *"|$1|"*)
            if [ "$#" -gt 1 ]; then
              FLAGS+=("$2")
              shift
            fi
            ;;
        esac
        ;;
      *)
        OPERANDS=$((OPERANDS + 1))
        # The value of an option missing from the list lands here too, so only
        # take what names something on disk, or a glob, for a path. Anything
        # else stays where it is, next to the option it belongs to.
        if [ -e "$1" ]; then
          PATHS+=("$1")
        else
          case "$1" in
            *[*?[]*) PATHS+=("$1") ;;
            *) FLAGS+=("$1") ;;
          esac
        fi
        ;;
    esac
    shift
  done
}

# Echoes the configuration file that covers a path: the nearest file with one of
# the given names in the path itself or a parent directory, up to the project
# root. This is how the code quality tools find a configuration when contrib CI
# runs them from a project directory. Echoes nothing when there is none.
#   config_for modules/contrib/token phpstan.neon phpstan.neon.dist
config_for() {
  local dir="$1" name
  shift

  [ -d "$dir" ] || dir=$(dirname "$dir")

  # Spell the directory the same way whichever way the path was given, so that
  # paths from one project end up in one group. Lexical only, so that a
  # symlinked directory keeps the parents it was reached through.
  dir=$(realpath -sm --relative-to="${DDEV_APPROOT:-$PWD}" "$dir")

  while :; do
    for name in "$@"; do
      if [ -f "$dir/$name" ]; then
        echo "$dir/$name"
        return
      fi
    done
    case "$dir" in
      . | /) return ;;
    esac
    dir=$(dirname "$dir")
  done
}

# Groups the paths in PATHS by the configuration the given function returns for
# each of them. Fills the CONFIGS array with the configurations, in the order
# they first come up, and the GROUP_PATHS map with the paths of each, one per
# line.
#   group_paths phpstan_config
group_paths() {
  local get_config="$1" path config

  CONFIGS=()
  unset GROUP_PATHS
  declare -gA GROUP_PATHS=()
  for path in "${PATHS[@]}"; do
    config=$("$get_config" "$path")
    [ -n "${GROUP_PATHS[$config]+set}" ] || CONFIGS+=("$config")
    GROUP_PATHS[$config]+="$path"$'\n'
  done
}

# Echoes the paths grouped under a configuration, one per line, for mapfile.
#   mapfile -t group < <(paths_of "$config")
paths_of() {
  printf '%s' "${GROUP_PATHS[$1]}"
}
