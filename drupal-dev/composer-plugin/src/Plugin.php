<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
use Composer\Json\JsonFile;
use Composer\Package\AliasPackage;
use Composer\Package\Locker;
use Composer\Package\Version\VersionParser;
use Composer\Plugin\PluginInterface;

class Plugin implements PluginInterface, EventSubscriberInterface
{
    private Composer $composer;
    private IOInterface $io;

    public static function getSubscribedEvents(): array
    {
        return [
            'pre-command-run' => ['onPreCommand', -100],
        ];
    }

    public function activate(Composer $composer, IOInterface $io): void
    {
        $this->composer = $composer;
        $this->io = $io;

        $coreFile = getcwd() . '/composer.json';
        if (file_exists($coreFile)) {
            $coreConfig = json_decode(file_get_contents($coreFile), true);

            // Seed installer-paths from core's composer.json into the root
            // package extra so the fallback in getInstallPath() works before
            // the merge plugin has had a chance to merge core's extra.
            $rootExtra = $composer->getPackage()->getExtra();
            if (empty($rootExtra['installer-paths']) && !empty($coreConfig['extra']['installer-paths'])) {
                $rootExtra['installer-paths'] = $coreConfig['extra']['installer-paths'];
                $composer->getPackage()->setExtra($rootExtra);
            }

            $platform = $coreConfig['config']['platform'] ?? [];
            if (is_array($platform) && $platform !== []) {
                $this->dropSyncedPlatformFromRootFile($platform);
            }
        }

        $this->pinRootVersionFromCoreLock();
        $this->registerInstaller();

        $composer->getEventDispatcher()->addSubscriber(new CoreLockPinner($composer, $io));
    }

    /**
     * Re-register before each command so our installer takes priority over
     * composer/installers, which activates from vendor after us.
     */
    public function onPreCommand(): void
    {
        $this->registerInstaller();
    }

    /**
     * Pin the root package's version from drupal/core's entry in composer.lock.
     *
     * composer-merge-plugin substitutes 'self.version' in merged requirements
     * with the root package's version. Composer's VersionGuesser is unreliable
     * inside the web container, and a missed guess defaults to 1.0.0.0, which
     * makes drupal/core's self.version requirements (drupal/core,
     * core-project-message, core-recipe-unpack, core-vendor-hardening)
     * unresolvable.
     *
     * core's own composer.lock always records drupal/core at the canonical
     * composer version for the current branch/tag (dev-main, 11.x-dev,
     * 11.1.6, …), so we take it from there.
     */
    private function pinRootVersionFromCoreLock(): void
    {
        $lockFile = new JsonFile(getcwd() . '/composer.lock');
        if (!$lockFile->exists()) {
            return;
        }

        $locker = new Locker($this->io, $lockFile, $this->composer->getInstallationManager(), '{}');
        if (!$locker->isLocked()) {
            return;
        }

        $package = $locker->getLockedRepository()->findPackage('drupal/core', '*');
        if (!$package) {
            return;
        }

        $root = $this->composer->getPackage();
        while ($root instanceof AliasPackage) {
            $root = $root->getAliasOf();
        }

        // Package's version-related fields are write-once via the constructor
        // and have no setters in modern Composer, so reflect to override them.
        $stability = VersionParser::parseStability($package->getVersion());
        $values = [
            'version' => $package->getVersion(),
            'prettyVersion' => $package->getPrettyVersion(),
            'stability' => $stability,
            'dev' => $stability === 'dev',
        ];
        $reflection = new \ReflectionClass($root);
        foreach ($values as $name => $value) {
            if (!$reflection->hasProperty($name)) {
                continue;
            }
            $property = $reflection->getProperty($name);
            $property->setValue($root, $value);
        }
    }

    private function registerInstaller(): void
    {
        $installer = new GitPreservingInstaller($this->io, $this->composer);
        $this->composer->getInstallationManager()->addInstaller($installer);
    }

    /**
     * Remove a config.platform that an older version of this plugin wrote into
     * the root composer file (composer.local.json).
     *
     * A platform in the root file constrains the solver and install-time checks
     * for everything in the overlay, so packages needing a newer PHP than
     * core's declared minimum become uninstallable, and an existing lock built
     * without the pin stops satisfying it. PHPStan gets core's version from
     * core's own composer.json instead, through the phpstan command.
     *
     * Only removes a value identical to core's, which is what the old sync
     * wrote. A platform the user set themselves is left alone.
     *
     * @param array<string, string> $platform
     */
    private function dropSyncedPlatformFromRootFile(array $platform): void
    {
        $configSource = $this->composer->getConfig()->getConfigSource();
        $rootFile = $configSource->getName();

        // Only act on an overlay separate from the core composer.json.
        if (basename($rootFile) === 'composer.json' || !file_exists($rootFile)) {
            return;
        }

        $rootData = json_decode((string) file_get_contents($rootFile), true);
        if (!is_array($rootData) || ($rootData['config']['platform'] ?? null) !== $platform) {
            return;
        }

        $configSource->removeConfigSetting('platform');
        $this->io->writeError('<info>Removed config.platform from ' . basename($rootFile) . '. It was mirrored from core and constrained every package in the overlay.</info>');

        // The lock records the platform it was solved with, and install honours
        // that, so a lock written while the mirror was in place stays stuck
        // until it is solved again.
        $lockFile = substr($rootFile, 0, -strlen('.json')) . '.lock';
        if (!file_exists($lockFile)) {
            return;
        }
        $lockData = json_decode((string) file_get_contents($lockFile), true);
        if (is_array($lockData) && ($lockData['platform-overrides'] ?? null) === $platform) {
            $this->io->writeError('<info>Run "ddev composer update" once to drop the matching platform-overrides from ' . basename($lockFile) . '.</info>');
        }
    }

    public function deactivate(Composer $composer, IOInterface $io): void
    {
    }

    public function uninstall(Composer $composer, IOInterface $io): void
    {
    }
}
