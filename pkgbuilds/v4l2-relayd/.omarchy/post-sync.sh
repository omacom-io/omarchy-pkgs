#!/bin/bash

set -euo pipefail
sed -i "s/^arch=.*/arch=('x86_64' 'aarch64')/" PKGBUILD
