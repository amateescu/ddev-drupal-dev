<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

/**
 * Identifies Composer platform packages by name.
 *
 * Platform packages represent the runtime environment (PHP, extensions,
 * Composer itself) and cannot be installed or pinned like regular packages.
 */
class PlatformPackages
{
    private const EXACT = ['php', 'composer'];

    private const PREFIXES = ['php-', 'ext-', 'lib-', 'composer-'];

    public static function isPlatform(string $name): bool
    {
        $name = strtolower($name);
        if (in_array($name, self::EXACT, true)) {
            return true;
        }
        foreach (self::PREFIXES as $prefix) {
            if (str_starts_with($name, $prefix)) {
                return true;
            }
        }
        return false;
    }
}
