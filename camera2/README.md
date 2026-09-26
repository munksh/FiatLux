# camera2 — how Fiat Lux reaches the camera

Everything in `sailfish/` and `android/` is copied unchanged from
[RAWfish](https://github.com/Logic-gate/RAWfish) by Logic-gate
(`sfos-camera2-bridge/`, release v1.3.1-alpha.3), under the BSD 3-Clause
licence in `../LICENSE.RAWfish`. Fiat Lux carries its own copy so that RAWfish
does not have to be installed.

Two halves:

* `sailfish/main.c` — a small Sailfish program. Qt Creator builds it along
  with the app and it is installed as
  `/usr/libexec/harbour-fiatlux/camera2-helper`. It loads the Android half
  through libhybris and streams the preview, the exposure the camera chose,
  and a JPEG on request.
* `android/*.c` — the Android half, built with the Android NDK into
  `libfiatluxcamera2.so` and installed in
  `/usr/libexec/droid-hybris/system/lib64/`, where libhybris looks.
  (RAWfish's own copy is called `libsfoscamera2.so`; the different name
  keeps the two packages from colliding.)

The app sets `SFOS_CAMERA2_BRIDGE=libfiatluxcamera2.so` for the helper. If
either half is missing it falls back to RAWfish's, when RAWfish is installed.

## Getting `prebuilt/libfiatluxcamera2.so`

The Android half cannot be built by the Sailfish SDK, so the built library is
kept in `prebuilt/`. Two ways to get it:

1. **From a phone with RAWfish installed** (no NDK needed; it is the same
   code, built by its author):

       camera2/fetch-bridge.sh            # defaults to defaultuser@192.168.2.15

2. **Build it** with the Android NDK r27c:

       ANDROID_NDK_HOME=~/android-ndk-r27c camera2/build-bridge.sh

Either way, commit `prebuilt/libfiatluxcamera2.so`. The .pro refuses to build
without it.
