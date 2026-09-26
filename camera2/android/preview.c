/**
 * @file preview.c
 * @brief Long-running Camera2 preview helper.
 *
 * Streams RGB preview frames to stdout using RAWfish's SF2P framing protocol
 * and accepts control commands on stdin for focus, capture, and request
 * settings. It also supports warm JPEG and RAW capture from the active session.
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

#include <errno.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

enum preview_error {
    PREVIEW_INVALID_ARGUMENT = -30,
    PREVIEW_UNSUPPORTED_SIZE = -31,
    PREVIEW_MANAGER_ERROR = -32,
    PREVIEW_CHARACTERISTICS_ERROR = -33,
    PREVIEW_READER_ERROR = -34,
    PREVIEW_OPEN_ERROR = -35,
    PREVIEW_CONFIGURATION_ERROR = -36,
    PREVIEW_SUBMIT_ERROR = -37,
    PREVIEW_TIMEOUT = -38,
    PREVIEW_WRITE_ERROR = -39,
};

struct preview_rational {
    int32_t numerator;
    int32_t denominator;
};

struct preview_static_raw_metadata {
    int32_t cfa;
    int32_t white_level;
    int32_t black_level[4];
    int32_t active_array[4];
    float focal_length;
    struct preview_rational color1[9];
    uint32_t color1_count;
};

struct preview_result_raw_metadata {
    int64_t timestamp_ns;
    int64_t exposure_time_ns;
    int32_t sensitivity;
    float color_gains[4];
    struct preview_rational neutral_color_point[3];
    struct preview_rational color_transform[9];
    uint32_t color_gains_count;
    uint32_t neutral_count;
    uint32_t color_transform_count;
};

struct preview_raw_image_metadata {
    int32_t width;
    int32_t height;
    int32_t format;
    int32_t planes;
    int32_t pixel_stride;
    int32_t row_stride;
    int32_t data_length;
    int64_t timestamp_ns;
};

struct preview_context {
    struct sfos_camera2_status status;
    atomic_int frames_written;
    atomic_int jpeg_status;
    atomic_int raw_status;
    atomic_int raw_result_status;
    atomic_int raw_sequence_status;
    int width;
    int height;
    int frame_count;
    int output_fd;
    int control_fd;
    int jpeg_width;
    int jpeg_height;
    int jpeg_quality;
    int jpeg_orientation;
    int jpeg_data_length;
    int raw_width;
    int raw_height;
    pthread_mutex_t output_lock;
    float zoom_ratio;
    float focal_length;
    float focus_x;
    float focus_y;
    int focus_mode;
    float focus_distance;
    int exposure_compensation;
    int scene_mode;
    int color_temperature_kelvin;
    int color_tint;
    int32_t sensor_sensitivity;
    int64_t exposure_time_ns;
    atomic_int live_sensor_sensitivity;
    atomic_llong live_exposure_time_ns;
    int aperture;
    int noise_reduction;
    int vendor_awb_value_supported;
    int awb_off_supported;
    char jpeg_path[4096];
    char raw_path[4096];
    char raw_metadata_path[4096];
    char camera_id[64];
    int32_t active_array[4];
    int max_ae_regions;
    int max_af_regions;
    int64_t jpeg_command_ms;
    int64_t jpeg_submit_ms;
    int64_t jpeg_available_ms;
    int64_t jpeg_written_ms;
    int64_t raw_command_ms;
    int64_t raw_submit_ms;
    int64_t raw_available_ms;
    int64_t raw_written_ms;
    int64_t raw_metadata_written_ms;
    struct preview_static_raw_metadata raw_static;
    struct preview_result_raw_metadata raw_result;
    struct preview_raw_image_metadata raw_image;
};

enum preview_command_type {
    PREVIEW_COMMAND_NONE = 0,
    PREVIEW_COMMAND_FOCUS,
    PREVIEW_COMMAND_CAPTURE_JPEG,
    PREVIEW_COMMAND_CAPTURE_RAW,
    PREVIEW_COMMAND_ZOOM,
    PREVIEW_COMMAND_SETTINGS,
};

struct preview_command {
    enum preview_command_type type;
    float focus_x;
    float focus_y;
    float zoom_ratio;
    int focus_mode;
    float focus_distance;
    int exposure_compensation;
    int scene_mode;
    int color_temperature_kelvin;
    int color_tint;
    int32_t sensor_sensitivity;
    int64_t exposure_time_ns;
    int aperture;
    int noise_reduction;
    char path[4096];
    char metadata_path[4096];
};

struct preview_command_buffer {
    char data[8192];
    size_t length;
};

static bool preview_parse_scene_mode(const char *text, int *mode)
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
            return true;
        }
    }
    return false;
}

static const char *preview_scene_mode_name(int scene_mode)
{
    switch (scene_mode) {
    case SFOS_CAMERA2_SCENE_NONE: return "manual";
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
    default: return "unknown";
    }
}

static uint32_t preview_copy_rational(const ACameraMetadata *metadata,
                                      uint32_t tag,
                                      struct preview_rational *destination,
                                      uint32_t wanted)
{
    ACameraMetadata_const_entry entry;
    if (ACameraMetadata_getConstEntry(metadata, tag, &entry) != ACAMERA_OK) {
        return 0;
    }
    uint32_t count = entry.count < wanted ? entry.count : wanted;
    for (uint32_t index = 0; index < count; ++index) {
        destination[index].numerator = entry.data.r[index].numerator;
        destination[index].denominator = entry.data.r[index].denominator;
    }
    return count;
}

static void preview_copy_raw_static_metadata(
    struct preview_static_raw_metadata *destination,
    const ACameraMetadata *metadata)
{
    memset(destination, 0, sizeof(*destination));
    destination->cfa = sfos_camera2_first_u8(
        metadata, ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT, -1);
    destination->white_level = sfos_camera2_first_i32(
        metadata, ACAMERA_SENSOR_INFO_WHITE_LEVEL, -1);
    destination->focal_length = sfos_camera2_first_float(
        metadata, ACAMERA_LENS_INFO_AVAILABLE_FOCAL_LENGTHS, 0.0f);
    sfos_camera2_copy_i32_array(metadata, ACAMERA_SENSOR_BLACK_LEVEL_PATTERN,
                                destination->black_level, 4);
    sfos_camera2_copy_i32_array(metadata, ACAMERA_SENSOR_INFO_ACTIVE_ARRAY_SIZE,
                                destination->active_array, 4);
    destination->color1_count = preview_copy_rational(
        metadata, ACAMERA_SENSOR_COLOR_TRANSFORM1, destination->color1, 9);
}

static void preview_read_metering_info(const ACameraMetadata *metadata,
                                       struct preview_context *context)
{
    ACameraMetadata_const_entry entry;
    context->active_array[0] = 0;
    context->active_array[1] = 0;
    context->active_array[2] = context->width;
    context->active_array[3] = context->height;
    context->max_ae_regions = 0;
    context->max_af_regions = 0;

    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_SENSOR_INFO_ACTIVE_ARRAY_SIZE, &entry) ==
            ACAMERA_OK && entry.count >= 4) {
        context->active_array[0] = entry.data.i32[0];
        context->active_array[1] = entry.data.i32[1];
        context->active_array[2] = entry.data.i32[2];
        context->active_array[3] = entry.data.i32[3];
    }
    if (ACameraMetadata_getConstEntry(
            metadata, ACAMERA_CONTROL_MAX_REGIONS, &entry) == ACAMERA_OK &&
            entry.count >= 3) {
        context->max_ae_regions = entry.data.i32[0];
        context->max_af_regions = entry.data.i32[2];
    }
}

static uint8_t preview_af_mode(const struct preview_context *context,
                               int trigger)
{
    switch (context->focus_mode) {
    case SFOS_CAMERA2_FOCUS_CONTINUOUS:
        return trigger || context->focus_x >= 0.0f
                ? ACAMERA_CONTROL_AF_MODE_AUTO
                : ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
    case SFOS_CAMERA2_FOCUS_MANUAL:
    case SFOS_CAMERA2_FOCUS_INFINITY:
    case SFOS_CAMERA2_FOCUS_NONE:
        return ACAMERA_CONTROL_AF_MODE_OFF;
    case SFOS_CAMERA2_FOCUS_AUTO:
    default:
        return ACAMERA_CONTROL_AF_MODE_AUTO;
    }
}

static bool preview_focus_regions_enabled(const struct preview_context *context)
{
    return context->focus_mode == SFOS_CAMERA2_FOCUS_AUTO ||
           context->focus_mode == SFOS_CAMERA2_FOCUS_CONTINUOUS;
}

static void preview_configure_focus_request(ACaptureRequest *request,
                                            const struct preview_context *context,
                                            float focus_x, float focus_y,
                                            int trigger)
{
    if (!request || !context || !preview_focus_regions_enabled(context) ||
            focus_x < 0.0f || focus_y < 0.0f) {
        return;
    }

    uint8_t af_mode = preview_af_mode(context, trigger);
    uint8_t af_trigger = trigger ? ACAMERA_CONTROL_AF_TRIGGER_START
                                 : ACAMERA_CONTROL_AF_TRIGGER_IDLE;
    sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_MODE, af_mode);
    sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_TRIGGER,
                                af_trigger);

    int32_t left = context->active_array[0];
    int32_t top = context->active_array[1];
    int32_t right = context->active_array[2];
    int32_t bottom = context->active_array[3];
    int32_t width = right - left;
    int32_t height = bottom - top;
    if (width <= 0 || height <= 0) {
        return;
    }
    int32_t box = width < height ? width / 8 : height / 8;
    if (box < 64) {
        box = 64;
    }
    int32_t cx = left + (int32_t)(focus_x * width);
    int32_t cy = top + (int32_t)(focus_y * height);
    int32_t region[5] = {
        sfos_camera2_clamp_i32(cx - box / 2, left, right - 1),
        sfos_camera2_clamp_i32(cy - box / 2, top, bottom - 1),
        sfos_camera2_clamp_i32(cx + box / 2, left + 1, right),
        sfos_camera2_clamp_i32(cy + box / 2, top + 1, bottom),
        1000,
    };
    if (context->max_af_regions > 0) {
        ACaptureRequest_setEntry_i32(
            request, ACAMERA_CONTROL_AF_REGIONS, 5, region);
    }
    if (context->max_ae_regions > 0) {
        ACaptureRequest_setEntry_i32(
            request, ACAMERA_CONTROL_AE_REGIONS, 5, region);
    }
}

/**
 * Applies controls that must track live preview state.
 */
