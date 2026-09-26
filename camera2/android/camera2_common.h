/**
 * @file camera2_common.h
 * @brief Internal helper API shared by Android bridge implementations.
 */

#ifndef SFOS_CAMERA2_COMMON_H
#define SFOS_CAMERA2_COMMON_H

#include <camera/NdkCameraMetadata.h>
#include <camera/NdkCaptureRequest.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>

#ifndef ACAMERA_CONTROL_ZOOM_RATIO_RANGE
#define ACAMERA_CONTROL_ZOOM_RATIO_RANGE ((uint32_t)0x1002e)
#endif

#ifndef ACAMERA_CONTROL_ZOOM_RATIO
#define ACAMERA_CONTROL_ZOOM_RATIO ((uint32_t)0x1002f)
#endif

#ifndef ACAMERA_SENSOR_NOISE_PROFILE
#define ACAMERA_SENSOR_NOISE_PROFILE ((uint32_t)0xe0013)
#endif

#define MTK_3A_AWB_AVAILABLE_RANGE ((uint32_t)0x8006000c)
#define MTK_3A_AWB_VALUE ((uint32_t)0x8006000d)
#define MTK_3A_AWB_CCT ((uint32_t)0x8006000e)

/**
 * @brief Common status fields used by asynchronous Camera2 operations.
 */
struct sfos_camera2_status {
    /**< Last ACameraDevice_StateCallbacks error, or 0. */
    atomic_int device_error;
    /**< Image availability/status flag used by reader callbacks. */
    atomic_int image_status;
    /**< Last Camera2 capture status observed by callbacks. */
    atomic_int last_camera_status;
    /**< Last media/ImageReader status observed by callbacks. */
    atomic_int last_media_status;
};

/**
 * @brief Initialize common operation status atoms.
 *
 * @param status Status structure to initialize.
 */
void sfos_camera2_status_init(struct sfos_camera2_status *status);

/**
 * @brief Return current monotonic time in milliseconds.
 *
 * @return Monotonic milliseconds suitable for bridge timeouts.
 */
int64_t sfos_camera2_now_ms(void);

/**
 * @brief Sleep for approximately ten milliseconds.
 */
void sfos_camera2_sleep_10_ms(void);

/**
 * @brief Check whether a metadata u8 array contains a value.
 *
 * @param metadata Camera metadata to inspect.
 * @param tag Camera2 metadata tag.
 * @param wanted Value to search for.
 * @return true when @p wanted is present.
 */
bool sfos_camera2_metadata_has_u8(const ACameraMetadata *metadata,
                                  uint32_t tag, uint8_t wanted);

/**
 * @brief Check whether a metadata i32 array contains a value.
 *
 * @param metadata Camera metadata to inspect.
 * @param tag Camera2 metadata tag.
 * @param wanted Value to search for.
 * @return true when @p wanted is present.
 */
bool sfos_camera2_metadata_has_i32(const ACameraMetadata *metadata,
                                   uint32_t tag, int32_t wanted);

/**
 * @brief Read first u8 metadata value.
 *
 * @return First metadata value converted to i32, or @p fallback when absent.
 */
int32_t sfos_camera2_first_u8(const ACameraMetadata *metadata,
                              uint32_t tag, int32_t fallback);

/**
 * @brief Read first i32 metadata value.
 *
 * @return First metadata value, or @p fallback when absent.
 */
int32_t sfos_camera2_first_i32(const ACameraMetadata *metadata,
                               uint32_t tag, int32_t fallback);

/**
 * @brief Read first i64 metadata value.
 *
 * @return First metadata value, or @p fallback when absent.
 */
int64_t sfos_camera2_first_i64(const ACameraMetadata *metadata,
                               uint32_t tag, int64_t fallback);

/**
 * @brief Read first float metadata value.
 *
 * @return First metadata value, or @p fallback when absent.
 */
float sfos_camera2_first_float(const ACameraMetadata *metadata,
                               uint32_t tag, float fallback);

/**
 * @brief Copy an i32 metadata array.
 *
 * @param destination Output array.
 * @param maximum Maximum number of values to copy.
 * @return Number of copied values.
 */
uint32_t sfos_camera2_copy_i32_array(const ACameraMetadata *metadata,
                                     uint32_t tag, int32_t *destination,
                                     uint32_t maximum);

/**
 * @brief Copy an i64 metadata array.
 *
 * @param destination Output array.
 * @param maximum Maximum number of values to copy.
 * @return Number of copied values.
 */
