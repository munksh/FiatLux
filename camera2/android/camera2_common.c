/**
 * @file camera2_common.c
 * @brief Shared Android Camera2 bridge helpers.
 *
 * Provides metadata readers, request setters, file I/O helpers, timing helpers,
 * and common controls used by RAW, JPEG, preview, and probe bridge code.
 */

#include "camera2_common.h"
#include "camera2_bridge.h"

#include <camera/NdkCameraMetadataTags.h>

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

void sfos_camera2_status_init(struct sfos_camera2_status *status)
{
    atomic_init(&status->device_error, 0);
    atomic_init(&status->image_status, 0);
    atomic_init(&status->last_camera_status, ACAMERA_OK);
    atomic_init(&status->last_media_status, 0);
}

int64_t sfos_camera2_now_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0;
    }
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

void sfos_camera2_sleep_10_ms(void)
{
    const struct timespec delay = {
        .tv_sec = 0,
        .tv_nsec = 10000000,
    };
    nanosleep(&delay, NULL);
}

bool sfos_camera2_metadata_has_u8(const ACameraMetadata *metadata,
                                  uint32_t tag, uint8_t wanted)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK) {
        return false;
    }
    for (uint32_t index = 0; index < entry.count; ++index) {
        if (entry.data.u8[index] == wanted) {
            return true;
        }
    }
    return false;
}

bool sfos_camera2_metadata_has_i32(const ACameraMetadata *metadata,
                                   uint32_t tag, int32_t wanted)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK) {
        return false;
    }
    for (uint32_t index = 0; index < entry.count; ++index) {
        if (entry.data.i32[index] == wanted) {
            return true;
        }
    }
    return false;
}

int32_t sfos_camera2_first_u8(const ACameraMetadata *metadata,
                              uint32_t tag, int32_t fallback)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK ||
            entry.count == 0) {
        return fallback;
    }
    return entry.data.u8[0];
}

int32_t sfos_camera2_first_i32(const ACameraMetadata *metadata,
                               uint32_t tag, int32_t fallback)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK ||
            entry.count == 0) {
        return fallback;
    }
    return entry.data.i32[0];
}

int64_t sfos_camera2_first_i64(const ACameraMetadata *metadata,
                               uint32_t tag, int64_t fallback)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK ||
            entry.count == 0) {
        return fallback;
    }
    return entry.data.i64[0];
}

float sfos_camera2_first_float(const ACameraMetadata *metadata,
                               uint32_t tag, float fallback)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK ||
            entry.count == 0) {
        return fallback;
    }
    return entry.data.f[0];
}