static void preview_configure_request(ACaptureRequest *request,
                                      const struct preview_context *context,
                                      const ACameraMetadata *metadata,
                                      int still)
{
    if (!request || !context) {
        return;
    }

    uint8_t af_mode = preview_af_mode(context, 0);
    if (metadata && !sfos_camera2_metadata_has_u8(
            metadata, ACAMERA_CONTROL_AF_AVAILABLE_MODES, af_mode)) {
        af_mode = ACAMERA_CONTROL_AF_MODE_OFF;
    }
    sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_MODE, af_mode);
    sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AF_TRIGGER,
                                ACAMERA_CONTROL_AF_TRIGGER_IDLE);
    sfos_camera2_set_request_i32(request,
                                 ACAMERA_CONTROL_AE_EXPOSURE_COMPENSATION,
                                 context->exposure_compensation);
    sfos_camera2_set_scene_mode(request, context->scene_mode);
    sfos_camera2_set_manual_sensor(metadata, request,
                                   context->sensor_sensitivity,
                                   context->exposure_time_ns);
    sfos_camera2_set_aperture(metadata, request, context->aperture);
    sfos_camera2_set_noise_reduction(metadata, request,
                                     context->noise_reduction);

    if (context->focus_mode == SFOS_CAMERA2_FOCUS_MANUAL ||
            context->focus_mode == SFOS_CAMERA2_FOCUS_INFINITY) {
        float distance = context->focus_mode == SFOS_CAMERA2_FOCUS_INFINITY
                ? 0.0f : context->focus_distance;
        sfos_camera2_set_request_float(request, ACAMERA_LENS_FOCUS_DISTANCE,
                                       distance);
    }

    if (preview_focus_regions_enabled(context) &&
            context->focus_x >= 0.0f && context->focus_y >= 0.0f) {
        preview_configure_focus_request(request, context, context->focus_x,
                                        context->focus_y, 0);
    }
    if (context->color_temperature_kelvin > 0) {
#ifdef ACAMERA_COLOR_CORRECTION_COLOR_TEMPERATURE
        sfos_camera2_set_request_i32(
            request, ACAMERA_COLOR_CORRECTION_COLOR_TEMPERATURE,
            context->color_temperature_kelvin);
#endif
        if (context->vendor_awb_value_supported &&
                context->awb_off_supported) {
            int32_t awb_value = sfos_camera2_clamp_i32(
                context->color_temperature_kelvin, 2000, 9000);
            sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AWB_MODE,
                                        ACAMERA_CONTROL_AWB_MODE_OFF);
            sfos_camera2_set_request_i32(request, MTK_3A_AWB_VALUE,
                                         awb_value);
        }
    } else {
        sfos_camera2_set_request_u8(request, ACAMERA_CONTROL_AWB_MODE,
                                    ACAMERA_CONTROL_AWB_MODE_AUTO);
    }
    if (context->color_tint != 0) {
#ifdef ACAMERA_COLOR_CORRECTION_COLOR_TINT
        sfos_camera2_set_request_i32(request, ACAMERA_COLOR_CORRECTION_COLOR_TINT,
                                     context->color_tint);
#endif
    } else {
#ifdef ACAMERA_COLOR_CORRECTION_COLOR_TINT
        sfos_camera2_set_request_i32(request, ACAMERA_COLOR_CORRECTION_COLOR_TINT,
                                     0);
#endif
    }
    if (still) {
        sfos_camera2_set_request_u8(request, ACAMERA_JPEG_QUALITY,
                                    (uint8_t)context->jpeg_quality);
        sfos_camera2_set_request_i32(request, ACAMERA_JPEG_ORIENTATION,
                                     context->jpeg_orientation);
    }
    sfos_camera2_set_zoom_ratio(metadata, request, context->zoom_ratio);
}

static bool preview_parse_command_line(const char *line,
                                       struct preview_command *command)
{
    if (!line || !command) {
        return false;
    }
    command->type = PREVIEW_COMMAND_NONE;

    float x = -1.0f;
    float y = -1.0f;
    if (!strcmp(line, "focus-reset")) {
        command->type = PREVIEW_COMMAND_FOCUS;
        command->focus_x = -1.0f;
        command->focus_y = -1.0f;
        return true;
    }
    if (sscanf(line, "focus %f %f", &x, &y) == 2 &&
            x >= 0.0f && x <= 1.0f && y >= 0.0f && y <= 1.0f) {
        command->type = PREVIEW_COMMAND_FOCUS;
        command->focus_x = x;
        command->focus_y = y;
        return true;
    }

    float zoom_ratio = 1.0f;
    if (sscanf(line, "zoom %f", &zoom_ratio) == 1 &&
            zoom_ratio >= 1.0f && zoom_ratio <= 100.0f) {
        command->type = PREVIEW_COMMAND_ZOOM;
        command->zoom_ratio = zoom_ratio;
        return true;
    }

    char focus_mode[32];
    float focus_distance = 0.0f;
    int exposure_compensation = 0;
    char scene_mode[32];
    int color_temperature_kelvin = 0;
    int color_tint = 0;
    int sensor_sensitivity = 0;
    long long exposure_time_ns = 0;
    int aperture = 0;
    int noise_reduction = 0;
    if (sscanf(line, "settings %31s %f %d %31s %d %d %d %lld %d %d %f",
               focus_mode, &focus_distance, &exposure_compensation, scene_mode,
               &color_temperature_kelvin, &color_tint, &sensor_sensitivity,
               &exposure_time_ns, &aperture, &noise_reduction,
               &zoom_ratio) == 11 &&
            focus_distance >= 0.0f &&
            color_temperature_kelvin >= 0 &&
            sensor_sensitivity >= 0 &&
            exposure_time_ns >= 0 &&
            aperture >= 0 && aperture <= 255 &&
            noise_reduction >= 0 &&
            zoom_ratio >= 1.0f && zoom_ratio <= 100.0f) {
        if (!strcmp(focus_mode, "none")) {
            command->focus_mode = SFOS_CAMERA2_FOCUS_NONE;
        } else if (!strcmp(focus_mode, "auto")) {
            command->focus_mode = SFOS_CAMERA2_FOCUS_AUTO;
        } else if (!strcmp(focus_mode, "continuous")) {
            command->focus_mode = SFOS_CAMERA2_FOCUS_CONTINUOUS;
        } else if (!strcmp(focus_mode, "manual")) {
            command->focus_mode = SFOS_CAMERA2_FOCUS_MANUAL;
        } else if (!strcmp(focus_mode, "infinity")) {
            command->focus_mode = SFOS_CAMERA2_FOCUS_INFINITY;
        } else {
            return false;
        }
        if (!preview_parse_scene_mode(scene_mode, &command->scene_mode)) {
            return false;
        }
        command->type = PREVIEW_COMMAND_SETTINGS;
        command->focus_distance = focus_distance;
        command->exposure_compensation = exposure_compensation;
        command->color_temperature_kelvin = color_temperature_kelvin;
        command->color_tint = color_tint;
        command->sensor_sensitivity = sensor_sensitivity;
        command->exposure_time_ns = exposure_time_ns;
        command->aperture = aperture;
        command->noise_reduction = noise_reduction;
        command->zoom_ratio = zoom_ratio;
        return true;
    }

