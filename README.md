[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/amateescu/ddev-drupal-dev/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/amateescu/ddev-drupal-dev/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/amateescu/ddev-drupal-dev)](https://github.com/amateescu/ddev-drupal-dev/commits)
[![release](https://img.shields.io/github/v/release/amateescu/ddev-drupal-dev)](https://github.com/amateescu/ddev-drupal-dev/releases/latest)

# DDEV Drupal Dev

## Overview

This add-on integrates Drupal Dev into your [DDEV](https://ddev.com/) project.

## Installation

```bash
ddev add-on get amateescu/ddev-drupal-dev
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev describe` | View service status and used ports for Drupal Dev |
| `ddev logs -s drupal-dev` | Check Drupal Dev logs |

## Advanced Customization

To change the Docker image:

```bash
ddev dotenv set .ddev/.env.drupal-dev --drupal-dev-docker-image="ddev/ddev-utilities:latest"
ddev add-on get amateescu/ddev-drupal-dev
ddev restart
```

Make sure to commit the `.ddev/.env.drupal-dev` file to version control.

All customization options (use with caution):

| Variable | Flag | Default |
| -------- | ---- | ------- |
| `DRUPAL_DEV_DOCKER_IMAGE` | `--drupal-dev-docker-image` | `ddev/ddev-utilities:latest` |

## Credits

**Contributed and maintained by [@amateescu](https://github.com/amateescu)**
