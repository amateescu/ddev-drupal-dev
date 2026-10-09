#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# CI runs "module management", tagged "modules", in a job of its own next to a
# job for the rest. To run what one of them runs for a pull request:
#   bats ./tests/test.bats --filter-tags 'modules,!release'
#   bats ./tests/test.bats --filter-tags '!modules,!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

# All tests share one project, a core clone with the add-on installed from the
# local directory. Starting a project, installing the add-on and running
# composer install take most of a minute, so this runs once instead of before
# every test. setup() resets what the tests change.
setup_file() {
  set -eu -o pipefail

  export GITHUB_REPO=amateescu/ddev-drupal-dev

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  load_libraries

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  # Ignore Composer security advisories in tests
  export COMPOSER_NO_SECURITY_BLOCKING=1

  create_project "${TESTDIR}" "${PROJNAME}"

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in ${TESTDIR}" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  run ddev composer install
  assert_success

  # Keep a copy of the Composer files that tests change, for setup() to put
  # back.
  cp composer.local.json composer.local.lock "${BATS_FILE_TMPDIR}/"
}

setup() {
  set -eu -o pipefail
  load_libraries
  cd "${TESTDIR}"
  reset_project
}

# setup_file and each test run in separate processes, and only exported
# variables carry over, so both load the libraries.
load_libraries() {
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support
}

# Clones Drupal core into a directory and starts a DDEV project there.
# Usage: create_project <dir> <project name>.
create_project() {
  ddev delete -Oy "$2" >/dev/null 2>&1 || true
  git clone --depth=1 --branch 11.x https://git.drupalcode.org/project/drupal.git "$1"
  cd "$1"
  run ddev config --project-name="$2" --project-tld=ddev.site --project-type=drupal11 --php-version=8.3
  assert_success
  run ddev start -y
  assert_success
}

# Puts the shared project back the way setup_file left it, so a test does not
# depend on what the tests before it did, or on whether they passed.
reset_project() {
  # "addon removal" uninstalls the add-on. It runs last, so this only kicks in
  # when tests run in another order.
  if [ ! -f .ddev/config.drupal-dev.yaml ]; then
    run ddev add-on get "${DIR}"
    assert_success
    run ddev restart -y
    assert_success
  fi

  # Restore core's tracked files and remove everything under modules/, where
  # tests put their modules and clones. The project root is not cleaned,
  # because without the add-on's .gitignore that would delete .ddev and vendor
  # too.
  git checkout -q -- .
  git clean -ffdxq -- modules

  cp "${BATS_FILE_TMPDIR}/composer.local.json" "${BATS_FILE_TMPDIR}/composer.local.lock" .
  run ddev composer install
  assert_success
}

# Assert that a directory is a proper Drupal git checkout: not in detached HEAD,
# no composer remote, and HTTPS origin from drupalcode.org. Pass an expected
# branch as the second argument to also assert the current branch name.
assert_git_checkout() {
  local dir="$1"
  local expected_branch="${2:-}"
  run git -C "${dir}" symbolic-ref --short HEAD
  assert_success
  [[ -n "${expected_branch}" ]] && assert_output "${expected_branch}"
  run git -C "${dir}" remote get-url composer
  assert_failure
  run git -C "${dir}" remote get-url origin
  assert_success
  assert_output --partial "https://git.drupalcode.org"
}

# Print the locked version of a package, looking in both the prod and dev
# sections of a composer.lock. Usage: locked_version <lock file> <package>.
locked_version() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(next(p['version'] for s in ('packages','packages-dev') for p in d.get(s,[]) if p['name']==sys.argv[2]))" "$1" "$2"
}

