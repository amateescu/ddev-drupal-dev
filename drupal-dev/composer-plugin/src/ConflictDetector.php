<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Package\Link;
use Composer\Semver\Constraint\Constraint;

/**
 * Finds overlay requirements whose constraints exclude the locked version
 * of a package from core's composer.lock.
 */
class ConflictDetector
{
    /**
     * @param array<Link> $links Root require + require-dev links to check.
     * @param array<string, array{version: string, version_normalized: string}> $locked
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
            $lockedConstraint = new Constraint('==', $locked[$name]['version_normalized']);
            if ($link->getConstraint()->matches($lockedConstraint)) {
                continue;
            }
            $conflicts[] = [
                'name' => $name,
                'overlay_constraint' => $link->getPrettyConstraint(),
                'locked_version' => $locked[$name]['version'],
            ];
        }
        return $conflicts;
    }
}
