# Running tests

## PHPUnit

`ddev phpunit` runs PHPUnit with core's configuration:

```bash
ddev phpunit core/modules/node             # a core module
ddev phpunit modules/contrib/token         # a contrib module
ddev phpunit core/modules/node --filter testNodeCreation
```

Every argument except `--db` goes to PHPUnit unchanged, including patterns with shell characters such as `--filter 'testFoo|testBar'`.

Test paths are relative to the directory you run the command from, so inside a module you can leave out the module's own path:

```bash
cd modules/contrib/token
ddev phpunit tests/src/Kernel
```

## Choosing a database

Tests run against the project's database by default. `--db` picks another one:

```bash
ddev phpunit --db=sqlite core/modules/node      # SQLite
ddev phpunit --db=pgsql core/modules/node       # PostgreSQL
ddev phpunit --db=mariadb core/modules/node     # MariaDB
ddev phpunit --db=mysql core/modules/node       # the project's db container, the default
```

SQLite needs no setup.

### PostgreSQL

If the project's database is PostgreSQL, `--db=pgsql` uses it. Otherwise install the [ddev-postgres](https://github.com/ddev/ddev-postgres) add-on first, which adds a second database container.

### MariaDB

If the project's database is MariaDB, `--db=mariadb` uses it and needs no extra container.

For a project whose database is MySQL, add a second database container from the example the add-on installs:

```bash
sed '/^#ddev-generated$/d' .ddev/drupal-dev/docker-compose.mariadb.yaml.example > .ddev/docker-compose.mariadb.yaml
ddev restart
```

Set the image tag in `.ddev/docker-compose.mariadb.yaml` to the MariaDB version you want to test.

## Browser tests

The add-on runs a Selenium Chromium container for functional JavaScript tests. They run like any other test:

```bash
ddev phpunit core/modules/ckeditor5/tests/src/FunctionalJavascript
```

`ddev phpunit` closes any WebDriver sessions left over from an earlier run before it starts.

To watch the browser while a test runs, open `https://<project>.ddev.site:7900` (noVNC, password `secret`).

HTML output of browser tests goes to `test_output/` in the project root.
