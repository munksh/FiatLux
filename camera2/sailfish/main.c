/**
 * @file main.c
 * @brief Sailfish command-line frontend for the Android Camera2 bridge.
 *
 * Loads the Android bridge library through libhybris, parses RAWfish helper
 * command-line options, and dispatches probe, preview, RAW, or JPEG operations.
 */

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../android/camera2_bridge.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef void *(*android_dlopen_fn)(const char *name, int flags);
typedef void *(*android_dlsym_fn)(void *handle, const char *name);
typedef int (*probe_fn)(char *out, size_t out_size);
typedef int (*capture_options_fn)(
    const char *camera_id, int width, int height,
    const char *raw_path, const char *metadata_path, int timeout_ms,
    const struct sfos_camera2_capture_options *options,
    char *out, size_t out_size);
typedef int (*preview_ppm_fn)(
    const char *camera_id, int width, int height, int frame_count,
    int timeout_ms, int output_fd, int control_fd,
    int jpeg_width, int jpeg_height, int jpeg_quality,
    int jpeg_orientation_degrees, int raw_width, int raw_height,
    float zoom_ratio,
    float focus_x, float focus_y,
    char *out, size_t out_size);
typedef int (*capture_jpeg_fn)(
    const char *camera_id, int width, int height, const char *jpeg_path,
    int timeout_ms, int jpeg_quality, int orientation_degrees,
    int scene_mode, int sensor_sensitivity, long long exposure_time_ns,
    int aperture, int noise_reduction, float zoom_ratio,
    char *out, size_t out_size);
typedef const char *(*version_fn)(void);
typedef void (*droid_media_init_fn)(void);
typedef void (*droid_media_deinit_fn)(void);

static droid_media_deinit_fn g_droid_media_deinit = NULL;

static void deinit_droid_media(void)
{
    if (g_droid_media_deinit) {
        g_droid_media_deinit();
        g_droid_media_deinit = NULL;
    }
}

/**
 * @brief Write bridge JSON next to an output image or RAW prefix.
 *
 * @return 0 on success, -1 on invalid input or file I/O failure.
 */
static int write_json_sidecar(const char *output_path, const char *json)
{
    char metadata_path[PATH_MAX];
    if (!output_path || !*output_path || !json || !*json) {
        return -1;
    }

    const char *slash = strrchr(output_path, '/');
    const char *name = slash ? slash + 1 : output_path;
    const char *dot = strrchr(name, '.');
    size_t prefix_length = dot ? (size_t)(dot - output_path)
                               : strlen(output_path);

    if (prefix_length + 5 >= sizeof(metadata_path)) {
        return -1;
    }

    memcpy(metadata_path, output_path, prefix_length);
    memcpy(metadata_path + prefix_length, ".json", 6);

    FILE *file = fopen(metadata_path, "w");
    if (!file) {
        return -1;
    }
    if (fputs(json, file) < 0 || fputc('\n', file) == EOF) {
        fclose(file);
        return -1;
    }
    return fclose(file) == 0 ? 0 : -1;
}

enum focus_mode {
    FOCUS_NONE = 0,
    FOCUS_AUTO = 1,
    FOCUS_CONTINUOUS = 2,
    FOCUS_MANUAL = 3,
    FOCUS_INFINITY = 4,
};

static void usage(FILE *stream, const char *program)
{
    fprintf(stream,
            "Usage:\n"
            "  %s\n"
            "  %s --capture --output PREFIX [--camera ID] [--size WIDTHxHEIGHT]\n"
            "     [--timeout SECONDS] [--focus MODE] [--focus-distance D]\n"
            "     [--focus-timeout SECONDS] [--focus-failure capture|abort]\n"
            "     [--scene MODE] [--portrait]\n"
            "     [--color-temperature K] [--color-tint N]\n"
            "     [--iso N] [--shutter-ns N] [--aperture N]\n"
            "     [--noise-reduction MODE] [--zoom R]\n"
            "     [--force]\n"
            "  %s --preview [--camera ID] [--size WIDTHxHEIGHT]\n"
            "     [--frames N] [--timeout SECONDS] [--output PATH]\n"
            "     [--jpeg-size WIDTHxHEIGHT] [--quality N]\n"
            "     [--orientation DEGREES] [--zoom R]\n"
            "     [--focus-x X --focus-y Y]\n"
            "  %s --capture-jpeg --output PATH [--camera ID]\n"
            "     [--size WIDTHxHEIGHT] [--timeout SECONDS]\n"
            "     [--quality N] [--orientation DEGREES]\n"
            "     [--scene MODE] [--portrait]\n"
            "     [--iso N] [--shutter-ns N] [--aperture N]\n"
            "     [--noise-reduction MODE] [--zoom R]\n"
            "     [--force]\n\n"
            "Without arguments, print Camera2 capabilities. Capture mode creates\n"
            "PREFIX.raw16 and PREFIX.json. Focus modes are none (default), auto,\n"
            "continuous, manual, and infinity. Manual distance is in diopters.\n"
            "Noise reduction is none, bayer, ycc, temporal, fixed, extra, or a flag value.\n"
            "Color temperature/tint use bridge Camera2 request tags when present.\n"
            "Preview mode writes consecutive binary RGB888 frames.\n",
            program, program, program, program);
}

