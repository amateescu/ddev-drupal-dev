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

        // Seed installer-paths from core's composer.json into the root package
        // extra so the fallback in getInstallPath() works before the merge
        // plugin has had a chance to merge core's extra.
        $rootExtra = $composer->getPackage()->getExtra();
        if (empty($rootExtra['installer-paths'])) {
            $coreFile = getcwd() . '/composer.json';
            if (file_exists($coreFile)) {
                $coreConfig = json_decode(file_get_contents($coreFile), true);
                if (!empty($coreConfig['extra']['installer-paths'])) {
                    $rootExtra['installer-paths'] = $coreConfig['extra']['installer-paths'];
                    $composer->getPackage()->setExtra($rootExtra);
                }
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

    public function deactivate(Composer $composer, IOInterface $io): void
    {
    }

    public function uninstall(Composer $composer, IOInterface $io): void
    {
    }
}
