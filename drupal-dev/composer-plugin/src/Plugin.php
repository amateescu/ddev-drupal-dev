<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\Factory;
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

            // Mirror core's config.platform so composer resolves dependencies
            // against core's declared PHP version instead of the runtime one.
            // composer-merge-plugin only merges package metadata, not config.
            $platform = $coreConfig['config']['platform'] ?? [];
            if (is_array($platform)) {
                $composer->getConfig()->merge(['config' => ['platform' => $platform]], $coreFile);
                $this->syncPlatformToRootFile($platform);
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
     * Mirror config.platform into the root composer file (composer.local.json).
     *
     * PHPStan runs in its own process and reads config.platform straight from
     * the root composer file (via the $COMPOSER env var), so the in-memory
     * Config merge is not visible to it. Adds, updates or removes the setting
     * so the file always matches core, and only writes when the value changed.
     *
     * @param array<string, string> $platform
     */
    private function syncPlatformToRootFile(array $platform): void
    {
        $configSource = $this->composer->getConfig()->getConfigSource();
        $rootFile = $configSource->getName();

        // Only act when the root file is an overlay separate from the core
        // composer.json we just read.
        if (basename($rootFile) === 'composer.json' || !file_exists($rootFile)) {
            return;
        }

        $oldContents = (string) file_get_contents($rootFile);
        $rootData = json_decode($oldContents, true);
        if (!is_array($rootData)) {
            return;
        }

        $current = $rootData['config']['platform'] ?? null;
        if ($platform === []) {
            if ($current === null) {
                return;
            }
            $configSource->removeConfigSetting('platform');
            $this->io->writeError('<info>Removed config.platform from ' . basename($rootFile) . ' because core no longer declares one.</info>');
        } else {
            if ($current === $platform) {
                return;
            }
            $configSource->addConfigSetting('platform', $platform);
            $this->io->writeError('<info>Synced config.platform from core composer.json into ' . basename($rootFile) . '.</info>');
        }

        $this->refreshLockContentHash($rootFile, $oldContents);
    }

    /**
     * Keep lock content hashes consistent after the root composer file changed
     * on disk during plugin activation.
     *
     * config.platform is part of the lock's content hash and the Locker
     * snapshots the root file before plugins are activated, so without a
     * refresh every install after a platform sync warns that the lock file is
     * out of date. Updates the Locker's in-memory hash for lock files written
     * later in this run, and re-stamps the lock file on disk when the sync is
     * the only divergence. Any other divergence, like a manual edit to the
     * root file, keeps the warning.
     */
    private function refreshLockContentHash(string $rootFile, string $oldContents): void
    {
        $locker = $this->composer->getLocker();
        if (!$locker) {
            return;
        }

        // The content hash is private with no setter, so reflect.
        $newHash = Locker::getContentHash((string) file_get_contents($rootFile));
        $reflection = new \ReflectionClass($locker);
        if ($reflection->hasProperty('contentHash')) {
            $reflection->getProperty('contentHash')->setValue($locker, $newHash);
        }

        $lockFile = Factory::getLockFile($rootFile);
        if (!file_exists($lockFile)) {
            return;
        }
        $lockData = json_decode((string) file_get_contents($lockFile), true);
        if (!is_array($lockData) || ($lockData['content-hash'] ?? null) !== Locker::getContentHash($oldContents)) {
            return;
        }
        if (!method_exists($locker, 'updateHash')) {
            return;
        }
        try {
            $locker->updateHash(new JsonFile($rootFile, null, $this->io));
        } catch (\Exception $e) {
            // A lock file that cannot be read or parsed is left alone.
        }
    }

    public function deactivate(Composer $composer, IOInterface $io): void
    {
    }

    public function uninstall(Composer $composer, IOInterface $io): void
    {
    }
}
