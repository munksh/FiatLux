/**
 * @file raw_capture.c
 * @brief Camera2 RAW16 still capture implementation.
 *
 * Creates Camera2 still/preview requests, waits for optional autofocus, captures
 * a RAW16 buffer, and writes JSON metadata needed by RAWfish conversion/DNG
 * paths.
 */

#include "camera2_bridge.h"
#include "camera2_common.h"

#include <camera/NdkCameraCaptureSession.h>
#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraManager.h>
#include <camera/NdkCameraMetadata.h>
#include <camera/NdkCameraMetadataTags.h>
#include <camera/NdkCaptureRequest.h>
#include <media/NdkImage.h>
#include <media/NdkImageReader.h>

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum capture_error {
    CAPTURE_INVALID_ARGUMENT = -10,
    CAPTURE_UNSUPPORTED_SIZE = -11,
    CAPTURE_MANAGER_ERROR = -12,
    CAPTURE_CHARACTERISTICS_ERROR = -13,
    CAPTURE_READER_ERROR = -14,
    CAPTURE_OPEN_ERROR = -15,
    CAPTURE_CONFIGURATION_ERROR = -16,
    CAPTURE_SUBMIT_ERROR = -18,
    CAPTURE_TIMEOUT = -19,
    CAPTURE_IMAGE_ERROR = -20,
    CAPTURE_RESULT_ERROR = -21,
    CAPTURE_METADATA_ERROR = -22,
    CAPTURE_FOCUS_UNSUPPORTED = -23,
    CAPTURE_FOCUS_CONFIGURATION_ERROR = -24,
    CAPTURE_FOCUS_FAILED = -25,
};

struct rational_value {
    int32_t numerator;
    int32_t denominator;
};

struct static_metadata {
    int32_t cfa;
    int32_t white_level;
    int32_t black_level[4];
    int32_t active_array[4];
    float focal_length;
    float minimum_focus_distance;
    int32_t focus_distance_calibration;
    struct rational_value calibration1[9];
    struct rational_value calibration2[9];
    struct rational_value color1[9];
    struct rational_value color2[9];
    struct rational_value forward1[9];
    struct rational_value forward2[9];
    uint32_t calibration1_count;
    uint32_t calibration2_count;
    uint32_t color1_count;
    uint32_t color2_count;
    uint32_t forward1_count;
    uint32_t forward2_count;
};

struct result_metadata {
    int64_t timestamp_ns;
    int64_t exposure_time_ns;
    int32_t sensitivity;
    int32_t dynamic_white_level;
    int32_t af_mode;
    int32_t af_state;
    float lens_focus_distance;
    float lens_aperture;
    float dynamic_black_level[4];
    float color_gains[4];
    struct rational_value neutral_color_point[3];
    struct rational_value color_transform[9];
    double noise_profile[8];
    int32_t vendor_awb_available_range[2];
    int32_t vendor_awb_cct;
    uint32_t dynamic_black_count;
    uint32_t color_gains_count;
    uint32_t neutral_count;
    uint32_t color_transform_count;
    uint32_t noise_profile_count;
    uint32_t vendor_awb_available_range_count;
};

struct image_metadata {
    int32_t width;
    int32_t height;
    int32_t format;
    int32_t planes;
    int32_t pixel_stride;
    int32_t row_stride;
    int32_t data_length;
    int64_t timestamp_ns;
};

struct capture_context {
    atomic_int device_error;
    atomic_int session_ready;
    atomic_int session_active;
    atomic_int session_closed;
    atomic_int image_status;
    atomic_int result_status;
    atomic_int sequence_status;
    atomic_int last_camera_status;
    atomic_int last_media_status;
    atomic_int af_state;
    atomic_int af_outcome;
    atomic_int af_result_count;
    atomic_int focus_timed_out;
    atomic_int preview_image_count;
    int focus_mode;
    float requested_focus_distance;
    int focus_timeout_ms;
    int capture_on_focus_failure;
    int scene_mode;
    int color_temperature_kelvin;
    int color_tint;
    int32_t sensor_sensitivity;
    int64_t exposure_time_ns;
    int aperture;
    int noise_reduction;
    float zoom_ratio;
    int vendor_awb_value_requested;
    int vendor_awb_value_supported;
    int awb_off_supported;
    int preview_width;
    int preview_height;
    char raw_path[4096];
    int64_t started_ms;
    int64_t characteristics_ms;
    int64_t raw_reader_ms;
    int64_t focus_reader_ms;
    int64_t camera_open_ms;
    int64_t session_ms;
    int64_t focus_done_ms;
    int64_t capture_submit_ms;
    int64_t image_available_ms;
    int64_t raw_file_written_ms;
    int64_t capture_done_ms;
    int64_t metadata_written_ms;
    struct static_metadata static_data;
    struct result_metadata result_data;
    struct image_metadata image_data;
};

static bool wait_for_nonzero(atomic_int *value, atomic_int *device_error,
                             int timeout_ms)
{
    int64_t deadline = sfos_camera2_now_ms() + timeout_ms;
    while (sfos_camera2_now_ms() < deadline) {
        if (atomic_load_explicit(device_error, memory_order_acquire) != 0) {
            return false;
        }
        if (atomic_load_explicit(value, memory_order_acquire) != 0) {
            return true;
        }
        sfos_camera2_sleep_10_ms();
    }
    return atomic_load_explicit(value, memory_order_acquire) != 0;
}

static bool wait_for_capture(struct capture_context *context, int timeout_ms)
{
    int64_t deadline = sfos_camera2_now_ms() + timeout_ms;
    while (sfos_camera2_now_ms() < deadline) {
        if (atomic_load_explicit(&context->device_error,
                                 memory_order_acquire) != 0) {
            return false;
        }
        if (atomic_load_explicit(&context->image_status,
                                 memory_order_acquire) != 0 &&
                atomic_load_explicit(&context->result_status,
                                     memory_order_acquire) != 0 &&
                atomic_load_explicit(&context->sequence_status,
                                     memory_order_acquire) != 0) {
            return true;
        }
        sfos_camera2_sleep_10_ms();
    }
    return false;
}

static bool wait_for_focus(struct capture_context *context)
{
    int64_t deadline = sfos_camera2_now_ms() + context->focus_timeout_ms;
    while (sfos_camera2_now_ms() < deadline) {
        if (atomic_load_explicit(&context->device_error,
                                 memory_order_acquire) != 0) {
            return false;
        }
        if (atomic_load_explicit(&context->af_outcome,
                                 memory_order_acquire) != 0) {
            return true;
        }
        sfos_camera2_sleep_10_ms();
    }
    atomic_store_explicit(&context->focus_timed_out, 1,
                          memory_order_release);
    return false;
}

static bool copy_i32(const ACameraMetadata *metadata, uint32_t tag,
                     int32_t *destination, uint32_t wanted)
{
    return sfos_camera2_copy_i32_array(metadata, tag, destination, wanted) ==
           wanted;
}

static uint32_t copy_rational(const ACameraMetadata *metadata, uint32_t tag,
                              struct rational_value *destination,
                              uint32_t maximum)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < maximum ? entry.count : maximum;
    for (uint32_t index = 0; index < count; ++index) {
        destination[index].numerator = entry.data.r[index].numerator;
        destination[index].denominator = entry.data.r[index].denominator;
    }
    return count;
}

static void copy_static_metadata(struct static_metadata *destination,
                                 const ACameraMetadata *metadata)
{
    memset(destination, 0, sizeof(*destination));
    destination->cfa = sfos_camera2_first_u8(
        metadata, ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT, -1);
    destination->white_level = sfos_camera2_first_i32(
        metadata, ACAMERA_SENSOR_INFO_WHITE_LEVEL, -1);
    destination->minimum_focus_distance = sfos_camera2_first_float(
        metadata, ACAMERA_LENS_INFO_MINIMUM_FOCUS_DISTANCE, 0.0f);
    destination->focal_length = sfos_camera2_first_float(
        metadata, ACAMERA_LENS_INFO_AVAILABLE_FOCAL_LENGTHS, 0.0f);
    destination->focus_distance_calibration = sfos_camera2_first_u8(
        metadata, ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION, -1);
    copy_i32(metadata, ACAMERA_SENSOR_BLACK_LEVEL_PATTERN,
             destination->black_level, 4);
    copy_i32(metadata, ACAMERA_SENSOR_INFO_ACTIVE_ARRAY_SIZE,
             destination->active_array, 4);
    destination->calibration1_count = copy_rational(
        metadata, ACAMERA_SENSOR_CALIBRATION_TRANSFORM1,
        destination->calibration1, 9);
    destination->calibration2_count = copy_rational(
        metadata, ACAMERA_SENSOR_CALIBRATION_TRANSFORM2,
        destination->calibration2, 9);
    destination->color1_count = copy_rational(
        metadata, ACAMERA_SENSOR_COLOR_TRANSFORM1, destination->color1, 9);
    destination->color2_count = copy_rational(
        metadata, ACAMERA_SENSOR_COLOR_TRANSFORM2, destination->color2, 9);
    destination->forward1_count = copy_rational(
        metadata, ACAMERA_SENSOR_FORWARD_MATRIX1, destination->forward1, 9);
    destination->forward2_count = copy_rational(
        metadata, ACAMERA_SENSOR_FORWARD_MATRIX2, destination->forward2, 9);
}