health_checks() {
  # Verify composer.local.json exists in project root
  assert_file_exists "${TESTDIR}/composer.local.json"

  # Verify .envrc exists in project root
  assert_file_exists "${TESTDIR}/.envrc"

  # Verify config.drupal-dev.yaml sets the COMPOSER env var
  run ddev exec 'echo $COMPOSER'
  assert_success
  assert_output "composer.local.json"

  # Verify ddev composer install succeeds
  run ddev composer install
  assert_success

  # Verify the core checkout is clean (no modified or untracked files)
  run bash -c "cd ${TESTDIR} && git status --porcelain 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"

  # Verify .gitignore was created by the add-on
  assert_file_exists "${TESTDIR}/.gitignore"
  run grep -q "#ddev-generated" "${TESTDIR}/.gitignore"
  assert_success

  # Verify the MariaDB compose example is installed but not active
  assert_file_exists "${TESTDIR}/.ddev/drupal-dev/docker-compose.mariadb.yaml.example"
  assert_file_not_exists "${TESTDIR}/.ddev/docker-compose.mariadb.yaml"

  # Verify the cheat sheet was copied and is gitignored
  assert_file_exists "${TESTDIR}/DRUPAL-DEV.md"
  run grep -qxF "/DRUPAL-DEV.md" "${TESTDIR}/.gitignore"
  assert_success

  # Verify the code quality commands work
  run ddev phpstan core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  run ddev phpcs core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success

  # cspell needs core's node dependencies, which are not installed here, so
  # verify the helpful error message instead.
  run ddev cspell composer.json
  assert_failure
  assert_output --partial "cspell is not installed"

  # Verify ddev phpunit works across all test types
  run ddev phpunit core/tests/Drupal/Tests/Core/Access/AccessGroupAndTest.php
  assert_success
  run ddev phpunit --filter=testSetUp core/tests/Drupal/KernelTests/KernelTestBaseTest.php
  assert_success
  run ddev phpunit --filter=testDrupalSettings core/tests/Drupal/FunctionalTests/BrowserTestBaseTest.php
  assert_success
  run ddev phpunit core/modules/announcements_feed/tests/src/FunctionalJavascript/AnnounceBlockTest.php
  assert_success
}

teardown() {
  # Only the release test makes a project of its own.
  if [ -n "${RELEASE_TESTDIR:-}" ]; then
    ddev delete -Oy "${RELEASE_PROJNAME}" >/dev/null 2>&1 || true
    rm -rf "${RELEASE_TESTDIR}"
  fi
}

teardown_file() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  # setup_file installed the add-on from the local directory.
  health_checks

  # A project with no configuration of its own is checked with core's, which
  # reports the missing return type and the missing class doc comment through
  # core's own rules.
  mkdir -p "${TESTDIR}/modules/custom/stantest/src"
  cat > "${TESTDIR}/modules/custom/stantest/src/Example.php" <<'EOF'
<?php

namespace Drupal\stantest;

class Example {

  public function value() {
    return 1;
  }

}
EOF
  run ddev phpstan modules/custom/stantest
  assert_failure
  assert_output --partial "no return type specified"
  run ddev phpcs modules/custom/stantest
  assert_failure
  assert_output --partial "Missing class doc comment"

  # A quoted glob reaches the command whole, so it is expanded before the tools
  # see it: they take paths, not globs. '**' crosses directories.
  run ddev phpcs 'modules/custom/stantest/src/*.php'
  assert_failure
  assert_output --partial "Missing class doc comment"
  run ddev phpstan 'modules/custom/**/*.php'
  assert_failure
  assert_output --partial "no return type specified"

  # Paths are relative to the directory the command runs from, and a run
  # without paths checks that directory instead of the whole codebase.
  cd "${TESTDIR}/modules/custom/stantest"
  run ddev phpstan
  assert_failure
  assert_output --partial "no return type specified"
  run ddev phpcs src
  assert_failure
  assert_output --partial "Missing class doc comment"
  run ddev phpcs
  assert_failure
  assert_output --partial "Missing class doc comment"

  # The directory a run without paths checks is not taken for the value of an
  # option at the end, so the baseline gets its default name.
  run ddev phpstan --generate-baseline
  assert_success
  assert_file_exists "${TESTDIR}/modules/custom/stantest/phpstan-baseline.neon"
  rm "${TESTDIR}/modules/custom/stantest/phpstan-baseline.neon"
  cd "${TESTDIR}"

  # A project with its own configuration is checked with it, from any path
  # inside the project.
  printf 'parameters:\n  level: 0\n' > "${TESTDIR}/modules/custom/stantest/phpstan.neon"
  printf '<ruleset name="stantest"><rule ref="Generic.PHP.LowerCaseKeyword"/></ruleset>\n' > "${TESTDIR}/modules/custom/stantest/phpcs.xml"
  run ddev phpstan modules/custom/stantest
  assert_success
  run ddev phpstan modules/custom/stantest/src/Example.php
  assert_success
  run ddev phpcs modules/custom/stantest
  assert_success
  run ddev phpcs modules/custom/stantest/src/Example.php
  assert_success

  # An option value that comes as a separate argument is not taken for a path,
  # and a path spelled differently still lands in the same group. Both would
  # split a single project's run in two, which prints one header per group.
  run ddev phpstan --level 0 modules/custom/stantest
  assert_success
  refute_output --partial "Analysing with"
  run ddev phpstan ./core/lib/Drupal/Core/Entity/EntityInterface.php core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  refute_output --partial "Analysing with"
  run ddev phpcs -d memory_limit=256M modules/custom/stantest
  assert_success
  refute_output --partial "Checking with"

  # Paths from several projects are checked one project at a time.
  run ddev phpstan modules/custom/stantest core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "modules/custom/stantest/phpstan.neon"
  assert_output --partial "core/phpstan-partial.neon"
  run ddev phpcs modules/custom/stantest core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "modules/custom/stantest/phpcs.xml"
  assert_output --partial "core/phpcs.xml.dist"

  # From inside a project, the paths in the messages are relative to it.
  cd "${TESTDIR}/modules/custom/stantest"
  run ddev phpstan . ../../../core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "Analysing with phpstan.neon"
  assert_output --partial "Analysing with ../../../core/phpstan-partial.neon"
  run ddev phpcs . ../../../core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "Checking with phpcs.xml"
  assert_output --partial "Checking with ../../../core/phpcs.xml.dist"
  cd "${TESTDIR}"

  # A failing project in a run of several does not go unnoticed.
  mkdir -p "${TESTDIR}/modules/custom/badtest"
  printf '<?php\n\nclass Bad {}\n' > "${TESTDIR}/modules/custom/badtest/Bad.php"
  run ddev phpcs modules/custom/stantest modules/custom/badtest
  assert_failure
  assert_output --partial "Missing class doc comment"
  rm -rf "${TESTDIR}/modules/custom"

  # A .gitlab-ci.yml marks a contrib project, and one without a configuration of
  # its own is checked with the default one contrib CI uses. Contrib CI's PHP
  # CodeSniffer standard checks the line length of comments in tests, where
  # core's does not. Contrib CI's PHPStan configuration runs at level 0, where
  # core's runs at level 1 and reports a variable that might not be defined.
  project="${TESTDIR}/modules/contrib/contribtest"
  mkdir -p "${project}/src" "${project}/tests/src"
  cat > "${project}/tests/src/Example.php" <<'EOF'
