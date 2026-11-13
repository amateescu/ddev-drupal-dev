# Code quality

## PHPStan, PHP CodeSniffer and cspell

Each tool runs with the configuration of the project being checked, or a default one when the project has none:

```bash
ddev phpstan core/modules/node         # PHPStan on specific paths
ddev phpstan modules/contrib/token     # the module's own configuration, if it has one
ddev phpstan                           # full analysis with core's baseline, from the project root
ddev phpcs core/modules/node           # coding standard checks
ddev phpcs                             # whole codebase, from the project root
ddev cspell core/modules/node/**       # spell checking (globs)
ddev cspell                            # whole codebase, from the project root
```

`ddev cspell` needs core's node dependencies. Install them once:

```bash
ddev exec 'corepack enable && cd core && yarn install'
```

### Paths

Paths and globs are relative to the directory you run the command from. Without any, a command checks that directory. From the project root, that is the whole codebase:

```bash
cd modules/contrib/token
ddev phpstan                           # the module
ddev phpcs src                         # the module's src directory
```

Paths that belong to several projects are checked one project at a time, each with its own configuration.

### Which configuration is used

Each command takes the nearest configuration in the checked path or a parent directory, the same way contrib CI finds one:

| Tool | Configuration files |
| ---- | ------------------- |
| PHPStan | `phpstan.neon`, `phpstan.neon.dist`, `phpstan.dist.neon` |
| PHP CodeSniffer | `.phpcs.xml`, `phpcs.xml`, `.phpcs.xml.dist`, `phpcs.xml.dist` |
| cspell | `.cspell.json`, `cspell.json`, and the other names cspell looks for |

A project without a configuration of its own falls back to a default:

- A contrib project (one with a `.gitlab-ci.yml`) gets the default configuration contrib CI uses.
- Everything else gets core's.

`ddev phpstan` analyses against the PHP version core declares in `config.platform`, not the container's PHP version, so results match core's CI.

### Contrib projects

A contrib project is checked the way contrib CI checks it. Contrib CI's defaults differ from core's:

- **PHP CodeSniffer** uses the full `Drupal` ruleset. Core's standard skips some rules, such as the line length check in tests.
- **PHPStan** runs at level 0 and adds the project's baseline (`phpstan-baseline.neon`, or whatever `_PHPSTAN_BASELINE_FILENAME` names). Core's configuration runs at level 1, with rules only core uses.
- **cspell** flags fewer words than core's configuration.

The project's `.gitlab-ci.yml` variables are applied too:

| Variable | Effect |
| -------- | ------ |
| `_PHPSTAN_LEVEL` | PHPStan level |
| `_PHPSTAN_BASELINE_FILENAME` | PHPStan baseline file |
| `_CSPELL_WORDS` | Extra allowed words |
| `_CSPELL_FLAGWORDS` | Extra flagged words |
| `_CSPELL_DICTIONARY` | Project dictionary file, `.cspell-project-words.txt` by default |
| `_CSPELL_IGNORE_PATHS` | Paths cspell skips |
| `_CSPELL_IGNORE_STANDARD_FILES` | Set to `0` to also check files such as `composer.json` and `CHANGELOG.txt` |

cspell also gets what contrib CI adds to every project's configuration: the module names, a few common words and core's dictionaries.

`_PHPCS_EXTRA`, `_PHPSTAN_EXTRA` and `_CSPELL_EXTRA` are not applied.

## Mago

`ddev mago` runs [Mago](https://mago.carthage.software) with the configuration of the project being checked. Install it first, with the Drupal rules from [drupal/mago](https://www.drupal.org/project/mago):

```bash
ddev composer require --dev carthage-software/mago "drupal/mago:^1.0@alpha"
```

```bash
ddev mago lint modules/contrib/token   # the module's own mago.toml
cd modules/contrib/token
ddev mago analyze                      # what the module's mago.toml lists
ddev mago format --check src           # the module's src directory
```

Mago only looks for a `mago.toml` in the directory it runs from. `ddev mago` takes the nearest `mago.toml` or `mago.dist.toml` in the checked path or a parent directory, and runs Mago with that project as its workspace. Paths that belong to several projects are checked one project at a time. A run that passes `--config` or `--workspace` is left alone.

### A configuration written for contrib CI

A contrib project's `mago.toml` is written for the layout of contrib CI, where Composer installs into the project's directory and the site is in `web`:

```toml
extends = "vendor/drupal/mago/drupal.mago.toml"

[source]
paths = ["."]
includes = ["vendor", "web"]
```

Here the project sits inside the site, so it doesn't have a `vendor` directory. `ddev mago` makes the same file work without changing it. It writes a configuration under `/tmp/drupal-dev-mago` in the container that:

- extends the project's file through a link, next to a link to the site's `vendor` directory, so the path to `drupal/mago` works
- lists `vendor`, core and every other module, theme and profile under `includes`, for the analyzer to read
- starts the `drupal/mago` worker in the project's directory

`mago analyze` warns about the project's own `includes` that don't exist here.

## Checking a change before committing

`ddev commit-code-check` runs core's `core/scripts/dev/commit-code-check.sh`. It checks only the files you changed, with cspell, PHP CodeSniffer, PHPStan, ESLint, Stylelint and a few file checks (file modes, no changes in `vendor/` or `core/node_modules/`):

```bash
ddev commit-code-check                      # modified and untracked files in the working directory
ddev commit-code-check --cached             # staged files only
ddev commit-code-check --branch 11.x        # everything your branch changed compared to 11.x
ddev commit-code-check --memory-unlimited   # no PHP memory limit
```

There has to be something to check: on a clean checkout it prints "There are no files to check" and stops. The spelling and JavaScript checks run through yarn, so the first run installs core's node dependencies, which takes a few minutes.
