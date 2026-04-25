<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Package\Link;
use Composer\Package\PackageInterface;
use Composer\Semver\Constraint\Constraint;

/**
 * Finds overlay requirements whose constraints exclude the locked version
 * of a package from core's composer.lock.
 */
class ConflictDetector
{
    /**
     * @param array<Link> $links Root require + require-dev links to check.
     * @param array<string, PackageInterface> $locked
     * @return array<int, array{name: string, overlay_constraint: string, locked_version: string}>
     */
    public static function detect(array $links, array $locked): array
    {
        $conflicts = [];
        foreach ($links as $link) {
            $name = $link->getTarget();
            if (!isset($locked[$name])) {
                continue;
            }
            $lockedConstraint = new Constraint('==', $locked[$name]->getVersion());
            if ($link->getConstraint()->matches($lockedConstraint)) {
                continue;
            }
            $conflicts[] = [
                'name' => $name,
                'overlay_constraint' => $link->getPrettyConstraint(),
                'locked_version' => $locked[$name]->getPrettyVersion(),
            ];
        }
        return $conflicts;
    }
}