uint32_t sfos_camera2_copy_i32_array(const ACameraMetadata *metadata,
                                     uint32_t tag, int32_t *destination,
                                     uint32_t maximum)
{
    ACameraMetadata_const_entry entry;
    if (!destination || maximum == 0 ||
            ACameraMetadata_getConstEntry(metadata, tag, &entry) !=
                ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < maximum ? entry.count : maximum;
    memcpy(destination, entry.data.i32, count * sizeof(*destination));
    return count;
}

uint32_t sfos_camera2_copy_i64_array(const ACameraMetadata *metadata,
                                     uint32_t tag, int64_t *destination,
                                     uint32_t maximum)
{
    ACameraMetadata_const_entry entry;
    if (!destination || maximum == 0 ||
            ACameraMetadata_getConstEntry(metadata, tag, &entry) !=
                ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < maximum ? entry.count : maximum;
    memcpy(destination, entry.data.i64, count * sizeof(*destination));
    return count;
}

uint32_t sfos_camera2_copy_float_array(const ACameraMetadata *metadata,
                                       uint32_t tag, float *destination,
                                       uint32_t maximum)
{
    ACameraMetadata_const_entry entry;
    if (!destination || maximum == 0 ||
            ACameraMetadata_getConstEntry(metadata, tag, &entry) !=
                ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < maximum ? entry.count : maximum;
    memcpy(destination, entry.data.f, count * sizeof(*destination));
    return count;
}

uint32_t sfos_camera2_copy_double_array(const ACameraMetadata *metadata,
                                        uint32_t tag, double *destination,
                                        uint32_t maximum)
{
    ACameraMetadata_const_entry entry;
    if (!destination || maximum == 0 ||
            ACameraMetadata_getConstEntry(metadata, tag, &entry) !=
                ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < maximum ? entry.count : maximum;
    memcpy(destination, entry.data.d, count * sizeof(*destination));
    return count;
}

bool sfos_camera2_has_output_size(const ACameraMetadata *metadata,
                                  int32_t format, int width, int height)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
            &entry) != ACAMERA_OK) {
        return false;
    }
    for (uint32_t index = 0; index + 3 < entry.count; index += 4) {
        if (entry.data.i32[index] == format &&
                entry.data.i32[index + 1] == width &&
                entry.data.i32[index + 2] == height &&
                entry.data.i32[index + 3] ==
                    ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT) {
            return true;
        }
    }
    return false;
}

int sfos_camera2_write_all(int fd, const void *data, size_t size)
{
    const char *cursor = data;
    while (size > 0) {
        ssize_t written = write(fd, cursor, size);
        if (written <= 0) {
            return -1;
        }
        cursor += written;
        size -= (size_t)written;
    }
    return 0;
}

int sfos_camera2_write_file(const char *path, const void *data, size_t size)
{
    FILE *file = fopen(path, "wb");
    if (!file) {
        return -1;
    }
    int result = fwrite(data, 1, size, file) == size ? 0 : -1;
    if (fclose(file) != 0) {
        result = -1;
    }
    return result;
}

int32_t sfos_camera2_clamp_i32(int32_t value, int32_t low, int32_t high)
{
    if (value < low) {
        return low;
    }
    return value > high ? high : value;
}

bool sfos_camera2_set_request_u8(ACaptureRequest *request, uint32_t tag,
                                 uint8_t value)
{
    return request &&
           ACaptureRequest_setEntry_u8(request, tag, 1, &value) == ACAMERA_OK;
}

bool sfos_camera2_set_request_i32(ACaptureRequest *request, uint32_t tag,
                                  int32_t value)
{
    return request &&
           ACaptureRequest_setEntry_i32(request, tag, 1, &value) == ACAMERA_OK;
}

bool sfos_camera2_set_request_i64(ACaptureRequest *request, uint32_t tag,
                                  int64_t value)
{
    return request &&
           ACaptureRequest_setEntry_i64(request, tag, 1, &value) == ACAMERA_OK;
}

bool sfos_camera2_set_request_float(ACaptureRequest *request, uint32_t tag,
                                    float value)
{
    return request &&
           ACaptureRequest_setEntry_float(request, tag, 1, &value) ==
               ACAMERA_OK;
}

static bool sfos_camera2_scene_to_android(int scene_mode,
                                          uint8_t *android_scene_mode)
{
    if (scene_mode == SFOS_CAMERA2_SCENE_MANUAL ||
            scene_mode == SFOS_CAMERA2_SCENE_AUTO) {
        return true;
    }
    if (!android_scene_mode) {
        return false;
    }

    switch (scene_mode) {
    case SFOS_CAMERA2_SCENE_PORTRAIT:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_PORTRAIT;
        break;
    case SFOS_CAMERA2_SCENE_LANDSCAPE:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_LANDSCAPE;
        break;
    case SFOS_CAMERA2_SCENE_SPORT:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_SPORTS;
        break;
    case SFOS_CAMERA2_SCENE_NIGHT:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_NIGHT;
        break;
    case SFOS_CAMERA2_SCENE_ACTION:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_ACTION;
        break;
    case SFOS_CAMERA2_SCENE_NIGHT_PORTRAIT:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_NIGHT_PORTRAIT;
        break;
    case SFOS_CAMERA2_SCENE_THEATRE:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_THEATRE;
        break;
    case SFOS_CAMERA2_SCENE_BEACH:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_BEACH;
        break;
    case SFOS_CAMERA2_SCENE_SNOW:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_SNOW;
        break;
    case SFOS_CAMERA2_SCENE_SUNSET:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_SUNSET;
        break;
    case SFOS_CAMERA2_SCENE_STEADY_PHOTO:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_STEADYPHOTO;
        break;
    case SFOS_CAMERA2_SCENE_FIREWORKS:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_FIREWORKS;
        break;
    case SFOS_CAMERA2_SCENE_PARTY:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_PARTY;
        break;
    case SFOS_CAMERA2_SCENE_CANDLELIGHT:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_CANDLELIGHT;
        break;
    case SFOS_CAMERA2_SCENE_BARCODE:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_BARCODE;
        break;
    case SFOS_CAMERA2_SCENE_HDR:
        *android_scene_mode = ACAMERA_CONTROL_SCENE_MODE_HDR;
        break;
    default:
        return false;
    }
    return true;
}

bool sfos_camera2_scene_mode_supported(const ACameraMetadata *metadata,
                                       int scene_mode)
{
    uint8_t android_scene_mode = 0;
    if (scene_mode == SFOS_CAMERA2_SCENE_MANUAL ||
            scene_mode == SFOS_CAMERA2_SCENE_AUTO) {
        return true;
    }
    if (!sfos_camera2_scene_to_android(scene_mode, &android_scene_mode)) {
        return false;
    }
    return sfos_camera2_metadata_has_u8(
        metadata, ACAMERA_CONTROL_AVAILABLE_SCENE_MODES,
        android_scene_mode);
}

bool sfos_camera2_set_scene_mode(ACaptureRequest *request, int scene_mode)
{
    uint8_t android_scene_mode = 0;
    if (scene_mode == SFOS_CAMERA2_SCENE_MANUAL ||
            scene_mode == SFOS_CAMERA2_SCENE_AUTO) {
        return sfos_camera2_set_request_u8(
            request, ACAMERA_CONTROL_MODE, ACAMERA_CONTROL_MODE_AUTO);
    }
    if (!sfos_camera2_scene_to_android(scene_mode, &android_scene_mode)) {
        return false;
    }
    return sfos_camera2_set_request_u8(
               request, ACAMERA_CONTROL_MODE,
               ACAMERA_CONTROL_MODE_USE_SCENE_MODE) &&
           sfos_camera2_set_request_u8(
               request, ACAMERA_CONTROL_SCENE_MODE,
               android_scene_mode);
}

bool sfos_camera2_set_manual_sensor(const ACameraMetadata *metadata,
                                    ACaptureRequest *request,
                                    int32_t sensitivity,
                                    int64_t exposure_time_ns)
{
    if (!metadata || !request || sensitivity < 0 || exposure_time_ns < 0) {
        return false;
    }
    if (sensitivity == 0 && exposure_time_ns == 0) {
        return sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AE_MODE,
                                           ACAMERA_CONTROL_AE_MODE_ON);
    }

    if (!sfos_camera2_metadata_has_i32(
            metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
            ACAMERA_SENSOR_SENSITIVITY) ||
            !sfos_camera2_metadata_has_i32(
                metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
                ACAMERA_SENSOR_EXPOSURE_TIME)) {
        return sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AE_MODE,
                                           ACAMERA_CONTROL_AE_MODE_ON);
    }

    if (sensitivity == 0) {
        sensitivity = 100;
    }
    if (exposure_time_ns == 0) {
        exposure_time_ns = 16666667;
    }

    bool ok = sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_MODE,
                                          ACAMERA_CONTROL_MODE_OFF) &&
              sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AE_MODE,
                                          ACAMERA_CONTROL_AE_MODE_OFF);
    if (sfos_camera2_metadata_has_i32(
            metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
            ACAMERA_CONTROL_CAPTURE_INTENT)) {
        ok = sfos_camera2_set_request_u8(request,
                                         ACAMERA_CONTROL_CAPTURE_INTENT,
                                         ACAMERA_CONTROL_CAPTURE_INTENT_MANUAL) &&
             ok;
    }
    int32_t sensitivity_range[2] = { sensitivity, sensitivity };
    if (sfos_camera2_copy_i32_array(
            metadata, ACAMERA_SENSOR_INFO_SENSITIVITY_RANGE,
            sensitivity_range, 2) >= 2) {
        sensitivity = sfos_camera2_clamp_i32(sensitivity, sensitivity_range[0],
                                             sensitivity_range[1]);
    }
    int64_t exposure_range[2] = { exposure_time_ns, exposure_time_ns };
    if (sfos_camera2_copy_i64_array(
            metadata, ACAMERA_SENSOR_INFO_EXPOSURE_TIME_RANGE,
            exposure_range, 2) >= 2) {
        if (exposure_time_ns < exposure_range[0]) {
            exposure_time_ns = exposure_range[0];
        } else if (exposure_time_ns > exposure_range[1]) {
            exposure_time_ns = exposure_range[1];
        }
    }

    int64_t frame_duration_ns = exposure_time_ns + 1000000;
    int64_t max_frame_duration_ns = sfos_camera2_first_i64(
        metadata, ACAMERA_SENSOR_INFO_MAX_FRAME_DURATION, 0);
    if (max_frame_duration_ns > 0 &&
            frame_duration_ns > max_frame_duration_ns) {
        frame_duration_ns = max_frame_duration_ns;
    }

    if (frame_duration_ns < exposure_time_ns) {
        frame_duration_ns = exposure_time_ns;
    }

    if (sfos_camera2_metadata_has_i32(
            metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
            ACAMERA_SENSOR_FRAME_DURATION)) {
        ok = sfos_camera2_set_request_i64(
                 request, ACAMERA_SENSOR_FRAME_DURATION,
                 frame_duration_ns) && ok;
    }

    return sfos_camera2_set_request_i32(
               request, ACAMERA_SENSOR_SENSITIVITY, sensitivity) &&
           sfos_camera2_set_request_i64(
               request, ACAMERA_SENSOR_EXPOSURE_TIME, exposure_time_ns) &&
           ok;
}

