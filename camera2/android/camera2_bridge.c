/**
 * @file camera2_bridge.c
 * @brief Camera2 capability probe for the Sailfish Camera2 bridge.
 *
 * Runs inside the Android/libhybris side of the bridge. The probe enumerates
 * Camera2 devices, extracts static metadata, and returns a compact JSON
 * description that the Sailfish-side helper can print for the QML application.
 */
#include "camera2_bridge.h"
#include "camera2_common.h"

#include <camera/NdkCameraManager.h>
#include <camera/NdkCameraMetadata.h>
#include <camera/NdkCameraMetadataTags.h>
#include <media/NdkImage.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct json_writer {
    char *data;
    size_t capacity;
    size_t length;
    bool truncated;
};

static void json_appendf(struct json_writer *writer, const char *format, ...)
{
    if (writer->truncated || writer->length >= writer->capacity) {
        writer->truncated = true;
        return;
    }

    va_list args;
    va_start(args, format);
    int written = vsnprintf(writer->data + writer->length,
                            writer->capacity - writer->length,
                            format, args);
    va_end(args);

    if (written < 0 || (size_t)written >= writer->capacity - writer->length) {
        writer->length = writer->capacity - 1;
        writer->data[writer->length] = '\0';
        writer->truncated = true;
        return;
    }

    writer->length += (size_t)written;
}

static void json_string(struct json_writer *writer, const char *value)
{
    const unsigned char *cursor = (const unsigned char *)(value ? value : "");
    json_appendf(writer, "\"");
    while (*cursor && !writer->truncated) {
        switch (*cursor) {
        case '\"': json_appendf(writer, "\\\""); break;
        case '\\': json_appendf(writer, "\\\\"); break;
        case '\b': json_appendf(writer, "\\b"); break;
        case '\f': json_appendf(writer, "\\f"); break;
        case '\n': json_appendf(writer, "\\n"); break;
        case '\r': json_appendf(writer, "\\r"); break;
        case '\t': json_appendf(writer, "\\t"); break;
        default:
            if (*cursor < 0x20) {
                json_appendf(writer, "\\u%04x", (unsigned int)*cursor);
            } else {
                json_appendf(writer, "%c", *cursor);
            }
        }
        ++cursor;
    }
    json_appendf(writer, "\"");
}

/* https://developer.android.com/ndk/reference/group/camera#acamera_metadata_enum_acamera_info_supported_hardware_level */

static const char *hardware_level_name(int32_t level)
{
    switch (level) {
    case ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY: return "legacy";
    case ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED: return "limited";
    case ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_FULL: return "full";
    case ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_3: return "level_3";
#ifdef ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL
    case ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL: return "external";
#endif
    default: return "unknown";
    }
}

static const char *stream_format_name(int32_t format)
{
    switch (format) {
    case AIMAGE_FORMAT_RAW16: return "RAW16";
    case AIMAGE_FORMAT_RAW10: return "RAW10";
    case AIMAGE_FORMAT_RAW12: return "RAW12";
    case AIMAGE_FORMAT_RAW_PRIVATE: return "RAW_PRIVATE";
    case AIMAGE_FORMAT_JPEG: return "JPEG";
    case AIMAGE_FORMAT_YUV_420_888: return "YUV_420_888";
    default: return NULL;
    }
}

static const char *af_mode_name(uint8_t mode)
{
    switch (mode) {
    case ACAMERA_CONTROL_AF_MODE_OFF: return "off";
    case ACAMERA_CONTROL_AF_MODE_AUTO: return "auto";
    case ACAMERA_CONTROL_AF_MODE_MACRO: return "macro";
    case ACAMERA_CONTROL_AF_MODE_CONTINUOUS_VIDEO: return "continuous_video";
    case ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE:
        return "continuous_picture";
    case ACAMERA_CONTROL_AF_MODE_EDOF: return "edof";
    default: return "unknown";
    }
}

static const char *focus_calibration_name(int32_t calibration)
{
    switch (calibration) {
        //  acamera_metadata_enum_acamera_lens_info_focus_distance_calibration
        // Setting the lens to the same focus distance on separate occasions may
        // result in a different real focus distance, depending on factors such as the orientation
        // of the device, the age of the focusing mechanism, and the device temperature.
        
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_UNCALIBRATED:
        return "uncalibrated";
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_APPROXIMATE:
        return "approximate";
    case ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_CALIBRATED:
        return "calibrated";
    default: return "unknown";
    }
}

