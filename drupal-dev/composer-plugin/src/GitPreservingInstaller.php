<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Installer\LibraryInstaller;
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
    private const SUPPORTED_TYPES = ['drupal-module', 'drupal-theme', 'drupal-profile'];

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

        throw new \RuntimeException("No installer-paths entry found for package type '$type'. Ensure your Composer configuration defines installer-paths.");
    }

    /**
     * Check if the install path has a git checkout.
     */
    private function hasGitCheckout(PackageInterface $package): bool
    {
        $installPath = $this->getInstallPath($package);
        return is_dir($installPath . '/.git');
    }

    /**
     * If a git checkout exists, tell Composer the package is already installed.
     */
    public function isInstalled(InstalledRepositoryInterface $repo, PackageInterface $package): bool
    {
        if ($this->hasGitCheckout($package)) {
            return true;
        }
        return parent::isInstalled($repo, $package);
    }

    /**
     * Skip download if a git checkout exists.
     */
    public function download(PackageInterface $package, ?PackageInterface $prevPackage = null): ?PromiseInterface
    {
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
        if ($this->hasGitCheckout($package)) {
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
        if ($this->hasGitCheckout($package)) {
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
        if ($this->hasGitCheckout($target)) {
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
