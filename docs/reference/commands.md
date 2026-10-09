# Commands

| Command | Description |
| ------- | ----------- |
| [`ddev add-module`](#ddev-add-module) | Clone a contrib module for development |
| [`ddev switch`](#ddev-switch) | Switch core or a module to a branch and update dependencies |
| [`ddev mr`](#ddev-mr) | Check out a merge request branch and update dependencies |
| [`ddev update-module`](#ddev-update-module) | Update a module's Composer constraint after switching its branch |
| [`ddev remove-module`](#ddev-remove-module) | Remove a cloned contrib module |
| [`ddev phpunit`](#ddev-phpunit) | Run PHPUnit tests |
| [`ddev phpstan`](#ddev-phpstan) | Run PHPStan with the configuration of the checked project |
| [`ddev phpcs`](#ddev-phpcs) | Run PHP CodeSniffer with the standard of the checked project |
| [`ddev cspell`](#ddev-cspell) | Run cspell with the configuration of the checked project |
| [`ddev commit-code-check`](#ddev-commit-code-check) | Run core's pre-commit checks on your changed files |

Run any of the module and branch commands without arguments to print its usage.

## `ddev add-module`

```
ddev add-module [--https] <module> [branch]
```

Clones a drupal.org project into `modules/contrib/<module>`, registers it as a path repository in `composer.local.json` and requires the dev version that matches the branch.

| Option | Description |
| ------ | ----------- |
| `--https` | Clone over HTTPS instead of SSH. The remote is read-only. |
| `branch` | The branch to clone. Defaults to the project's default branch on drupal.org. |

If the directory already holds a git checkout, the command asks whether to register it with Composer and uses its current branch.

See [Contrib modules](../guides/contrib-modules.md).

## `ddev switch`

```
ddev switch [--pull] <project> <branch>
```

Switches `core` (the checkout at the project root) or a cloned module to another branch, then updates Composer to match. For core it runs `ddev composer update`. For a module it requires the dev version that matches the new branch.

| Option | Description |
| ------ | ----------- |
| `--pull` | Fetch the branch and fast-forward it before Composer runs. A branch that has diverged from the remote is left as it is. |

A branch that only exists on remotes is created from the drupal.org repository, even when issue fork remotes have a branch of the same name.

See [Core](../guides/core.md#switching-core-branches) and [Contrib modules](../guides/contrib-modules.md#switching-branches).

## `ddev mr`

```
ddev mr [--https] <project> <merge request or issue number>
ddev mr [--https] <merge request or drupal.org issue URL>
```

Adds the issue fork as a remote that tracks only the merge request branch, checks the branch out and updates Composer. The project is `core` or a module cloned with `ddev add-module`.

| Option | Description |
| ------ | ----------- |
| `--https` | Add the fork remote over HTTPS instead of SSH. The remote is read-only. |

See [Merge requests](../guides/merge-requests.md).

## `ddev update-module`

```
ddev update-module <module>
```

Reads the branch a cloned module is on and requires the dev version that matches it. Use it after switching the branch with git or your IDE.

## `ddev remove-module`

```
ddev remove-module <module>
```

Removes the Composer requirement and the path repository, then deletes the module's directory. Stops without changing anything if the checkout has uncommitted or untracked changes, or if another package depends on the module.

## `ddev phpunit`

```
ddev phpunit [--db=mysql|mariadb|sqlite|pgsql] [phpunit arguments]
```

Runs PHPUnit with core's configuration, from the container directory that matches the one you run it from. All arguments except `--db` go to PHPUnit unchanged.

| Option | Description |
| ------ | ----------- |
| `--db=mysql` | The project's `db` container. This is the default. |
| `--db=mariadb` | The project database if it is MariaDB, otherwise a separate MariaDB container. |
| `--db=sqlite` | A SQLite database file. |
| `--db=pgsql` | The project database if it is PostgreSQL, otherwise the container from the ddev-postgres add-on. |

See [Running tests](../guides/testing.md).

## `ddev phpstan`

```
ddev phpstan [phpstan arguments] [paths]
```

Runs `phpstan analyse` with the configuration of the project each path belongs to. Without paths, checks the current directory. From the project root that is a full analysis with core's baseline.

## `ddev phpcs`

```
ddev phpcs [phpcs arguments] [paths]
```

Runs PHP CodeSniffer with the coding standard of the project each path belongs to. Without paths, checks the current directory.

## `ddev cspell`

```
ddev cspell [cspell arguments] [globs]
```

Runs cspell with the configuration and words of the project each glob belongs to. Without globs, checks the current directory. Needs core's node dependencies: `ddev exec 'corepack enable && cd core && yarn install'`.

See [Code quality](../guides/code-quality.md) for how the configuration is picked.

## `ddev commit-code-check`

```
ddev commit-code-check [--cached] [--branch <branch>] [--memory-unlimited]
```

Runs core's `core/scripts/dev/commit-code-check.sh` on the files you changed.

| Option | Description |
| ------ | ----------- |
| (none) | Modified and untracked files in the working directory. |
| `--cached` | Staged files only. |
| `--branch <branch>` | Everything your branch changed compared to `<branch>`. |
| `--memory-unlimited` | Run without a PHP memory limit. |

See [Checking a change before committing](../guides/code-quality.md#checking-a-change-before-committing).