static const char *scene_mode_name(uint8_t mode)
{
    switch (mode) {
    case 1: return "face-priority";
    case ACAMERA_CONTROL_SCENE_MODE_ACTION: return "action";
    case ACAMERA_CONTROL_SCENE_MODE_PORTRAIT: return "portrait";
    case ACAMERA_CONTROL_SCENE_MODE_LANDSCAPE: return "landscape";
    case ACAMERA_CONTROL_SCENE_MODE_NIGHT: return "night";
    case ACAMERA_CONTROL_SCENE_MODE_NIGHT_PORTRAIT: return "night-portrait";
    case ACAMERA_CONTROL_SCENE_MODE_THEATRE: return "theatre";
    case ACAMERA_CONTROL_SCENE_MODE_BEACH: return "beach";
    case ACAMERA_CONTROL_SCENE_MODE_SNOW: return "snow";
    case ACAMERA_CONTROL_SCENE_MODE_SUNSET: return "sunset";
    case ACAMERA_CONTROL_SCENE_MODE_STEADYPHOTO: return "steady-photo";
    case ACAMERA_CONTROL_SCENE_MODE_FIREWORKS: return "fireworks";
    case ACAMERA_CONTROL_SCENE_MODE_SPORTS: return "sport";
    case ACAMERA_CONTROL_SCENE_MODE_PARTY: return "party";
    case ACAMERA_CONTROL_SCENE_MODE_CANDLELIGHT: return "candlelight";
    case ACAMERA_CONTROL_SCENE_MODE_BARCODE: return "barcode";
    case ACAMERA_CONTROL_SCENE_MODE_HDR: return "hdr";
    default: return "unknown";
    }
}

static const char *noise_reduction_mode_name(uint8_t mode)
{
    switch (mode) {
    case ACAMERA_NOISE_REDUCTION_MODE_OFF: return "off";
    case ACAMERA_NOISE_REDUCTION_MODE_FAST: return "fast";
    case ACAMERA_NOISE_REDUCTION_MODE_HIGH_QUALITY: return "high_quality";
    case 3: return "minimal";
    case 4: return "zero_shutter_lag";
    default: return "unknown";
    }
}

static void append_scene_capabilities(struct json_writer *writer,
                                      const ACameraMetadata *metadata)
{
    ACameraMetadata_const_entry entry;
    bool first = true;

    json_appendf(writer, "{\"modes\":[");
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_CONTROL_AVAILABLE_SCENE_MODES,
            &entry) == ACAMERA_OK) {
        for (uint32_t index = 0; index < entry.count; ++index) {
            uint8_t mode = entry.data.u8[index];
            json_appendf(writer, "%s{\"name\":", first ? "" : ",");
            json_string(writer, scene_mode_name(mode));
            json_appendf(writer, ",\"value\":%u}", (unsigned int)mode);
            first = false;
        }
    }
    json_appendf(writer, "]}");
}

static void append_noise_reduction_capabilities(struct json_writer *writer,
                                                const ACameraMetadata *metadata)
{
    ACameraMetadata_const_entry entry;
    bool first = true;
    bool request_supported = sfos_camera2_metadata_has_i32(
        metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        ACAMERA_NOISE_REDUCTION_MODE);

    json_appendf(writer, "{\"request_supported\":%s,\"modes\":[",
                 request_supported ? "true" : "false");
    if (ACameraMetadata_getConstEntry(
            metadata,
            ACAMERA_NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
            &entry) == ACAMERA_OK) {
        for (uint32_t index = 0; index < entry.count; ++index) {
            uint8_t mode = entry.data.u8[index];
            json_appendf(writer, "%s{\"name\":", first ? "" : ",");
            json_string(writer, noise_reduction_mode_name(mode));
            json_appendf(writer, ",\"value\":%u}", (unsigned int)mode);
            first = false;
        }
    }
    json_appendf(writer, "]}");
}

