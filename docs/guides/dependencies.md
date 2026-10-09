# Dependencies

Inside DDEV, `ddev composer` reads `composer.local.json`, the overlay that sits on top of core's `composer.json`. Anything you add goes into the overlay, and core's `composer.json` and `composer.lock` stay untouched. See [How it works](../reference/how-it-works.md) for the mechanics.

## Adding packages

Any package can be added through the overlay:

```bash
ddev composer require drush/drush
ddev composer require --dev phpstan/phpstan
ddev composer require drupal/pathauto
```

A contrib module added this way is downloaded like any other package. To work on a module, clone it with [`ddev add-module`](contrib-modules.md) instead.

## Pinning core's locked versions

The overlay's dependencies are solved fresh, so shared packages like Symfony or Guzzle may resolve to newer versions than core's `composer.lock`. When you reproduce a core bug or check a patch, you sometimes need exactly the versions core records.

Turn on pinning in `composer.local.json`:

```json
{
    "extra": {
        "drupal-dev": {
            "pin-core-lock": true
        }
    }
}
```

Then solve again:

```bash
ddev composer update
```

Packages that appear in core's `composer.lock` are pinned to the exact version, and to the exact commit for dev versions. Packages only the overlay requires resolve normally. Later `ddev composer install` runs install from the pinned `composer.local.lock` as it is.

Pinning applies when Composer solves dependencies, so run `ddev composer update` once after turning it on or off. Core's lock is read again on every solve, so there is nothing else to refresh after core's lock changes.

To turn it off, set the flag to `false` or remove the key, then run `ddev composer update`.

## Changing the module directory layout

Modules are installed into `modules/contrib/` by default, the standard Drupal layout. `ddev add-module` and the add-on's Composer plugin both read `installer-paths` from your Composer configuration, so you can change the layout by overriding it in `composer.local.json`:

```json
{
    "extra": {
        "installer-paths": {
            "modules/{$name}": ["type:drupal-module"]
        }
    }
}
```

## Running bare `composer install`

Running `composer install` without the overlay, for example on the host without the [shell helpers](host.md), is harmless. It replaces `vendor/` with core's dependencies only, so overlay packages are missing until you install them again:

```bash
ddev composer install
```
