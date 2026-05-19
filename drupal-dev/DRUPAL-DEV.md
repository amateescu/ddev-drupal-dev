<!-- #ddev-generated -->
# ddev-drupal-dev cheat sheet

Quick reference for the most common commands. See the [full README](https://github.com/amateescu/ddev-drupal-dev) for details.

## Contrib modules

```bash
ddev auth ssh                          # forward SSH keys (once per session)
ddev add-module token                  # clone + require token
ddev add-module token 2.0.x            # specific branch
ddev add-module --https token          # clone over HTTPS (no push access)
ddev update-module token               # re-sync constraint after switching branches
ddev remove-module token               # remove require, repo entry, and clone
```

Modules land in `modules/contrib/<name>` as git checkouts.

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

## Pin core's exact dependency versions

In `composer.local.json`:

```json
{ "extra": { "drupal-dev": { "pin-core-lock": true } } }
```

Then `ddev composer update` once to regenerate the lock with pinning applied.

## Host-side shell helpers

Add to `~/.bashrc` or `~/.zshrc` so bare `composer`, `drush`, `php`, `phpunit` auto-delegate to DDEV:

```bash
source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
```

If you use `direnv`: run `direnv allow` in the project root.