static bool select_preview_size(const ACameraMetadata *metadata,
                                int *selected_width, int *selected_height)
{
    ACameraMetadata_const_entry entry;
    int fallback_width = 0;
    int fallback_height = 0;
    int64_t fallback_area = 0;
    int preferred_width = 0;
    int preferred_height = 0;
    int64_t preferred_area = 0;

    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
            &entry) != ACAMERA_OK) {
        return false;
    }
    for (uint32_t index = 0; index + 3 < entry.count; index += 4) {
        int32_t format = entry.data.i32[index];
        int32_t width = entry.data.i32[index + 1];
        int32_t height = entry.data.i32[index + 2];
        int32_t direction = entry.data.i32[index + 3];
        int64_t area = (int64_t)width * height;

        if (format != AIMAGE_FORMAT_YUV_420_888 || width <= 0 || height <= 0 ||
                direction !=
                    ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT) {
            continue;
        }
        if (fallback_area == 0 || area < fallback_area) {
            fallback_width = width;
            fallback_height = height;
            fallback_area = area;
        }
        if (width <= 640 && height <= 480 && area > preferred_area) {
            preferred_width = width;
            preferred_height = height;
            preferred_area = area;
        }
    }
    if (preferred_area > 0) {
        *selected_width = preferred_width;
        *selected_height = preferred_height;
        return true;
    }
    if (fallback_area > 0) {
        *selected_width = fallback_width;
        *selected_height = fallback_height;
        return true;
    }
    return false;
}

static const char *focus_mode_name(int mode)
{
    switch (mode) {
    case SFOS_CAMERA2_FOCUS_NONE: return "none";
    case SFOS_CAMERA2_FOCUS_AUTO: return "auto";
    case SFOS_CAMERA2_FOCUS_CONTINUOUS: return "continuous";
    case SFOS_CAMERA2_FOCUS_MANUAL: return "manual";
    case SFOS_CAMERA2_FOCUS_INFINITY: return "infinity";
    default: return "unknown";
    }
}

static const char *af_state_name(int state)
{
    switch (state) {
    case ACAMERA_CONTROL_AF_STATE_INACTIVE: return "inactive";
    case ACAMERA_CONTROL_AF_STATE_PASSIVE_SCAN: return "passive_scan";
    case ACAMERA_CONTROL_AF_STATE_PASSIVE_FOCUSED: return "passive_focused";
    case ACAMERA_CONTROL_AF_STATE_ACTIVE_SCAN: return "active_scan";
    case ACAMERA_CONTROL_AF_STATE_FOCUSED_LOCKED: return "focused_locked";
    case ACAMERA_CONTROL_AF_STATE_NOT_FOCUSED_LOCKED:
        return "not_focused_locked";
    case ACAMERA_CONTROL_AF_STATE_PASSIVE_UNFOCUSED:
        return "passive_unfocused";
    default: return "unknown";
    }
}

static const char *focus_calibration_name(int calibration)
{
    switch (calibration) {
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_UNCALIBRATED:
        return "uncalibrated";
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_APPROXIMATE:
        return "approximate";
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_CALIBRATED:
        return "calibrated";
    default: return "unknown";
    }
}

static const char *focus_outcome_name(const struct capture_context *context)
{
    int outcome = atomic_load_explicit(&context->af_outcome,
                                       memory_order_acquire);
    if (context->focus_mode == SFOS_CAMERA2_FOCUS_NONE) {
        return "not_requested";
    }
    if (context->focus_mode == SFOS_CAMERA2_FOCUS_MANUAL) {
        return "manual";
    }
    if (context->focus_mode == SFOS_CAMERA2_FOCUS_INFINITY) {
        return "infinity";
    }
    if (atomic_load_explicit(&context->focus_timed_out,
                             memory_order_acquire) != 0) {
        return "timeout";
    }
    if (outcome > 0) {
        return "focused";
    }
    if (outcome == -1) {
        return "not_focused";
    }
    if (outcome < -1) {
        return "request_failed";
    }
    return "pending";
}

static const char *scene_mode_name(int scene_mode)
{
    switch (scene_mode) {
    case SFOS_CAMERA2_SCENE_CLOSEUP: return "closeup";
    case SFOS_CAMERA2_SCENE_PORTRAIT: return "portrait";
    case SFOS_CAMERA2_SCENE_LANDSCAPE: return "landscape";
    case SFOS_CAMERA2_SCENE_SPORT: return "sport";
    case SFOS_CAMERA2_SCENE_NIGHT: return "night";
    case SFOS_CAMERA2_SCENE_AUTO: return "auto";
    case SFOS_CAMERA2_SCENE_ACTION: return "action";
    case SFOS_CAMERA2_SCENE_NIGHT_PORTRAIT: return "night-portrait";
    case SFOS_CAMERA2_SCENE_THEATRE: return "theatre";
    case SFOS_CAMERA2_SCENE_BEACH: return "beach";
    case SFOS_CAMERA2_SCENE_SNOW: return "snow";
    case SFOS_CAMERA2_SCENE_SUNSET: return "sunset";
    case SFOS_CAMERA2_SCENE_STEADY_PHOTO: return "steady-photo";
    case SFOS_CAMERA2_SCENE_FIREWORKS: return "fireworks";
    case SFOS_CAMERA2_SCENE_PARTY: return "party";
    case SFOS_CAMERA2_SCENE_CANDLELIGHT: return "candlelight";
    case SFOS_CAMERA2_SCENE_BARCODE: return "barcode";
    case SFOS_CAMERA2_SCENE_BACKLIGHT: return "backlight";
    case SFOS_CAMERA2_SCENE_FLOWERS: return "flowers";
    case SFOS_CAMERA2_SCENE_AR: return "ar";
    case SFOS_CAMERA2_SCENE_HDR: return "hdr";
    case SFOS_CAMERA2_SCENE_MANUAL:
    default:
        return "manual";
    }
}

static bool focus_mode_supported(const ACameraMetadata *metadata, int mode)
{
    uint8_t required;
    switch (mode) {
    case SFOS_CAMERA2_FOCUS_AUTO:
        required = ACAMERA_CONTROL_AF_MODE_AUTO;
        break;
    case SFOS_CAMERA2_FOCUS_CONTINUOUS:
        required = ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
        break;
    case SFOS_CAMERA2_FOCUS_MANUAL:
    case SFOS_CAMERA2_FOCUS_INFINITY:
        required = ACAMERA_CONTROL_AF_MODE_OFF;
        break;
    case SFOS_CAMERA2_FOCUS_NONE:
        return true;
    default:
        return false;
    }
    return sfos_camera2_metadata_has_u8(
        metadata, ACAMERA_CONTROL_AF_AVAILABLE_MODES, required);
}

static bool configure_color_request(ACaptureRequest *request,
                                    const struct capture_context *context)
{
    if (context->color_temperature_kelvin > 0) {
#ifdef ACAMERA_COLOR_CORRECTION_COLOR_TEMPERATURE
        sfos_camera2_set_request_i32(
            request, ACAMERA_COLOR_CORRECTION_COLOR_TEMPERATURE,
            context->color_temperature_kelvin);
#endif
        if (context->vendor_awb_value_supported &&
                context->awb_off_supported) {
            int32_t awb_value = context->vendor_awb_value_requested;
            sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AWB_MODE,
                                        ACAMERA_CONTROL_AWB_MODE_OFF);
            sfos_camera2_set_request_i32(request, MTK_3A_AWB_VALUE,
                                         awb_value);
        }
    }

    if (context->color_tint != 0) {
#ifdef ACAMERA_COLOR_CORRECTION_COLOR_TINT
        sfos_camera2_set_request_i32(request, ACAMERA_COLOR_CORRECTION_COLOR_TINT,
                                     context->color_tint);
#endif
    }

    return true;
}