    char path[sizeof(command->path)];
    if (sscanf(line, "capture-jpeg %4095s", path) == 1 && path[0]) {
        command->type = PREVIEW_COMMAND_CAPTURE_JPEG;
        snprintf(command->path, sizeof(command->path), "%s", path);
        return true;
    }
    char metadata_path[sizeof(command->metadata_path)];
    if (sscanf(line, "capture-raw %4095s %4095s", path, metadata_path) == 2 &&
            path[0] && metadata_path[0]) {
        command->type = PREVIEW_COMMAND_CAPTURE_RAW;
        snprintf(command->path, sizeof(command->path), "%s", path);
        snprintf(command->metadata_path, sizeof(command->metadata_path), "%s",
                 metadata_path);
        return true;
    }
    return false;
}

static void preview_read_command_data(int fd,
                                      struct preview_command_buffer *buffer)
{
    if (fd < 0 || !buffer) {
        return;
    }

    while (buffer->length < sizeof(buffer->data) - 1) {
        ssize_t bytes = read(fd, buffer->data + buffer->length,
                             sizeof(buffer->data) - buffer->length - 1);
        if (bytes > 0) {
            buffer->length += (size_t)bytes;
            buffer->data[buffer->length] = '\0';
            continue;
        }
        if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return;
        }
        return;
    }

    buffer->length = 0;
    buffer->data[0] = '\0';
}

static bool preview_pop_command(struct preview_command_buffer *buffer,
                                struct preview_command *command)
{
    if (!buffer || !command) {
        return false;
    }

    for (;;) {
        char *newline = memchr(buffer->data, '\n', buffer->length);
        if (!newline) {
            return false;
        }

        size_t line_length = (size_t)(newline - buffer->data);
        char line[4096];
        if (line_length >= sizeof(line)) {
            line_length = sizeof(line) - 1;
        }
        memcpy(line, buffer->data, line_length);
        line[line_length] = '\0';

        size_t consumed = (size_t)(newline - buffer->data) + 1;
        memmove(buffer->data, buffer->data + consumed,
                buffer->length - consumed);
        buffer->length -= consumed;
        buffer->data[buffer->length] = '\0';

        if (preview_parse_command_line(line, command)) {
            return true;
        }
    }
}

static unsigned char preview_clip(int value)
{
    if (value < 0) {
        return 0;
    }
    return (unsigned char)(value > 255 ? 255 : value);
}

static void preview_write_le32(unsigned char *target, uint32_t value)
{
    target[0] = (unsigned char)(value & 0xff);
    target[1] = (unsigned char)((value >> 8) & 0xff);
    target[2] = (unsigned char)((value >> 16) & 0xff);
    target[3] = (unsigned char)((value >> 24) & 0xff);
}

/**
 * @brief Samples one YUV420 chroma plane with a small bilinear filter.
 *
 * Camera2 YUV420 chroma planes are half-resolution. Using a single nearest
 * chroma sample for every 2x2 luma block makes colored edges shimmer when the
 * app scales the preview again, so odd luma rows/columns blend toward the next
 * chroma sample while edges clamp to the valid plane area.
 */
static int preview_sample_chroma(const uint8_t *plane, int length,
                                 int row_stride, int pixel_stride,
                                 int chroma_width, int chroma_height,
                                 int x, int y, int *value)
{
    if (!plane || !value || length <= 0 || row_stride <= 0 ||
            pixel_stride <= 0 || chroma_width <= 0 || chroma_height <= 0) {
        return -1;
    }

    int x0 = x / 2;
    int y0 = y / 2;
    int x1 = x0 + 1 < chroma_width ? x0 + 1 : x0;
    int y1 = y0 + 1 < chroma_height ? y0 + 1 : y0;
    int fx = x & 1;
    int fy = y & 1;
    int w00 = (2 - fx) * (2 - fy);
    int w10 = fx * (2 - fy);
    int w01 = (2 - fx) * fy;
    int w11 = fx * fy;
    int i00 = y0 * row_stride + x0 * pixel_stride;
    int i10 = y0 * row_stride + x1 * pixel_stride;
    int i01 = y1 * row_stride + x0 * pixel_stride;
    int i11 = y1 * row_stride + x1 * pixel_stride;

    if (i00 < 0 || i10 < 0 || i01 < 0 || i11 < 0 ||
            i00 >= length || i10 >= length ||
            i01 >= length || i11 >= length) {
        return -1;
    }

    *value = (plane[i00] * w00 + plane[i10] * w10 +
              plane[i01] * w01 + plane[i11] * w11 + 2) / 4;
    return 0;
}

/**
 * @brief Converts one Camera2 YUV420 preview image to framed RGB888 output.
 *
 * The Sailfish side consumes the unchanged SF2P protocol: a 16-byte header
 * followed by tightly-packed RGB888 pixels. Only chroma reconstruction happens
 * here; final preview scaling remains in the Qt scene graph.
 */
static int preview_write_rgb_frame(struct preview_context *context,
                                   AImage *image)
{
    uint8_t *plane_y = NULL;
    uint8_t *plane_u = NULL;
    uint8_t *plane_v = NULL;
    int len_y = 0;
    int len_u = 0;
    int len_v = 0;
    int row_y = 0;
    int row_u = 0;
    int row_v = 0;
    int pixel_y = 0;
    int pixel_u = 0;
    int pixel_v = 0;
    int width = 0;
    int height = 0;
    int format = 0;
    int planes = 0;

    if (AImage_getWidth(image, &width) != AMEDIA_OK ||
            AImage_getHeight(image, &height) != AMEDIA_OK ||
            AImage_getFormat(image, &format) != AMEDIA_OK ||
            AImage_getNumberOfPlanes(image, &planes) != AMEDIA_OK ||
            width != context->width || height != context->height ||
            format != AIMAGE_FORMAT_YUV_420_888 || planes < 3 ||
            AImage_getPlaneData(image, 0, &plane_y, &len_y) != AMEDIA_OK ||
            AImage_getPlaneData(image, 1, &plane_u, &len_u) != AMEDIA_OK ||
            AImage_getPlaneData(image, 2, &plane_v, &len_v) != AMEDIA_OK ||
            AImage_getPlaneRowStride(image, 0, &row_y) != AMEDIA_OK ||
            AImage_getPlaneRowStride(image, 1, &row_u) != AMEDIA_OK ||
            AImage_getPlaneRowStride(image, 2, &row_v) != AMEDIA_OK ||
            AImage_getPlanePixelStride(image, 0, &pixel_y) != AMEDIA_OK ||
            AImage_getPlanePixelStride(image, 1, &pixel_u) != AMEDIA_OK ||
            AImage_getPlanePixelStride(image, 2, &pixel_v) != AMEDIA_OK ||
            !plane_y || !plane_u || !plane_v || len_y <= 0 ||
            len_u <= 0 || len_v <= 0) {
        return -1;
    }

    const size_t frame_size = (size_t)width * (size_t)height * 3;
    unsigned char *frame = malloc(frame_size);
    if (!frame) {
        return -1;
    }

    int result = 0;
    const int chroma_width = (width + 1) / 2;
    const int chroma_height = (height + 1) / 2;
    for (int y = 0; y < height; ++y) {
        unsigned char *row = frame + (size_t)y * (size_t)width * 3;
        for (int x = 0; x < width; ++x) {
            int y_index = y * row_y + x * pixel_y;
            int sampled_u = 0;
            int sampled_v = 0;
            if (y_index < 0 || y_index >= len_y ||
                    preview_sample_chroma(plane_u, len_u, row_u, pixel_u,
                                          chroma_width, chroma_height,
                                          x, y, &sampled_u) != 0 ||
                    preview_sample_chroma(plane_v, len_v, row_v, pixel_v,
                                          chroma_width, chroma_height,
                                          x, y, &sampled_v) != 0) {
                result = -1;
                goto done;
            }
            int yy = plane_y[y_index];
            int uu = sampled_u - 128;
            int vv = sampled_v - 128;
            row[x * 3] = preview_clip(yy + ((91881 * vv) >> 16));
            row[x * 3 + 1] = preview_clip(
                yy - ((22554 * uu + 46802 * vv) >> 16));
            row[x * 3 + 2] = preview_clip(yy + ((116130 * uu) >> 16));
        }
    }

    unsigned char header[16] = { 'S', 'F', '2', 'P' };
    preview_write_le32(header + 4, (uint32_t)width);
    preview_write_le32(header + 8, (uint32_t)height);
    preview_write_le32(header + 12, (uint32_t)frame_size);
    pthread_mutex_lock(&context->output_lock);
    if (sfos_camera2_write_all(context->output_fd, header,
                               sizeof(header)) != 0 ||
            sfos_camera2_write_all(context->output_fd, frame,
                                   frame_size) != 0) {
        result = -1;
    }
    pthread_mutex_unlock(&context->output_lock);
done:
    free(frame);
    return result;
}