static void append_focus_capabilities(struct json_writer *writer,
                                      const ACameraMetadata *metadata)
{
    ACameraMetadata_const_entry entry;
    bool first = true;
    float minimum_distance = sfos_camera2_first_float(
        metadata, ACAMERA_LENS_INFO_MINIMUM_FOCUS_DISTANCE, 0.0f);
    int32_t calibration = sfos_camera2_first_u8(
        metadata, ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION, -1);

    json_appendf(writer, "{\"af_modes\":[");
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_CONTROL_AF_AVAILABLE_MODES,
            &entry) == ACAMERA_OK) {
        for (uint32_t index = 0; index < entry.count; ++index) {
            uint8_t mode = entry.data.u8[index];
            json_appendf(writer, "%s{\"name\":", first ? "" : ",");
            json_string(writer, af_mode_name(mode));
            json_appendf(writer, ",\"value\":%u}", (unsigned int)mode);
            first = false;
        }
    }
    json_appendf(writer,
                 "],\"minimum_focus_distance_diopters\":%.9g,"
                 "\"fixed_focus\":%s,\"focus_distance_calibration\":",
                 minimum_distance, minimum_distance > 0.0f ? "false" : "true");
    json_string(writer, focus_calibration_name(calibration));
    json_appendf(writer, ",\"focus_distance_calibration_value\":%d}",
                 calibration);
}

static void append_zoom_capabilities(struct json_writer *writer,
                                     const ACameraMetadata *metadata)
{
    float ratio_range[2] = { 1.0f, 1.0f };
    float max_digital_zoom = sfos_camera2_first_float(
        metadata, ACAMERA_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM, 1.0f);
    bool ratio_supported = sfos_camera2_metadata_has_i32(
        metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        ACAMERA_CONTROL_ZOOM_RATIO);

    sfos_camera2_copy_float_array(
        metadata, ACAMERA_CONTROL_ZOOM_RATIO_RANGE, ratio_range, 2);

    json_appendf(writer,
                 "{\"zoom_ratio_supported\":%s,"
                 "\"zoom_ratio_range\":[%.9g,%.9g],"
                 "\"max_digital_zoom\":%.9g}",
                 ratio_supported ? "true" : "false",
                 ratio_range[0], ratio_range[1], max_digital_zoom);
}

static void append_exposure_capabilities(struct json_writer *writer,
                                         const ACameraMetadata *metadata)
{
    int32_t sensitivity_range[2] = { 0, 0 };
    int64_t exposure_time_range[2] = { 0, 0 };
    bool iso_supported = sfos_camera2_metadata_has_i32(
        metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        ACAMERA_SENSOR_SENSITIVITY);
    bool shutter_supported = sfos_camera2_metadata_has_i32(
        metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        ACAMERA_SENSOR_EXPOSURE_TIME);

    sfos_camera2_copy_i32_array(
        metadata, ACAMERA_SENSOR_INFO_SENSITIVITY_RANGE,
        sensitivity_range, 2);
    sfos_camera2_copy_i64_array(
        metadata, ACAMERA_SENSOR_INFO_EXPOSURE_TIME_RANGE,
        exposure_time_range, 2);

    json_appendf(writer,
                 "{\"manual_supported\":%s,"
                 "\"iso_supported\":%s,\"iso_range\":[%d,%d],"
                 "\"shutter_supported\":%s,"
                 "\"shutter_ns_range\":[%lld,%lld]}",
                 iso_supported && shutter_supported ? "true" : "false",
                 iso_supported ? "true" : "false",
                 sensitivity_range[0], sensitivity_range[1],
                 shutter_supported ? "true" : "false",
                 (long long)exposure_time_range[0],
                 (long long)exposure_time_range[1]);
}

static void append_aperture_capabilities(struct json_writer *writer,
                                         const ACameraMetadata *metadata)
{
    ACameraMetadata_const_entry entry;
    bool first = true;
    bool request_supported = sfos_camera2_metadata_has_i32(
        metadata, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        ACAMERA_LENS_APERTURE);

    json_appendf(writer, "{\"request_supported\":%s,\"values\":[",
                 request_supported ? "true" : "false");
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_LENS_INFO_AVAILABLE_APERTURES,
            &entry) == ACAMERA_OK) {
        for (uint32_t index = 0; index < entry.count; ++index) {
            json_appendf(writer, "%s%.3g", first ? "" : ",",
                         entry.data.f[index]);
            first = false;
        }
    }
    json_appendf(writer, "]}");
}

