#!/bin/bash
set -euo pipefail

sed -i "s/'armv7h')/'armv7h' 'aarch64')/" PKGBUILD