static bool configure_option_request(ACaptureRequest *request,
                                     const ACameraMetadata *metadata,
                                     const struct capture_context *context)
{
    return sfos_camera2_set_scene_mode(request, context->scene_mode) &&
           sfos_camera2_set_manual_sensor(metadata, request,
                                          context->sensor_sensitivity,
                                          context->exposure_time_ns) &&
           sfos_camera2_set_aperture(metadata, request,
                                     context->aperture) &&
           sfos_camera2_set_noise_reduction(metadata, request,
                                            context->noise_reduction) &&
           configure_color_request(request, context);
}

static bool configure_focus_request(ACaptureRequest *request, int focus_mode,
                                    float focus_distance, bool trigger_start)
{
    uint8_t af_mode;
    uint8_t af_trigger = trigger_start ? ACAMERA_CONTROL_AF_TRIGGER_START :
                                        ACAMERA_CONTROL_AF_TRIGGER_IDLE;

    switch (focus_mode) {
    case SFOS_CAMERA2_FOCUS_AUTO:
        af_mode = ACAMERA_CONTROL_AF_MODE_AUTO;
        break;
    case SFOS_CAMERA2_FOCUS_CONTINUOUS:
        af_mode = ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
        break;
    case SFOS_CAMERA2_FOCUS_MANUAL:
    case SFOS_CAMERA2_FOCUS_INFINITY:
        af_mode = ACAMERA_CONTROL_AF_MODE_OFF;
        break;
    case SFOS_CAMERA2_FOCUS_NONE:
        return true;
    default:
        return false;
    }
    if (!sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_MODE,
                                     af_mode) ||
            !sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_TRIGGER,
                                         af_trigger)) {
        return false;
    }
    if (focus_mode == SFOS_CAMERA2_FOCUS_MANUAL ||
            focus_mode == SFOS_CAMERA2_FOCUS_INFINITY) {
        return ACaptureRequest_setEntry_float(
                   request, ACAMERA_LENS_FOCUS_DISTANCE, 1,
                   &focus_distance) == ACAMERA_OK;
    }
    return true;
}

static void update_af_state(struct capture_context *context,
                            const ACameraMetadata *result)
{
    int state = sfos_camera2_first_u8(result, ACAMERA_CONTROL_AF_STATE, -1);
    if (state < 0) {
        return;
    }
    atomic_store_explicit(&context->af_state, state, memory_order_release);
    atomic_fetch_add_explicit(&context->af_result_count, 1,
                              memory_order_relaxed);
    if (state == ACAMERA_CONTROL_AF_STATE_FOCUSED_LOCKED ||
            (context->focus_mode == SFOS_CAMERA2_FOCUS_CONTINUOUS &&
             state == ACAMERA_CONTROL_AF_STATE_PASSIVE_FOCUSED)) {
        atomic_store_explicit(&context->af_outcome, 1, memory_order_release);
    } else if (context->focus_mode == SFOS_CAMERA2_FOCUS_AUTO &&
               state == ACAMERA_CONTROL_AF_STATE_NOT_FOCUSED_LOCKED) {
        atomic_store_explicit(&context->af_outcome, -1, memory_order_release);
    }
}

static void device_disconnected(void *opaque, ACameraDevice *device)
{
    (void)device;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->device_error, -1, memory_order_release);
}

static void device_error(void *opaque, ACameraDevice *device, int error)
{
    (void)device;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->device_error,
                          error > 0 ? error : -1, memory_order_release);
}

static void session_closed(void *opaque, ACameraCaptureSession *session)
{
    (void)session;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->session_closed, 1, memory_order_release);
}

static void session_ready(void *opaque, ACameraCaptureSession *session)
{
    (void)session;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->session_ready, 1, memory_order_release);
}

static void session_active(void *opaque, ACameraCaptureSession *session)
{
    (void)session;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->session_active, 1, memory_order_release);
}

static void raw_image_available(void *opaque, AImageReader *reader)
{
    struct capture_context *context = opaque;
    if (atomic_load_explicit(&context->image_status,
                             memory_order_acquire) != 0) {
        return;
    }
    AImage *image = NULL;
    media_status_t media_status = AImageReader_acquireNextImage(reader, &image);
    atomic_store_explicit(&context->last_media_status, media_status,
                          memory_order_release);
    if (media_status != AMEDIA_OK || !image) {
        atomic_store_explicit(&context->image_status, -1,
                              memory_order_release);
        return;
    }

    int32_t status = 1;
    uint8_t *data = NULL;
    context->image_available_ms = sfos_camera2_now_ms() - context->started_ms;
    if (AImage_getWidth(image, &context->image_data.width) != AMEDIA_OK ||
            AImage_getHeight(image, &context->image_data.height) != AMEDIA_OK ||
            AImage_getFormat(image, &context->image_data.format) != AMEDIA_OK ||
            AImage_getNumberOfPlanes(image,
                                     &context->image_data.planes) != AMEDIA_OK ||
            AImage_getTimestamp(image,
                                &context->image_data.timestamp_ns) != AMEDIA_OK ||
            context->image_data.format != AIMAGE_FORMAT_RAW16 ||
            context->image_data.planes != 1 ||
            AImage_getPlanePixelStride(
                image, 0, &context->image_data.pixel_stride) != AMEDIA_OK ||
            AImage_getPlaneRowStride(
                image, 0, &context->image_data.row_stride) != AMEDIA_OK ||
            AImage_getPlaneData(image, 0, &data,
                                &context->image_data.data_length) != AMEDIA_OK ||
            !data || context->image_data.data_length <= 0) {
        status = -2;
    }
    if (status > 0) {
        FILE *raw = fopen(context->raw_path, "wb");
        if (!raw || fwrite(data, 1,
                           (size_t)context->image_data.data_length, raw) !=
                        (size_t)context->image_data.data_length ||
                fflush(raw) != 0) {
            status = -3;
        }
        if (raw && fclose(raw) != 0) {
            status = -3;
        }
        if (status < 0) {
            unlink(context->raw_path);
        } else {
            context->raw_file_written_ms = sfos_camera2_now_ms()
                                           - context->started_ms;
        }
    }
    AImage_delete(image);
    atomic_store_explicit(&context->image_status, status,
                          memory_order_release);
}

static void preview_image_available(void *opaque, AImageReader *reader)
{
    struct capture_context *context = opaque;
    AImage *image = NULL;
    media_status_t status = AImageReader_acquireNextImage(reader, &image);
    if (status == AMEDIA_OK && image) {
        atomic_fetch_add_explicit(&context->preview_image_count, 1,
                                  memory_order_relaxed);
        AImage_delete(image);
    }
}

static void capture_started(void *opaque, ACameraCaptureSession *session,
                            const ACaptureRequest *request, int64_t timestamp)
{
    (void)opaque;
    (void)session;
    (void)request;
    (void)timestamp;
}

static void capture_progressed(void *opaque, ACameraCaptureSession *session,
                               ACaptureRequest *request,
                               const ACameraMetadata *result)
{
    (void)opaque;
    (void)session;
    (void)request;
    (void)result;
}