uint32_t sfos_camera2_copy_i64_array(const ACameraMetadata *metadata,
                                     uint32_t tag, int64_t *destination,
                                     uint32_t maximum);

/**
 * @brief Copy a float metadata array.
 *
 * @param destination Output array.
 * @param maximum Maximum number of values to copy.
 * @return Number of copied values.
 */
uint32_t sfos_camera2_copy_float_array(const ACameraMetadata *metadata,
                                       uint32_t tag, float *destination,
                                       uint32_t maximum);

/**
 * @brief Copy a double metadata array.
 *
 * @param destination Output array.
 * @param maximum Maximum number of values to copy.
 * @return Number of copied values.
 */
uint32_t sfos_camera2_copy_double_array(const ACameraMetadata *metadata,
                                        uint32_t tag, double *destination,
                                        uint32_t maximum);

/**
 * @brief Check whether a stream configuration advertises an exact output size.
 *
 * @return true when @p metadata advertises @p format at @p width x @p height.
 */
bool sfos_camera2_has_output_size(const ACameraMetadata *metadata,
                                  int32_t format, int width, int height);

/**
 * @brief Write every byte to a file descriptor.
 *
 * @return 0 on success, -1 on write failure.
 */
int sfos_camera2_write_all(int fd, const void *data, size_t size);

/**
 * @brief Write an in-memory buffer to a file, replacing existing contents.
 *
 * @return 0 on success, -1 on open/write/close failure.
 */
int sfos_camera2_write_file(const char *path, const void *data, size_t size);

/**
 * @brief Clamp an i32 value to the inclusive range [low, high].
 *
 * @return Clamped value.
 */
int32_t sfos_camera2_clamp_i32(int32_t value, int32_t low, int32_t high);

/**
 * @brief Write one u8 capture request entry.
 *
 * @return true when ACaptureRequest_setEntry_u8 succeeds.
 */
bool sfos_camera2_set_request_u8(ACaptureRequest *request, uint32_t tag,
                                 uint8_t value);

/**
 * @brief Write one i32 capture request entry.
 *
 * @return true when ACaptureRequest_setEntry_i32 succeeds.
 */
bool sfos_camera2_set_request_i32(ACaptureRequest *request, uint32_t tag,
                                  int32_t value);

/**
 * @brief Write one i64 capture request entry.
 *
 * @return true when ACaptureRequest_setEntry_i64 succeeds.
 */
bool sfos_camera2_set_request_i64(ACaptureRequest *request, uint32_t tag,
                                  int64_t value);

/**
 * @brief Write one float capture request entry.
 *
 * @return true when ACaptureRequest_setEntry_float succeeds.
 */
bool sfos_camera2_set_request_float(ACaptureRequest *request, uint32_t tag,
                                    float value);

/**
 * @brief Check whether a bridge scene mode is supported by the camera.
 *
 * @return true when the mode is supported. Mode 0 is always supported.
 */
bool sfos_camera2_scene_mode_supported(const ACameraMetadata *metadata,
                                       int scene_mode);

/**
 * @brief Apply scene mode controls to a capture request.
 *
 * Mode 0 leaves the request unchanged.
 *
 * @return true when the request was unchanged or all entries were set.
 */
bool sfos_camera2_set_scene_mode(ACaptureRequest *request, int scene_mode);

/**
 * @brief Apply manual ISO/shutter values.
 *
 * Zero values leave that field automatic.
 *
 * @return true when requested entries were set or not needed.
 */
bool sfos_camera2_set_manual_sensor(const ACameraMetadata *metadata,
                                    ACaptureRequest *request,
                                    int32_t sensitivity,
                                    int64_t exposure_time_ns);

/**
 * @brief Apply aperture as tenths of an f-number.
 *
 * Zero leaves aperture automatic/default.
 *
 * @return true when the aperture was set or not needed.
 */
bool sfos_camera2_set_aperture(const ACameraMetadata *metadata,
                               ACaptureRequest *request,
                               int aperture);

/**
 * @brief Apply a Camera2 noise reduction mode or compatible legacy alias.
 *
 * @return true when the mode was set or not needed.
 */
bool sfos_camera2_set_noise_reduction(const ACameraMetadata *metadata,
                                       ACaptureRequest *request,
                                       int noise_reduction);

/**
 * @brief Apply android.control.zoomRatio when advertised by the camera.
 *
 * @return true when zoom was set, clamped, or not needed.
 */
bool sfos_camera2_set_zoom_ratio(const ACameraMetadata *metadata,
                                 ACaptureRequest *request,
                                 float zoom_ratio);

#endif