bool sfos_camera2_set_aperture(const ACameraMetadata *metadata,
                               ACaptureRequest *request,
                               int aperture)
{
    if (!metadata || !request || aperture < 0 || aperture > 255) {
        return false;
    }
    if (aperture == 0 ||
            !sfos_camera2_metadata_has_i32(
                metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
                ACAMERA_LENS_APERTURE)) {
        return true;
    }

    float apertures[32];
    uint32_t count = sfos_camera2_copy_float_array(
        metadata, ACAMERA_LENS_INFO_AVAILABLE_APERTURES,
        apertures, sizeof(apertures) / sizeof(apertures[0]));
    if (count == 0) {
        return true;
    }

    float wanted = (float)aperture / 10.0f;
    float selected = apertures[0];
    float best_delta = selected > wanted ? selected - wanted : wanted - selected;
    for (uint32_t index = 1; index < count; ++index) {
        float delta = apertures[index] > wanted
            ? apertures[index] - wanted : wanted - apertures[index];
        if (delta < best_delta) {
            selected = apertures[index];
            best_delta = delta;
        }
    }

    return sfos_camera2_set_request_float(
        request, ACAMERA_LENS_APERTURE, selected);
}

static uint8_t noise_reduction_mode_for_value(int noise_reduction)
{
    switch (noise_reduction) {
    case 0:
    case 1:
    case 2:
    case 3:
    case 4:
        return (uint8_t)noise_reduction;
    case 8:
        return 3;
    case 16:
        return 4;
    default:
        return ACAMERA_NOISE_REDUCTION_MODE_OFF;
    }
}