<?php

declare(strict_types=1);

namespace Drupal\Tests\contribtest;

/**
 * Checks the line length of comments in tests.
 */
class Example {

  /**
   * Returns a value.
   */
  public function value(): int {
    // This comment is one character longer than the line length limit allows it.
    return 1;
  }

}
EOF
  cat > "${project}/src/Plain.php" <<'EOF'
<?php

declare(strict_types=1);

namespace Drupal\contribtest;

/**
 * Returns a value that is not always set.
 */
class Plain {

  /**
   * Returns a value.
   */
  public function value(bool $set): int {
    if ($set) {
      $value = 1;
    }
    return $value;
  }

}
EOF
  run ddev phpcs modules/contrib/contribtest
  assert_success
  run ddev phpstan modules/contrib/contribtest
  assert_failure
  assert_output --partial "might not be defined"
  printf 'include: []\n' > "${project}/.gitlab-ci.yml"
  run ddev phpcs modules/contrib/contribtest
  assert_failure
  assert_output --partial "Line exceeds 80 characters"
  run ddev phpstan modules/contrib/contribtest
  assert_success

  # PHPStan runs at the level _PHPSTAN_LEVEL names, and the default
  # configuration takes in the project's baseline.
  printf 'variables:\n  _PHPSTAN_LEVEL: 1\n' > "${project}/.gitlab-ci.yml"
  run ddev phpstan modules/contrib/contribtest
  assert_failure
  assert_output --partial "might not be defined"

  # The same from inside the project.
  cd "${project}"
  run ddev phpstan
  assert_failure
  assert_output --partial "might not be defined"
  cd "${TESTDIR}"

  printf 'parameters:\n  ignoreErrors:\n    - identifier: variable.undefined\n' > "${project}/phpstan-baseline.neon"
  run ddev phpstan modules/contrib/contribtest
  assert_success

  # Core has a .gitlab-ci.yml too, but its files keep core's configuration.
  run ddev phpcs modules/contrib/contribtest core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_failure
  assert_output --partial "Checking with /mnt/ddev_config/drupal-dev/phpcs.contrib.xml.dist"
  assert_output --partial "Checking with core/phpcs.xml.dist"
  run ddev phpstan modules/contrib/contribtest core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "Analysing modules/contrib/contribtest with /mnt/ddev_config/drupal-dev/phpstan.contrib.neon at level 1"
  assert_output --partial "Analysing with core/phpstan-partial.neon"
  rm -rf "${TESTDIR}/modules/contrib"

  # Web commands keep argument boundaries too, so a path with a space in it
  # reaches the tool as one path instead of being split at the space.
  run ddev phpcs "modules/custom/no such path"
  assert_failure
  assert_output --partial 'The file "modules/custom/no such path" does not exist'

  # A glob that matches nothing stays as it is, so the tool reports it instead
  # of the run quietly widening to the whole codebase.
  run ddev phpcs 'modules/custom/nope/*.php'
  assert_failure
  assert_output --partial 'The file "modules/custom/nope/*.php" does not exist'

  # Test paths are relative to the directory the command runs from. The SQLite
  # database path is relative to the Drupal root, which the test changes to.
  cd "${TESTDIR}/core/modules/link"
  run ddev phpunit --db=sqlite tests/src/Kernel/LinkItemTest.php
  assert_success
  cd "${TESTDIR}"

  # --db flag: SQLite works
  run ddev phpunit --db=sqlite core/tests/Drupal/Tests/Core/Access/AccessGroupAndTest.php
  assert_success

  # --db flag: MariaDB uses the project database, DDEV's default. A Kernel test
  # so the run actually connects to it.
  run ddev phpunit --db=mariadb --filter=testSetUp core/tests/Drupal/KernelTests/KernelTestBaseTest.php
  assert_success
  assert_output --partial "Using database: mariadb"

  # Tab completion offers the --db values for a flag, and nothing for a path so
  # the shell completes files
  run ddev __complete phpunit --d
  assert_success
  assert_line -- --db=mariadb
  run ddev __complete phpunit core/
  assert_success
  refute_line --partial -- --db=

  # --db flag: unknown value fails with a helpful message
  run ddev phpunit --db=oracle core/tests/Drupal/Tests/Core/Access/AccessGroupAndTest.php
  assert_failure
  assert_output --partial "Unknown database type"

  # Arguments reach PHPUnit whole: the alternation stays inside --filter instead
  # of turning into a shell pipe in the container.
  run ddev phpunit --filter 'testConstruction|testCacheMaxAge' core/tests/Drupal/Tests/Core/Access/AccessResultTest.php
  assert_success
  assert_output --partial "OK (2 tests"

  # commit-code-check finds core's script and passes flags through to it
  run ddev commit-code-check --help
  assert_success
  assert_output --partial "Drupal code quality checks"

  # The checkout is clean here, so the script has nothing to check. Running the
  # actual checks would need core's node dependencies.
  run ddev commit-code-check
  assert_success
  assert_output --partial "There are no files to check"

  # The project at the root is read from its remotes rather than assumed to be
  # core, which is what lets a distribution checkout resolve its own repository.
  run bash -c ". '${TESTDIR}/.ddev/drupal-dev/command-helpers.sh' && drupalcode_project_path '${TESTDIR}'"
  assert_success
  assert_output "project/drupal"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  # The release goes on a project of its own, so the shared project keeps the
  # add-on from the local directory.
  RELEASE_PROJNAME="${PROJNAME}-release"
  RELEASE_TESTDIR="$(mktemp -d "${HOME}/tmp/${RELEASE_PROJNAME}.XXXXXX")"
  TESTDIR="${RELEASE_TESTDIR}"
  create_project "${TESTDIR}" "${RELEASE_PROJNAME}"
  echo "# ddev add-on get ${GITHUB_REPO} with project ${RELEASE_PROJNAME} in ${TESTDIR}" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=modules
