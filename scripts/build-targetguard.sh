#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-"$root/addons/targetguard/targetguard.dll"}
mkdir -p "$(dirname -- "$out")"
i686-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror -shared \
  -static-libgcc -Wl,--no-insert-timestamp -o "$out" "$root/addons/targetguard/targetguard.c"
