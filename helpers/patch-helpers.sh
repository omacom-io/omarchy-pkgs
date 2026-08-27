#!/bin/bash

apply_patch_strict() {
  local package_dir="$1"
  local patch_file="$2"

  (
    cd "$package_dir"
    patch -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch < "$patch_file"
  )
}