static void preview_write_metadata(struct preview_context *context,
                                   int32_t sensor_sensitivity,
                                   int64_t exposure_time_ns)
{
    if (!context || context->output_fd < 0) {
        return;
    }

    int32_t previous_sensitivity = atomic_exchange_explicit(
        &context->live_sensor_sensitivity, sensor_sensitivity,
        memory_order_acq_rel);
    long long previous_exposure = atomic_exchange_explicit(
        &context->live_exposure_time_ns, (long long)exposure_time_ns,
        memory_order_acq_rel);
    if (previous_sensitivity == sensor_sensitivity &&
            previous_exposure == (long long)exposure_time_ns) {
        return;
    }

    char payload[128];
    int payload_size = snprintf(payload, sizeof(payload),
                                "focal=%.3f iso=%d shutter=%lld\n",
                                context->focal_length, sensor_sensitivity,
                                (long long)exposure_time_ns);
    if (payload_size <= 0 || payload_size >= (int)sizeof(payload)) {
        return;
    }

    unsigned char header[8] = { 'S', 'F', '2', 'M' };
    preview_write_le32(header + 4, (uint32_t)payload_size);

    pthread_mutex_lock(&context->output_lock);
    sfos_camera2_write_all(context->output_fd, header, sizeof(header));
    sfos_camera2_write_all(context->output_fd, payload, (size_t)payload_size);
    pthread_mutex_unlock(&context->output_lock);
}

static void preview_write_capture_result(struct preview_context *context,
                                         const char *status,
                                         const char *path,
                                         int code)
{
    if (!context || context->output_fd < 0 || !status) {
        return;
    }

    char payload[8192];
    int payload_size = snprintf(
        payload, sizeof(payload),
        "capture-status=%s path=%s code=%d width=%d height=%d bytes=%d "
        "submit_ms=%lld available_ms=%lld written_ms=%lld\n",
        status, path ? path : "", code, context->jpeg_width,
        context->jpeg_height, context->jpeg_data_length,
        context->jpeg_submit_ms > 0
            ? (long long)(context->jpeg_submit_ms - context->jpeg_command_ms)
            : -1LL,
        context->jpeg_available_ms > 0
            ? (long long)(context->jpeg_available_ms -
                          context->jpeg_command_ms)
            : -1LL,
        context->jpeg_written_ms > 0
            ? (long long)(context->jpeg_written_ms - context->jpeg_command_ms)
            : -1LL);
    if (payload_size <= 0 || payload_size >= (int)sizeof(payload)) {
        return;
    }

    unsigned char header[8] = { 'S', 'F', '2', 'M' };
    preview_write_le32(header + 4, (uint32_t)payload_size);

    pthread_mutex_lock(&context->output_lock);
    sfos_camera2_write_all(context->output_fd, header, sizeof(header));
    sfos_camera2_write_all(context->output_fd, payload, (size_t)payload_size);
    pthread_mutex_unlock(&context->output_lock);
}

static void preview_device_disconnected(void *opaque, ACameraDevice *device)
{
    (void)device;
    struct preview_context *context = opaque;
    atomic_store_explicit(&context->status.device_error, -1,
                          memory_order_release);
}

static void preview_device_error(void *opaque, ACameraDevice *device,
                                 int error)
{
    (void)device;
    struct preview_context *context = opaque;
    atomic_store_explicit(&context->status.device_error,
                          error > 0 ? error : -1, memory_order_release);
}

static void preview_image_available(void *opaque, AImageReader *reader)
{
    struct preview_context *context = opaque;
    if (atomic_load_explicit(&context->frames_written,
                             memory_order_acquire) >= context->frame_count ||
            atomic_load_explicit(&context->status.image_status,
                                 memory_order_acquire) < 0) {
        return;
    }

    AImage *image = NULL;
    media_status_t status = AImageReader_acquireLatestImage(reader, &image);
    atomic_store_explicit(&context->status.last_media_status, status,
                          memory_order_release);
    if (status != AMEDIA_OK || !image) {
        return;
    }
    if (preview_write_rgb_frame(context, image) == 0) {
        atomic_fetch_add_explicit(&context->frames_written, 1,
                                  memory_order_release);
    } else {
        atomic_store_explicit(&context->status.image_status, -1,
                              memory_order_release);
    }
    AImage_delete(image);
}

static void preview_capture_completed(void *opaque,
                                      ACameraCaptureSession *session,
                                      ACaptureRequest *request,
                                      const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    struct preview_context *context = opaque;
    if (!context || !result) {
        return;
    }

    int32_t sensitivity = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_SENSITIVITY, 0);
    int64_t exposure_time = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_EXPOSURE_TIME, 0);
    if (sensitivity > 0 || exposure_time > 0) {
        preview_write_metadata(context, sensitivity, exposure_time);
    }
}

static void preview_jpeg_capture_completed(void *opaque,
                                           ACameraCaptureSession *session,
                                           ACaptureRequest *request,
                                           const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    struct preview_context *context = opaque;
    if (!context || !result) {
        return;
    }

    int32_t actual_sensitivity = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_SENSITIVITY, -1);
    int64_t actual_exposure_time = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_EXPOSURE_TIME, -1);
    int64_t actual_frame_duration = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_FRAME_DURATION, -1);
    fprintf(stderr,
            "capture-exposure warm-jpeg requested_iso=%d "
            "requested_shutter=%lld actual_iso=%d actual_shutter=%lld "
            "actual_frame=%lld\n",
            context->sensor_sensitivity,
            (long long)context->exposure_time_ns,
            actual_sensitivity,
            (long long)actual_exposure_time,
            (long long)actual_frame_duration);
}

