#!/bin/bash

set -euo pipefail

install -m0644 \
  .omarchy/files/limine-entry-tool-aarch64.patch \
  limine-entry-tool-aarch64.patch
