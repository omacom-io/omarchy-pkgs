#!/bin/bash
set -euo pipefail

x86_hash=$(sed -n '/^sha256sums=(/,/)/p' PKGBUILD | grep -oE '[0-9a-f]{64}' | head -n 1)
[[ -n $x86_hash ]] || { echo "ERROR: Grok Bot x86_64 checksum is missing" >&2; exit 1; }

sed -i "s/arch=('x86_64')/arch=('x86_64' 'aarch64')/" PKGBUILD
sed -i '/^source=(/,/^)/c\source=(\n  "grok-bot.sh"\n  "grok-bot.desktop"\n)\nsource_x86_64=("${pkgname}_${pkgver}.deb::https://downloads.cursor.com/grokbot/stable/${_commit}/linux/x64/Grok_Bot_${pkgver}.deb")\nsource_aarch64=("${pkgname}_${pkgver}.deb::https://downloads.cursor.com/grokbot/stable/${_commit}/linux/arm64/Grok_Bot_${pkgver}.deb")' PKGBUILD
sed -i "/^sha256sums=(/,/)/c\\sha256sums=(\\n  '6dfa6c305941afa6cbaefbeaae06d05ab5a88f31630005d25a819a160c20c7a3'\\n  '856056c9ca63dda5d01158ce8fb6a9a7cbb3f67c13a92b573cd196d3e50f26e7'\\n)\\nsha256sums_x86_64=('$x86_hash')\\nsha256sums_aarch64=('SKIP')" PKGBUILD

pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
commit=$(sed -n 's/^_commit=//p' PKGBUILD)
arm_url="https://downloads.cursor.com/grokbot/stable/${commit}/linux/arm64/Grok_Bot_${pkgver}.deb"
arm_checksum=$(curl -fsSL --retry 3 "$arm_url" | sha256sum | awk '{ print $1 }')
sed -i "s/sha256sums_aarch64=('SKIP')/sha256sums_aarch64=('${arm_checksum}')/" PKGBUILD