static void preview_jpeg_image_available(void *opaque, AImageReader *reader)
{
    struct preview_context *context = opaque;
    if (atomic_load_explicit(&context->jpeg_status,
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
    if (AImage_getWidth(image, &width) != AMEDIA_OK ||
            AImage_getHeight(image, &height) != AMEDIA_OK ||
            AImage_getFormat(image, &format) != AMEDIA_OK ||
            AImage_getPlaneData(image, 0, &data, &data_length) != AMEDIA_OK ||
            width != context->jpeg_width ||
            height != context->jpeg_height ||
            format != AIMAGE_FORMAT_JPEG || !data || data_length <= 0) {
        atomic_store_explicit(&context->jpeg_status, -1,
                              memory_order_release);
        preview_write_capture_result(context, "error", context->jpeg_path,
                                     PREVIEW_WRITE_ERROR);
    } else {
        context->jpeg_available_ms = sfos_camera2_now_ms();
        fprintf(stderr, "capture-timing bridge warm-jpeg available t=%lld\n",
                (long long)(context->jpeg_available_ms -
                            context->jpeg_command_ms));
        if (sfos_camera2_write_file(context->jpeg_path, data,
                                    (size_t)data_length) != 0) {
            atomic_store_explicit(&context->jpeg_status, -1,
                                  memory_order_release);
            preview_write_capture_result(context, "error",
                                         context->jpeg_path,
                                         PREVIEW_WRITE_ERROR);
        } else {
            context->jpeg_written_ms = sfos_camera2_now_ms();
            fprintf(stderr, "capture-timing bridge warm-jpeg written t=%lld\n",
                    (long long)(context->jpeg_written_ms -
                                context->jpeg_command_ms));
            context->jpeg_data_length = data_length;
            atomic_store_explicit(&context->jpeg_status, 1,
                                  memory_order_release);
            preview_write_capture_result(context, "ok", context->jpeg_path, 0);
        }
    }
    AImage_delete(image);
}

static const char *preview_cfa_name(int32_t cfa)
{
    switch (cfa) {
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_RGGB: return "RGGB";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GRBG: return "GRBG";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GBRG: return "GBRG";
    case ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_BGGR: return "BGGR";
    default: return "UNKNOWN";
    }
}

static void preview_print_json_string(FILE *file, const char *value)
{
    fputc('"', file);
    const unsigned char *cursor = (const unsigned char *)(value ? value : "");
    while (*cursor) {
        if (*cursor == '"' || *cursor == '\\') {
            fputc('\\', file);
            fputc(*cursor, file);
        } else if (*cursor < 0x20) {
            fprintf(file, "\\u%04x", (unsigned int)*cursor);
        } else {
            fputc(*cursor, file);
        }
        ++cursor;
    }
    fputc('"', file);
}

static void preview_print_float_array(FILE *file, const float *values,
                                      uint32_t count)
{
    fputc('[', file);
    for (uint32_t index = 0; index < count; ++index) {
        fprintf(file, "%s%.9g", index ? "," : "", values[index]);
    }
    fputc(']', file);
}

static void preview_print_rational_array(
    FILE *file, const struct preview_rational *values, uint32_t count)
{
    fputc('[', file);
    for (uint32_t index = 0; index < count; ++index) {
        fprintf(file, "%s[%d,%d]", index ? "," : "",
                values[index].numerator, values[index].denominator);
    }
    fputc(']', file);
}

static bool preview_write_raw_metadata(const char *camera_id,
                                       struct preview_context *context)
{
    FILE *file = fopen(context->raw_metadata_path, "w");
    if (!file) {
        return false;
    }
    const struct preview_raw_image_metadata *image = &context->raw_image;
    const struct preview_static_raw_metadata *static_data =
        &context->raw_static;
    const struct preview_result_raw_metadata *result = &context->raw_result;

    fputs("{\n  \"camera_id\":", file);
    preview_print_json_string(file, camera_id);
    fputs(",\n  \"raw_path\":", file);
    preview_print_json_string(file, context->raw_path);
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
            "\n  \"black_level_pattern\":[%d,%d,%d,%d],"
            "\n  \"active_array\":[%d,%d,%d,%d],"
            "\n  \"focal_length_mm\":%.9g,"
            "\n  \"focus_mode_requested\":\"continuous\","
            "\n  \"scene_mode_requested\":\"%s\","
            "\n  \"sensor_sensitivity_requested\":%d,"
            "\n  \"exposure_time_requested_ns\":%lld,"
            "\n  \"aperture_requested\":%d,"
            "\n  \"noise_reduction_requested\":%d,"
            "\n  \"color_temperature_requested_kelvin\":%d,"
            "\n  \"color_tint_requested\":%d,"
            "\n  \"timing_ms\":{\"capture_submit\":%lld,"
            "\"image_available\":%lld,\"raw_file_written\":%lld,"
            "\"metadata_written\":%lld,\"total\":%lld}",
            image->format, image->width, image->height, image->planes,
            image->pixel_stride, image->row_stride, image->data_length,
            (long long)image->timestamp_ns,
            (long long)result->timestamp_ns,
            (long long)result->exposure_time_ns, result->sensitivity,
            preview_cfa_name(static_data->cfa), static_data->cfa,
            static_data->white_level,
            static_data->black_level[0], static_data->black_level[1],
            static_data->black_level[2], static_data->black_level[3],
            static_data->active_array[0], static_data->active_array[1],
            static_data->active_array[2], static_data->active_array[3],
            static_data->focal_length,
            preview_scene_mode_name(context->scene_mode),
            context->sensor_sensitivity,
            (long long)context->exposure_time_ns, context->aperture,
            context->noise_reduction, context->color_temperature_kelvin,
            context->color_tint,
            (long long)(context->raw_submit_ms - context->raw_command_ms),
            (long long)(context->raw_available_ms - context->raw_command_ms),
            (long long)(context->raw_written_ms - context->raw_command_ms),
            (long long)(context->raw_metadata_written_ms -
                        context->raw_command_ms),
            (long long)(sfos_camera2_now_ms() - context->raw_command_ms));
    fputs(",\n  \"color_correction_gains\":", file);
    preview_print_float_array(file, result->color_gains,
                              result->color_gains_count);
    fputs(",\n  \"neutral_color_point\":", file);
    preview_print_rational_array(file, result->neutral_color_point,
                                 result->neutral_count);
    fputs(",\n  \"capture_color_transform\":", file);
    preview_print_rational_array(file, result->color_transform,
                                 result->color_transform_count);
    fputs(",\n  \"color_transform1\":", file);
    preview_print_rational_array(file, static_data->color1,
                                 static_data->color1_count);
    fputs("\n}\n", file);

    bool success = ferror(file) == 0 && fflush(file) == 0;
    if (fclose(file) != 0) {
        success = false;
    }
    if (!success) {
        unlink(context->raw_metadata_path);
    }
    return success;
}

static void preview_raw_image_available(void *opaque, AImageReader *reader)
{
    struct preview_context *context = opaque;
    if (atomic_load_explicit(&context->raw_status,
                             memory_order_acquire) != 0) {
        return;
    }

    AImage *image = NULL;
    media_status_t status = AImageReader_acquireNextImage(reader, &image);
    atomic_store_explicit(&context->status.last_media_status, status,
                          memory_order_release);
    if (status != AMEDIA_OK || !image) {
        atomic_store_explicit(&context->raw_status, -1, memory_order_release);
        preview_write_capture_result(context, "error", context->raw_path,
                                     PREVIEW_READER_ERROR);
        return;
    }

    uint8_t *data = NULL;
    int data_length = 0;
    int raw_status = 1;
    context->raw_available_ms = sfos_camera2_now_ms();
    if (AImage_getWidth(image, &context->raw_image.width) != AMEDIA_OK ||
            AImage_getHeight(image, &context->raw_image.height) != AMEDIA_OK ||
            AImage_getFormat(image, &context->raw_image.format) != AMEDIA_OK ||
            AImage_getNumberOfPlanes(image, &context->raw_image.planes) !=
                AMEDIA_OK ||
            AImage_getTimestamp(image, &context->raw_image.timestamp_ns) !=
                AMEDIA_OK ||
            context->raw_image.format != AIMAGE_FORMAT_RAW16 ||
            context->raw_image.planes != 1 ||
            AImage_getPlanePixelStride(
                image, 0, &context->raw_image.pixel_stride) != AMEDIA_OK ||
            AImage_getPlaneRowStride(
                image, 0, &context->raw_image.row_stride) != AMEDIA_OK ||
            AImage_getPlaneData(image, 0, &data, &data_length) != AMEDIA_OK ||
            !data || data_length <= 0) {
        raw_status = -2;
    }
    context->raw_image.data_length = data_length;
    if (raw_status > 0 &&
            sfos_camera2_write_file(context->raw_path, data,
                                    (size_t)data_length) != 0) {
        raw_status = -3;
    }
    if (raw_status > 0) {
        context->raw_written_ms = sfos_camera2_now_ms();
    } else {
        unlink(context->raw_path);
    }
    AImage_delete(image);

    int64_t metadata_deadline = sfos_camera2_now_ms() + 500;
    while (raw_status > 0 &&
            atomic_load_explicit(&context->raw_result_status,
                                 memory_order_acquire) == 0 &&
            sfos_camera2_now_ms() < metadata_deadline) {
        sfos_camera2_sleep_10_ms();
    }
    if (raw_status > 0 &&
            atomic_load_explicit(&context->raw_result_status,
                                 memory_order_acquire) <= 0) {
        raw_status = -5;
    }
    if (raw_status > 0) {
        context->raw_metadata_written_ms = sfos_camera2_now_ms();
        if (!preview_write_raw_metadata(context->camera_id, context)) {
            raw_status = -4;
        }
    }
    atomic_store_explicit(&context->raw_status, raw_status,
                          memory_order_release);
    preview_write_capture_result(context, raw_status > 0 ? "ok" : "error",
                                 context->raw_metadata_path,
                                 raw_status > 0 ? 0 : PREVIEW_WRITE_ERROR);
}

static void preview_raw_capture_completed(void *opaque,
                                          ACameraCaptureSession *session,
                                          ACaptureRequest *request,
                                          const ACameraMetadata *result)
{
    (void)session;
    (void)request;
    struct preview_context *context = opaque;
    struct preview_result_raw_metadata *destination = &context->raw_result;
    memset(destination, 0, sizeof(*destination));
    destination->timestamp_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_TIMESTAMP, -1);
    destination->exposure_time_ns = sfos_camera2_first_i64(
        result, ACAMERA_SENSOR_EXPOSURE_TIME, -1);
    destination->sensitivity = sfos_camera2_first_i32(
        result, ACAMERA_SENSOR_SENSITIVITY, -1);
    fprintf(stderr,
            "capture-exposure warm-raw requested_iso=%d "
            "requested_shutter=%lld actual_iso=%d actual_shutter=%lld "
            "actual_frame=%lld\n",
            context->sensor_sensitivity,
            (long long)context->exposure_time_ns,
            destination->sensitivity,
            (long long)destination->exposure_time_ns,
            (long long)sfos_camera2_first_i64(
                result, ACAMERA_SENSOR_FRAME_DURATION, -1));
    destination->color_gains_count = sfos_camera2_copy_float_array(
        result, ACAMERA_COLOR_CORRECTION_GAINS,
        destination->color_gains, 4);
    destination->neutral_count = preview_copy_rational(
        result, ACAMERA_SENSOR_NEUTRAL_COLOR_POINT,
        destination->neutral_color_point, 3);
    destination->color_transform_count = preview_copy_rational(
        result, ACAMERA_COLOR_CORRECTION_TRANSFORM,
        destination->color_transform, 9);
    atomic_store_explicit(&context->raw_result_status, 1,
                          memory_order_release);
}