static int parse_positive_int(const char *text, int *value)
{
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || !end || *end || parsed <= 0 || parsed > INT_MAX) {
        return -1;
    }
    *value = (int)parsed;
    return 0;
}

static int parse_nonnegative_int(const char *text, int *value)
{
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || !end || *end || parsed < 0 || parsed > INT_MAX) {
        return -1;
    }
    *value = (int)parsed;
    return 0;
}

static int parse_nonnegative_i64(const char *text, long long *value)
{
    char *end = NULL;
    errno = 0;
    long long parsed = strtoll(text, &end, 10);
    if (errno || !end || *end || parsed < 0) {
        return -1;
    }
    *value = parsed;
    return 0;
}

static int parse_int(const char *text, int *value)
{
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || !end || *end || parsed < INT_MIN || parsed > INT_MAX) {
        return -1;
    }
    *value = (int)parsed;
    return 0;
}

static int parse_size(const char *text, int *width, int *height)
{
    char tail = '\0';
    if (sscanf(text, "%dx%d%c", width, height, &tail) != 2 ||
            *width <= 0 || *height <= 0) {
        return -1;
    }
    return 0;
}

static int parse_nonnegative_float(const char *text, float *value)
{
    char *end = NULL;
    errno = 0;
    float parsed = strtof(text, &end);
    if (errno || !end || *end || parsed < 0.0f || parsed > 10000.0f ||
            parsed != parsed) {
        return -1;
    }
    *value = parsed;
    return 0;
}

static int parse_unit_float(const char *text, float *value)
{
    char *end = NULL;
    errno = 0;
    float parsed = strtof(text, &end);
    if (errno || !end || *end || parsed < 0.0f || parsed > 1.0f ||
            parsed != parsed) {
        return -1;
    }
    *value = parsed;
    return 0;
}

static int parse_focus_mode(const char *text, int *mode)
{
    if (!strcmp(text, "none")) {
        *mode = FOCUS_NONE;
    } else if (!strcmp(text, "auto")) {
        *mode = FOCUS_AUTO;
    } else if (!strcmp(text, "continuous")) {
        *mode = FOCUS_CONTINUOUS;
    } else if (!strcmp(text, "manual")) {
        *mode = FOCUS_MANUAL;
    } else if (!strcmp(text, "infinity")) {
        *mode = FOCUS_INFINITY;
    } else {
        return -1;
    }
    return 0;
}