static void capture_completed(void *opaque, ACameraCaptureSession *session,
                              ACaptureRequest *request,
                              const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    struct capture_context *context = opaque;
    struct result_metadata *destination = &context->result_data;

    memset(destination, 0, sizeof(*destination));
    destination->timestamp_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_TIMESTAMP, -1);
    destination->exposure_time_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_EXPOSURE_TIME, -1);
    destination->sensitivity = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_SENSITIVITY, -1);
    fprintf(stderr,
            "capture-exposure raw requested_iso=%d requested_shutter=%lld "
            "actual_iso=%d actual_shutter=%lld actual_frame=%lld\n",
            context->sensor_sensitivity,
            (long long)context->exposure_time_ns,
            destination->sensitivity,
            (long long)destination->exposure_time_ns,
            (long long)sfos_camera2_first_i64(
                result, ACAMERA_SENSOR_FRAME_DURATION, -1));
    destination->dynamic_white_level = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_DYNAMIC_WHITE_LEVEL, -1);
    destination->af_mode = sfos_camera2_first_u8(
        result, ACAMERA_CONTROL_AF_MODE, -1);
    destination->af_state = sfos_camera2_first_u8(
        result, ACAMERA_CONTROL_AF_STATE, -1);
    destination->lens_focus_distance = sfos_camera2_first_float(
        result, ACAMERA_LENS_FOCUS_DISTANCE, -1.0f);
    destination->lens_aperture = sfos_camera2_first_float(
        result, ACAMERA_LENS_APERTURE, -1.0f);
    destination->dynamic_black_count = sfos_camera2_copy_float_array(
        result, ACAMERA_SENSOR_DYNAMIC_BLACK_LEVEL,
        destination->dynamic_black_level, 4);
    destination->color_gains_count = sfos_camera2_copy_float_array(
        result, ACAMERA_COLOR_CORRECTION_GAINS,
        destination->color_gains, 4);
    destination->neutral_count = copy_rational(
        result, ACAMERA_SENSOR_NEUTRAL_COLOR_POINT,
        destination->neutral_color_point, 3);
    destination->color_transform_count = copy_rational(
        result, ACAMERA_COLOR_CORRECTION_TRANSFORM,
        destination->color_transform, 9);
    destination->noise_profile_count = sfos_camera2_copy_double_array(
        result, ACAMERA_SENSOR_NOISE_PROFILE,
        destination->noise_profile, 8);
    destination->vendor_awb_available_range_count = sfos_camera2_copy_i32_array(
        result, MTK_3A_AWB_AVAILABLE_RANGE,
        destination->vendor_awb_available_range, 2);
    destination->vendor_awb_cct = sfos_camera2_first_i32(
        result, MTK_3A_AWB_CCT, 0);
    atomic_store_explicit(&context->result_status, 1,
                          memory_order_release);
}

static void capture_failed(void *opaque, ACameraCaptureSession *session,
                           ACaptureRequest *request,
                           ACameraCaptureFailure *failure)
{
    (void)session;
    (void)request;
    (void)failure;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->result_status, -1,
                          memory_order_release);
}

static void sequence_completed(void *opaque, ACameraCaptureSession *session,
                               int sequence_id, int64_t frame_number)
{
    (void)session;
    (void)sequence_id;
    (void)frame_number;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->sequence_status, 1,
                          memory_order_release);
}

static void sequence_aborted(void *opaque, ACameraCaptureSession *session,
                             int sequence_id)
{
    (void)session;
    (void)sequence_id;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->sequence_status, -1,
                          memory_order_release);
}

static void buffer_lost(void *opaque, ACameraCaptureSession *session,
                        ACaptureRequest *request, ANativeWindow *window,
                        int64_t frame_number)
{
    (void)session;
    (void)request;
    (void)window;
    (void)frame_number;
    struct capture_context *context = opaque;
    atomic_store_explicit(&context->image_status, -4,
                          memory_order_release);
}

static void focus_capture_progressed(void *opaque,
                                     ACameraCaptureSession *session,
                                     ACaptureRequest *request,
                                     const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    update_af_state(opaque, result);
}

static void focus_capture_completed(void *opaque,
                                    ACameraCaptureSession *session,
                                    ACaptureRequest *request,
                                    const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    update_af_state(opaque, result);
}

static void focus_capture_failed(void *opaque,
                                 ACameraCaptureSession *session,
                                 ACaptureRequest *request,
                                 ACameraCaptureFailure *failure)
{
    (void)session;
    (void)failure;
    ACameraMetadata_const_entry entry;
    struct capture_context *context = opaque;
    if (ACaptureRequest_getConstEntry(
            request, ACAMERA_CONTROL_AF_TRIGGER, &entry) == ACAMERA_OK &&
            entry.count > 0 &&
            entry.data.u8[0] == ACAMERA_CONTROL_AF_TRIGGER_START) {
        atomic_store_explicit(&context->af_outcome, -2,
                              memory_order_release);
    }
}

static const char *cfa_name(int32_t cfa)
{
    switch (cfa) {
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_RGGB: return "RGGB";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GRBG: return "GRBG";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GBRG: return "GBRG";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_BGGR: return "BGGR";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_RGB: return "RGB";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_MONO: return "MONO";
    default: return "UNKNOWN";
    }
}

static void print_json_string(FILE *file, const char *value)
{
    fputc('\"', file);
    const unsigned char *cursor = (const unsigned char *)(value ? value : "");
    while (*cursor) {
        if (*cursor == '\"' || *cursor == '\\') {
            fputc('\\', file);
            fputc(*cursor, file);
        } else if (*cursor < 0x20) {
            fprintf(file, "\\u%04x", (unsigned int)*cursor);
        } else {
            fputc(*cursor, file);
        }
        ++cursor;
    }
    fputc('\"', file);
}

static void print_rational_array(FILE *file,
                                 const struct rational_value *values,
                                 uint32_t count)
{
    fputc('[', file);
    for (uint32_t index = 0; index < count; ++index) {
        fprintf(file, "%s[%d,%d]", index ? "," : "",
                values[index].numerator, values[index].denominator);
    }
    fputc(']', file);
}

static void print_float_array(FILE *file, const float *values, uint32_t count)
{
    fputc('[', file);
    for (uint32_t index = 0; index < count; ++index) {
        fprintf(file, "%s%.9g", index ? "," : "", values[index]);
    }
    fputc(']', file);
}

static void print_double_array(FILE *file, const double *values, uint32_t count)
{
    fputc('[', file);
    for (uint32_t index = 0; index < count; ++index) {
        fprintf(file, "%s%.17g", index ? "," : "", values[index]);
    }
    fputc(']', file);
}

