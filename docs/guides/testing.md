# Running tests

## PHPUnit

`ddev phpunit` runs PHPUnit with core's configuration:

```bash
ddev phpunit core/modules/node             # a core module
ddev phpunit modules/contrib/token         # a contrib module
ddev phpunit core/modules/node --filter testNodeCreation
```

Every argument except `--db`, `--memory` and `--no-memory` goes to PHPUnit unchanged, including patterns with shell characters such as `--filter 'testFoo|testBar'`.

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
ddev phpunit --db=mysql core/modules/node       # MySQL
```

SQLite needs no setup. Its database is in memory unless you pass `--no-memory`, see [Faster runs](#faster-runs-database-in-memory).

### PostgreSQL

If the project's database is PostgreSQL, `--db=pgsql` uses it and needs no extra container.

For a project whose database is MySQL or MariaDB, add a second database container from the example the add-on installs:

```bash
sed '/^#ddev-generated$/d' .ddev/drupal-dev/docker-compose.postgres.yaml.example > .ddev/docker-compose.postgres.yaml
ddev restart
```

Set the image tag in `.ddev/docker-compose.postgres.yaml` to the PostgreSQL version you want to test. The container keeps its data in memory.

`--db=pgsql` works with any container named `ddev-<project>-postgres` that has a `db` database with the db/db credentials, such as one you wrote yourself. `--memory` uses it only if its data directory, the container's `PGDATA`, is on tmpfs. For a container with its data on a volume, replace the volume with a `tmpfs` entry for that directory, for example `/var/lib/postgresql/18/docker` for `postgres:18`.

### MariaDB

If the project's database is MariaDB, `--db=mariadb` uses it and needs no extra container.

For a project whose database is MySQL or PostgreSQL, add a second database container from the example the add-on installs:

```bash
sed '/^#ddev-generated$/d' .ddev/drupal-dev/docker-compose.mariadb.yaml.example > .ddev/docker-compose.mariadb.yaml
ddev restart
```

Set the image tag in `.ddev/docker-compose.mariadb.yaml` to the MariaDB version you want to test. The container keeps its data in memory, so its tests run as fast as on testdb.

A copy made before the add-on moved this container to memory keeps its data on disk, and `--memory` doesn't use it. To switch, copy the example again with the `sed` command above and restart. The old data stays in a volume until you remove it with `docker volume rm ddev-<project>_mariadb-data`.

### MySQL

If the project's database is MySQL, `--db=mysql` uses it and needs no extra container.

For a project whose database is MariaDB or PostgreSQL, add a second database container from the example the add-on installs:

```bash
sed '/^#ddev-generated$/d' .ddev/drupal-dev/docker-compose.mysql.yaml.example > .ddev/docker-compose.mysql.yaml
ddev restart
```

Set the image tag in `.ddev/docker-compose.mysql.yaml` to the MySQL version you want to test. Like the MariaDB container, it keeps its data in memory.

## Faster runs: database in memory

Kernel and functional tests spend most of their time creating and dropping tables. With the database in memory those statements don't wait for the disk, which makes a typical kernel test class about three times faster.

The add-on includes a second database container, testdb, that keeps its data in memory. It runs the same database server as the project database, so results match a run on the project database. For MySQL and MariaDB it uses DDEV's database image and the same `.ddev/mysql` configuration. For PostgreSQL it uses the official image with its default configuration. The project database stays on disk and doesn't get any test tables.

testdb is behind a Docker Compose profile and doesn't run until you turn it on. To keep it on for the project:

```bash
ddev dotenv set .ddev/.env --compose-profiles=testdb && ddev restart
```

If `COMPOSE_PROFILES` in `.ddev/.env` already lists other profiles, add `testdb` to the list instead, for example `--compose-profiles=other,testdb`. To start it only until the next restart, without restarting anything else:

```bash
ddev start --profiles=testdb
```

While testdb runs, `ddev phpunit` uses it by default:

```bash
ddev phpunit core/modules/node                          # testdb, while it runs
ddev phpunit --no-memory core/modules/node              # the project database
ddev phpunit --memory core/modules/node                 # testdb, or an error with how to start it
ddev phpunit --memory --db=mariadb core/modules/node    # MariaDB, in memory
ddev phpunit --db=sqlite core/modules/node              # SQLite, in memory
```

| Command | Project on MySQL | Project on MariaDB | Project on PostgreSQL |
| ------- | ---------------- | ------------------ | --------------------- |
| no `--db`, testdb running | testdb | testdb | testdb |
| `--memory` | testdb | testdb | testdb |
| `--memory --db=mysql` | testdb | the [mysql container](#mysql) | the [mysql container](#mysql) |
| `--memory --db=mariadb` | the [mariadb container](#mariadb) | testdb | the [mariadb container](#mariadb) |
| `--memory --db=pgsql` | the [postgres container](#postgresql) | the [postgres container](#postgresql) | testdb |
| `--db=sqlite` | the web container's `/mnt/test-db` | the web container's `/mnt/test-db` | the web container's `/mnt/test-db` |
| `--no-memory` | the project database | the project database | the project database |
| `--no-memory --db=sqlite` | `sites/default/files/db.sqlite` | `sites/default/files/db.sqlite` | `sites/default/files/db.sqlite` |

A separate container has to keep its data in memory for `--memory` to use it. `ddev phpunit` doesn't start testdb itself. The output shows which database a run uses, for example `Using database: mysql (in memory)`.

Things to know:

- The data is gone on every restart. Tests don't need it to stay: each test creates its own tables.
- testdb sets up an empty data directory each time it starts, which adds a few seconds to `ddev start`.
- Memory use is capped at 1 GB per container and 256 MB for SQLite, and only what is stored counts. An empty MySQL or MariaDB server takes about 350 MB of testdb's cap, and a run of core's Views kernel tests added about 30 MB on top. An empty PostgreSQL server takes about 50 MB. To raise a cap, change the `size=` of the `tmpfs` entry and restart: in `.ddev/docker-compose.drupal-dev-testdb.yaml` for testdb, `.ddev/docker-compose.drupal-dev-sqlite.yaml` for SQLite, or your copy of the mysql, mariadb or postgres example. Remove the `#ddev-generated` line from an add-on file first, so updating the add-on doesn't overwrite your change.
- A SQLite test that crashes leaves its database file in `/mnt/test-db` until the next restart.

## Browser tests

The add-on runs a Selenium Chromium container for functional JavaScript tests. They run like any other test:

```bash
ddev phpunit core/modules/ckeditor5/tests/src/FunctionalJavascript
```

`ddev phpunit` closes any WebDriver sessions left over from an earlier run before it starts.

To watch the browser while a test runs, open `https://<project>.ddev.site:7900` (noVNC, password `secret`).

HTML output of browser tests goes to `test_output/` in the project root.