static void append_outputs(struct json_writer *writer,
                           const ACameraMetadata *metadata,
                           int32_t wanted_format)
{
    ACameraMetadata_const_entry entry;
    bool first = true;

    json_appendf(writer, "[");
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
            &entry) == ACAMERA_OK) {
        for (uint32_t index = 0; index + 3 < entry.count; index += 4) {
            int32_t format = entry.data.i32[index];
            int32_t width = entry.data.i32[index + 1];
            int32_t height = entry.data.i32[index + 2];
            int32_t direction = entry.data.i32[index + 3];
            const char *name = stream_format_name(format);

            if (format != wanted_format || !name || direction !=
                    ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT) {
                continue;
            }

            json_appendf(writer, "%s{\"format\":", first ? "" : ",");
            json_string(writer, name);
            json_appendf(writer,
                         ",\"format_value\":%d,\"width\":%d,\"height\":%d}",
                         format, width, height);
            first = false;
        }
    }
    json_appendf(writer, "]");
}

/**
 * @brief Return the bridge ABI version string exported to Sailfish.
 */
const char *sfos_camera2_bridge_version(void)
{
    return "0.10.0";
}

/**
 * @brief Build a JSON capability report for all available Camera2 devices.
 */
int sfos_camera2_probe(char *out, size_t out_size)
{
    if (!out || out_size < 2) {
        return -1;
    }

    struct json_writer writer = {
        .data = out,
        .capacity = out_size,
        .length = 0,
        .truncated = false,
    };
    out[0] = '\0';

    ACameraManager *manager = ACameraManager_create();
    if (!manager) {
        snprintf(out, out_size,
                 "{\"status\":\"error\",\"stage\":\"manager_create\"}");
        return -2;
    }

    ACameraIdList *camera_ids = NULL;
    camera_status_t status =
        ACameraManager_getCameraIdList(manager, &camera_ids);
    if (status != ACAMERA_OK || !camera_ids) {
        snprintf(out, out_size,
                 "{\"status\":\"error\",\"stage\":\"camera_list\","
                 "\"camera_status\":%d}", status);
        ACameraManager_delete(manager);
        return -3;
    }

    json_appendf(&writer,
                 "{\"status\":\"ok\",\"bridge_version\":\"%s\","
                 "\"camera_count\":%d,\"cameras\":[",
                 sfos_camera2_bridge_version(), camera_ids->numCameras);

    for (int camera_index = 0;
         camera_index < camera_ids->numCameras;
         ++camera_index) {
        const char *camera_id = camera_ids->cameraIds[camera_index];
        ACameraMetadata *metadata = NULL;

        if (camera_index != 0) {
            json_appendf(&writer, ",");
        }
        json_appendf(&writer, "{\"id\":");
        json_string(&writer, camera_id);

        status = ACameraManager_getCameraCharacteristics(
            manager, camera_id, &metadata);
        if (status != ACAMERA_OK || !metadata) {
            json_appendf(&writer,
                         ",\"status\":\"error\",\"camera_status\":%d}",
                         status);
            continue;
        }

        bool raw_capability = sfos_camera2_metadata_has_u8(
            metadata, ACAMERA_REQUEST_AVAILABLE_CAPABILITIES,
            ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_RAW);
        int32_t hardware_level = sfos_camera2_first_u8(
            metadata, ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL, -1);

        json_appendf(&writer,
                     ",\"status\":\"ok\",\"raw_capability\":%s,"
                     "\"hardware_level\":",
                     raw_capability ? "true" : "false");
        json_string(&writer, hardware_level_name(hardware_level));
        json_appendf(&writer, ",\"hardware_level_value\":%d,\"focus\":",
                     hardware_level);
        append_focus_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"scene\":");
        append_scene_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"zoom\":");
        append_zoom_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"exposure\":");
        append_exposure_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"aperture\":");
        append_aperture_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"noise_reduction\":");
        append_noise_reduction_capabilities(&writer, metadata);
        json_appendf(&writer, ",\"raw_outputs\":");
        append_outputs(&writer, metadata, AIMAGE_FORMAT_RAW16);
        json_appendf(&writer, ",\"jpeg_outputs\":");
        append_outputs(&writer, metadata, AIMAGE_FORMAT_JPEG);
        json_appendf(&writer, ",\"preview_outputs\":");
        append_outputs(&writer, metadata, AIMAGE_FORMAT_YUV_420_888);
        json_appendf(&writer, "}");

        ACameraMetadata_free(metadata);
    }

    json_appendf(&writer, "]}");
    ACameraManager_deleteCameraIdList(camera_ids);
    ACameraManager_delete(manager);

    return writer.truncated ? -4 : 0;
}