static bool write_metadata_file(const char *path, const char *camera_id,
                                const char *raw_path,
                                const struct capture_context *context)
{
    FILE *file = fopen(path, "w");
    if (!file) {
        return false;
    }
    const struct image_metadata *image = &context->image_data;
    const struct result_metadata *result = &context->result_data;
    const struct static_metadata *static_data = &context->static_data;
    int preparatory_af_state = atomic_load_explicit(
        &context->af_state, memory_order_acquire);

    fputs("{\n  \"camera_id\":", file);
    print_json_string(file, camera_id);
    fputs(",\n  \"raw_path\":", file);
    print_json_string(file, raw_path);
    fprintf(file,
            ",\n  \"format\":\"RAW16\",\n  \"format_value\":%d,"
            "\n  \"width\":%d,\n  \"height\":%d,"
            "\n  \"planes\":%d,\n  \"pixel_stride\":%d,"
            "\n  \"row_stride\":%d,\n  \"data_length\":%d,"
            "\n  \"image_timestamp_ns\":%lld,"
            "\n  \"sensor_timestamp_ns\":%lld,"
            "\n  \"exposure_time_ns\":%lld,\n  \"iso\":%d,"
            "\n  \"cfa\":\"%s\",\n  \"cfa_value\":%d,"
            "\n  \"white_level\":%d,"
            "\n  \"dynamic_white_level\":%d,"
            "\n  \"black_level_pattern\":[%d,%d,%d,%d],"
            "\n  \"active_array\":[%d,%d,%d,%d],",
            image->format, image->width, image->height, image->planes,
            image->pixel_stride, image->row_stride, image->data_length,
            (long long)image->timestamp_ns,
            (long long)result->timestamp_ns,
            (long long)result->exposure_time_ns, result->sensitivity,
            cfa_name(static_data->cfa), static_data->cfa,
            static_data->white_level, result->dynamic_white_level,
            static_data->black_level[0], static_data->black_level[1],
            static_data->black_level[2], static_data->black_level[3],
            static_data->active_array[0], static_data->active_array[1],
            static_data->active_array[2], static_data->active_array[3]);
    fprintf(file,
            "\n  \"focus_mode_requested\":\"%s\","
            "\n  \"focal_length_mm\":%.9g,"
            "\n  \"focus_distance_requested_diopters\":%.9g,"
            "\n  \"minimum_focus_distance_diopters\":%.9g,"
            "\n  \"focus_distance_calibration\":\"%s\","
            "\n  \"focus_outcome\":\"%s\","
            "\n  \"focus_timed_out\":%s,"
            "\n  \"focus_result_count\":%d,"
            "\n  \"focus_preview_size\":[%d,%d],"
            "\n  \"scene_mode_requested\":\"%s\","
            "\n  \"sensor_sensitivity_requested\":%d,"
            "\n  \"exposure_time_requested_ns\":%lld,"
            "\n  \"aperture_requested\":%d,"
            "\n  \"noise_reduction_requested\":%d,"
            "\n  \"color_temperature_requested_kelvin\":%d,"
            "\n  \"vendor_awb_value_requested\":%d,"
            "\n  \"vendor_awb_value_supported\":%s,"
            "\n  \"awb_off_supported\":%s,"
            "\n  \"color_tint_requested\":%d,"
            "\n  \"pre_capture_af_state\":\"%s\","
            "\n  \"pre_capture_af_state_value\":%d,"
            "\n  \"capture_af_mode_value\":%d,"
            "\n  \"capture_af_state\":\"%s\","
            "\n  \"capture_af_state_value\":%d,"
            "\n  \"lens_focus_distance_diopters\":%.9g,"
            "\n  \"lens_aperture\":%.9g,",
            focus_mode_name(context->focus_mode),
            static_data->focal_length,
            context->requested_focus_distance,
            static_data->minimum_focus_distance,
            focus_calibration_name(static_data->focus_distance_calibration),
            focus_outcome_name(context),
            atomic_load_explicit(&context->focus_timed_out,
                                 memory_order_acquire) ? "true" : "false",
            atomic_load_explicit(&context->af_result_count,
                                 memory_order_acquire),
            context->preview_width, context->preview_height,
            scene_mode_name(context->scene_mode),
            context->sensor_sensitivity,
            (long long)context->exposure_time_ns,
            context->aperture,
            context->noise_reduction,
            context->color_temperature_kelvin,
            context->vendor_awb_value_requested,
            context->vendor_awb_value_supported ? "true" : "false",
            context->awb_off_supported ? "true" : "false",
            context->color_tint,
            af_state_name(preparatory_af_state), preparatory_af_state,
            result->af_mode, af_state_name(result->af_state), result->af_state,
            result->lens_focus_distance, result->lens_aperture);
    fprintf(file,
            "\n  \"timing_ms\":{"
            "\n    \"characteristics\":%lld,"
            "\n    \"raw_reader\":%lld,"
            "\n    \"focus_reader\":%lld,"
            "\n    \"camera_open\":%lld,"
            "\n    \"session\":%lld,"
            "\n    \"focus_done\":%lld,"
            "\n    \"capture_submit\":%lld,"
            "\n    \"image_available\":%lld,"
            "\n    \"raw_file_written\":%lld,"
            "\n    \"capture_done\":%lld,"
            "\n    \"metadata_written\":%lld,"
            "\n    \"total\":%lld"
            "\n  },",
            (long long)context->characteristics_ms,
            (long long)context->raw_reader_ms,
            (long long)context->focus_reader_ms,
            (long long)context->camera_open_ms,
            (long long)context->session_ms,
            (long long)context->focus_done_ms,
            (long long)context->capture_submit_ms,
            (long long)context->image_available_ms,
            (long long)context->raw_file_written_ms,
            (long long)context->capture_done_ms,
            (long long)context->metadata_written_ms,
            (long long)(sfos_camera2_now_ms() - context->started_ms));
    fprintf(file,
            "\n  \"vendor_awb_available_range\":[%d,%d],"
            "\n  \"vendor_awb_available_range_count\":%u,"
            "\n  \"vendor_awb_cct\":%d,",
            result->vendor_awb_available_range[0],
            result->vendor_awb_available_range[1],
            result->vendor_awb_available_range_count,
            result->vendor_awb_cct);
    fputs("\n  \"dynamic_black_level\":", file);
    print_float_array(file, result->dynamic_black_level,
                      result->dynamic_black_count);
    fputs(",\n  \"color_correction_gains\":", file);
    print_float_array(file, result->color_gains, result->color_gains_count);
    fputs(",\n  \"neutral_color_point\":", file);
    print_rational_array(file, result->neutral_color_point,
                         result->neutral_count);
    fputs(",\n  \"capture_color_transform\":", file);
    print_rational_array(file, result->color_transform,
                         result->color_transform_count);
    fputs(",\n  \"noise_profile\":", file);
    print_double_array(file, result->noise_profile,
                       result->noise_profile_count);
    fputs(",\n  \"calibration_transform1\":", file);
    print_rational_array(file, static_data->calibration1,
                         static_data->calibration1_count);
    fputs(",\n  \"calibration_transform2\":", file);
    print_rational_array(file, static_data->calibration2,
                         static_data->calibration2_count);
    fputs(",\n  \"color_transform1\":", file);
    print_rational_array(file, static_data->color1,
                         static_data->color1_count);
    fputs(",\n  \"color_transform2\":", file);
    print_rational_array(file, static_data->color2,
                         static_data->color2_count);
    fputs(",\n  \"forward_matrix1\":", file);
    print_rational_array(file, static_data->forward1,
                         static_data->forward1_count);
    fputs(",\n  \"forward_matrix2\":", file);
    print_rational_array(file, static_data->forward2,
                         static_data->forward2_count);
    fputs("\n}\n", file);

    bool success = ferror(file) == 0 && fflush(file) == 0;
    if (fclose(file) != 0) {
        success = false;
    }
    if (!success) {
        unlink(path);
    }
    return success;
}

static void status_json(char *out, size_t out_size, bool success,
                        const char *stage, int code,
                        const char *raw_path, const char *metadata_path,
                        const struct capture_context *context)
{
    if (!out || out_size == 0) {
        return;
    }
    if (!context) {
        snprintf(out, out_size,
                 "{\"status\":\"%s\",\"stage\":\"%s\",\"code\":%d,"
                 "\"raw_path\":\"%s\",\"metadata_path\":\"%s\"}",
                 success ? "ok" : "error", stage ? stage : "unknown", code,
                 raw_path ? raw_path : "", metadata_path ? metadata_path : "");
        return;
    }
    int af_state = atomic_load_explicit(&context->af_state,
                                        memory_order_acquire);
    snprintf(out, out_size,
             "{\"status\":\"%s\",\"stage\":\"%s\",\"code\":%d,"
             "\"raw_path\":\"%s\",\"metadata_path\":\"%s\","
             "\"focus\":{\"mode\":\"%s\",\"outcome\":\"%s\","
             "\"af_state\":\"%s\",\"af_state_value\":%d,"
             "\"preview_size\":[%d,%d]},"
             "\"timing_ms\":{\"characteristics\":%lld,"
             "\"raw_reader\":%lld,\"focus_reader\":%lld,"
             "\"camera_open\":%lld,\"session\":%lld,"
             "\"focus_done\":%lld,\"capture_submit\":%lld,"
             "\"image_available\":%lld,\"raw_file_written\":%lld,"
             "\"capture_done\":%lld,\"metadata_written\":%lld,"
             "\"total\":%lld},"
		             "\"color\":{\"temperature_requested\":%d,"
	             "\"vendor_awb_value_requested\":%d,"
	             "\"vendor_awb_value_supported\":%s,"
	             "\"awb_off_supported\":%s,"
	             "\"vendor_awb_cct\":%d},"
             "\"exposure\":{\"iso_requested\":%d,"
             "\"exposure_time_requested_ns\":%lld,"
             "\"iso\":%d,\"exposure_time_ns\":%lld},"
             "\"aperture\":{\"requested\":%d},"
             "\"noise_reduction\":{\"requested\":%d},"
	             "\"diagnostics\":{\"camera_status\":%d,"
             "\"media_status\":%d,\"device_error\":%d,"
             "\"session_ready\":%d,\"session_active\":%d,"
             "\"session_closed\":%d,\"image_status\":%d,"
             "\"result_status\":%d,\"sequence_status\":%d,"
             "\"af_results\":%d,\"preview_images\":%d}}",
             success ? "ok" : "error", stage ? stage : "unknown", code,
             raw_path ? raw_path : "", metadata_path ? metadata_path : "",
	             focus_mode_name(context->focus_mode), focus_outcome_name(context),
	             af_state_name(af_state), af_state,
	             context->preview_width, context->preview_height,
             (long long)context->characteristics_ms,
             (long long)context->raw_reader_ms,
             (long long)context->focus_reader_ms,
             (long long)context->camera_open_ms,
             (long long)context->session_ms,
             (long long)context->focus_done_ms,
             (long long)context->capture_submit_ms,
             (long long)context->image_available_ms,
             (long long)context->raw_file_written_ms,
             (long long)context->capture_done_ms,
             (long long)context->metadata_written_ms,
             (long long)(sfos_camera2_now_ms() - context->started_ms),
	             context->color_temperature_kelvin,
	             context->vendor_awb_value_requested,
	             context->vendor_awb_value_supported ? "true" : "false",
	             context->awb_off_supported ? "true" : "false",
	             context->result_data.vendor_awb_cct,
             context->sensor_sensitivity,
             (long long)context->exposure_time_ns,
             context->result_data.sensitivity,
             (long long)context->result_data.exposure_time_ns,
             context->aperture,
             context->noise_reduction,
	             atomic_load_explicit(&context->last_camera_status,
                                  memory_order_acquire),
             atomic_load_explicit(&context->last_media_status,
                                  memory_order_acquire),
             atomic_load_explicit(&context->device_error,
                                  memory_order_acquire),
             atomic_load_explicit(&context->session_ready,
                                  memory_order_acquire),
             atomic_load_explicit(&context->session_active,
                                  memory_order_acquire),
             atomic_load_explicit(&context->session_closed,
                                  memory_order_acquire),
             atomic_load_explicit(&context->image_status,
                                  memory_order_acquire),
             atomic_load_explicit(&context->result_status,
                                  memory_order_acquire),
             atomic_load_explicit(&context->sequence_status,
                                  memory_order_acquire),
             atomic_load_explicit(&context->af_result_count,
                                  memory_order_acquire),
             atomic_load_explicit(&context->preview_image_count,
                                  memory_order_acquire));
}

