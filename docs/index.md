# DDEV Drupal Dev

A DDEV add-on for working on Drupal core and contrib modules together, using a core git checkout as the project root.

Other add-ons target either core or contrib in isolation. This one is for when you need both:

- developing a contrib module against the latest core,
- fixing a core bug that affects contrib,
- running contrib tests on a core patch.

Extra dependencies (contrib modules, Drush, dev tools) are managed through a `composer.local.json` overlay, keeping core's `composer.json` and `composer.lock` untouched.

## Quick start

```bash
git clone https://git.drupalcode.org/project/drupal.git drupal-dev
cd drupal-dev
ddev config --project-type=drupal12
ddev start
ddev add-on get amateescu/ddev-drupal-dev
ddev restart
ddev composer install
```

Then clone a contrib module and run its tests:

```bash
ddev add-module token
ddev phpunit modules/contrib/token
```

See [Getting started](getting-started.md) for the details.

## Where to go next

- [Contrib modules](guides/contrib-modules.md): clone, switch and remove modules you work on.
- [Core](guides/core.md): switch core branches.
- [Merge requests](guides/merge-requests.md): check out a drupal.org merge request with one command.
- [Dependencies](guides/dependencies.md): add packages, pin core's locked versions.
- [Running tests](guides/testing.md): PHPUnit against MySQL, MariaDB, PostgreSQL or SQLite, and browser tests.
- [Code quality](guides/code-quality.md): PHPStan, PHP CodeSniffer, cspell and core's pre-commit checks.
- [Working from the host](guides/host.md): shell helpers, direnv and tab completion.
- [Commands](reference/commands.md): every command and option.

## Comparison with other add-ons

| Add-on | Core | Contrib modules | Use it when |
| ------ | ---- | --------------- | ----------- |
| ddev-drupal-dev | Git checkout | Any number, as git checkouts | You work on core and contrib at the same time |
| [ddev-drupal-core-dev](https://github.com/justafish/ddev-drupal-core-dev) | Git checkout | None | You only work on core |
| [ddev-drupal-contrib](https://github.com/ddev/ddev-drupal-contrib) | Composer dependency | One | You work on one contrib module and don't need a core checkout |
| [ddev-drupal-suite](https://github.com/lussoluca/ddev-drupal-suite) | Composer dependency | Several | You work on several contrib modules and don't need a core checkout |
