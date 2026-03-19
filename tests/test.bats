#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=amateescu/ddev-drupal-dev

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  # Clone Drupal core as the test project
  git clone --depth=1 --branch 11.x https://git.drupalcode.org/project/drupal.git "${TESTDIR}"
  cd "${TESTDIR}"

  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --project-type=drupal11 --php-version=8.3
  assert_success
  run ddev start -y
  assert_success
}

# Install the addon from the local directory and run composer install.
addon_setup() {
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
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
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks

  # --db flag: SQLite works
  run ddev phpunit --db=sqlite core/tests/Drupal/Tests/Core/Access/AccessGroupAndTest.php
  assert_success

  # --db flag: unknown value fails with a helpful message
  run ddev phpunit --db=oracle core/tests/Drupal/Tests/Core/Access/AccessGroupAndTest.php
  assert_failure
  assert_output --partial "Unknown database type"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "module management" {
  set -eu -o pipefail
  addon_setup

  # Rejects invalid module name
  run ddev add-module Invalid-Name
  assert_failure
  assert_output --partial "Invalid module name"

  # Clones and requires a contrib module (auto-detect branch)
  run ddev add-module --https token
  assert_success
  assert_file_exists "${TESTDIR}/modules/contrib/token/token.info.yml"
  assert_git_checkout "${TESTDIR}/modules/contrib/token"

  # composer update preserves the git checkout
  run ddev composer update
  assert_success
  assert_git_checkout "${TESTDIR}/modules/contrib/token"

  # Path repository was registered and module is installed
  run grep -q "modules/contrib/token" "${TESTDIR}/composer.local.json"
  assert_success
  run ddev composer show drupal/token
  assert_success

  # Rejects a non-git directory at the install path
  run ddev exec -- mkdir -p modules/contrib/fakemodule
  assert_success
  run ddev add-module --https fakemodule
  assert_failure
  assert_output --partial "not a git checkout"
  run ddev exec -- rmdir modules/contrib/fakemodule
  assert_success

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

@test "addon removal" {
  set -eu -o pipefail
  addon_setup

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
  run ddev add-on remove drupal-dev
  assert_success
  refute_output --partial "Unwilling to remove"
  assert_file_not_exists "${TESTDIR}/composer.local.json"
  assert_file_not_exists "${TESTDIR}/composer.local.lock"
  assert_file_not_exists "${TESTDIR}/.envrc"
  assert_file_not_exists "${TESTDIR}/.gitignore"
  assert_file_not_exists "${TESTDIR}/.ddev/drupal-dev"
  assert_file_not_exists "${TESTDIR}/.ddev/config.drupal-dev.yaml"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/host/phpunit"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/web/add-module"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/web/remove-module"
  assert_file_not_exists "${TESTDIR}/.ddev/commands/web/update-module"
}
