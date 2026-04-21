<?php
// #ddev-generated

namespace DrupalDev\ComposerGitInstaller;

use Composer\Semver\VersionParser;

/**
 * Parses a composer.lock file into a name-keyed dictionary of locked packages.
 *
 * Returned entries merge the lock's `packages` and `packages-dev` sections,
 * exclude platform packages and the root package, and cross-reference the
 * top-level `aliases` array.
 */
class LockFileParser
{
    /**
     * @return array<string, array{
     *     name: string,
     *     version: string,
     *     version_normalized: string,
     *     source_reference: ?string,
     *     dist_reference: ?string,
     *     dist_url: ?string,
     *     is_dev: bool,
     *     alias: ?array{alias: string, alias_normalized: string}
     * }>
     */
    public static function parse(string $lockPath, ?string $rootPackageName = null): array
    {
        if (!is_file($lockPath)) {
            throw new \RuntimeException("composer.lock not found at {$lockPath}");
        }

        $raw = file_get_contents($lockPath);
        if ($raw === false) {
            throw new \RuntimeException("Unable to read {$lockPath}");
        }

        $data = json_decode($raw, true);
        if (!is_array($data)) {
            throw new \RuntimeException("Malformed composer.lock at {$lockPath}: not valid JSON");
        }

        if (!isset($data['plugin-api-version']) || !is_string($data['plugin-api-version']) || !str_starts_with($data['plugin-api-version'], '2.')) {
            throw new \RuntimeException("Unsupported composer.lock format at {$lockPath}: Composer 2.x lock required");
        }

        $aliasMap = self::buildAliasMap($data['aliases'] ?? []);
        $versionParser = new VersionParser();
        $rootName = $rootPackageName !== null ? strtolower($rootPackageName) : null;
        $result = [];

        foreach (['packages', 'packages-dev'] as $section) {
            foreach ($data[$section] ?? [] as $entry) {
                if (!is_array($entry) || !isset($entry['name'], $entry['version']) || !is_string($entry['name']) || !is_string($entry['version'])) {
                    continue;
                }

                $name = $entry['name'];
                if ($rootName !== null && strtolower($name) === $rootName) {
                    continue;
                }
                if (PlatformPackages::isPlatform($name)) {
                    continue;
                }

                $version = $entry['version'];
                try {
                    $normalized = $versionParser->normalize($version);
                } catch (\UnexpectedValueException $e) {
                    throw new \RuntimeException("Malformed composer.lock at {$lockPath}: package {$name} has invalid version '{$version}'", 0, $e);
                }

                $result[$name] = [
                    'name' => $name,
                    'version' => $version,
                    'version_normalized' => $normalized,
                    'source_reference' => $entry['source']['reference'] ?? null,
                    'dist_reference' => $entry['dist']['reference'] ?? null,
                    'dist_url' => $entry['dist']['url'] ?? null,
                    'is_dev' => str_starts_with($version, 'dev-') || str_ends_with($normalized, '-dev'),
                    'alias' => $aliasMap[$name] ?? null,
                ];
            }
        }

        return $result;
    }

    /**
     * @param array<int, mixed> $aliases
     * @return array<string, array{alias: string, alias_normalized: string}>
     */
    private static function buildAliasMap(array $aliases): array
    {
        $map = [];
        foreach ($aliases as $entry) {
            if (!is_array($entry) || !isset($entry['package'], $entry['alias']) || !is_string($entry['package']) || !is_string($entry['alias'])) {
                continue;
            }
            $map[$entry['package']] = [
                'alias' => $entry['alias'],
                'alias_normalized' => is_string($entry['alias_normalized'] ?? null) ? $entry['alias_normalized'] : $entry['alias'],
            ];
        }
        return $map;
    }
}
