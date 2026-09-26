#!/bin/sh
# Copy the Android half of the Camera2 bridge from a phone that has RAWfish
# installed, and keep it here under Fiat Lux's own name.
#
#   camera2/fetch-bridge.sh [user@phone]
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
phone=${1:-defaultuser@192.168.2.15}
out="$here/prebuilt/libfiatluxcamera2.so"

mkdir -p "$here/prebuilt"
echo "Copying libsfoscamera2.so from $phone ..."
scp "$phone:/usr/libexec/droid-hybris/system/lib64/libsfoscamera2.so" "$out.part"
mv "$out.part" "$out"

if command -v file >/dev/null 2>&1; then
    file "$out"
fi
echo "Saved $out"
