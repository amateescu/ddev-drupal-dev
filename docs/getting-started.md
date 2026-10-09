# Getting started

## Requirements

- [DDEV](https://docs.ddev.com/en/stable/users/install/) 1.25.3 or newer.
- Git on the host. Module clones and merge request checkouts run on the host and use your host SSH keys.
- An SSH key on your drupal.org account if you want to push. Without one, use the `--https` option of [`ddev add-module`](reference/commands.md#ddev-add-module) and [`ddev mr`](reference/commands.md#ddev-mr) to get read-only remotes.

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

`ddev composer install` installs core's dependencies and the overlay's own packages into one `vendor/` directory.

Drush is not part of core's dependencies. Add it through the overlay if you need it:

```bash
ddev composer require drush/drush
```

## What the add-on adds to your project

In the project root:

| File | Purpose |
| ---- | ------- |
| `composer.local.json` | The [Composer overlay](reference/how-it-works.md). Contrib modules and other packages you add are recorded here. |
| `composer.local.lock` | The overlay's lock file, written by the first `ddev composer install`. |
| `.gitignore` | Based on core's `example.gitignore`, plus the files above. Only created when the project has no `.gitignore` yet. |
| `.envrc` | Sets `COMPOSER=composer.local.json` for [direnv](guides/host.md#direnv) users. |
| `DRUPAL-DEV.md` | A [cheat sheet](reference/cheat-sheet.md) of the common commands. |
| `test_output/` | Output of browser tests. |

In `.ddev/`: the [commands](reference/commands.md), a Selenium Chromium container for browser tests, and the test environment variables.

If the project already has a `.gitignore`, the add-on only appends `/DRUPAL-DEV.md` to it. Make sure `composer.local.json`, `composer.local.lock`, `.envrc` and `test_output` are ignored too, so they don't end up in a core commit.

## Upgrading

```bash
ddev add-on get amateescu/ddev-drupal-dev
ddev restart
```

Your `composer.local.json` is preserved, since it contains your modules and custom packages. If a new version of the add-on changes the base `composer.local.json`, compare yours with `.ddev/drupal-dev/composer.local.json` and add any new dependencies by hand.

!!! note "Upgrading from versions that mirrored `config.platform`"
    Earlier versions copied core's `config.platform` into `composer.local.json`, which held every package in the overlay to core's minimum PHP version. The next Composer run removes that setting. Your `composer.local.lock` also recorded it as `platform-overrides`, so run `ddev composer update` once to solve without it.

## Removing the add-on

```bash
ddev add-on remove drupal-dev
```

This removes the add-on's files from `.ddev/`, plus `.envrc`, `DRUPAL-DEV.md`, `test_output/` and the add-on's own `.gitignore` from the project root. `composer.local.json` and `composer.local.lock` are kept once `ddev add-module` has added a module to them, and removed otherwise. Modules cloned with `ddev add-module` stay where they are.