@test "module management" {
  set -eu -o pipefail

  # Rejects invalid module name
  run ddev add-module Invalid-Name
  assert_failure
  assert_output --partial "Invalid module name"

  # Clones and requires a contrib module (auto-detect branch)
  run ddev add-module --https token
  assert_success
  assert_file_exists "${TESTDIR}/modules/contrib/token/token.info.yml"
  assert_git_checkout "${TESTDIR}/modules/contrib/token"

  # Tab completion lists the cloned module and the branches of a checkout
  run ddev __complete remove-module ''
  assert_success
  assert_line token
  run ddev __complete switch ''
  assert_success
  assert_line core
  assert_line token
  run ddev __complete switch --pull token ''
  assert_success
  assert_line 8.x-1.x
  run ddev __complete switch core ''
  assert_success
  assert_line 11.x
  # Host completion scripts get no DDEV_APPROOT, so they find the project root
  # from their own path. Completing from a subdirectory checks that.
  cd "${TESTDIR}/modules/contrib/token"
  run ddev __complete mr ''
  assert_success
  assert_line token
  cd "${TESTDIR}"

  # The overlay holds user-specific config now, so the generated marker is gone.
  run grep -q "#ddev-generated" "${TESTDIR}/composer.local.json"
  assert_failure

  # composer update preserves the git checkout
  run ddev composer update
  assert_success
  assert_git_checkout "${TESTDIR}/modules/contrib/token"

  # Path repository was registered and module is installed
  run grep -q "modules/contrib/token" "${TESTDIR}/composer.local.json"
  assert_success
  run ddev composer show drupal/token
  assert_success

  # mr: resolves a merge request number, adds the fork remote, checks out its
  # branch and points the constraint at the path repository. 133 is merged, so
  # what it resolves to does not drift.
  run ddev mr --https token 133
  assert_success
  assert_output --partial "3609143-do-not-load -> 8.x-1.x"
  run git -C "${TESTDIR}/modules/contrib/token" symbolic-ref --short HEAD
  assert_output "3609143-do-not-load"
  # The constraint tracks the branch the merge request targets, because that is
  # the one drupal.org publishes a dev version for. Requiring the merge request
  # branch itself cannot resolve: the drupal.org repository is canonical and
  # outranks the path repository.
  run grep -o '"drupal/token": "[^"]*"' "${TESTDIR}/composer.local.json"
  assert_output --partial "1.x-dev"
  run ddev composer show drupal/token
  assert_success

  # Only the merge request branch is fetched from the fork. A fork carries a
  # copy of every branch, and those copies would make 'ddev switch' ambiguous.
  run git -C "${TESTDIR}/modules/contrib/token" for-each-ref --format='%(refname)' 'refs/remotes/token-3609143/*'
  assert_output "refs/remotes/token-3609143/3609143-do-not-load"

  # mr: an issue number and a merge request URL reach the same merge request
  git -C "${TESTDIR}/modules/contrib/token" switch -q 8.x-1.x
  run ddev mr --https token 3609143
  assert_success
  assert_output --partial "Merge request !133"
  git -C "${TESTDIR}/modules/contrib/token" switch -q 8.x-1.x
  run ddev mr --https https://git.drupalcode.org/project/token/-/merge_requests/133
  assert_success
  assert_output --partial "Merge request !133"
  git -C "${TESTDIR}/modules/contrib/token" switch -q 8.x-1.x
  run ddev mr --https https://www.drupal.org/project/token/issues/3609143
  assert_success
  assert_output --partial "Merge request !133"

  # mr: a number that is neither a merge request nor an issue
  run ddev mr token 99999999
  assert_failure
  assert_output --partial "no merge request 99999999"

  # mr: usage and argument checks
  run ddev mr
  assert_failure
  assert_output --partial "Usage: ddev mr"
  run ddev mr Bad-Name 1
  assert_failure
  assert_output --partial "Invalid module name"
  run ddev mr token abc
  assert_failure
  assert_output --partial "is not a merge request or issue number"

  # Put token back on its release branch for the checks below.
  run ddev switch token 8.x-1.x
  assert_success

  # Rejects a non-git directory at the install path
  mkdir -p "${TESTDIR}/modules/contrib/fakemodule"
  run ddev add-module --https fakemodule
  assert_failure
  assert_output --partial "not a git checkout"
  rmdir "${TESTDIR}/modules/contrib/fakemodule"

  # remove-module aborts when there are uncommitted changes
  echo 'dirty' > "${TESTDIR}/modules/contrib/token/dirty.txt"
  run ddev remove-module token
  assert_failure
  assert_output --partial "uncommitted or untracked"
  rm "${TESTDIR}/modules/contrib/token/dirty.txt"

  # remove-module cleans up a module
  run ddev remove-module token
  assert_success
  assert_file_not_exists "${TESTDIR}/modules/contrib/token"
  run grep -q "modules/contrib/token" "${TESTDIR}/composer.local.json"
  assert_failure
  run ddev composer show drupal/token
  assert_failure

  # Clones with a specific branch
  run ddev add-module --https redirect 8.x-1.x
  assert_success
  assert_file_exists "${TESTDIR}/modules/contrib/redirect/redirect.info.yml"
  assert_git_checkout "${TESTDIR}/modules/contrib/redirect" "8.x-1.x"

  # update-module: clone wse on 3.0.x, switch to 2.0.x, update constraint
  run ddev add-module --https wse 3.0.x
  assert_success

  # The jq program that reads require-dev is full of pipes, so this list only
  # shows up when the program reaches the container in one piece.
  assert_output --partial "Dev dependencies (not installed)"
  assert_output --partial "ddev add-module trash"

  run git -C "${TESTDIR}/modules/contrib/wse" symbolic-ref --short HEAD
  assert_output "3.0.x"
  run grep -o '"drupal/wse": "[^"]*"' "${TESTDIR}/composer.local.json"
  assert_output --partial "3.0.x-dev"

  git -C "${TESTDIR}/modules/contrib/wse" checkout 2.0.x
  run ddev update-module wse
  assert_success
  run grep -o '"drupal/wse": "[^"]*"' "${TESTDIR}/composer.local.json"
  assert_output --partial "2.0.x-dev"
  run git -C "${TESTDIR}/modules/contrib/wse" symbolic-ref --short HEAD
  assert_output "2.0.x"

  # switch: shows usage when the branch is missing
  run ddev switch wse
  assert_failure
  assert_output --partial "Usage: ddev switch"

  # switch: checks out the branch and updates the constraint in one step
  run ddev switch wse 3.0.x
  assert_success
  run git -C "${TESTDIR}/modules/contrib/wse" symbolic-ref --short HEAD
  assert_output "3.0.x"
  run grep -o '"drupal/wse": "[^"]*"' "${TESTDIR}/composer.local.json"
  assert_output --partial "3.0.x-dev"

  # switch --pull: catches up a branch that is behind. Rewinding the local
  # branch puts the checkout in the same state as one left alone for weeks.
  git -C "${TESTDIR}/modules/contrib/wse" reset -q --hard HEAD~1
  run ddev switch --pull wse 3.0.x
  assert_success
  assert_output --partial "Fetching 3.0.x from origin"
  assert_output --partial "Fast-forwarded 3.0.x"
  # Compare against the tracking ref rather than a tip recorded before the
  # fetch. A commit pushed to 3.0.x while the test runs would move both.
  WSE_TIP=$(git -C "${TESTDIR}/modules/contrib/wse" rev-parse refs/remotes/origin/3.0.x)
  run git -C "${TESTDIR}/modules/contrib/wse" rev-parse HEAD
  assert_output "${WSE_TIP}"

  # switch: a flag only counts before the project name
  run ddev switch wse 3.0.x --pull
  assert_failure
  assert_output --partial "Usage: ddev switch"

  # switch: rejects an unknown option
  run ddev switch --nope wse 3.0.x
  assert_failure
  assert_output --partial "Unknown option"

  # switch: rejects a module that was never cloned
  run ddev switch nonexistent 1.0.x
  assert_failure
  assert_output --partial "is not a git checkout"

  # switch: picks the canonical remote when issue forks carry the same branch
  # names. Faking a fork remote is enough: the URL namespace tells forks apart
  # from the project repo, and the tracking ref is all a branch switch reads.
  git -C "${TESTDIR}/modules/contrib/wse" branch -D 2.0.x
  git -C "${TESTDIR}/modules/contrib/wse" remote add drupal-123456 https://git.drupalcode.org/issue/wse-123456.git
  git -C "${TESTDIR}/modules/contrib/wse" update-ref refs/remotes/drupal-123456/2.0.x refs/remotes/origin/2.0.x

  # Plain git cannot resolve the branch any more.
  run git -C "${TESTDIR}/modules/contrib/wse" switch 2.0.x
  assert_failure
  assert_output --partial "matched multiple"

  run ddev switch wse 2.0.x
  assert_success
  run git -C "${TESTDIR}/modules/contrib/wse" rev-parse --abbrev-ref '@{upstream}'
  assert_output "origin/2.0.x"

  # Drop the fake fork, and leave 2.0.x unoccupied for the worktree below.
  git -C "${TESTDIR}/modules/contrib/wse" remote remove drupal-123456
  git -C "${TESTDIR}/modules/contrib/wse" switch 3.0.x

  # Worktree checkouts work: .git is a file, not a directory
  mv "${TESTDIR}/modules/contrib/wse" "${TESTDIR}/wse-main"
  git -C "${TESTDIR}/wse-main" worktree add "${TESTDIR}/modules/contrib/wse" 2.0.x
  assert [ -f "${TESTDIR}/modules/contrib/wse/.git" ]
  run ddev update-module wse
  assert_success
  run grep -o '"drupal/wse": "[^"]*"' "${TESTDIR}/composer.local.json"
  assert_output --partial "2.0.x-dev"

  # remove-module guards a dirty worktree, then prunes it from the main repo
  echo 'dirty' > "${TESTDIR}/modules/contrib/wse/dirty.txt"
  run ddev remove-module wse
  assert_failure
  assert_output --partial "uncommitted or untracked"
  rm "${TESTDIR}/modules/contrib/wse/dirty.txt"
  run ddev remove-module wse
  assert_success
  assert_file_not_exists "${TESTDIR}/modules/contrib/wse"
  run git -C "${TESTDIR}/wse-main" worktree list
  refute_output --partial "modules/contrib/wse"
  rm -rf "${TESTDIR}/wse-main"

  # Custom installer-paths: modules/ instead of modules/contrib/
  run ddev composer config extra.installer-paths.modules/\{\$name\} '["type:drupal-module"]' --json
  assert_success
  run ddev add-module --https token
  assert_success
  assert_file_exists "${TESTDIR}/modules/token/token.info.yml"
  assert_file_not_exists "${TESTDIR}/modules/contrib/token"
  run grep -q '"modules/token"' "${TESTDIR}/composer.local.json"
  assert_success
  run ddev composer show drupal/token
  assert_success
  run ddev remove-module token
  assert_success
  assert_file_not_exists "${TESTDIR}/modules/token"
}

