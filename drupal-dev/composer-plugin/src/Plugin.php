<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
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

        $this->registerInstaller();
    }

    /**
     * Re-register before each command so our installer takes priority over
     * composer/installers, which activates from vendor after us.
     */
    public function onPreCommand(): void
    {
        $this->registerInstaller();
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