bool sfos_camera2_set_noise_reduction(const ACameraMetadata *metadata,
                                      ACaptureRequest *request,
                                      int noise_reduction)
{
    if (!metadata || !request || noise_reduction < 0) {
        return false;
    }

    uint8_t mode = noise_reduction_mode_for_value(noise_reduction);
    if (!sfos_camera2_metadata_has_i32(
            metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
            ACAMERA_NOISE_REDUCTION_MODE)) {
        return true;
    }

    if (!sfos_camera2_metadata_has_u8(
            metadata, ACAMERA_NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
            mode)) {
        if (mode == ACAMERA_NOISE_REDUCTION_MODE_OFF) {
            return true;
        }
        mode = sfos_camera2_metadata_has_u8(
            metadata, ACAMERA_NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
            ACAMERA_NOISE_REDUCTION_MODE_FAST)
            ? ACAMERA_NOISE_REDUCTION_MODE_FAST
            : ACAMERA_NOISE_REDUCTION_MODE_HIGH_QUALITY;
        if (!sfos_camera2_metadata_has_u8(
                metadata, ACAMERA_NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
                mode)) {
            return true;
        }
    }

    return sfos_camera2_set_request_u8(
        request, ACAMERA_NOISE_REDUCTION_MODE, mode);
}

bool sfos_camera2_set_zoom_ratio(const ACameraMetadata *metadata,
                                 ACaptureRequest *request,
                                 float zoom_ratio)
{
    float range[2] = { 1.0f, 1.0f };

    if (!metadata || !request || zoom_ratio != zoom_ratio ||
            !sfos_camera2_metadata_has_i32(
                metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
                ACAMERA_CONTROL_ZOOM_RATIO) ||
            sfos_camera2_copy_float_array(
                metadata, ACAMERA_CONTROL_ZOOM_RATIO_RANGE, range, 2) < 2 ||
            range[1] <= 1.0f) {
        return false;
    }

    if (zoom_ratio < range[0]) {
        zoom_ratio = range[0];
    } else if (zoom_ratio > range[1]) {
        zoom_ratio = range[1];
    }

    return ACaptureRequest_setEntry_float(
        request, ACAMERA_CONTROL_ZOOM_RATIO, 1, &zoom_ratio) == ACAMERA_OK;
}
