<!-- #ddev-generated -->
# ddev-drupal-dev cheat sheet

Quick reference for the most common commands. See the [full README](https://github.com/amateescu/ddev-drupal-dev) for details.

## Contrib modules

```bash
ddev auth ssh                          # forward SSH keys (once per session)
ddev add-module token                  # clone + require token
ddev add-module token 2.0.x            # specific branch
ddev add-module --https token          # clone over HTTPS (no push access)
ddev switch token 2.0.x                # switch branch + update constraint
ddev update-module token               # re-sync constraint after switching branches yourself
ddev remove-module token               # remove require, repo entry, and clone
```

Modules land in `modules/contrib/<name>` as git checkouts.

## Core

```bash
ddev switch core 11.x                  # switch core branch + composer update
```

## Composer overlay

```bash
ddev composer install                  # install everything (core + overlay)
ddev composer require drupal/pathauto  # add a package without cloning
ddev composer require --dev phpstan/phpstan
ddev composer update                   # re-solve overlay
```

The overlay lives in `composer.local.json`; core's `composer.json` and `composer.lock` are never touched.

## Tests

```bash
ddev phpunit core/modules/node                  # project database (default)
ddev phpunit --db=sqlite core/modules/node      # SQLite
ddev phpunit --db=pgsql core/modules/node       # PostgreSQL (needs ddev-postgres)
ddev phpunit modules/contrib/token              # contrib module tests
```

## Code quality

```bash
ddev phpstan core/modules/node         # PHPStan on specific paths
ddev phpcs core/modules/node           # coding standard checks
ddev cspell core/modules/node/**       # spell checking (globs)
```

Run any of them without arguments to check the whole codebase. `ddev cspell`
needs core's node dependencies: `ddev exec 'corepack enable && cd core && yarn install'`.

Core's pre-commit script, on your changed files only:

```bash
ddev commit-code-check                 # working directory changes
ddev commit-code-check --cached        # staged files only
ddev commit-code-check --branch 11.x   # changes compared to a branch
```

## Always run tools from the project root

When working on a contrib modules, run `ddev phpunit`, `ddev phpcs`, `ddev phpstan`, etc. from the Drupal project root and pass the module path, e.g. `ddev phpcs modules/contrib/dashboard`. The Drupal core tooling/config (for example `core/phpcs.xml.dist`) relative to the Drupal site root.

## Pin core's exact dependency versions

In `composer.local.json`:

```json
{ "extra": { "drupal-dev": { "pin-core-lock": true } } }
```

Then `ddev composer update` once to regenerate the lock with pinning applied.

## Host-side shell helpers

Add to `~/.bashrc` or `~/.zshrc` so bare `composer`, `drush`, `php`, `phpunit`, `dr` auto-delegate to DDEV:

```bash
source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
```

If you use `direnv`: run `direnv allow` in the project root.