static int parse_scene_mode(const char *text, int *mode)
{
    static const struct {
        const char *name;
        int mode;
    } scenes[] = {
        { "none", SFOS_CAMERA2_SCENE_NONE },
        { "manual", SFOS_CAMERA2_SCENE_MANUAL },
        { "closeup", SFOS_CAMERA2_SCENE_CLOSEUP },
        { "portrait", SFOS_CAMERA2_SCENE_PORTRAIT },
        { "landscape", SFOS_CAMERA2_SCENE_LANDSCAPE },
        { "sport", SFOS_CAMERA2_SCENE_SPORT },
        { "night", SFOS_CAMERA2_SCENE_NIGHT },
        { "auto", SFOS_CAMERA2_SCENE_AUTO },
        { "action", SFOS_CAMERA2_SCENE_ACTION },
        { "night-portrait", SFOS_CAMERA2_SCENE_NIGHT_PORTRAIT },
        { "theatre", SFOS_CAMERA2_SCENE_THEATRE },
        { "beach", SFOS_CAMERA2_SCENE_BEACH },
        { "snow", SFOS_CAMERA2_SCENE_SNOW },
        { "sunset", SFOS_CAMERA2_SCENE_SUNSET },
        { "steady-photo", SFOS_CAMERA2_SCENE_STEADY_PHOTO },
        { "fireworks", SFOS_CAMERA2_SCENE_FIREWORKS },
        { "party", SFOS_CAMERA2_SCENE_PARTY },
        { "candlelight", SFOS_CAMERA2_SCENE_CANDLELIGHT },
        { "barcode", SFOS_CAMERA2_SCENE_BARCODE },
        { "backlight", SFOS_CAMERA2_SCENE_BACKLIGHT },
        { "flowers", SFOS_CAMERA2_SCENE_FLOWERS },
        { "ar", SFOS_CAMERA2_SCENE_AR },
        { "hdr", SFOS_CAMERA2_SCENE_HDR },
    };

    for (size_t index = 0; index < sizeof(scenes) / sizeof(scenes[0]);
            ++index) {
        if (!strcmp(text, scenes[index].name)) {
            *mode = scenes[index].mode;
            return 0;
        }
    }
    return -1;
}

static int parse_noise_reduction(const char *text, int *mode)
{
    static const struct {
        const char *name;
        int mode;
    } modes[] = {
        { "none", SFOS_CAMERA2_NOISE_REDUCTION_NONE },
        { "off", SFOS_CAMERA2_NOISE_REDUCTION_NONE },
        { "fast", SFOS_CAMERA2_NOISE_REDUCTION_FAST },
        { "high_quality", SFOS_CAMERA2_NOISE_REDUCTION_HIGH_QUALITY },
        { "high-quality", SFOS_CAMERA2_NOISE_REDUCTION_HIGH_QUALITY },
        { "minimal", SFOS_CAMERA2_NOISE_REDUCTION_MINIMAL },
        { "zsl", SFOS_CAMERA2_NOISE_REDUCTION_ZERO_SHUTTER_LAG },
        { "zero_shutter_lag",
          SFOS_CAMERA2_NOISE_REDUCTION_ZERO_SHUTTER_LAG },
        { "zero-shutter-lag",
          SFOS_CAMERA2_NOISE_REDUCTION_ZERO_SHUTTER_LAG },
        { "bayer", SFOS_CAMERA2_NOISE_REDUCTION_BAYER },
        { "ycc", SFOS_CAMERA2_NOISE_REDUCTION_YCC },
        { "temporal", SFOS_CAMERA2_NOISE_REDUCTION_TEMPORAL },
        { "fixed", SFOS_CAMERA2_NOISE_REDUCTION_FIXED },
        { "extra", SFOS_CAMERA2_NOISE_REDUCTION_EXTRA },
    };

    for (size_t index = 0; index < sizeof(modes) / sizeof(modes[0]);
            ++index) {
        if (!strcmp(text, modes[index].name)) {
            *mode = modes[index].mode;
            return 0;
        }
    }
    return parse_nonnegative_int(text, mode);
}

static void *open_libhybris(const char **loaded_name)
{
    const char *override = getenv("SFOS_LIBHYBRIS");
    const char *candidates[] = {
        override,
        "libhybris-common.so.1",
        "libhybris-common.so",
        NULL,
    };

    for (size_t index = 0; candidates[index] || index == 0; ++index) {
        if (!candidates[index]) {
            continue;
        }
        void *handle = dlopen(candidates[index], RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            *loaded_name = candidates[index];
            return handle;
        }
    }
    return NULL;
}

/**
 * @brief Sailfish helper entry point.
 *
 * Loads the Android bridge, parses command-line mode/options, and dispatches to
 * probe, preview, RAW capture, or JPEG capture.
 */