static void preview_status_json(char *out, size_t out_size, bool success,
                                const char *stage, int code,
                                const struct preview_context *context)
{
    if (!out || out_size == 0) {
        return;
    }
    snprintf(out, out_size,
             "{\"status\":\"%s\",\"stage\":\"%s\",\"code\":%d,"
             "\"preview\":{\"width\":%d,\"height\":%d,"
             "\"frames_requested\":%d,\"frames_written\":%d},"
             "\"jpeg\":{\"width\":%d,\"height\":%d,\"data_length\":%d},"
             "\"diagnostics\":{\"camera_status\":%d,"
             "\"media_status\":%d,\"device_error\":%d,"
             "\"image_status\":%d,\"jpeg_status\":%d}}",
             success ? "ok" : "error", stage ? stage : "unknown", code,
             context ? context->width : 0, context ? context->height : 0,
             context ? context->frame_count : 0,
             context ? atomic_load_explicit(&context->frames_written,
                                            memory_order_acquire) : 0,
             context ? context->jpeg_width : 0,
             context ? context->jpeg_height : 0,
             context ? context->jpeg_data_length : 0,
             context ? atomic_load_explicit(&context->status.last_camera_status,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.last_media_status,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.device_error,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->status.image_status,
                                            memory_order_acquire) : 0,
             context ? atomic_load_explicit(&context->jpeg_status,
                                            memory_order_acquire) : 0);
}

/**
 * @brief Run the live preview loop and service warm capture commands.
 *
 * This is the long-lived bridge entry point used by the QML preview item. It
 * writes framed RGB preview buffers and listens for focus/settings/capture
 * commands on a control file descriptor.
 */