static void remember_camera_status(struct capture_context *context,
                                   camera_status_t status)
{
    atomic_store_explicit(&context->last_camera_status, status,
                          memory_order_release);
}

static void remember_media_status(struct capture_context *context,
                                  media_status_t status)
{
    atomic_store_explicit(&context->last_media_status, status,
                          memory_order_release);
}

/**
 * @brief Capture a RAW16 still image and write bridge metadata.
 *
 * Performs optional focus, preview warm-up, still capture, metadata collection,
 * and diagnostic status reporting for the exported RAW capture APIs.
 */
static int capture_raw_internal(
    const char *camera_id, int width, int height,
    const char *raw_path, const char *metadata_path, int timeout_ms,
    int focus_mode, float focus_distance_diopters, int focus_timeout_ms,
    int capture_on_focus_failure, int scene_mode,
    int color_temperature_kelvin, int color_tint, int32_t sensor_sensitivity,
    int64_t exposure_time_ns, int aperture, int noise_reduction,
    float zoom_ratio, char *out, size_t out_size)
{
    int result_code = 0;
    const char *stage = "complete";
    ACameraManager *manager = NULL;
    ACameraMetadata *characteristics = NULL;
    ACameraDevice *device = NULL;
    AImageReader *raw_reader = NULL;
    AImageReader *preview_reader = NULL;
    ANativeWindow *raw_window = NULL;
    ANativeWindow *preview_window = NULL;
    ACaptureRequest *still_request = NULL;
    ACaptureRequest *preview_request = NULL;
    ACaptureRequest *trigger_request = NULL;
    ACameraOutputTarget *raw_target = NULL;
    ACameraOutputTarget *preview_target = NULL;
    ACaptureSessionOutput *raw_output = NULL;
    ACaptureSessionOutput *preview_output = NULL;
    ACaptureSessionOutputContainer *container = NULL;
    ACameraCaptureSession *session = NULL;
    bool repeating_started = false;

    if (!camera_id || !*camera_id || width <= 0 || height <= 0 ||
            !raw_path || !*raw_path || !metadata_path || !*metadata_path ||
            timeout_ms < 1000 || focus_timeout_ms < 100 ||
            focus_mode < SFOS_CAMERA2_FOCUS_NONE ||
            focus_mode > SFOS_CAMERA2_FOCUS_INFINITY ||
            scene_mode < SFOS_CAMERA2_SCENE_NONE ||
            scene_mode > SFOS_CAMERA2_SCENE_HDR ||
            color_temperature_kelvin < 0 ||
            sensor_sensitivity < 0 ||
            exposure_time_ns < 0 ||
            aperture < 0 || aperture > 255 ||
            noise_reduction < 0 ||
            focus_distance_diopters < 0.0f ||
            focus_distance_diopters != focus_distance_diopters ||
            !out || out_size < 2 ||
            strlen(raw_path) >= sizeof(((struct capture_context *)0)->raw_path)) {
        status_json(out, out_size, false, "arguments",
                    CAPTURE_INVALID_ARGUMENT, raw_path, metadata_path, NULL);
        return CAPTURE_INVALID_ARGUMENT;
    }

    struct capture_context context;
    memset(&context, 0, sizeof(context));
    atomic_init(&context.device_error, 0);
    atomic_init(&context.session_ready, 0);
    atomic_init(&context.session_active, 0);
    atomic_init(&context.session_closed, 0);
    atomic_init(&context.image_status, 0);
    atomic_init(&context.result_status, 0);
    atomic_init(&context.sequence_status, 0);
    atomic_init(&context.last_camera_status, ACAMERA_OK);
    atomic_init(&context.last_media_status, AMEDIA_OK);
    atomic_init(&context.af_state, -1);
    atomic_init(&context.af_outcome, 0);
    atomic_init(&context.af_result_count, 0);
    atomic_init(&context.focus_timed_out, 0);
    atomic_init(&context.preview_image_count, 0);
    context.started_ms = sfos_camera2_now_ms();
    context.focus_mode = focus_mode;
    context.requested_focus_distance =
        focus_mode == SFOS_CAMERA2_FOCUS_INFINITY ? 0.0f :
                                                    focus_distance_diopters;
    context.focus_timeout_ms = focus_timeout_ms;
    context.capture_on_focus_failure = capture_on_focus_failure != 0;
    context.scene_mode = scene_mode;
    context.color_temperature_kelvin = color_temperature_kelvin;
    context.color_tint = color_tint;
    context.sensor_sensitivity = sensor_sensitivity;
    context.exposure_time_ns = exposure_time_ns;
    context.aperture = aperture;
    context.noise_reduction = noise_reduction;
    context.zoom_ratio = zoom_ratio < 1.0f ? 1.0f : zoom_ratio;
    context.vendor_awb_value_requested = color_temperature_kelvin;
    if (context.vendor_awb_value_requested > 0 &&
            context.vendor_awb_value_requested < 2000) {
        context.vendor_awb_value_requested = 2000;
    } else if (context.vendor_awb_value_requested > 9000) {
        context.vendor_awb_value_requested = 9000;
    }
    strcpy(context.raw_path, raw_path);

    manager = ACameraManager_create();
    if (!manager) {
        result_code = CAPTURE_MANAGER_ERROR;
        stage = "manager_create";
        goto cleanup;
    }
    camera_status_t camera_status = ACameraManager_getCameraCharacteristics(
        manager, camera_id, &characteristics);
    remember_camera_status(&context, camera_status);
    if (camera_status != ACAMERA_OK || !characteristics) {
        result_code = CAPTURE_CHARACTERISTICS_ERROR;
        stage = "characteristics";
        goto cleanup;
    }
    if (!sfos_camera2_has_output_size(
            characteristics, AIMAGE_FORMAT_RAW16, width, height)) {
        result_code = CAPTURE_UNSUPPORTED_SIZE;
        stage = "raw_size";
        goto cleanup;
    }
    copy_static_metadata(&context.static_data, characteristics);
    context.characteristics_ms = sfos_camera2_now_ms() - context.started_ms;
    if (!focus_mode_supported(characteristics, focus_mode)) {
        focus_mode = SFOS_CAMERA2_FOCUS_NONE;
        context.focus_mode = focus_mode;
    }
    context.vendor_awb_value_supported = sfos_camera2_metadata_has_i32(
        characteristics, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        (int32_t)MTK_3A_AWB_VALUE);
    context.awb_off_supported = sfos_camera2_metadata_has_u8(
        characteristics, ACAMERA_CONTROL_AWB_AVAILABLE_MODES,
        ACAMERA_CONTROL_AWB_MODE_OFF);
    if (!sfos_camera2_scene_mode_supported(characteristics,
                                           context.scene_mode)) {
        context.scene_mode = SFOS_CAMERA2_SCENE_NONE;
    }
    if (focus_mode == SFOS_CAMERA2_FOCUS_MANUAL &&
            (context.static_data.minimum_focus_distance <= 0.0f ||
             context.requested_focus_distance >
                 context.static_data.minimum_focus_distance)) {
        result_code = CAPTURE_FOCUS_UNSUPPORTED;
        stage = "focus_distance";
        goto cleanup;
    }
    if ((focus_mode == SFOS_CAMERA2_FOCUS_AUTO ||
         focus_mode == SFOS_CAMERA2_FOCUS_CONTINUOUS) &&
            !select_preview_size(characteristics, &context.preview_width,
                                 &context.preview_height)) {
        result_code = CAPTURE_FOCUS_UNSUPPORTED;
        stage = "focus_preview_size";
        goto cleanup;
    }

    media_status_t media_status = AImageReader_new(
        width, height, AIMAGE_FORMAT_RAW16, 2, &raw_reader);
    remember_media_status(&context, media_status);
    if (media_status != AMEDIA_OK || !raw_reader) {
        result_code = CAPTURE_READER_ERROR;
        stage = "raw_reader_create";
        goto cleanup;
    }
    AImageReader_ImageListener raw_listener = {
        .context = &context,
        .onImageAvailable = raw_image_available,
    };
    media_status = AImageReader_setImageListener(raw_reader, &raw_listener);
    remember_media_status(&context, media_status);
    if (media_status == AMEDIA_OK) {
        media_status = AImageReader_getWindow(raw_reader, &raw_window);
        remember_media_status(&context, media_status);
    }
    if (media_status != AMEDIA_OK || !raw_window) {
        result_code = CAPTURE_READER_ERROR;
        stage = "raw_reader_configure";
        goto cleanup;
    }
    context.raw_reader_ms = sfos_camera2_now_ms() - context.started_ms;

    if (context.preview_width > 0) {
        media_status = AImageReader_new(
            context.preview_width, context.preview_height,
            AIMAGE_FORMAT_YUV_420_888, 4, &preview_reader);
        remember_media_status(&context, media_status);
        if (media_status != AMEDIA_OK || !preview_reader) {
            result_code = CAPTURE_READER_ERROR;
            stage = "focus_reader_create";
            goto cleanup;
        }
        AImageReader_ImageListener preview_listener = {
            .context = &context,
            .onImageAvailable = preview_image_available,
        };
        media_status = AImageReader_setImageListener(
            preview_reader, &preview_listener);
        remember_media_status(&context, media_status);
        if (media_status == AMEDIA_OK) {
            media_status = AImageReader_getWindow(
                preview_reader, &preview_window);
            remember_media_status(&context, media_status);
        }
        if (media_status != AMEDIA_OK || !preview_window) {
            result_code = CAPTURE_READER_ERROR;
            stage = "focus_reader_configure";
            goto cleanup;
        }
        context.focus_reader_ms = sfos_camera2_now_ms() - context.started_ms;
    }

    ACameraDevice_StateCallbacks device_callbacks = {
        .context = &context,
        .onDisconnected = device_disconnected,
        .onError = device_error,
    };
    camera_status = ACameraManager_openCamera(
        manager, camera_id, &device_callbacks, &device);
    remember_camera_status(&context, camera_status);
    if (camera_status != ACAMERA_OK || !device) {
        result_code = CAPTURE_OPEN_ERROR;
        stage = "camera_open";
        goto cleanup;
    }
    context.camera_open_ms = sfos_camera2_now_ms() - context.started_ms;

    camera_status = ACameraDevice_createCaptureRequest(
        device, TEMPLATE_STILL_CAPTURE, &still_request);
    remember_camera_status(&context, camera_status);
    if (camera_status == ACAMERA_OK) {
        camera_status = ACameraOutputTarget_create(raw_window, &raw_target);
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK) {
        camera_status = ACaptureRequest_addTarget(still_request, raw_target);
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK &&
            !configure_focus_request(still_request, focus_mode,
                                     context.requested_focus_distance, false)) {
        camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK &&
            !configure_option_request(still_request, characteristics,
                                      &context)) {
        camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK) {
        sfos_camera2_set_zoom_ratio(characteristics, still_request,
                                    context.zoom_ratio);
    }
    if (camera_status == ACAMERA_OK) {
        camera_status = ACaptureSessionOutput_create(raw_window, &raw_output);
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK) {
        camera_status = ACaptureSessionOutputContainer_create(&container);
        remember_camera_status(&context, camera_status);
    }
    if (camera_status == ACAMERA_OK) {
        camera_status = ACaptureSessionOutputContainer_add(
            container, raw_output);
        remember_camera_status(&context, camera_status);
    }
    if (camera_status != ACAMERA_OK) {
        result_code = CAPTURE_CONFIGURATION_ERROR;
        stage = "raw_output_configure";
        goto cleanup;
    }

    if (preview_window) {
        camera_status = ACameraOutputTarget_create(
            preview_window, &preview_target);
        remember_camera_status(&context, camera_status);
        if (camera_status == ACAMERA_OK) {
            camera_status = ACaptureSessionOutput_create(
                preview_window, &preview_output);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK) {
            camera_status = ACaptureSessionOutputContainer_add(
                container, preview_output);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK) {
            camera_status = ACameraDevice_createCaptureRequest(
                device, TEMPLATE_PREVIEW, &preview_request);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK) {
            camera_status = ACaptureRequest_addTarget(
                preview_request, preview_target);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK &&
                !configure_focus_request(
                    preview_request, focus_mode,
                    context.requested_focus_distance, false)) {
            camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK &&
                !configure_option_request(preview_request, characteristics,
                                          &context)) {
            camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK) {
            sfos_camera2_set_zoom_ratio(characteristics, preview_request,
                                        context.zoom_ratio);
        }
        if (camera_status == ACAMERA_OK &&
                focus_mode == SFOS_CAMERA2_FOCUS_AUTO) {
            camera_status = ACameraDevice_createCaptureRequest(
                device, TEMPLATE_PREVIEW, &trigger_request);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK && trigger_request) {
            camera_status = ACaptureRequest_addTarget(
                trigger_request, preview_target);
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK && trigger_request &&
                !configure_focus_request(
                    trigger_request, focus_mode,
                    context.requested_focus_distance, true)) {
            camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK && trigger_request &&
                !configure_option_request(trigger_request, characteristics,
                                          &context)) {
            camera_status = ACAMERA_ERROR_INVALID_PARAMETER;
            remember_camera_status(&context, camera_status);
        }
        if (camera_status == ACAMERA_OK && trigger_request) {
            sfos_camera2_set_zoom_ratio(characteristics, trigger_request,
                                        context.zoom_ratio);
        }
        if (camera_status != ACAMERA_OK) {
            result_code = CAPTURE_FOCUS_CONFIGURATION_ERROR;
            stage = "focus_output_configure";
            goto cleanup;
        }
    }

    ACameraCaptureSession_stateCallbacks session_callbacks = {
        .context = &context,
        .onClosed = session_closed,
        .onReady = session_ready,
        .onActive = session_active,
    };
    camera_status = ACameraDevice_createCaptureSession(
        device, container, &session_callbacks, &session);
    remember_camera_status(&context, camera_status);
    if (camera_status != ACAMERA_OK || !session) {
        result_code = CAPTURE_CONFIGURATION_ERROR;
        stage = "session_create";
        goto cleanup;
    }
    context.session_ms = sfos_camera2_now_ms() - context.started_ms;

    ACameraCaptureSession_captureCallbacks focus_callbacks = {
        .context = &context,
        .onCaptureStarted = capture_started,
        .onCaptureProgressed = focus_capture_progressed,
        .onCaptureCompleted = focus_capture_completed,
        .onCaptureFailed = focus_capture_failed,
        .onCaptureSequenceCompleted = NULL,
        .onCaptureSequenceAborted = NULL,
        .onCaptureBufferLost = NULL,
    };
    if (preview_request) {
        ACaptureRequest *preview_requests[] = { preview_request };
        camera_status = ACameraCaptureSession_setRepeatingRequest(
            session, &focus_callbacks, 1, preview_requests, NULL);
        remember_camera_status(&context, camera_status);
        if (camera_status != ACAMERA_OK) {
            result_code = CAPTURE_SUBMIT_ERROR;
            stage = "focus_repeat_submit";
            goto cleanup;
        }
        repeating_started = true;
        if (trigger_request) {
            ACaptureRequest *trigger_requests[] = { trigger_request };
            camera_status = ACameraCaptureSession_capture(
                session, &focus_callbacks, 1, trigger_requests, NULL);
            remember_camera_status(&context, camera_status);
            if (camera_status != ACAMERA_OK) {
                result_code = CAPTURE_SUBMIT_ERROR;
                stage = "focus_trigger_submit";
                goto cleanup;
            }
        }
        bool focus_finished = wait_for_focus(&context);
        int af_outcome = atomic_load_explicit(
            &context.af_outcome, memory_order_acquire);
        if ((!focus_finished || af_outcome < 0) &&
                !context.capture_on_focus_failure) {
            result_code = CAPTURE_FOCUS_FAILED;
            stage = "focus_wait";
            goto cleanup;
        }
        context.focus_done_ms = sfos_camera2_now_ms() - context.started_ms;
        camera_status = ACameraCaptureSession_stopRepeating(session);
        remember_camera_status(&context, camera_status);
        repeating_started = false;
        if (camera_status != ACAMERA_OK) {
            result_code = CAPTURE_SUBMIT_ERROR;
            stage = "focus_repeat_stop";
            goto cleanup;
        }
    }

    ACameraCaptureSession_captureCallbacks capture_callbacks = {
        .context = &context,
        .onCaptureStarted = capture_started,
        .onCaptureProgressed = capture_progressed,
        .onCaptureCompleted = capture_completed,
        .onCaptureFailed = capture_failed,
        .onCaptureSequenceCompleted = sequence_completed,
        .onCaptureSequenceAborted = sequence_aborted,
        .onCaptureBufferLost = buffer_lost,
    };
    ACaptureRequest *requests[] = { still_request };
    camera_status = ACameraCaptureSession_capture(
        session, &capture_callbacks, 1, requests, NULL);
    remember_camera_status(&context, camera_status);
    if (camera_status != ACAMERA_OK) {
        result_code = CAPTURE_SUBMIT_ERROR;
        stage = "capture_submit";
        goto cleanup;
    }
    context.capture_submit_ms = sfos_camera2_now_ms() - context.started_ms;
    if (!wait_for_capture(&context, timeout_ms)) {
        result_code = CAPTURE_TIMEOUT;
        stage = "capture_wait";
        goto cleanup;
    }
    if (atomic_load_explicit(&context.image_status,
                             memory_order_acquire) < 0) {
        result_code = CAPTURE_IMAGE_ERROR;
        stage = "raw_image";
        goto cleanup;
    }
    if (atomic_load_explicit(&context.result_status,
                             memory_order_acquire) < 0 ||
            atomic_load_explicit(&context.sequence_status,
                                 memory_order_acquire) < 0) {
        result_code = CAPTURE_RESULT_ERROR;
        stage = "capture_result";
        goto cleanup;
    }
    context.capture_done_ms = sfos_camera2_now_ms() - context.started_ms;
    if (!write_metadata_file(metadata_path, camera_id, raw_path, &context)) {
        result_code = CAPTURE_METADATA_ERROR;
        stage = "metadata_write";
        goto cleanup;
    }
    context.metadata_written_ms = sfos_camera2_now_ms() - context.started_ms;

cleanup:
    if (result_code == 0) {
        status_json(out, out_size, true, "complete", 0,
                    raw_path, metadata_path, &context);
    } else {
        status_json(out, out_size, false, stage, result_code,
                    raw_path, metadata_path, &context);
    }
    if (session && repeating_started) {
        ACameraCaptureSession_stopRepeating(session);
    }
    if (session) {
        ACameraCaptureSession_close(session);
        wait_for_nonzero(&context.session_closed, &context.device_error, 2000);
    }
    if (raw_target) {
        ACameraOutputTarget_free(raw_target);
    }
    if (preview_target) {
        ACameraOutputTarget_free(preview_target);
    }
    if (raw_output) {
        ACaptureSessionOutput_free(raw_output);
    }
    if (preview_output) {
        ACaptureSessionOutput_free(preview_output);
    }
    if (container) {
        ACaptureSessionOutputContainer_free(container);
    }
    if (still_request) {
        ACaptureRequest_free(still_request);
    }
    if (preview_request) {
        ACaptureRequest_free(preview_request);
    }
    if (trigger_request) {
        ACaptureRequest_free(trigger_request);
    }
    if (raw_reader) {
        AImageReader_setImageListener(raw_reader, NULL);
        AImageReader_delete(raw_reader);
    }
    if (preview_reader) {
        AImageReader_setImageListener(preview_reader, NULL);
        AImageReader_delete(preview_reader);
    }
    if (device) {
        ACameraDevice_close(device);
    }
    if (characteristics) {
        ACameraMetadata_free(characteristics);
    }
    if (manager) {
        ACameraManager_delete(manager);
    }
    return result_code;
}

