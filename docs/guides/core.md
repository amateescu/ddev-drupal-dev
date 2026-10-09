# Core

The project root is a normal core git checkout. The overlay never modifies core's `composer.json` or `composer.lock`, so you work on core as usual: edit files, run tests, commit, push and create patches.

## Switching core branches

Another core branch can have a different `composer.json`, so the overlay needs a fresh solve after a switch. `ddev switch` does both:

```bash
ddev switch core 11.x
```

This runs `git switch`, waits for the container to see the new files, and runs `ddev composer update`. The same thing by hand is `git switch 11.x && ddev composer update`.

`--pull` fetches the branch and fast-forwards it first, so Composer resolves against the code that is on drupal.org today rather than whatever your last checkout left behind:

```bash
ddev switch --pull core 11.x
```

The branch is only fast-forwarded. If yours and the remote's have diverged, the checkout stays where it is, with a note on how to see what differs, and the Composer update still runs.

`ddev switch` only switches to branches you have already fetched, with or without `--pull`. For a branch that is new on drupal.org, run `git fetch` first.

### Branches with the same name on several remotes

A branch that doesn't exist locally yet is created from the drupal.org repository. Issue fork remotes carry copies of the same branches, so a plain `git switch 11.x` fails with "matched multiple remote tracking branches" once you have fetched a few forks. `ddev switch` picks the drupal.org repository instead.

If none of the remotes with that branch is the drupal.org repository, it uses the remote set in git's `checkout.defaultRemote`, then `origin`. If that still leaves several, `ddev switch` lists them and asks you to choose with `git switch --track <remote>/<branch>`.

## Distributions

`core` means whichever project is at the project root. The add-on reads it from the checkout's git remotes, so `ddev switch core` and [`ddev mr core`](merge-requests.md) also work on a distribution checkout.

## Reproducing core's exact dependency versions

The overlay's dependencies are solved fresh, so shared packages like Symfony or Guzzle may resolve to newer versions than core's `composer.lock`. To reproduce a core bug or check a patch against the same versions core records, see [Pinning core's locked versions](dependencies.md#pinning-cores-locked-versions).