SFOS_CAMERA2_EXPORT int sfos_camera2_preview_ppm(
    const char *camera_id, int width, int height, int frame_count,
    int timeout_ms, int output_fd, int control_fd, int jpeg_width,
    int jpeg_height, int jpeg_quality, int jpeg_orientation_degrees,
    int raw_width, int raw_height,
    float zoom_ratio, float focus_x, float focus_y,
    char *out, size_t out_size)
{
    int result_code = 0;
    const char *stage = "complete";
    ACameraManager *manager = NULL;
    ACameraMetadata *characteristics = NULL;
    ACameraDevice *device = NULL;
    AImageReader *reader = NULL;
    AImageReader *jpeg_reader = NULL;
    AImageReader *raw_reader = NULL;
    ANativeWindow *window = NULL;
    ANativeWindow *jpeg_window = NULL;
    ANativeWindow *raw_window = NULL;
    ACameraOutputTarget *target = NULL;
    ACameraOutputTarget *jpeg_target = NULL;
    ACameraOutputTarget *raw_target = NULL;
    ACaptureRequest *request = NULL;
    ACaptureRequest *focus_request = NULL;
    ACaptureRequest *jpeg_request = NULL;
    ACaptureRequest *raw_request = NULL;
    ACaptureSessionOutput *output = NULL;
    ACaptureSessionOutput *jpeg_output = NULL;
    ACaptureSessionOutput *raw_output = NULL;
    ACaptureSessionOutputContainer *container = NULL;
    ACameraCaptureSession *session = NULL;
    bool output_lock_ready = false;

    struct preview_context context;
    memset(&context, 0, sizeof(context));
    sfos_camera2_status_init(&context.status);
    atomic_init(&context.frames_written, 0);
    atomic_init(&context.jpeg_status, -1);
    atomic_init(&context.raw_status, -1);
    atomic_init(&context.raw_result_status, -1);
    atomic_init(&context.raw_sequence_status, -1);
    atomic_init(&context.live_sensor_sensitivity, -1);
    atomic_init(&context.live_exposure_time_ns, -1);
    context.width = width;
    context.height = height;
    context.frame_count = frame_count;
    context.output_fd = output_fd;
    context.control_fd = control_fd;
    context.jpeg_width = jpeg_width;
    context.jpeg_height = jpeg_height;
    context.jpeg_quality = jpeg_quality;
    context.jpeg_orientation = jpeg_orientation_degrees;
    context.raw_width = raw_width;
    context.raw_height = raw_height;
    snprintf(context.camera_id, sizeof(context.camera_id), "%s",
             camera_id ? camera_id : "");
    context.zoom_ratio = zoom_ratio < 1.0f ? 1.0f : zoom_ratio;
    context.focus_x = focus_x;
    context.focus_y = focus_y;
    context.focus_mode = SFOS_CAMERA2_FOCUS_CONTINUOUS;
    context.focus_distance = 0.0f;
    context.exposure_compensation = 0;
    context.scene_mode = SFOS_CAMERA2_SCENE_NONE;
    context.color_temperature_kelvin = 0;
    context.color_tint = 0;
    context.sensor_sensitivity = 0;
    context.exposure_time_ns = 0;
    context.aperture = 0;
    context.noise_reduction = SFOS_CAMERA2_NOISE_REDUCTION_NONE;

		    if (!camera_id || !*camera_id || width <= 0 || height <= 0 ||
		            frame_count <= 0 || frame_count > 10000 ||
		            timeout_ms < 1000 || output_fd < 0 ||
		            jpeg_quality < 1 || jpeg_quality > 100 ||
                    raw_width < 0 || raw_height < 0 ||
                    (raw_width == 0 && raw_height > 0) ||
                    (raw_width > 0 && raw_height == 0) ||
                    !out || out_size < 2) {
	        preview_status_json(out, out_size, false, "arguments",
	                            PREVIEW_INVALID_ARGUMENT, &context);
	        return PREVIEW_INVALID_ARGUMENT;
	    }

    if (pthread_mutex_init(&context.output_lock, NULL) != 0) {
        result_code = PREVIEW_WRITE_ERROR;
        stage = "output_lock";
        goto cleanup;
    }
    output_lock_ready = true;

    manager = ACameraManager_create();
    if (!manager) {
        result_code = PREVIEW_MANAGER_ERROR;
        stage = "manager_create";
        goto cleanup;
    }
    camera_status_t camera_status = ACameraManager_getCameraCharacteristics(
        manager, camera_id, &characteristics);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !characteristics) {
        result_code = PREVIEW_CHARACTERISTICS_ERROR;
        stage = "characteristics";
        goto cleanup;
    }
    if (!sfos_camera2_has_output_size(
            characteristics, AIMAGE_FORMAT_YUV_420_888, width, height)) {
        result_code = PREVIEW_UNSUPPORTED_SIZE;
        stage = "preview_size";
        goto cleanup;
    }
    if (jpeg_width > 0 && jpeg_height > 0 &&
            !sfos_camera2_has_output_size(
                characteristics, AIMAGE_FORMAT_JPEG, jpeg_width,
                jpeg_height)) {
        context.jpeg_width = 0;
        context.jpeg_height = 0;
    }
    if (raw_width > 0 && raw_height > 0 &&
            !sfos_camera2_has_output_size(
                characteristics, AIMAGE_FORMAT_RAW16, raw_width,
                raw_height)) {
        context.raw_width = 0;
        context.raw_height = 0;
    }
		    preview_read_metering_info(characteristics, &context);
    preview_copy_raw_static_metadata(&context.raw_static, characteristics);
    context.focal_length = sfos_camera2_first_float(
        characteristics, ACAMERA_LENS_INFO_AVAILABLE_FOCAL_LENGTHS, 0.0f);
	    context.vendor_awb_value_supported = sfos_camera2_metadata_has_i32(
        characteristics, ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS,
        (int32_t)MTK_3A_AWB_VALUE);
    context.awb_off_supported = sfos_camera2_metadata_has_u8(
        characteristics, ACAMERA_CONTROL_AWB_AVAILABLE_MODES,
        ACAMERA_CONTROL_AWB_MODE_OFF);

    media_status_t media_status = AImageReader_new(
        width, height, AIMAGE_FORMAT_YUV_420_888, 4, &reader);
    atomic_store_explicit(&context.status.last_media_status, media_status,
                          memory_order_release);
    if (media_status != AMEDIA_OK || !reader) {
        result_code = PREVIEW_READER_ERROR;
        stage = "reader_create";
        goto cleanup;
    }
    AImageReader_ImageListener listener = {
        .context = &context,
        .onImageAvailable = preview_image_available,
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
        result_code = PREVIEW_READER_ERROR;
        stage = "reader_configure";
        goto cleanup;
    }

    if (context.jpeg_width > 0 && context.jpeg_height > 0) {
        media_status = AImageReader_new(
            context.jpeg_width, context.jpeg_height, AIMAGE_FORMAT_JPEG, 2,
            &jpeg_reader);
        atomic_store_explicit(&context.status.last_media_status,
                              media_status, memory_order_release);
        if (media_status == AMEDIA_OK && jpeg_reader) {
            AImageReader_ImageListener jpeg_listener = {
                .context = &context,
                .onImageAvailable = preview_jpeg_image_available,
            };
            media_status = AImageReader_setImageListener(jpeg_reader,
                                                         &jpeg_listener);
            if (media_status == AMEDIA_OK) {
                media_status = AImageReader_getWindow(jpeg_reader,
                                                      &jpeg_window);
            }
        }
        atomic_store_explicit(&context.status.last_media_status,
                              media_status, memory_order_release);
        if (media_status != AMEDIA_OK || !jpeg_window) {
            context.jpeg_width = 0;
            context.jpeg_height = 0;
        } else {
            atomic_store_explicit(&context.jpeg_status, 1,
                                  memory_order_release);
        }
    }

    if (context.raw_width > 0 && context.raw_height > 0) {
        media_status = AImageReader_new(
            context.raw_width, context.raw_height, AIMAGE_FORMAT_RAW16, 2,
            &raw_reader);
        atomic_store_explicit(&context.status.last_media_status,
                              media_status, memory_order_release);
        if (media_status == AMEDIA_OK && raw_reader) {
            AImageReader_ImageListener raw_listener = {
                .context = &context,
                .onImageAvailable = preview_raw_image_available,
            };
            media_status = AImageReader_setImageListener(raw_reader,
                                                         &raw_listener);
            if (media_status == AMEDIA_OK) {
                media_status = AImageReader_getWindow(raw_reader, &raw_window);
            }
        }
        atomic_store_explicit(&context.status.last_media_status,
                              media_status, memory_order_release);
        if (media_status != AMEDIA_OK || !raw_window) {
            context.raw_width = 0;
            context.raw_height = 0;
        } else {
            atomic_store_explicit(&context.raw_status, 1,
                                  memory_order_release);
        }
    }

    ACameraDevice_StateCallbacks device_callbacks = {
        .context = &context,
        .onDisconnected = preview_device_disconnected,
        .onError = preview_device_error,
    };
    camera_status = ACameraManager_openCamera(
        manager, camera_id, &device_callbacks, &device);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !device) {
        result_code = PREVIEW_OPEN_ERROR;
        stage = "camera_open";
        goto cleanup;
    }

    if (ACameraOutputTarget_create(window, &target) != ACAMERA_OK ||
            ACameraDevice_createCaptureRequest(device, TEMPLATE_PREVIEW,
                                               &request) != ACAMERA_OK ||
            ACaptureRequest_addTarget(request, target) != ACAMERA_OK ||
            ACameraDevice_createCaptureRequest(device, TEMPLATE_PREVIEW,
                                               &focus_request) != ACAMERA_OK ||
            ACaptureRequest_addTarget(focus_request, target) != ACAMERA_OK ||
            ACaptureSessionOutput_create(window, &output) != ACAMERA_OK ||
            ACaptureSessionOutputContainer_create(&container) != ACAMERA_OK ||
            ACaptureSessionOutputContainer_add(container, output) !=
                ACAMERA_OK) {
        result_code = PREVIEW_CONFIGURATION_ERROR;
        stage = "configure";
        goto cleanup;
    }
    if (jpeg_window &&
            (ACameraOutputTarget_create(jpeg_window, &jpeg_target) !=
                 ACAMERA_OK ||
             ACaptureSessionOutput_create(jpeg_window, &jpeg_output) !=
                 ACAMERA_OK ||
             ACaptureSessionOutputContainer_add(container, jpeg_output) !=
                 ACAMERA_OK ||
             ACameraDevice_createCaptureRequest(device, TEMPLATE_STILL_CAPTURE,
                                                &jpeg_request) != ACAMERA_OK ||
             ACaptureRequest_addTarget(jpeg_request, jpeg_target) !=
                 ACAMERA_OK)) {
        result_code = PREVIEW_CONFIGURATION_ERROR;
        stage = "jpeg_configure";
        goto cleanup;
    }
    if (raw_window &&
            (ACameraOutputTarget_create(raw_window, &raw_target) !=
                 ACAMERA_OK ||
             ACaptureSessionOutput_create(raw_window, &raw_output) !=
                 ACAMERA_OK ||
             ACaptureSessionOutputContainer_add(container, raw_output) !=
                 ACAMERA_OK ||
             ACameraDevice_createCaptureRequest(device, TEMPLATE_STILL_CAPTURE,
                                                &raw_request) != ACAMERA_OK ||
             ACaptureRequest_addTarget(raw_request, raw_target) !=
                 ACAMERA_OK)) {
        result_code = PREVIEW_CONFIGURATION_ERROR;
        stage = "raw_configure";
        goto cleanup;
    }
    preview_configure_request(request, &context, characteristics, 0);
    preview_configure_request(focus_request, &context, characteristics, 0);
    preview_configure_focus_request(focus_request, &context, context.focus_x,
                                    context.focus_y, 1);
    if (jpeg_request) {
        preview_configure_request(jpeg_request, &context, characteristics, 1);
    }
    if (raw_request) {
        preview_configure_request(raw_request, &context, characteristics, 1);
    }

    ACameraCaptureSession_stateCallbacks session_callbacks = {
        .context = &context,
        .onClosed = NULL,
        .onReady = NULL,
        .onActive = NULL,
    };
    ACameraCaptureSession_captureCallbacks preview_callbacks = {
        .context = &context,
        .onCaptureStarted = NULL,
        .onCaptureProgressed = NULL,
        .onCaptureCompleted = preview_capture_completed,
        .onCaptureFailed = NULL,
        .onCaptureSequenceCompleted = NULL,
        .onCaptureSequenceAborted = NULL,
        .onCaptureBufferLost = NULL,
    };
    camera_status = ACameraDevice_createCaptureSession(
        device, container, &session_callbacks, &session);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK || !session) {
        result_code = PREVIEW_CONFIGURATION_ERROR;
        stage = "session_create";
        goto cleanup;
    }

    ACaptureRequest *requests[] = { request };
    camera_status = ACameraCaptureSession_setRepeatingRequest(
        session, &preview_callbacks, 1, requests, NULL);
    atomic_store_explicit(&context.status.last_camera_status, camera_status,
                          memory_order_release);
    if (camera_status != ACAMERA_OK) {
        result_code = PREVIEW_SUBMIT_ERROR;
        stage = "repeat_submit";
        goto cleanup;
    }
    if (focus_x >= 0.0f && focus_y >= 0.0f) {
        ACaptureRequest *focus_requests[] = { focus_request };
        ACameraCaptureSession_capture(session, NULL, 1, focus_requests, NULL);
    }
    if (control_fd >= 0) {
        fcntl(control_fd, F_SETFL, fcntl(control_fd, F_GETFL, 0) | O_NONBLOCK);
    }

    struct preview_command_buffer command_buffer;
    memset(&command_buffer, 0, sizeof(command_buffer));
    int64_t deadline = sfos_camera2_now_ms() + timeout_ms;
    while (sfos_camera2_now_ms() < deadline &&
            atomic_load_explicit(&context.status.device_error,
                                 memory_order_acquire) == 0 &&
            atomic_load_explicit(&context.status.image_status,
                                 memory_order_acquire) >= 0) {
        struct preview_command command;
        preview_read_command_data(control_fd, &command_buffer);
        while (preview_pop_command(&command_buffer, &command)) {
            if (command.type == PREVIEW_COMMAND_FOCUS) {
                context.focus_x = command.focus_x;
                context.focus_y = command.focus_y;
                preview_configure_request(request, &context, characteristics,
                                          0);
                preview_configure_request(focus_request, &context,
                                          characteristics, 0);
                preview_configure_focus_request(
                    focus_request, &context, context.focus_x, context.focus_y,
                    1);
                if (jpeg_request) {
                    preview_configure_request(jpeg_request, &context,
                                              characteristics, 1);
                }
                if (raw_request) {
                    preview_configure_request(raw_request, &context,
                                              characteristics, 1);
                }
                ACaptureRequest *requests[] = { request };
                ACameraCaptureSession_setRepeatingRequest(
                    session, &preview_callbacks, 1, requests, NULL);
                ACaptureRequest *focus_requests[] = { focus_request };
                ACameraCaptureSession_capture(session, NULL, 1, focus_requests,
                                              NULL);
            } else if (command.type == PREVIEW_COMMAND_ZOOM) {
                context.zoom_ratio = command.zoom_ratio;
                preview_configure_request(request, &context, characteristics,
                                          0);
                preview_configure_request(focus_request, &context,
                                          characteristics, 0);
                if (jpeg_request) {
                    preview_configure_request(jpeg_request, &context,
                                              characteristics, 1);
                }
                if (raw_request) {
                    preview_configure_request(raw_request, &context,
                                              characteristics, 1);
                }
                ACaptureRequest *requests[] = { request };
                ACameraCaptureSession_setRepeatingRequest(
                    session, &preview_callbacks, 1, requests, NULL);
            } else if (command.type == PREVIEW_COMMAND_SETTINGS) {
                context.focus_mode = command.focus_mode;
                context.focus_distance = command.focus_distance;
                context.exposure_compensation = command.exposure_compensation;
                context.scene_mode =
                    sfos_camera2_scene_mode_supported(characteristics,
                                                      command.scene_mode)
                    ? command.scene_mode : SFOS_CAMERA2_SCENE_NONE;
                context.color_temperature_kelvin =
                    command.color_temperature_kelvin;
                context.color_tint = command.color_tint;
                context.sensor_sensitivity = command.sensor_sensitivity;
                context.exposure_time_ns = command.exposure_time_ns;
                context.aperture = command.aperture;
                context.noise_reduction = command.noise_reduction;
                context.zoom_ratio = command.zoom_ratio;
                preview_configure_request(request, &context, characteristics,
                                          0);
                preview_configure_request(focus_request, &context,
                                          characteristics, 0);
                if (jpeg_request) {
                    preview_configure_request(jpeg_request, &context,
                                              characteristics, 1);
                }
                if (raw_request) {
                    preview_configure_request(raw_request, &context,
                                              characteristics, 1);
                }
                ACaptureRequest *requests[] = { request };
                ACameraCaptureSession_setRepeatingRequest(
                    session, &preview_callbacks, 1, requests, NULL);
            } else if (command.type == PREVIEW_COMMAND_CAPTURE_JPEG &&
                    jpeg_request) {
                snprintf(context.jpeg_path, sizeof(context.jpeg_path), "%s",
                         command.path);
                context.jpeg_data_length = 0;
                context.jpeg_command_ms = sfos_camera2_now_ms();
                context.jpeg_submit_ms = 0;
                context.jpeg_available_ms = 0;
                context.jpeg_written_ms = 0;
                fprintf(stderr, "capture-timing bridge warm-jpeg command\n");
                fprintf(stderr,
                        "capture-exposure warm-jpeg submit requested_iso=%d "
                        "requested_shutter=%lld\n",
                        context.sensor_sensitivity,
                        (long long)context.exposure_time_ns);
                atomic_store_explicit(&context.jpeg_status, 0,
                                      memory_order_release);
                ACameraCaptureSession_captureCallbacks jpeg_callbacks = {
                    .context = &context,
                    .onCaptureStarted = NULL,
                    .onCaptureProgressed = NULL,
                    .onCaptureCompleted = preview_jpeg_capture_completed,
                    .onCaptureFailed = NULL,
                    .onCaptureSequenceCompleted = NULL,
                    .onCaptureSequenceAborted = NULL,
                    .onCaptureBufferLost = NULL,
                };
                ACaptureRequest *jpeg_requests[] = { jpeg_request };
                camera_status_t jpeg_status = ACameraCaptureSession_capture(
                    session, &jpeg_callbacks, 1, jpeg_requests, NULL);
                atomic_store_explicit(&context.status.last_camera_status,
                                      jpeg_status, memory_order_release);
                if (jpeg_status == ACAMERA_OK) {
                    context.jpeg_submit_ms = sfos_camera2_now_ms();
                    fprintf(stderr,
                            "capture-timing bridge warm-jpeg submitted t=%lld\n",
                            (long long)(context.jpeg_submit_ms -
                                        context.jpeg_command_ms));
                } else {
                    atomic_store_explicit(&context.jpeg_status, -1,
                                          memory_order_release);
                    preview_write_capture_result(&context, "error",
                                                 context.jpeg_path,
                                                 jpeg_status);
                    fprintf(stderr,
                            "capture-timing bridge warm-jpeg submit-failed status=%d\n",
                            jpeg_status);
                }
            } else if (command.type == PREVIEW_COMMAND_CAPTURE_RAW &&
                    raw_request) {
                snprintf(context.raw_path, sizeof(context.raw_path), "%s",
                         command.path);
                snprintf(context.raw_metadata_path,
                         sizeof(context.raw_metadata_path), "%s",
                         command.metadata_path);
                memset(&context.raw_image, 0, sizeof(context.raw_image));
                memset(&context.raw_result, 0, sizeof(context.raw_result));
                context.raw_command_ms = sfos_camera2_now_ms();
                context.raw_submit_ms = 0;
                context.raw_available_ms = 0;
                context.raw_written_ms = 0;
                context.raw_metadata_written_ms = 0;
                atomic_store_explicit(&context.raw_status, 0,
                                      memory_order_release);
                atomic_store_explicit(&context.raw_result_status, 0,
                                      memory_order_release);
                atomic_store_explicit(&context.raw_sequence_status, 0,
                                      memory_order_release);
                ACaptureRequest *raw_requests[] = { raw_request };
                ACameraCaptureSession_captureCallbacks raw_callbacks = {
                    .context = &context,
                    .onCaptureStarted = NULL,
                    .onCaptureProgressed = NULL,
                    .onCaptureCompleted = preview_raw_capture_completed,
                    .onCaptureFailed = NULL,
                    .onCaptureSequenceCompleted = NULL,
                    .onCaptureSequenceAborted = NULL,
                    .onCaptureBufferLost = NULL,
                };
                camera_status_t raw_status = ACameraCaptureSession_capture(
                    session, &raw_callbacks, 1, raw_requests, NULL);
                atomic_store_explicit(&context.status.last_camera_status,
                                      raw_status, memory_order_release);
                if (raw_status == ACAMERA_OK) {
                    context.raw_submit_ms = sfos_camera2_now_ms();
                } else {
                    atomic_store_explicit(&context.raw_status, -1,
                                          memory_order_release);
                    preview_write_capture_result(&context, "error",
                                                 context.raw_metadata_path,
                                                 raw_status);
                }
            }
        }
        sfos_camera2_sleep_10_ms();
    }
    if (atomic_load_explicit(&context.status.image_status,
                             memory_order_acquire) < 0) {
        result_code = PREVIEW_WRITE_ERROR;
        stage = "frame_write";
        goto cleanup;
    }
    if (atomic_load_explicit(&context.frames_written,
                             memory_order_acquire) <= 0) {
        result_code = PREVIEW_TIMEOUT;
        stage = "preview_wait";
        goto cleanup;
    }

