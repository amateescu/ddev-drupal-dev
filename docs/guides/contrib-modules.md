# Contrib modules

## Adding a module

`ddev add-module` clones a contrib module for development:

```bash
ddev add-module token
ddev add-module token 2.0.x     # a specific branch
ddev add-module --https token   # read-only HTTPS remote, no push access
```

In one step, it:

1. clones the module into `modules/contrib/token`, on the branch you name or on the project's default branch,
2. registers the checkout as a path repository in `composer.local.json`,
3. runs `composer require` with the dev version that matches the branch, for example `drupal/token:2.0.x-dev`.

The clone runs on the host, so it uses your host SSH keys directly. There is no need for `ddev auth ssh`.

The module stays a git checkout. Composer sees the `.git` directory and doesn't download the package over it. Its dependencies are resolved through the overlay, so core's files stay untouched. You can add as many modules as you like, and commit and push in each one independently.

When the module has `require-dev` dependencies, `ddev add-module` lists them with the command that installs each one: `ddev add-module` for other drupal.org projects, `ddev composer require --dev` for everything else. They are not installed automatically.

The overlay includes [composer-drupal-lenient](https://github.com/mglaman/composer-drupal-lenient), so modules that don't declare compatibility with your core version yet still install. For example, a module that only supports `^11` installs on core's `main` branch.

### Using an existing checkout

If `modules/contrib/<name>` already holds a git checkout, `ddev add-module` offers to register it with Composer instead of cloning. It uses the branch the checkout is on. The checkout can be a git worktree.

## Switching branches

`ddev switch` checks out another branch and updates the module's Composer constraint to match:

```bash
ddev switch token 2.0.x
```

A branch you checked out weeks ago is behind by now. Add `--pull` to fetch it and fast-forward before Composer runs:

```bash
ddev switch --pull token 2.0.x
```

The branch is only fast-forwarded. If your branch and the remote's have diverged, the checkout stays where it is and the command prints how to see what differs. The Composer update still runs.

A branch that doesn't exist locally yet is created from the drupal.org repository. Issue fork remotes carry the same branch names, so a plain `git switch 2.0.x` fails with "matched multiple remote tracking branches" once you have fetched a few forks. `ddev switch` picks the drupal.org repository instead.

### Switching branches yourself

If you switched branches with git or your IDE, update the Composer constraint without touching the checkout:

```bash
cd modules/contrib/token && git checkout 2.0.x && cd -
ddev update-module token
```

## Removing a module

```bash
ddev remove-module token
```

This removes the Composer requirement and the path repository, then deletes the module's directory. It stops without changing anything if the checkout has uncommitted or untracked changes. It also stops if another package still depends on the module.

## Modules you don't work on

If you only need a module as a dependency, require it directly. It is downloaded like any other Composer package:

```bash
ddev composer require drupal/pathauto
```

See [Dependencies](dependencies.md) for more.
