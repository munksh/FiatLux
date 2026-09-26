/**
 * @file camera2_bridge.h
 * @brief Public ABI for the Android Camera2 bridge used by RAWfish.
 *
 * The declarations in this header are loaded from the Sailfish helper through
 * libhybris. Keep exported symbols and option structs ABI-stable.
 */

#ifndef SFOS_CAMERA2_BRIDGE_H
#define SFOS_CAMERA2_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__)
#define SFOS_CAMERA2_EXPORT __attribute__((visibility("default")))
#else
#define SFOS_CAMERA2_EXPORT
#endif

/**
 * @brief Probe available Camera2 devices and capabilities.
 *
 * @param[out] out Destination buffer for a JSON document.
 * @param out_size Size of @p out in bytes.
 * @return 0 on success, -1 for invalid arguments, -2 when CameraManager
 * creation fails, -3 when camera enumeration fails, or -4 when @p out is too
 * small.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_probe(char *out, size_t out_size);

/**
 * @brief Camera2 focus modes accepted by capture APIs.
 */
enum sfos_camera2_focus_mode {
    /**< Do not request autofocus or manual lens control. */
    SFOS_CAMERA2_FOCUS_NONE = 0,
    /**< Trigger a one-shot autofocus request before capture. */
    SFOS_CAMERA2_FOCUS_AUTO = 1,
    /**< Use continuous-picture autofocus behavior. */
    SFOS_CAMERA2_FOCUS_CONTINUOUS = 2,
    /**< Set a manual focus distance in diopters. */
    SFOS_CAMERA2_FOCUS_MANUAL = 3,
    /**< Set focus distance to infinity where supported. */
    SFOS_CAMERA2_FOCUS_INFINITY = 4,
};

/**
 * @brief Camera2 scene modes accepted by capture APIs.
 */
enum sfos_camera2_scene_mode {
    SFOS_CAMERA2_SCENE_MANUAL = 0,
    SFOS_CAMERA2_SCENE_NONE = SFOS_CAMERA2_SCENE_MANUAL,
    SFOS_CAMERA2_SCENE_CLOSEUP = 1,
    SFOS_CAMERA2_SCENE_PORTRAIT = 2,
    SFOS_CAMERA2_SCENE_LANDSCAPE = 3,
    SFOS_CAMERA2_SCENE_SPORT = 4,
    SFOS_CAMERA2_SCENE_NIGHT = 5,
    SFOS_CAMERA2_SCENE_AUTO = 6,
    SFOS_CAMERA2_SCENE_ACTION = 7,
    SFOS_CAMERA2_SCENE_NIGHT_PORTRAIT = 8,
    SFOS_CAMERA2_SCENE_THEATRE = 9,
    SFOS_CAMERA2_SCENE_BEACH = 10,
    SFOS_CAMERA2_SCENE_SNOW = 11,
    SFOS_CAMERA2_SCENE_SUNSET = 12,
    SFOS_CAMERA2_SCENE_STEADY_PHOTO = 13,
    SFOS_CAMERA2_SCENE_FIREWORKS = 14,
    SFOS_CAMERA2_SCENE_PARTY = 15,
    SFOS_CAMERA2_SCENE_CANDLELIGHT = 16,
    SFOS_CAMERA2_SCENE_BARCODE = 17,
    SFOS_CAMERA2_SCENE_BACKLIGHT = 18,
    SFOS_CAMERA2_SCENE_FLOWERS = 19,
    SFOS_CAMERA2_SCENE_AR = 20,
    SFOS_CAMERA2_SCENE_HDR = 21,
};

/**
 * @brief Camera2 noise reduction modes accepted by capture APIs.
 *
 * Legacy GStreamer-style names are retained as aliases for callers that still
 * pass the old values.
 */
enum sfos_camera2_noise_reduction {
    SFOS_CAMERA2_NOISE_REDUCTION_NONE = 0,
    SFOS_CAMERA2_NOISE_REDUCTION_FAST = 1,
    SFOS_CAMERA2_NOISE_REDUCTION_HIGH_QUALITY = 2,
    SFOS_CAMERA2_NOISE_REDUCTION_MINIMAL = 3,
    SFOS_CAMERA2_NOISE_REDUCTION_ZERO_SHUTTER_LAG = 4,
    SFOS_CAMERA2_NOISE_REDUCTION_BAYER = SFOS_CAMERA2_NOISE_REDUCTION_FAST,
    SFOS_CAMERA2_NOISE_REDUCTION_YCC = SFOS_CAMERA2_NOISE_REDUCTION_FAST,
    SFOS_CAMERA2_NOISE_REDUCTION_TEMPORAL =
        SFOS_CAMERA2_NOISE_REDUCTION_HIGH_QUALITY,
    SFOS_CAMERA2_NOISE_REDUCTION_FIXED = SFOS_CAMERA2_NOISE_REDUCTION_MINIMAL,
    SFOS_CAMERA2_NOISE_REDUCTION_EXTRA =
        SFOS_CAMERA2_NOISE_REDUCTION_ZERO_SHUTTER_LAG,
};

/**
 * @brief Options for RAW capture.
 *
 * Set unsupported optional values to 0. The size field must be initialized to
 * sizeof(struct sfos_camera2_capture_options) so future versions can remain
 * ABI-compatible.
 */
