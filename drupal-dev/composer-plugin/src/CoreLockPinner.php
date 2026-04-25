<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\Factory;
use Composer\IO\IOInterface;
use Composer\Json\JsonFile;
use Composer\Package\CompletePackage;
use Composer\Package\Locker;
use Composer\Plugin\PluginEvents;
use Composer\Plugin\PrePoolCreateEvent;

/**
 * Pins the solver's pool to core's composer.lock versions for packages both
 * core and the overlay require.
 *
 * Activated by extra.drupal-dev.pin-core-lock in the overlay composer file.
 * Reads core's composer.lock fresh on every install and filters the solver's
 * pool to only candidate packages whose versions match the lock. Dev entries
 * have their source/dist references rewritten to match the locked SHA.
 *
 * Aliased lock entries are accepted on either side: both the underlying
 * package and the AliasPackage wrapper end up keyed under the same name,
 * and the wrapper proxies its references to the underlying package so dev
 * pinning works through the alias.
 */
class CoreLockPinner implements EventSubscriberInterface
{
    private const EXTRA_NAMESPACE = 'drupal-dev';
    private const FLAG_KEY = 'pin-core-lock';

    private Composer $composer;
    private IOInterface $io;

    public function __construct(Composer $composer, IOInterface $io)
    {
        $this->composer = $composer;
        $this->io = $io;
    }

    public static function getSubscribedEvents(): array
    {
        return [
            PluginEvents::PRE_POOL_CREATE => 'onPrePoolCreate',
        ];
    }

    public function onPrePoolCreate(PrePoolCreateEvent $event): void
    {
        if (!$this->isEnabled()) {
            return;
        }

        $lockPath = $this->locateCoreLock();
        if (!is_file($lockPath)) {
            throw new \RuntimeException(sprintf(
                "Core lock pinning is enabled but %s was not found.\n"
                . "Either generate core's composer.lock (`composer install` against core's composer.json),\n"
                . 'or set extra.drupal-dev.pin-core-lock to false in composer.local.json.',
                $lockPath
            ));
        }

        $locker = new Locker($this->io, new JsonFile($lockPath), $this->composer->getInstallationManager(), '{}');
        if (!$locker->isLocked()) {
            throw new \RuntimeException(sprintf(
                "Core lock pinning is enabled but %s is not a valid Composer lock file.",
                $lockPath
            ));
        }

        // Build a name-keyed map of locked packages. Aliases appear as both
        // the underlying package and an AliasPackage wrapping it; storing
        // both under the same name lets the pool filter accept either
        // version, and AliasPackage proxies its references to the underlying
        // package so dev-ref pinning works through the wrapper.
        /** @var array<string, list<\Composer\Package\PackageInterface>> $locked */
        $locked = [];
        foreach ($locker->getLockedRepository()->getPackages() as $pkg) {
            $locked[$pkg->getName()][] = $pkg;
        }

        if ($locked === []) {
            return;
        }

        $root = $this->composer->getPackage();
        $links = array_merge(array_values($root->getRequires()), array_values($root->getDevRequires()));
        $conflicts = ConflictDetector::detect($links, $locked);
        if ($conflicts !== []) {
            throw new \RuntimeException($this->formatConflictMessage($conflicts));
        }

        $this->io->writeError('<info>Core lock pinning active. If solve fails, try setting extra.drupal-dev.pin-core-lock to false to isolate the cause.</info>');

        $filtered = [];
        $seen = [];
        $matched = [];
        $poolVersions = [];
        foreach ($event->getPackages() as $package) {
            $name = $package->getName();
            if (!isset($locked[$name])) {
                $filtered[] = $package;
                continue;
            }
            $seen[$name] = true;
            $poolVersions[$name][] = $package->getPrettyVersion();
            $entry = null;
            foreach ($locked[$name] as $candidate) {
                if ($candidate->getVersion() === $package->getVersion()) {
                    $entry = $candidate;
                    break;
                }
            }
            if ($entry === null) {
                continue;
            }
            $matched[$name] = true;
            if ($entry->isDev() && $package instanceof CompletePackage) {
                $sourceRef = $entry->getSourceReference();
                if ($sourceRef !== null) {
                    $package->setSourceReference($sourceRef);
                }
                $distRef = $entry->getDistReference();
                if ($distRef !== null) {
                    $package->setDistReference($distRef);
                    // GitHub, GitLab, and Bitbucket archive URLs embed the
                    // commit SHA in the path. Setting distReference alone is
                    // not enough: the URL itself must be rewritten or the
                    // downloader fetches the wrong archive.
                    $oldUrl = $package->getDistUrl();
                    if ($oldUrl !== null && preg_match('/[a-f0-9]{40}/i', $oldUrl)) {
                        $package->setDistUrl(preg_replace('/[a-f0-9]{40}/i', $distRef, $oldUrl, 1));
                    } elseif ($oldUrl !== null && $this->io->isDebug()) {
                        $this->io->writeError(sprintf(
                            '<warning>pin-core-lock: %s has no 40-char SHA in dist URL (%s); pin may resolve to the wrong archive.</warning>',
                            $name,
                            $oldUrl
                        ));
                    }
                }
            }
            $filtered[] = $package;
        }

        $missing = array_diff_key($seen, $matched);
        if ($missing !== []) {
            throw new \RuntimeException($this->formatMissingVersionsMessage(array_keys($missing), $locked, $poolVersions));
        }

        $event->setPackages($filtered);
    }

