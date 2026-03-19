[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/amateescu/ddev-drupal-dev/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/amateescu/ddev-drupal-dev/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/amateescu/ddev-drupal-dev)](https://github.com/amateescu/ddev-drupal-dev/commits)
[![release](https://img.shields.io/github/v/release/amateescu/ddev-drupal-dev)](https://github.com/amateescu/ddev-drupal-dev/releases/latest)

# DDEV Drupal Dev

A DDEV add-on for working on Drupal core and contrib modules together, using a core git checkout as the project root.

Other add-ons target either core or contrib in isolation. This one is for when you need both: developing a contrib module against the latest core, fixing a core bug that affects contrib, or running contrib tests on a core patch.

Extra dependencies (contrib modules, Drush, dev tools) are managed through a `composer.local.json` overlay, keeping core's `composer.json` and `composer.lock` untouched.

## Installation

Clone Drupal core and configure DDEV to use it as the project root:

```bash
git clone https://git.drupalcode.org/project/drupal.git drupal-dev
cd drupal-dev
ddev config --project-type=drupal12
ddev start
```

Then install the add-on:

```bash
ddev add-on get amateescu/ddev-drupal-dev
ddev restart
ddev composer install
```

## Working on contrib modules

Use `ddev add-module` to clone a contrib module for development:

```bash
ddev auth ssh                   # forward SSH keys (needed once per session)
ddev add-module token
ddev add-module token 2.0.x     # specific branch
ddev add-module --https token   # or use HTTPS (no push access)
```

This clones the module into `modules/contrib/`, registers it as a path repository in `composer.local.json`, and runs `composer require`, all in one step.

The module is a preserved git checkout. Composer detects the `.git` directory and skips re-downloading it. Its dependencies are resolved through the overlay, keeping core's files untouched.

You can work on multiple modules this way; each gets its own git checkout that you can commit and push to independently.

The overlay includes [composer-drupal-lenient](https://github.com/mglaman/composer-drupal-lenient), so contrib modules that don't yet declare compatibility with your core version (e.g. working on `main`/12.x-dev with a module that only supports `^11`) will still install.

### Switching branches

After switching a module's git branch, update the Composer constraint to match:

```bash
cd modules/contrib/token && git checkout 2.0.x && cd -
ddev update-module token
```

### Removing a contrib module

```bash
ddev remove-module token
```

This removes the composer requirement, unsets the path repository, and deletes the cloned directory. It will abort if the module has uncommitted changes.

### Installing a contrib module without cloning

If you just need a module as a dependency (not for active development), require it directly:

```bash
ddev composer require drupal/pathauto
```

## Working on core

Core's `composer.json` and `composer.lock` are never modified by the overlay. You work on core normally: edit files, run tests, commit, create patches.

## Running tests

Tests run against your project's configured database by default. Use `--db` to switch:

```bash
ddev phpunit core/modules/node                  # project database (default)
ddev phpunit --db=sqlite core/modules/node      # SQLite
ddev phpunit --db=pgsql core/modules/node       # PostgreSQL
ddev phpunit modules/contrib/token              # contrib module tests
```

For PostgreSQL, install the [ddev-postgres](https://github.com/ddev/ddev-postgres) add-on first.

## Adding other packages

Any package can be added through the overlay:

```bash
ddev composer require drush/drush
ddev composer require --dev phpstan/phpstan
```

## Working from the host

Inside DDEV, `ddev composer` always uses the overlay automatically. On the host, bare `composer`, `drush` and `php` will bypass DDEV. To prevent that, use one of these options:

### Shell helpers (recommended)

The add-on includes a shell helpers script that wraps `composer`, `drush`, `php` and `phpunit`, automatically delegating to DDEV when you're inside a DDEV project and falling back to the host binary otherwise.

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
```

### direnv

An `.envrc` file is created during installation. If you have [direnv](https://direnv.net/docs/installation.html) installed, run:

```bash
direnv allow
```

This sets the `COMPOSER` env var on the host so that running `composer` directly on the host uses the overlay. Note that direnv cannot export shell functions, so you still need the shell helpers above for `composer`, `drush`, `php` and `phpunit` delegation.

## Command reference

| Command | Description |
| ------- | ----------- |
| `ddev phpunit [path]` | Run PHPUnit tests |
| `ddev add-module <name>` | Clone a contrib module for development |
| `ddev update-module <name>` | Update composer constraint after switching a module's branch |
| `ddev remove-module <name>` | Remove a previously cloned contrib module |

## How it works

1. A `composer.local.json` file lives in the core root (ignored via `.gitignore`).
2. It requires `wikimedia/composer-merge-plugin`, which pulls in everything from core's `composer.json`.
3. The `COMPOSER` env var is set to `composer.local.json` inside the DDEV web container, so Composer reads the overlay instead of core's file.
4. Result: a unified `vendor/` and autoloader with both core's deps and your extras, while core's `composer.json` and `composer.lock` remain untouched.
5. A custom Composer plugin (`drupal-dev/composer-git-installer`) intercepts installs for `drupal-module`, `drupal-theme`, and `drupal-profile` packages. If a `.git` directory already exists at the install path, the download is skipped and the package is registered in the installed repository so autoloading works correctly.

Only `composer.local.json` and `composer.local.lock` are written (both ignored via `.gitignore`).

## Advanced

### Changing the module directory layout

By default, modules are installed into `modules/contrib/` (the standard Drupal layout). Both `ddev add-module` and the Composer plugin read the `installer-paths` from your Composer configuration, so you can change the layout by overriding it in `composer.local.json`:

```json
{
    "extra": {
        "installer-paths": {
            "modules/{$name}": ["type:drupal-module"]
        }
    }
}
```

### What happens if you run bare `composer install`

It's harmless. It just overwrites `vendor/` with only core's deps, losing any overlay packages until re-installed. Fix it with:

```bash
ddev composer install
```

## Upgrading

When upgrading the add-on, your `composer.local.json` is preserved (it contains your modules and custom packages). If a new version of the add-on introduces changes to the base `composer.local.json`, check `.ddev/drupal-dev/composer.local.json` for any new dependencies and add them manually.

## Comparison with other add-ons

- **[ddev-drupal-core-dev](https://github.com/justafish/ddev-drupal-core-dev)** -- Core development only. Same project layout (core git checkout), but no contrib module or Composer management. Use this if you only work on core.
- **[ddev-drupal-contrib](https://github.com/ddev/ddev-drupal-contrib)** -- Single contrib module development. Core is pulled in as a Composer dependency. Use this if you work on one contrib module and don't need a core checkout.
- **[ddev-drupal-suite](https://github.com/lussoluca/ddev-drupal-suite)** -- Multiple contrib modules. Similar to ddev-drupal-contrib but supports working on several modules at once. Core is a dependency, not a checkout.

## Credits

**Contributed and maintained by [@amateescu](https://github.com/amateescu)**