@test "pin-core-lock" {
  set -eu -o pipefail

  # Flag off (default): no pinning hint on a fresh solve.
  rm -f "${TESTDIR}/composer.local.lock"
  run ddev composer install
  assert_success
  refute_output --partial "Core lock pinning active"

  # Enable the flag.
  run ddev composer config --json extra.drupal-dev '{"pin-core-lock":true}'
  assert_success

  # Pinning applies during a fresh solve and a shared package matches core's lock.
  rm -f "${TESTDIR}/composer.local.lock"
  run ddev composer install
  assert_success
  assert_output --partial "Core lock pinning active"
  [ "$(locked_version "${TESTDIR}/composer.lock" symfony/error-handler)" = "$(locked_version "${TESTDIR}/composer.local.lock" symfony/error-handler)" ]

  # Packages from core's require-dev are pinned too, not just require.
  [ "$(locked_version "${TESTDIR}/composer.lock" mglaman/phpstan-drupal)" = "$(locked_version "${TESTDIR}/composer.local.lock" mglaman/phpstan-drupal)" ]

  # Direct conflict: overlay require incompatible with the locked version
  # triggers the pre-check error and aborts before the solver runs.
  python3 - <<'PY'
import json, os
path = os.path.join(os.environ['TESTDIR'], 'composer.local.json')
data = json.load(open(path))
data.setdefault('require', {})['guzzlehttp/promises'] = '^1'
json.dump(data, open(path, 'w'), indent=4)
PY
  rm -f "${TESTDIR}/composer.local.lock"
  run ddev composer install
  assert_failure
  assert_output --partial "Core lock pinning conflict"

  # Revert the conflict so the next assertions exercise unrelated paths.
  python3 - <<'PY'
import json, os
path = os.path.join(os.environ['TESTDIR'], 'composer.local.json')
data = json.load(open(path))
data.get('require', {}).pop('guzzlehttp/promises', None)
json.dump(data, open(path, 'w'), indent=4)
PY

  # Missing core lock with pinning enabled fails loudly instead of silently
  # falling back to a fresh solve.
  mv "${TESTDIR}/composer.lock" "${TESTDIR}/composer.lock.bak"
  rm -f "${TESTDIR}/composer.local.lock"
  run ddev composer install
  assert_failure
  assert_output --partial "Core lock pinning is enabled"
  mv "${TESTDIR}/composer.lock.bak" "${TESTDIR}/composer.lock"

  # Dev refs (when present in core's lock) are pinned to the locked SHA so
  # the overlay's composer.local.lock records the same source reference.
  # Match Composer's notion of dev: dev- prefix or -dev suffix on the version.
  dev_package=$(python3 - <<'PY'
import json, os
d = json.load(open(os.path.join(os.environ['TESTDIR'], 'composer.lock')))
for p in d.get('packages', []) + d.get('packages-dev', []):
    v = p.get('version', '')
    if (v.startswith('dev-') or v.endswith('-dev')) and p.get('source', {}).get('reference'):
        print(p['name'])
        break
PY
)
  if [ -n "${dev_package}" ]; then
    rm -f "${TESTDIR}/composer.local.lock"
    run ddev composer install
    assert_success
    core_sha=$(python3 -c "import json, os; d=json.load(open(os.path.join(os.environ['TESTDIR'],'composer.lock'))); pkg=next(p for p in d['packages']+d.get('packages-dev',[]) if p['name']=='${dev_package}'); print(pkg['source']['reference'])")
    overlay_sha=$(python3 -c "import json, os; d=json.load(open(os.path.join(os.environ['TESTDIR'],'composer.local.lock'))); pkg=next(p for p in d['packages']+d.get('packages-dev',[]) if p['name']=='${dev_package}'); print(pkg['source']['reference'])")
    [ "${core_sha}" = "${overlay_sha}" ]
  fi
}