    private function isEnabled(): bool
    {
        $extra = $this->composer->getPackage()->getExtra();
        return !empty($extra[self::EXTRA_NAMESPACE][self::FLAG_KEY]);
    }

    /**
     * Return the absolute path to core's composer.lock.
     *
     * The overlay file (composer.local.json) is what Composer loads when
     * COMPOSER points at it, so Factory::getComposerFile() returns the
     * overlay path. Core's composer.json always lives next to the overlay
     * in the project root, and so does core's composer.lock.
     */
    private function locateCoreLock(): string
    {
        $composerFile = Factory::getComposerFile();
        $real = realpath($composerFile);
        $dir = $real !== false ? dirname($real) : getcwd();
        return $dir . '/composer.lock';
    }

    /**
     * @param array<int, string> $names
     * @param array<string, list<\Composer\Package\PackageInterface>> $locked
     * @param array<string, array<int, string>> $poolVersions
     */
    private function formatMissingVersionsMessage(array $names, array $locked, array $poolVersions): string
    {
        $lines = ['Core lock pinning: locked versions not available in the dependency pool:'];
        foreach ($names as $name) {
            $pool = $poolVersions[$name] ?? [];
            $poolDesc = $pool === [] ? 'nothing' : implode(', ', array_unique($pool));
            $lockedDesc = implode('/', array_unique(array_map(static fn($p) => $p->getPrettyVersion(), $locked[$name])));
            $lines[] = sprintf('  %s: locked "%s", pool had %s', $name, $lockedDesc, $poolDesc);
        }
        $lines[] = '';
        $lines[] = 'If you enabled or changed pin-core-lock recently, your composer.local.lock is stale.';
        $lines[] = 'Run `ddev composer update` to regenerate it with pinning applied.';
        $lines[] = '';
        $lines[] = 'Otherwise core\'s composer.lock may reference a yanked version; update core\'s lock';
        $lines[] = 'or set extra.drupal-dev.pin-core-lock to false in composer.local.json.';
        return implode("\n", $lines);
    }

    /**
     * @param array<int, array{name: string, overlay_constraint: string, locked_version: string}> $conflicts
     */
    private function formatConflictMessage(array $conflicts): string
    {
        $lines = ['Core lock pinning conflict:'];
        foreach ($conflicts as $c) {
            $lines[] = sprintf(
                '  %s: overlay requires "%s", core\'s lock has "%s"',
                $c['name'],
                $c['overlay_constraint'],
                $c['locked_version']
            );
        }
        $lines[] = '';
        $lines[] = 'Either relax the overlay constraint, remove it if it is already in core\'s requires,';
        $lines[] = 'or set extra.drupal-dev.pin-core-lock to false in composer.local.json.';
        return implode("\n", $lines);
    }
}