int main(int argc, char **argv)
{
    if (argc > 1 && (!strcmp(argv[1], "--help") ||
                     !strcmp(argv[1], "-h"))) {
        usage(stdout, argv[0]);
        return 0;
    }

    const char *hybris_name = NULL;
    void *hybris = open_libhybris(&hybris_name);
    if (!hybris) {
        fprintf(stderr, "Unable to load libhybris-common: %s\n", dlerror());
        return 10;
    }

    android_dlopen_fn android_dlopen =
        (android_dlopen_fn)dlsym(hybris, "android_dlopen");
    android_dlsym_fn android_dlsym =
        (android_dlsym_fn)dlsym(hybris, "android_dlsym");
    if (!android_dlopen || !android_dlsym) {
        fprintf(stderr, "%s does not export android_dlopen/android_dlsym\n",
                hybris_name);
        return 11;
    }

    /* Match the initialization used by normal gst-droid clients. */
    void *droidmedia = android_dlopen("libdroidmedia.so", RTLD_NOW);
    if (droidmedia) {
        droid_media_init_fn initialize =
            (droid_media_init_fn)android_dlsym(droidmedia, "_droid_media_init");
        if (initialize) {
            initialize();
            g_droid_media_deinit = (droid_media_deinit_fn)android_dlsym(
                droidmedia, "_droid_media_deinit");
            if (g_droid_media_deinit) {
                atexit(deinit_droid_media);
            } else {
                fprintf(stderr,
                        "Warning: libdroidmedia has no _droid_media_deinit symbol\n");
            }
        } else {
            fprintf(stderr,
                    "Warning: libdroidmedia has no _droid_media_init symbol\n");
        }
    } else {
        fprintf(stderr,
                "Warning: could not preload libdroidmedia; continuing probe\n");
    }

    const char *bridge_name = getenv("SFOS_CAMERA2_BRIDGE");
    if (!bridge_name || !*bridge_name) {
        bridge_name = "libsfoscamera2.so";
    }

    void *bridge = android_dlopen(bridge_name, RTLD_NOW);
    if (!bridge) {
        fprintf(stderr,
                "Android linker could not load %s. Install it under "
                "/usr/libexec/droid-hybris/system/lib64/.\n",
                bridge_name);
        return 12;
    }

    probe_fn probe = (probe_fn)android_dlsym(bridge, "sfos_camera2_probe");
    capture_options_fn capture_options = (capture_options_fn)android_dlsym(
        bridge, "sfos_camera2_capture_raw_options");
    preview_ppm_fn preview_ppm = (preview_ppm_fn)android_dlsym(
        bridge, "sfos_camera2_preview_ppm");
    capture_jpeg_fn capture_jpeg = (capture_jpeg_fn)android_dlsym(
        bridge, "sfos_camera2_capture_jpeg");
    version_fn version =
        (version_fn)android_dlsym(bridge, "sfos_camera2_bridge_version");
    if (!probe || !capture_options || !version) {
        fprintf(stderr, "%s does not export the expected bridge API\n",
                bridge_name);
        return 13;
    }

    char json[32768] = {0};
    int result;

    if (argc == 1) {
        result = probe(json, sizeof(json));
    } else if (!strcmp(argv[1], "--preview")) {
        const char *camera_id = "0";
        const char *output_path = NULL;
        int width = 640;
        int height = 480;
        int frames = 30;
        int timeout_seconds = 10;
        int jpeg_width = 0;
        int jpeg_height = 0;
        int jpeg_quality = 92;
        int jpeg_orientation = 0;
        int raw_width = 0;
        int raw_height = 0;
        float zoom_ratio = 1.0f;
        float focus_x = -1.0f;
        float focus_y = -1.0f;

        if (!preview_ppm) {
            fprintf(stderr,
                    "The installed bridge does not support Camera2 preview. "
                    "Install libsfoscamera2.so 0.10.0 or newer.\n");
            return 14;
        }

        for (int index = 2; index < argc; ++index) {
            if (!strcmp(argv[index], "--camera") && index + 1 < argc) {
                camera_id = argv[++index];
            } else if (!strcmp(argv[index], "--size") && index + 1 < argc) {
                if (parse_size(argv[++index], &width, &height) != 0) {
                    fprintf(stderr, "Invalid --size value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--frames") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &frames) != 0) {
                    fprintf(stderr, "Invalid --frames value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--timeout") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &timeout_seconds) != 0 ||
                        timeout_seconds > INT_MAX / 1000) {
                    fprintf(stderr, "Invalid --timeout value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--output") && index + 1 < argc) {
                output_path = argv[++index];
            } else if (!strcmp(argv[index], "--jpeg-size") && index + 1 < argc) {
                if (parse_size(argv[++index], &jpeg_width, &jpeg_height) != 0) {
                    fprintf(stderr, "Invalid --jpeg-size value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--raw-size") && index + 1 < argc) {
                if (parse_size(argv[++index], &raw_width, &raw_height) != 0) {
                    fprintf(stderr, "Invalid --raw-size value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--quality") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &jpeg_quality) != 0 ||
                        jpeg_quality > 100) {
                    fprintf(stderr, "Invalid --quality value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--orientation") && index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index], &jpeg_orientation) != 0 ||
                        jpeg_orientation > 359) {
                    fprintf(stderr, "Invalid --orientation value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--zoom") && index + 1 < argc) {
                if (parse_nonnegative_float(argv[++index], &zoom_ratio) != 0 ||
                        zoom_ratio < 1.0f) {
                    fprintf(stderr, "Invalid --zoom value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus-x") && index + 1 < argc) {
                if (parse_unit_float(argv[++index], &focus_x) != 0) {
                    fprintf(stderr, "Invalid --focus-x value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus-y") && index + 1 < argc) {
                if (parse_unit_float(argv[++index], &focus_y) != 0) {
                    fprintf(stderr, "Invalid --focus-y value\n");
                    return 2;
                }
            } else {
                fprintf(stderr, "Unknown or incomplete option: %s\n",
                        argv[index]);
                usage(stderr, argv[0]);
                return 2;
            }
        }

        int output_fd = STDOUT_FILENO;
        if (output_path && *output_path) {
            output_fd = open(output_path, O_CREAT | O_TRUNC | O_WRONLY, 0666);
            if (output_fd < 0) {
                fprintf(stderr, "Could not open preview output: %s\n",
                        strerror(errno));
                return 3;
            }
        }
        if ((focus_x < 0.0f) != (focus_y < 0.0f)) {
            fprintf(stderr, "--focus-x and --focus-y must be used together\n");
            return 2;
        }
        result = preview_ppm(camera_id, width, height, frames,
                             timeout_seconds * 1000, output_fd, STDIN_FILENO,
                             jpeg_width, jpeg_height, jpeg_quality,
                             jpeg_orientation, raw_width, raw_height,
                             zoom_ratio,
                             focus_x, focus_y,
                             json, sizeof(json));
        if (output_fd != STDOUT_FILENO) {
            close(output_fd);
        }
        if (json[0]) {
            fprintf(output_path && *output_path ? stdout : stderr,
                    "%s\n", json);
        }
        if (result != 0) {
            fprintf(stderr, "Camera2 bridge %s failed with code %d\n",
                    version(), result);
            return 20 - result;
        }
        return 0;
    } else if (!strcmp(argv[1], "--capture-jpeg")) {
        const char *camera_id = "0";
        const char *output_path = NULL;
        int width = 4096;
        int height = 3072;
        int timeout_seconds = 10;
        int quality = 92;
        int orientation = 0;
        int scene_mode = SFOS_CAMERA2_SCENE_NONE;
        int sensor_sensitivity = 0;
        long long exposure_time_ns = 0;
        int aperture = 0;
        int noise_reduction = SFOS_CAMERA2_NOISE_REDUCTION_NONE;
        float zoom_ratio = 1.0f;
        int force = 0;

        if (!capture_jpeg) {
            fprintf(stderr,
                    "The installed bridge does not support direct JPEG capture. "
                    "Install libsfoscamera2.so 0.6.0 or newer.\n");
            return 14;
        }

        for (int index = 2; index < argc; ++index) {
            if (!strcmp(argv[index], "--camera") && index + 1 < argc) {
                camera_id = argv[++index];
            } else if (!strcmp(argv[index], "--size") && index + 1 < argc) {
                if (parse_size(argv[++index], &width, &height) != 0) {
                    fprintf(stderr, "Invalid --size value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--output") && index + 1 < argc) {
                output_path = argv[++index];
            } else if (!strcmp(argv[index], "--timeout") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &timeout_seconds) != 0 ||
                        timeout_seconds > INT_MAX / 1000) {
                    fprintf(stderr, "Invalid --timeout value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--quality") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &quality) != 0 ||
                        quality > 100) {
                    fprintf(stderr, "Invalid --quality value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--orientation") &&
                       index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index], &orientation) != 0) {
                    fprintf(stderr, "Invalid --orientation value\n");
                    return 2;
                }
                orientation %= 360;
            } else if (!strcmp(argv[index], "--zoom") && index + 1 < argc) {
                if (parse_nonnegative_float(argv[++index], &zoom_ratio) != 0 ||
                        zoom_ratio < 1.0f) {
                    fprintf(stderr, "Invalid --zoom value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--scene") && index + 1 < argc) {
                if (parse_scene_mode(argv[++index], &scene_mode) != 0) {
                    fprintf(stderr, "Invalid --scene mode\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--portrait")) {
                scene_mode = SFOS_CAMERA2_SCENE_PORTRAIT;
            } else if (!strcmp(argv[index], "--iso") && index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index],
                                          &sensor_sensitivity) != 0) {
                    fprintf(stderr, "Invalid --iso value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--shutter-ns") &&
                       index + 1 < argc) {
                if (parse_nonnegative_i64(argv[++index],
                                          &exposure_time_ns) != 0) {
                    fprintf(stderr, "Invalid --shutter-ns value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--noise-reduction") &&
                       index + 1 < argc) {
                if (parse_noise_reduction(argv[++index],
                                          &noise_reduction) != 0) {
                    fprintf(stderr, "Invalid --noise-reduction value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--aperture") &&
                       index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index], &aperture) != 0 ||
                        aperture > 255) {
                    fprintf(stderr, "Invalid --aperture value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--force")) {
                force = 1;
            } else {
                fprintf(stderr, "Unknown or incomplete option: %s\n",
                        argv[index]);
                usage(stderr, argv[0]);
                return 2;
            }
        }
        if (!output_path || !*output_path) {
            fprintf(stderr, "--output PATH is required for JPEG capture\n");
            return 2;
        }
        if (!force && access(output_path, F_OK) == 0) {
            fprintf(stderr,
                    "Output exists; choose another path or pass --force\n");
            return 3;
        }
        result = capture_jpeg(camera_id, width, height, output_path,
                              timeout_seconds * 1000, quality, orientation,
                              scene_mode, sensor_sensitivity, exposure_time_ns,
                              aperture, noise_reduction, zoom_ratio,
                              json, sizeof(json));
        if (result == 0 && write_json_sidecar(output_path, json) != 0) {
            fprintf(stderr, "Could not write JPEG metadata sidecar\n");
            return 15;
        }
    } else if (!strcmp(argv[1], "--capture")) {
        const char *camera_id = "0";
        const char *prefix = NULL;
        int width = 4096;
        int height = 3072;
        int timeout_seconds = 30;
        int focus_mode = FOCUS_NONE;
        float focus_distance = 0.0f;
        int focus_timeout_seconds = 3;
        int capture_on_focus_failure = 1;
        int scene_mode = SFOS_CAMERA2_SCENE_NONE;
        int color_temperature = 0;
        int color_tint = 0;
        int sensor_sensitivity = 0;
        long long exposure_time_ns = 0;
        int aperture = 0;
        int noise_reduction = SFOS_CAMERA2_NOISE_REDUCTION_NONE;
        float zoom_ratio = 1.0f;
        int force = 0;

        for (int index = 2; index < argc; ++index) {
            if (!strcmp(argv[index], "--camera") && index + 1 < argc) {
                camera_id = argv[++index];
            } else if (!strcmp(argv[index], "--size") && index + 1 < argc) {
                if (parse_size(argv[++index], &width, &height) != 0) {
                    fprintf(stderr, "Invalid --size value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--output") && index + 1 < argc) {
                prefix = argv[++index];
            } else if (!strcmp(argv[index], "--timeout") && index + 1 < argc) {
                if (parse_positive_int(argv[++index], &timeout_seconds) != 0 ||
                        timeout_seconds > INT_MAX / 1000) {
                    fprintf(stderr, "Invalid --timeout value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus") && index + 1 < argc) {
                if (parse_focus_mode(argv[++index], &focus_mode) != 0) {
                    fprintf(stderr, "Invalid --focus mode\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus-distance") &&
                       index + 1 < argc) {
                if (parse_nonnegative_float(argv[++index],
                                            &focus_distance) != 0) {
                    fprintf(stderr, "Invalid --focus-distance value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus-timeout") &&
                       index + 1 < argc) {
                if (parse_positive_int(argv[++index],
                                       &focus_timeout_seconds) != 0 ||
                        focus_timeout_seconds > INT_MAX / 1000) {
                    fprintf(stderr, "Invalid --focus-timeout value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--focus-failure") &&
                       index + 1 < argc) {
                const char *policy = argv[++index];
                if (!strcmp(policy, "capture")) {
                    capture_on_focus_failure = 1;
                } else if (!strcmp(policy, "abort")) {
                    capture_on_focus_failure = 0;
                } else {
                    fprintf(stderr,
                            "--focus-failure must be capture or abort\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--scene") && index + 1 < argc) {
                if (parse_scene_mode(argv[++index], &scene_mode) != 0) {
                    fprintf(stderr, "Invalid --scene mode\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--portrait")) {
                scene_mode = SFOS_CAMERA2_SCENE_PORTRAIT;
            } else if (!strcmp(argv[index], "--color-temperature") &&
                       index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index],
                                          &color_temperature) != 0) {
                    fprintf(stderr, "Invalid --color-temperature value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--color-tint") &&
                       index + 1 < argc) {
                if (parse_int(argv[++index], &color_tint) != 0) {
                    fprintf(stderr, "Invalid --color-tint value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--iso") && index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index],
                                          &sensor_sensitivity) != 0) {
                    fprintf(stderr, "Invalid --iso value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--shutter-ns") &&
                       index + 1 < argc) {
                if (parse_nonnegative_i64(argv[++index],
                                          &exposure_time_ns) != 0) {
                    fprintf(stderr, "Invalid --shutter-ns value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--noise-reduction") &&
                       index + 1 < argc) {
                if (parse_noise_reduction(argv[++index],
                                          &noise_reduction) != 0) {
                    fprintf(stderr, "Invalid --noise-reduction value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--aperture") &&
                       index + 1 < argc) {
                if (parse_nonnegative_int(argv[++index], &aperture) != 0 ||
                        aperture > 255) {
                    fprintf(stderr, "Invalid --aperture value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--zoom") && index + 1 < argc) {
                if (parse_nonnegative_float(argv[++index], &zoom_ratio) != 0 ||
                        zoom_ratio < 1.0f) {
                    fprintf(stderr, "Invalid --zoom value\n");
                    return 2;
                }
            } else if (!strcmp(argv[index], "--force")) {
                force = 1;
            } else {
                fprintf(stderr, "Unknown or incomplete option: %s\n",
                        argv[index]);
                usage(stderr, argv[0]);
                return 2;
            }
        }
        if (!prefix || !*prefix) {
            fprintf(stderr, "--output PREFIX is required for capture\n");
            return 2;
        }

        char raw_path[PATH_MAX];
        char metadata_path[PATH_MAX];
        if (snprintf(raw_path, sizeof(raw_path), "%s.raw16", prefix) >=
                    (int)sizeof(raw_path) ||
                snprintf(metadata_path, sizeof(metadata_path), "%s.json", prefix) >=
                    (int)sizeof(metadata_path)) {
            fprintf(stderr, "Output prefix is too long\n");
            return 2;
        }
        if (!force && (access(raw_path, F_OK) == 0 ||
                       access(metadata_path, F_OK) == 0)) {
            fprintf(stderr,
                    "Output exists; choose another prefix or pass --force\n");
            return 3;
        }

        struct sfos_camera2_capture_options options = {
            .size = sizeof(options),
            .focus_mode = focus_mode,
            .focus_distance_diopters = focus_distance,
            .focus_timeout_ms = focus_timeout_seconds * 1000,
            .capture_on_focus_failure = capture_on_focus_failure,
            .scene_mode = scene_mode,
            .color_temperature_kelvin = color_temperature,
            .color_tint = color_tint,
            .zoom_ratio = zoom_ratio,
            .sensor_sensitivity = sensor_sensitivity,
            .exposure_time_ns = exposure_time_ns,
            .aperture = aperture,
            .noise_reduction = noise_reduction,
        };
        result = capture_options(
            camera_id, width, height, raw_path, metadata_path,
            timeout_seconds * 1000, &options, json, sizeof(json));
    } else {
        usage(stderr, argv[0]);
        return 2;
    }

    if (json[0]) {
        puts(json);
    }
    if (result != 0) {
        fprintf(stderr, "Camera2 bridge %s failed with code %d\n",
                version(), result);
        return 20 - result;
    }

    return 0;
}