@test "config-platform" {
  set -eu -o pipefail

  if ! python3 -c "import json, sys; sys.exit(0 if json.load(open('${TESTDIR}/composer.json')).get('config', {}).get('platform') else 1)"; then
    skip "core composer.json does not declare config.platform"
  fi

  # config.platform must stay out of composer.local.json. A platform there
  # constrains the solver and install-time checks for the whole overlay, so
  # packages needing a newer PHP than core's minimum become uninstallable.
  run python3 -c "import json; print('platform' in json.load(open('${TESTDIR}/composer.local.json')).get('config', {}))"
  assert_output "False"

  # PHPStan still analyses against core's declared version, because the command
  # points it at core's composer.json. -vvv emits
  # "PHP version for analysis: X.Y (from config.platform.php in composer.json)"
  core_platform=$(python3 -c "import json; print(json.load(open('${TESTDIR}/composer.json'))['config']['platform']['php'])")
  run ddev phpstan -vvv core/lib/Drupal/Core/Entity/EntityInterface.php
  assert_success
  assert_output --partial "PHP version for analysis: ${core_platform%.*} (from config.platform.php"

  # A config.platform left behind by an older version of the add-on, which
  # mirrored core's value into the overlay, is removed on the next composer run.
  python3 -c "
import json
core = json.load(open('${TESTDIR}/composer.json'))['config']['platform']
p = '${TESTDIR}/composer.local.json'
d = json.load(open(p))
d.setdefault('config', {})['platform'] = core
json.dump(d, open(p, 'w'), indent=4)
"
  run ddev composer show drupal/core
  assert_success
  assert_output --partial "Removed config.platform"
  run python3 -c "import json; print('platform' in json.load(open('${TESTDIR}/composer.local.json')).get('config', {}))"
  assert_output "False"

  # A platform the user set themselves is left alone.
  python3 -c "
import json
p = '${TESTDIR}/composer.local.json'
d = json.load(open(p))
d.setdefault('config', {})['platform'] = {'php': '8.3.99'}
json.dump(d, open(p, 'w'), indent=4)
"
  run ddev composer show drupal/core
  assert_success
  overlay_platform=$(python3 -c "import json; print(json.load(open('${TESTDIR}/composer.local.json'))['config']['platform']['php'])")
  [ "${overlay_platform}" = "8.3.99" ]
  python3 -c "
import json
p = '${TESTDIR}/composer.local.json'
d = json.load(open(p))
d['config'].pop('platform')
json.dump(d, open(p, 'w'), indent=4)
"
}