struct sfos_camera2_capture_options {
    /**< ABI size guard. Must be sizeof(struct sfos_camera2_capture_options). */
    size_t size;
    /**< One of enum sfos_camera2_focus_mode. */
    int focus_mode;
    /**< Manual lens distance in diopters when focus_mode is manual. */
    float focus_distance_diopters;
    /**< Autofocus wait timeout in milliseconds. */
    int focus_timeout_ms;
    /**< Non-zero captures even if autofocus fails or times out. */
    int capture_on_focus_failure;
    /**< One of enum sfos_camera2_scene_mode. */
    int scene_mode;
    /**< Requested color temperature in kelvin, or 0 for automatic. */
    int color_temperature_kelvin;
    /**< Vendor tint adjustment, or 0 for neutral. */
    int color_tint;
    /**< Camera2 zoom ratio, or <= 0 / 1 for no zoom. */
    float zoom_ratio;
    /**< Manual ISO value, or 0 for automatic exposure. */
    int sensor_sensitivity;
    /**< Manual shutter time in nanoseconds, or 0 for automatic exposure. */
    long long exposure_time_ns;
    /**< Aperture in tenths of an f-number, or 0 for automatic/default. */
    int aperture;
    /**< One of enum sfos_camera2_noise_reduction, or 0 to leave default. */
    int noise_reduction;
};

/**
 * @brief Capture one RAW16 frame and write JSON metadata.
 *
 * @param camera_id Android Camera2 camera identifier.
 * @param width Requested RAW width in pixels.
 * @param height Requested RAW height in pixels.
 * @param raw_path Destination path for the RAW16 buffer.
 * @param metadata_path Destination path for bridge JSON metadata.
 * @param timeout_ms Capture timeout in milliseconds.
 * @param options Optional capture controls; may be NULL.
 * @param[out] out Destination buffer for status JSON.
 * @param out_size Size of @p out in bytes.
 * @return 0 on success, or a negative error code with details in @p out.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_capture_raw_options(
    const char *camera_id,
    int width,
    int height,
    const char *raw_path,
    const char *metadata_path,
    int timeout_ms,
    const struct sfos_camera2_capture_options *options,
    char *out,
    size_t out_size);

/**
 * @brief Stream Camera2 preview frames and handle warm capture commands.
 *
 * Streams YUV preview frames as consecutive RGB888 frames to @p output_fd. Each
 * frame is "SF2P" followed by little-endian width, height, payload length, then
 * width * height * 3 RGB bytes. Commands read from @p control_fd can update
 * focus/settings and request warm JPEG/RAW captures.
 *
 * @param camera_id Android Camera2 camera identifier.
 * @param width Preview width in pixels.
 * @param height Preview height in pixels.
 * @param frame_count Number of frames to stream, or 0 for continuous.
 * @param timeout_ms Startup/capture timeout in milliseconds.
 * @param output_fd File descriptor receiving framed RGB preview data.
 * @param control_fd File descriptor receiving text commands.
 * @param jpeg_width Warm JPEG width in pixels.
 * @param jpeg_height Warm JPEG height in pixels.
 * @param jpeg_quality JPEG encoder quality from 1 to 100.
 * @param jpeg_orientation_degrees JPEG orientation metadata.
 * @param raw_width Warm RAW width in pixels.
 * @param raw_height Warm RAW height in pixels.
 * @param zoom_ratio Initial Camera2 zoom ratio.
 * @param focus_x Initial normalized focus X, or negative for none.
 * @param focus_y Initial normalized focus Y, or negative for none.
 * @param[out] out Destination buffer for status JSON.
 * @param out_size Size of @p out in bytes.
 * @return 0 on normal completion, or a negative error code with details in
 * @p out.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_preview_ppm(
    const char *camera_id,
    int width,
    int height,
    int frame_count,
    int timeout_ms,
    int output_fd,
    int control_fd,
    int jpeg_width,
    int jpeg_height,
    int jpeg_quality,
    int jpeg_orientation_degrees,
    int raw_width,
    int raw_height,
    float zoom_ratio,
    float focus_x,
    float focus_y,
    char *out,
    size_t out_size);

/**
 * @brief Capture one JPEG frame directly from the Camera2 HAL.
 *
 * @param camera_id Android Camera2 camera identifier.
 * @param width Requested JPEG width in pixels.
 * @param height Requested JPEG height in pixels.
 * @param jpeg_path Destination path for the JPEG file.
 * @param timeout_ms Capture timeout in milliseconds.
 * @param jpeg_quality JPEG encoder quality from 1 to 100.
 * @param orientation_degrees JPEG orientation metadata.
 * @param scene_mode One of enum sfos_camera2_scene_mode.
 * @param sensor_sensitivity Manual ISO value, or 0 for automatic exposure.
 * @param exposure_time_ns Manual shutter time in nanoseconds, or 0 for auto.
 * @param aperture Aperture in tenths of an f-number, or 0 for default.
 * @param noise_reduction One of enum sfos_camera2_noise_reduction.
 * @param zoom_ratio Camera2 zoom ratio, or <= 0 / 1 for no zoom.
 * @param[out] out Destination buffer for status JSON.
 * @param out_size Size of @p out in bytes.
 * @return 0 on success, or a negative error code with details in @p out.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_capture_jpeg(
    const char *camera_id,
    int width,
    int height,
    const char *jpeg_path,
    int timeout_ms,
    int jpeg_quality,
    int orientation_degrees,
    int scene_mode,
    int sensor_sensitivity,
    long long exposure_time_ns,
    int aperture,
    int noise_reduction,
    float zoom_ratio,
    char *out,
    size_t out_size);

/**
 * @brief Return the bridge ABI version string.
 *
 * @return Static version string for feature/ABI diagnostics.
 */
SFOS_CAMERA2_EXPORT const char *sfos_camera2_bridge_version(void);

#ifdef __cplusplus
}
#endif

#endif
