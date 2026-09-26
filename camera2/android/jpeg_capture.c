/**
 * @file jpeg_capture.c
 * @brief Direct Camera2 JPEG still capture implementation.
 *
 * Opens a Camera2 device, configures a JPEG ImageReader, submits a single still
 * request, writes the JPEG payload to disk, and reports timing/status as JSON.
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
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum jpeg_error {
    JPEG_INVALID_ARGUMENT = -40,
    JPEG_UNSUPPORTED_SIZE = -41,
    JPEG_MANAGER_ERROR = -42,
    JPEG_CHARACTERISTICS_ERROR = -43,
    JPEG_READER_ERROR = -44,
    JPEG_OPEN_ERROR = -45,
    JPEG_CONFIGURATION_ERROR = -46,
    JPEG_SUBMIT_ERROR = -47,
    JPEG_TIMEOUT = -48,
    JPEG_WRITE_ERROR = -49,
};

struct jpeg_context {
    struct sfos_camera2_status status;
    int width;
    int height;
    int data_length;
    const char *jpeg_path;
    int64_t started_ms;
    int64_t characteristics_ms;
    int64_t reader_ms;
    int64_t camera_open_ms;
    int64_t session_ms;
    int64_t capture_submit_ms;
    int64_t image_available_ms;
    int64_t file_written_ms;
    int32_t requested_sensitivity;
    int64_t requested_exposure_time_ns;
    int32_t actual_sensitivity;
    int64_t actual_exposure_time_ns;
    int64_t actual_frame_duration_ns;
};

static void jpeg_device_disconnected(void *opaque, ACameraDevice *device)
{
    (void)device;
    struct jpeg_context *context = opaque;
    atomic_store_explicit(&context->status.device_error, -1,
                          memory_order_release);
}

static void jpeg_device_error(void *opaque, ACameraDevice *device, int error)
{
    (void)device;
    struct jpeg_context *context = opaque;
    atomic_store_explicit(&context->status.device_error,
                          error > 0 ? error : -1, memory_order_release);
}

static void jpeg_image_available(void *opaque, AImageReader *reader)
{
    struct jpeg_context *context = opaque;
    if (atomic_load_explicit(&context->status.image_status,
                             memory_order_acquire) != 0) {
        return;
    }

    AImage *image = NULL;
    media_status_t status = AImageReader_acquireNextImage(reader, &image);
    atomic_store_explicit(&context->status.last_media_status, status,
                          memory_order_release);
    if (status != AMEDIA_OK || !image) {
        return;
    }

    uint8_t *data = NULL;
    int data_length = 0;
    int width = 0;
    int height = 0;
    int format = 0;
    context->image_available_ms = sfos_camera2_now_ms() - context->started_ms;
    if (AImage_getWidth(image, &width) != AMEDIA_OK ||
            AImage_getHeight(image, &height) != AMEDIA_OK ||
            AImage_getFormat(image, &format) != AMEDIA_OK ||
            AImage_getPlaneData(image, 0, &data, &data_length) != AMEDIA_OK ||
            width != context->width || height != context->height ||
            format != AIMAGE_FORMAT_JPEG || !data || data_length <= 0 ||
            sfos_camera2_write_file(context->jpeg_path, data,
                                    (size_t)data_length) != 0) {
        atomic_store_explicit(&context->status.image_status, -1,
                              memory_order_release);
    } else {
        context->data_length = data_length;
        context->file_written_ms = sfos_camera2_now_ms() - context->started_ms;
        atomic_store_explicit(&context->status.image_status, 1,
                              memory_order_release);
    }
    AImage_delete(image);
}

static void jpeg_capture_completed(void *opaque,
                                   ACameraCaptureSession *session,
                                   ACaptureRequest *request,
                                   const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    struct jpeg_context *context = opaque;
    if (!context || !result) {
        return;
    }

    context->actual_sensitivity = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_SENSITIVITY, -1);
    context->actual_exposure_time_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_EXPOSURE_TIME, -1);
    context->actual_frame_duration_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_FRAME_DURATION, -1);
    fprintf(stderr,
            "capture-exposure jpeg requested_iso=%d requested_shutter=%lld "
            "actual_iso=%d actual_shutter=%lld actual_frame=%lld\n",
            context->requested_sensitivity,
            (long long)context->requested_exposure_time_ns,
            context->actual_sensitivity,
            (long long)context->actual_exposure_time_ns,
            (long long)context->actual_frame_duration_ns);
}

static void jpeg_status_json(char *out, size_t out_size, bool success,
                             const char *stage, int code,
                             const struct jpeg_context *context)
{
    if (!out || out_size == 0) {
        return;
    }
    snprintf(out, out_size,
             "{\"status\":\"%s\",\"stage\":\"%s\",\"code\":%d,"
             "\"jpeg_path\":\"%s\",\"width\":%d,\"height\":%d,"
             "\"data_length\":%d,"
             "\"timing_ms\":{\"characteristics\":%lld,"
             "\"reader\":%lld,\"camera_open\":%lld,"
             "\"session\":%lld,\"capture_submit\":%lld,"
             "\"image_available\":%lld,\"file_written\":%lld,"
             "\"total\":%lld},"
             "\"diagnostics\":{\"camera_status\":%d,"
             "\"media_status\":%d,\"device_error\":%d,"
             "\"image_status\":%d}}",
             success ? "ok" : "error", stage ? stage : "unknown", code,
             context && context->jpeg_path ? context->jpeg_path : "",
             context ? context->width : 0, context ? context->height : 0,
             context ? context->data_length : 0,
             context ? (long long)context->characteristics_ms : 0,
             context ? (long long)context->reader_ms : 0,
             context ? (long long)context->camera_open_ms : 0,
             context ? (long long)context->session_ms : 0,
             context ? (long long)context->capture_submit_ms : 0,
             context ? (long long)context->image_available_ms : 0,
             context ? (long long)context->file_written_ms : 0,
             context ? (long long)(sfos_camera2_now_ms() - context->started_ms) : 0,
             context ? atomic_load_explicit(&context->status.last_camera_status,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.last_media_status,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.device_error,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.image_status,
                                            memory_order_acquire) : 0);
}

/**
 * @brief Capture one JPEG image through a short-lived Camera2 session.
 *
 * The function owns the full Camera2 lifecycle for direct JPEG capture:
 * manager, device, ImageReader, session, request, and output file write.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_capture_jpeg(
    const char *camera_id, int width, int height, const char *jpeg_path,
    int timeout_ms, int jpeg_quality, int orientation_degrees,
    int scene_mode, int sensor_sensitivity, long long exposure_time_ns,
    int aperture, int noise_reduction, float zoom_ratio, char *out,
    size_t out_size)
{
    int result_code = 0;
    const char *stage = "complete";
    ACameraManager *manager = NULL;
    ACameraMetadata *characteristics = NULL;
    ACameraDevice *device = NULL;
    AImageReader *reader = NULL;
    ANativeWindow *window = NULL;
    ACameraOutputTarget *target = NULL;
    ACaptureRequest *request = NULL;
    ACaptureSessionOutput *output = NULL;
    ACaptureSessionOutputContainer *container = NULL;
    ACameraCaptureSession *session = NULL;

    struct jpeg_context context;
    memset(&context, 0, sizeof(context));
    sfos_camera2_status_init(&context.status);
    context.width = width;
    context.height = height;
    context.jpeg_path = jpeg_path;
    context.started_ms = sfos_camera2_now_ms();
    context.requested_sensitivity = sensor_sensitivity;
    context.requested_exposure_time_ns = exposure_time_ns;

    if (!camera_id || !*camera_id || width <= 0 || height <= 0 ||
            !jpeg_path || !*jpeg_path || timeout_ms < 1000 ||
            jpeg_quality < 1 || jpeg_quality > 100 ||
            scene_mode < SFOS_CAMERA2_SCENE_NONE ||
            scene_mode > SFOS_CAMERA2_SCENE_HDR ||
            sensor_sensitivity < 0 ||
            exposure_time_ns < 0 ||
            aperture < 0 || aperture > 255 ||
            noise_reduction < 0 ||
            !out || out_size < 2) {
        jpeg_status_json(out, out_size, false, "arguments",
                         JPEG_INVALID_ARGUMENT, &context);
        return JPEG_INVALID_ARGUMENT;
    }

    manager = ACameraManager_create();
    if (!manager) {
        result_code = JPEG_MANAGER_ERROR;
        stage = "manager_create";
        goto cleanup;
    }
    camera_status_t camera_status = ACameraManager_getCameraCharacteristics(
        manager, camera_id, &characteristics);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !characteristics) {
        result_code = JPEG_CHARACTERISTICS_ERROR;
        stage = "characteristics";
        goto cleanup;
    }
    context.characteristics_ms = sfos_camera2_now_ms() - context.started_ms;
    if (!sfos_camera2_has_output_size(
            characteristics, AIMAGE_FORMAT_JPEG, width, height)) {
        result_code = JPEG_UNSUPPORTED_SIZE;
        stage = "jpeg_size";
        goto cleanup;
    }
    if (!sfos_camera2_scene_mode_supported(characteristics, scene_mode)) {
        scene_mode = SFOS_CAMERA2_SCENE_NONE;
    }

    media_status_t media_status = AImageReader_new(
        width, height, AIMAGE_FORMAT_JPEG, 2, &reader);
    atomic_store_explicit(&context.status.last_media_status, media_status,
                          memory_order_release);
    if (media_status != AMEDIA_OK || !reader) {
        result_code = JPEG_READER_ERROR;
        stage = "reader_create";
        goto cleanup;
    }
    AImageReader_ImageListener listener = {
        .context = &context,
        .onImageAvailable = jpeg_image_available,
    };
    media_status = AImageReader_setImageListener(reader, &listener);
    atomic_store_explicit(&context.status.last_media_status, media_status,
                          memory_order_release);
    if (media_status == AMEDIA_OK) {
        media_status = AImageReader_getWindow(reader, &window);
        atomic_store_explicit(&context.status.last_media_status, media_status,
                              memory_order_release);
    }
    if (media_status != AMEDIA_OK || !window) {
        result_code = JPEG_READER_ERROR;
        stage = "reader_configure";
        goto cleanup;
    }
    context.reader_ms = sfos_camera2_now_ms() - context.started_ms;

    ACameraDevice_StateCallbacks device_callbacks = {
        .context = &context,
        .onDisconnected = jpeg_device_disconnected,
        .onError = jpeg_device_error,
    };
    camera_status = ACameraManager_openCamera(
        manager, camera_id, &device_callbacks, &device);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !device) {
        result_code = JPEG_OPEN_ERROR;
        stage = "camera_open";
        goto cleanup;
    }
    context.camera_open_ms = sfos_camera2_now_ms() - context.started_ms;

    if (ACameraOutputTarget_create(window, &target) != ACAMERA_OK ||
            ACameraDevice_createCaptureRequest(device, TEMPLATE_STILL_CAPTURE,
                                               &request) != ACAMERA_OK ||
            ACaptureRequest_addTarget(request, target) != ACAMERA_OK ||
            ACaptureSessionOutput_create(window, &output) != ACAMERA_OK ||
            ACaptureSessionOutputContainer_create(&container) != ACAMERA_OK ||
            ACaptureSessionOutputContainer_add(container, output) !=
                ACAMERA_OK) {
        result_code = JPEG_CONFIGURATION_ERROR;
        stage = "configure";
        goto cleanup;
    }

    uint8_t quality = (uint8_t)jpeg_quality;
    int32_t orientation = orientation_degrees;
    uint8_t af_mode = ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
    if (!sfos_camera2_metadata_has_u8(
            characteristics, ACAMERA_CONTROL_AF_AVAILABLE_MODES, af_mode)) {
        af_mode = ACAMERA_CONTROL_AF_MODE_OFF;
    }
    ACaptureRequest_setEntry_u8(request, ACAMERA_JPEG_QUALITY, 1, &quality);
    ACaptureRequest_setEntry_i32(request, ACAMERA_JPEG_ORIENTATION, 1,
                                 &orientation);
    ACaptureRequest_setEntry_u8(request, ACAMERA_CONTROL_AF_MODE, 1,
                                &af_mode);
    sfos_camera2_set_scene_mode(request, scene_mode);
    sfos_camera2_set_manual_sensor(characteristics, request,
                                   sensor_sensitivity, exposure_time_ns);
    sfos_camera2_set_aperture(characteristics, request, aperture);
    sfos_camera2_set_noise_reduction(characteristics, request,
                                     noise_reduction);
    sfos_camera2_set_zoom_ratio(characteristics, request, zoom_ratio);

    ACameraCaptureSession_stateCallbacks session_callbacks = {
        .context = &context,
        .onClosed = NULL,
        .onReady = NULL,
        .onActive = NULL,
    };
    camera_status = ACameraDevice_createCaptureSession(
        device, container, &session_callbacks, &session);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !session) {
        result_code = JPEG_CONFIGURATION_ERROR;
        stage = "session_create";
        goto cleanup;
    }
    context.session_ms = sfos_camera2_now_ms() - context.started_ms;

    ACameraCaptureSession_captureCallbacks capture_callbacks = {
        .context = &context,
        .onCaptureStarted = NULL,
        .onCaptureProgressed = NULL,
        .onCaptureCompleted = jpeg_capture_completed,
        .onCaptureFailed = NULL,
        .onCaptureSequenceCompleted = NULL,
        .onCaptureSequenceAborted = NULL,
        .onCaptureBufferLost = NULL,
    };
    ACaptureRequest *requests[] = { request };
    camera_status = ACameraCaptureSession_capture(
        session, &capture_callbacks, 1, requests, NULL);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK) {
        result_code = JPEG_SUBMIT_ERROR;
        stage = "capture_submit";
        goto cleanup;
    }
    context.capture_submit_ms = sfos_camera2_now_ms() - context.started_ms;

    int64_t deadline = sfos_camera2_now_ms() + timeout_ms;
    while (sfos_camera2_now_ms() < deadline &&
            atomic_load_explicit(&context.status.device_error,
                                 memory_order_acquire) == 0 &&
            atomic_load_explicit(&context.status.image_status,
                                 memory_order_acquire) == 0) {
        sfos_camera2_sleep_10_ms();
    }
    if (atomic_load_explicit(&context.status.image_status,
                             memory_order_acquire) < 0) {
        result_code = JPEG_WRITE_ERROR;
        stage = "image_write";
        goto cleanup;
    }
    if (atomic_load_explicit(&context.status.image_status,
                             memory_order_acquire) == 0) {
        result_code = JPEG_TIMEOUT;
        stage = "image_wait";
        goto cleanup;
    }

cleanup:
    jpeg_status_json(out, out_size, result_code == 0, stage, result_code,
                     &context);
    if (session) {
        ACameraCaptureSession_close(session);
    }
    if (target) {
        ACameraOutputTarget_free(target);
    }
    if (output) {
        ACaptureSessionOutput_free(output);
    }
    if (container) {
        ACaptureSessionOutputContainer_free(container);
    }
    if (request) {
        ACaptureRequest_free(request);
    }
    if (reader) {
        AImageReader_setImageListener(reader, NULL);
        AImageReader_delete(reader);
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