# Runs last, because it leaves the add-on uninstalled and the next test would
# have to install it again.
@test "addon removal" {
  set -eu -o pipefail

  # Customized composer.local.json (marker stripped) is preserved on removal
  sed -i '/"_comment": "#ddev-generated"/d' "${TESTDIR}/composer.local.json"
  run grep -q "#ddev-generated" "${TESTDIR}/composer.local.json"
  assert_failure
  run ddev add-on remove drupal-dev
  assert_success
  assert_file_exists "${TESTDIR}/composer.local.json"

  # Re-install with an unmodified composer.local.json (remove the customized
  # one first so the post-install action copies a fresh copy with the marker)
  rm "${TESTDIR}/composer.local.json"
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  run ddev composer install
  assert_success

  # Unmodified files are all cleaned up on removal
  assert_file_exists "${TESTDIR}/composer.local.json"
  assert_file_exists "${TESTDIR}/.envrc"
  assert_file_exists "${TESTDIR}/DRUPAL-DEV.md"
  run ddev add-on remove drupal-dev
  assert_success
  refute_output --partial "Unwilling to remove"
  assert_file_not_exists "${TESTDIR}/composer.local.json"
  assert_file_not_exists "${TESTDIR}/composer.local.lock"
  assert_file_not_exists "${TESTDIR}/.envrc"
  assert_file_not_exists "${TESTDIR}/.gitignore"
  assert_file_not_exists "${TESTDIR}/DRUPAL-DEV.md"
  assert_file_not_exists "${TESTDIR}/.ddev/drupal-dev"
  assert_file_not_exists "${TESTDIR}/.ddev/config.drupal-dev.yaml"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/phpunit"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/add-module"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/remove-module"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/update-module"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/switch"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/mr"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/autocomplete/switch"
}
