# Working from the host

Inside DDEV, `ddev composer` always reads the overlay. On the host, a bare `composer`, `drush` or `php` runs the host binary, which bypasses DDEV and ignores the overlay. Two things help with that.

## Shell helpers (recommended)

The add-on ships a script with shell functions for `composer`, `drush`, `dr`, `php`, `phpunit`, `phpstan`, `phpcs` and `cspell`. Inside a DDEV project, each one runs the `ddev` command of the same name. Anywhere else, it runs the host binary.

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/your/project/.ddev/drupal-dev/shell-helpers.sh
```

The add-on prints the exact line for your project when it is installed. One project's copy works for every DDEV project, since the functions look for `.ddev/config.yaml` from the current directory upwards.

## direnv

The add-on creates an `.envrc` file in the project root. If you use [direnv](https://direnv.net/docs/installation.html), allow it once:

```bash
direnv allow
```

This sets `COMPOSER=composer.local.json` on the host, so a host `composer` uses the overlay too. direnv cannot export shell functions, so you still need the shell helpers above to run the tools through DDEV.

## Tab completion

With DDEV's [shell completion](https://docs.ddev.com/en/stable/users/install/shell-completion/) set up, Tab completes:

| Command | Completes |
| ------- | --------- |
| `ddev switch`, `ddev mr` | `core` and the cloned modules, then (for `switch`) the checkout's branches |
| `ddev update-module`, `ddev remove-module` | The cloned modules |
| `ddev add-module`, `ddev mr` | Their `--https` option |
| `ddev switch` | Its `--pull` option |
| `ddev phpunit` | The `--db` values |
