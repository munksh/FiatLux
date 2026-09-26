#!/bin/sh
# Build the Android half of the Camera2 bridge with the Android NDK.
# Same flags as RAWfish's scripts/build-android.sh; only the output name
# differs.
#
#   ANDROID_NDK_HOME=~/android-ndk-r27c camera2/build-bridge.sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ndk_dir=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}

if [ -z "$ndk_dir" ]; then
    for guess in "$HOME/android-ndk-r27c" "$HOME/Android/Sdk/ndk/27.2.12479018"; do
        [ -d "$guess" ] && ndk_dir=$guess && break
    done
fi
if [ -z "$ndk_dir" ]; then
    echo "Set ANDROID_NDK_HOME to the Android NDK (r27c):" >&2
    echo "  https://dl.google.com/android/repository/android-ndk-r27c-linux.zip" >&2
    exit 2
fi

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) host_tag=linux-x86_64 ;;
    Darwin-*) host_tag=darwin-x86_64 ;;
    *) echo "Unsupported NDK host: $(uname -s)-$(uname -m)" >&2; exit 3 ;;
esac

cc="$ndk_dir/toolchains/llvm/prebuilt/$host_tag/bin/aarch64-linux-android24-clang"
if [ ! -x "$cc" ]; then
    echo "Android NDK compiler not found: $cc" >&2
    exit 4
fi

mkdir -p "$here/prebuilt"
"$cc" \
    -std=c11 -O2 -g -fPIC -fvisibility=hidden -pthread \
    -Wall -Wextra -Werror \
    -shared -Wl,--no-undefined \
    "$here/android/camera2_bridge.c" \
    "$here/android/camera2_common.c" \
    "$here/android/raw_capture.c" \
    "$here/android/preview.c" \
    "$here/android/jpeg_capture.c" \
    -I"$here/android" \
    -lcamera2ndk -lmediandk -landroid \
    -o "$here/prebuilt/libfiatluxcamera2.so"

echo "Built $here/prebuilt/libfiatluxcamera2.so"
