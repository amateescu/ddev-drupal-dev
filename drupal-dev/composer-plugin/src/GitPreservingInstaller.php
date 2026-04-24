<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Installer\LibraryInstaller;
use Composer\Package\AliasPackage;
use Composer\Package\PackageInterface;
use Composer\Repository\InstalledRepositoryInterface;
use React\Promise\PromiseInterface;

/**
 * Composer installer that skips file operations when the install path already
 * contains a git checkout.
 *
 * This prevents Composer from overwriting manually cloned Drupal packages
 * (modules, themes, profiles) with its own git clone. The package is still
 * registered in the installed repository so autoloading works correctly.
 */
class GitPreservingInstaller extends LibraryInstaller
{
    private const SUPPORTED_TYPES = ['drupal-module', 'drupal-theme', 'drupal-profile', 'drupal-core'];

    /**
     * Only handle Drupal module/theme/profile types.
     */
    public function supports(string $packageType): bool
    {
        return in_array($packageType, self::SUPPORTED_TYPES, true);
    }

    /**
     * Return the install path for a package.
     *
     * Checks the overlay file (pointed to by the COMPOSER env var) first so
     * user-defined paths take priority over paths merged in from core's
     * composer.json. Falls back to the merged root package extra.
     */
    public function getInstallPath(PackageInterface $package): string
    {
        $type = $package->getType();
        $prettyName = $package->getPrettyName();
        $name = substr($prettyName, strpos($prettyName, '/') + 1);

        $composerFile = getenv('COMPOSER') ?: 'composer.json';
        if ($composerFile !== 'composer.json') {
            $overlayPath = getcwd() . '/' . $composerFile;
            if (file_exists($overlayPath)) {
                $overlayConfig = json_decode(file_get_contents($overlayPath), true);
                foreach ($overlayConfig['extra']['installer-paths'] ?? [] as $path => $conditions) {
                    foreach ($conditions as $condition) {
                        if ($condition === "type:$type") {
                            return str_replace('{$name}', $name, $path);
                        }
                    }
                }
            }
        }

        $extra = $this->composer->getPackage()->getExtra();
        foreach ($extra['installer-paths'] ?? [] as $path => $conditions) {
            foreach ($conditions as $condition) {
                if ($condition === "type:$type") {
                    return str_replace('{$name}', $name, $path);
                }
            }
        }

        if ($type === 'drupal-core') {
            return 'core';
        }

        throw new \RuntimeException("No installer-paths entry found for package type '$type'. Ensure your Composer configuration defines installer-paths.");
    }

    /**
     * Check if the install path has a git checkout.
     */
    private function hasGitCheckout(PackageInterface $package): bool
    {
        return is_dir($this->getInstallPath($package) . '/.git');
    }

    /**
     * Check if this package's files should be left alone on disk.
     *
     * drupal-core lives inside the project's own git repo rather than a
     * separate checkout, so .git is in the parent. Preserve it whenever the
     * directory exists, regardless of dist type: letting composer process a
     * dist-type change (e.g. zip in installed.json to path in the lock)
     * triggers a destructive remove + install that wipes out core/.
     *
     * download(), prepare() and cleanup() still fall through to the parent so
     * composer can set up package state (notably installationSource) that the
     * rest of its pipeline relies on.
     */
    private function shouldPreserveInstall(PackageInterface $package): bool
    {
        if ($this->hasGitCheckout($package)) {
            return true;
        }
        if ($package->getType() === 'drupal-core') {
            return is_dir($this->getInstallPath($package));
        }
        return false;
    }

    /**
     * If a git checkout exists, tell Composer the package is already installed.
     */
    public function isInstalled(InstalledRepositoryInterface $repo, PackageInterface $package): bool
    {
        if ($package instanceof AliasPackage) {
            return parent::isInstalled($repo, $package);
        }
        if ($this->shouldPreserveInstall($package)) {
            return true;
        }
        return parent::isInstalled($repo, $package);
    }

    /**
     * Skip download if a git checkout exists.
     *
     * Alias packages have no installation source of their own, so calling
     * parent::download() would throw. They are never downloaded individually;
     * Composer downloads the underlying package. Return a resolved promise so
     * parallel cleanup after another package fails does not surface the alias.
     */
    public function download(PackageInterface $package, ?PackageInterface $prevPackage = null): ?PromiseInterface
    {
        if ($package instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->hasGitCheckout($package)) {
            return \React\Promise\resolve(null);
        }
        return parent::download($package, $prevPackage);
    }

    /**
     * No-op prepare for preserved checkouts.
     */
    public function prepare($type, PackageInterface $package, ?PackageInterface $prevPackage = null): ?PromiseInterface
    {
        if ($package instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->hasGitCheckout($package)) {
            return \React\Promise\resolve(null);
        }
        return parent::prepare($type, $package, $prevPackage);
    }

    /**
     * No-op cleanup for preserved checkouts.
     */
    public function cleanup($type, PackageInterface $package, ?PackageInterface $prevPackage = null): ?PromiseInterface
    {
        if ($package instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->hasGitCheckout($package)) {
            return \React\Promise\resolve(null);
        }
        return parent::cleanup($type, $package, $prevPackage);
    }

    /**
     * Skip install if a git checkout exists; just register the package.
     */
    public function install(InstalledRepositoryInterface $repo, PackageInterface $package): ?PromiseInterface
    {
        if ($package instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->shouldPreserveInstall($package)) {
            if (!$repo->hasPackage($package)) {
                $repo->addPackage(clone $package);
            }
            $this->io->writeError(sprintf(
                '  - Preserving git checkout of <info>%s</info>',
                $package->getName()
            ));
            return \React\Promise\resolve(null);
        }
        return parent::install($repo, $package);
    }

    /**
     * Handle uninstall for packages that were preserved (no source/dist set).
     * Just remove from the repository. The actual directory cleanup is handled
     * by the "ddev remove-module" command.
     */
    public function uninstall(InstalledRepositoryInterface $repo, PackageInterface $package): ?PromiseInterface
    {
        if ($package instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->shouldPreserveInstall($package)) {
            $repo->removePackage($package);
            return \React\Promise\resolve(null);
        }
        return parent::uninstall($repo, $package);
    }

    /**
     * Skip update if a git checkout exists; just update the repository record.
     */
    public function update(InstalledRepositoryInterface $repo, PackageInterface $initial, PackageInterface $target): ?PromiseInterface
    {
        if ($target instanceof AliasPackage) {
            return \React\Promise\resolve(null);
        }
        if ($this->shouldPreserveInstall($target)) {
            $repo->removePackage($initial);
            if (!$repo->hasPackage($target)) {
                $repo->addPackage(clone $target);
            }
            $this->io->writeError(sprintf(
                '  - Preserving git checkout of <info>%s</info>',
                $target->getName()
            ));
            return \React\Promise\resolve(null);
        }
        return parent::update($repo, $initial, $target);
    }
}