cleanup:
    preview_status_json(out, out_size, result_code == 0, stage, result_code,
                        &context);
    if (session) {
        ACameraCaptureSession_stopRepeating(session);
        ACameraCaptureSession_close(session);
    }
    if (target) {
        ACameraOutputTarget_free(target);
    }
    if (jpeg_target) {
        ACameraOutputTarget_free(jpeg_target);
    }
    if (raw_target) {
        ACameraOutputTarget_free(raw_target);
    }
    if (output) {
        ACaptureSessionOutput_free(output);
    }
    if (jpeg_output) {
        ACaptureSessionOutput_free(jpeg_output);
    }
    if (raw_output) {
        ACaptureSessionOutput_free(raw_output);
    }
    if (container) {
        ACaptureSessionOutputContainer_free(container);
    }
    if (request) {
        ACaptureRequest_free(request);
    }
    if (focus_request) {
        ACaptureRequest_free(focus_request);
    }
    if (jpeg_request) {
        ACaptureRequest_free(jpeg_request);
    }
    if (raw_request) {
        ACaptureRequest_free(raw_request);
    }
    if (reader) {
        AImageReader_setImageListener(reader, NULL);
        AImageReader_delete(reader);
    }
    if (jpeg_reader) {
        AImageReader_setImageListener(jpeg_reader, NULL);
        AImageReader_delete(jpeg_reader);
    }
    if (raw_reader) {
        AImageReader_setImageListener(raw_reader, NULL);
        AImageReader_delete(raw_reader);
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
    if (output_lock_ready) {
        pthread_mutex_destroy(&context.output_lock);
    }
    return result_code;
}