/**
 * @brief ABI-safe RAW capture wrapper that accepts an options struct.
 */
int sfos_camera2_capture_raw_options(
    const char *camera_id, int width, int height,
    const char *raw_path, const char *metadata_path, int timeout_ms,
    const struct sfos_camera2_capture_options *options,
    char *out, size_t out_size)
{
    struct sfos_camera2_capture_options defaults = {
        .size = sizeof(defaults),
        .focus_mode = SFOS_CAMERA2_FOCUS_NONE,
        .focus_distance_diopters = 0.0f,
        .focus_timeout_ms = 3000,
        .capture_on_focus_failure = 1,
        .scene_mode = SFOS_CAMERA2_SCENE_NONE,
        .color_temperature_kelvin = 0,
        .color_tint = 0,
        .zoom_ratio = 1.0f,
        .sensor_sensitivity = 0,
        .exposure_time_ns = 0,
        .aperture = 0,
        .noise_reduction = SFOS_CAMERA2_NOISE_REDUCTION_NONE,
    };

    if (options) {
        if (options->size < offsetof(struct sfos_camera2_capture_options,
                                     color_tint) + sizeof(options->color_tint)) {
            status_json(out, out_size, false, "options",
                        CAPTURE_INVALID_ARGUMENT, raw_path, metadata_path,
                        NULL);
            return CAPTURE_INVALID_ARGUMENT;
        }
        defaults.focus_mode = options->focus_mode;
        defaults.focus_distance_diopters = options->focus_distance_diopters;
        defaults.focus_timeout_ms = options->focus_timeout_ms;
        defaults.capture_on_focus_failure = options->capture_on_focus_failure;
        defaults.scene_mode = options->scene_mode;
        defaults.color_temperature_kelvin = options->color_temperature_kelvin;
        defaults.color_tint = options->color_tint;
        if (options->size >=
                offsetof(struct sfos_camera2_capture_options, zoom_ratio) +
                    sizeof(options->zoom_ratio)) {
            defaults.zoom_ratio = options->zoom_ratio;
        }
        if (options->size >=
                offsetof(struct sfos_camera2_capture_options,
                         sensor_sensitivity) +
                    sizeof(options->sensor_sensitivity)) {
            defaults.sensor_sensitivity = options->sensor_sensitivity;
        }
        if (options->size >=
                offsetof(struct sfos_camera2_capture_options,
                         exposure_time_ns) +
                    sizeof(options->exposure_time_ns)) {
            defaults.exposure_time_ns = options->exposure_time_ns;
        }
        if (options->size >=
                offsetof(struct sfos_camera2_capture_options, aperture) +
                    sizeof(options->aperture)) {
            defaults.aperture = options->aperture;
        }
        if (options->size >=
                offsetof(struct sfos_camera2_capture_options,
                         noise_reduction) +
                    sizeof(options->noise_reduction)) {
            defaults.noise_reduction = options->noise_reduction;
        }
    }

    return capture_raw_internal(
        camera_id, width, height, raw_path, metadata_path, timeout_ms,
        defaults.focus_mode, defaults.focus_distance_diopters,
        defaults.focus_timeout_ms, defaults.capture_on_focus_failure,
        defaults.scene_mode, defaults.color_temperature_kelvin,
        defaults.color_tint, defaults.sensor_sensitivity,
        defaults.exposure_time_ns, defaults.aperture,
        defaults.noise_reduction,
        defaults.zoom_ratio, out, out_size);
}
