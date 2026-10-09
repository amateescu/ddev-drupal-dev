# How it works

## The Composer overlay

1. A `composer.local.json` file lives in the project root, next to core's `composer.json`.
2. It requires [`wikimedia/composer-merge-plugin`](https://github.com/wikimedia/composer-merge-plugin), which pulls in everything from core's `composer.json`.
3. The `COMPOSER` environment variable is set to `composer.local.json` inside the DDEV web container, so Composer reads the overlay instead of core's file.
4. The result is one `vendor/` directory and one autoloader with core's dependencies and your extras. Core's `composer.json` and `composer.lock` are never modified.

Composer only writes `composer.local.json` and `composer.local.lock`.

The overlay also sets `minimum-stability: dev`, which core's development branches need, and requires [`mglaman/composer-drupal-lenient`](https://github.com/mglaman/composer-drupal-lenient) so contrib modules install even when they don't declare support for your core version yet.

## The Composer plugin

The add-on ships a small Composer plugin, `drupal-dev/composer-git-installer`, with two jobs.

**Keeping git checkouts.** It handles installs of `drupal-module`, `drupal-theme` and `drupal-profile` packages. If a git checkout (a clone or a worktree) already exists at the install path, it skips the download and registers the package as installed, so autoloading works and your checkout stays untouched. This is what lets [`ddev add-module`](../guides/contrib-modules.md) require a module without Composer replacing the clone.

**Pinning core's versions.** When `extra.drupal-dev.pin-core-lock` is on, it filters the versions the solver can pick against core's `composer.lock`, so shared packages can only resolve to the versions core locked. See [Pinning core's locked versions](../guides/dependencies.md#pinning-cores-locked-versions).

## The DDEV setup

The add-on adds to `.ddev/`:

- the [commands](commands.md): host commands for modules, branches, merge requests and PHPUnit, and web container commands for the code quality tools,
- a Selenium Chromium container for browser tests,
- environment variables in the web container: `COMPOSER`, and the `SIMPLETEST_*`, `BROWSERTEST_*` and WebDriver variables core's tests read.

The host commands run git on the host, so they use your host SSH keys and git configuration. They run Composer inside the container.
