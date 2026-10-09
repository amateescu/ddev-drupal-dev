# Merge requests

Checking out a merge request by hand means finding the issue fork, adding it as a remote, fetching, checking out the branch and solving the overlay again. `ddev mr` does all of it:

```bash
ddev mr core 16853      # a merge request number
ddev mr core 3563677    # an issue number, resolved to its merge request
ddev mr token 136       # a contrib module's merge request
ddev mr https://git.drupalcode.org/project/drupal/-/merge_requests/16853
ddev mr https://www.drupal.org/project/drupal/issues/3563677    # or the issue page
```

The project is `core` for the checkout at the project root, or the name of a module you cloned with [`ddev add-module`](contrib-modules.md). A URL already names the project, so it is the only argument.

## What it does

1. Looks up the merge request on git.drupalcode.org. If the number is not a merge request, it is treated as an issue number and resolved to the issue's merge request.
2. Adds the issue fork as a remote named after the fork, for example `drupal-3563677`, set up to track only the merge request branch. The fork's copies of `11.x` and `main` stay out of your branch list.
3. Fetches the branch, checks it out, and fast-forwards it if you checked it out on an earlier run.
4. Updates Composer:
    - For core it runs `ddev composer update`. That also clears the "package is in the lock file as 11.x-dev but that does not satisfy your constraint 12.x-dev" error you get from `ddev composer install` after switching between major branches by hand.
    - For a contrib module the constraint follows the branch the merge request targets, for example `2.0.x-dev`. The code installed is still the merge request checkout.

## Pushing

The branch tracks the fork, so a plain `git push` updates the merge request. The fork remote uses SSH, so pushing needs your SSH key on drupal.org and push access to the issue fork. Pass `--https` for a read-only remote:

```bash
ddev mr --https core 16853
```

## Issues with several merge requests

When you pass an issue number:

- With one open merge request, that one is checked out.
- With several open merge requests, `ddev mr` lists them and asks you to pick one by its merge request number.
- With no open merge request, the newest one is checked out, even if it is already merged or closed.
