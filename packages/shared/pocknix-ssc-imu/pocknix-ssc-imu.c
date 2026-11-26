/*
 * pocknix-ssc-imu: bridges Qualcomm ADSP QMI SSC gyroscope and accelerometer
 * streams over kernel AF_QIPCRTR directly into a virtual /dev/uinput motion
 * sensor device for InputPlumber, with zero external library dependencies.
 *
 * License: GPL-2.0-or-later
 */
#define _GNU_SOURCE
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <linux/input.h>
#include <linux/qrtr.h>
#include <linux/uinput.h>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif

#define QMI_SERVICE_SSC                 400u
#define QMI_FLAG_REQUEST                0x00u
#define QMI_FLAG_INDICATION             0x04u
#define QMI_SSC_MSG_CONTROL             0x0020u
#define QMI_SSC_MSG_REPORT_SMALL        0x0021u
#define QMI_SSC_MSG_REPORT_LARGE        0x0022u
#define QMI_SSC_REPORT_TYPE_LARGE       0x01u

#define SNS_SUID_MSGID_REQ              512u
#define SNS_SUID_MSGID_EVENT            768u
#define SNS_STD_SENSOR_MSGID_CONFIG     513u
#define SNS_STD_SENSOR_MSGID_EVENT      1025u
#define SNS_CLIENT_MSGID_DISABLE_REQ    10u

#define SUID_LOOKUP_LOW                 0xababababababababULL
#define SUID_LOOKUP_HIGH                0xababababababababULL

typedef struct {
    int idx[3];
    float sign[3];
} AxisMap;

typedef struct {
    int qrtr_fd;
    int uinput_fd;
    bool ssc_found;
    uint32_t ssc_node;
    uint32_t ssc_port;
    uint16_t txn_id;

    float target_rate;
    float accel_rate;
    int gyro_emit_div;
    float gyro_scale;
    float gyro_deadzone;
    float accel_deadband;
    bool test_mode;
    bool use_dither;
    bool bias_cal;
    AxisMap gyro_map;
    AxisMap accel_map;

    bool has_gyro_uid;
    bool has_accel_uid;
    uint64_t gyro_low, gyro_high;
    uint64_t accel_low, accel_high;
    bool gyro_opened;
    bool accel_opened;

    double gyro_accum[3];
    int gyro_accum_n;
    double gyro_err[3];
    int last_gyro_q[3];
    bool last_gyro_valid;

    float last_accel_mps2[3];
    int last_accel_q[3];
    bool last_accel_valid;
    uint64_t last_accel_sync_ms;
    bool accel_sync_restore;

    double gyro_bias[3];
    double bias_init_sum[3];
    int bias_init_n;
    bool bias_ready;
    int still_ticks;

    unsigned long gyro_count;
    unsigned long accel_count;
} AppState;

static AppState g_app;
static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000L);
}

static uint16_t rd_le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t rd_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t rd_le64(const uint8_t *p) {
    return (uint64_t)rd_le32(p) | ((uint64_t)rd_le32(p + 4) << 32);
}

static void wr_le16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xffu);
    p[1] = (uint8_t)((v >> 8) & 0xffu);
}

typedef struct {
    uint8_t data[512];
    size_t len;
} PbBuf;

static void pb_varint(PbBuf *b, uint64_t v) {
    do {
        uint8_t byte = (uint8_t)(v & 0x7fu);
        v >>= 7;
        if (v) byte |= 0x80u;
        if (b->len < sizeof(b->data)) b->data[b->len++] = byte;
    } while (v);
}

static void pb_tag(PbBuf *b, uint32_t field, uint32_t wire) {
    pb_varint(b, ((uint64_t)field << 3) | wire);
}

static void pb_fixed32(PbBuf *b, uint32_t v) {
    for (int i = 0; i < 4 && b->len < sizeof(b->data); i++)
        b->data[b->len++] = (uint8_t)((v >> (8 * i)) & 0xffu);
}

static void pb_fixed64(PbBuf *b, uint64_t v) {
    for (int i = 0; i < 8 && b->len < sizeof(b->data); i++)
        b->data[b->len++] = (uint8_t)((v >> (8 * i)) & 0xffu);
}

static void pb_bytes(PbBuf *b, uint32_t field, const uint8_t *p, size_t n) {
    pb_tag(b, field, 2);
    pb_varint(b, n);
    if (b->len + n <= sizeof(b->data)) {
        memcpy(b->data + b->len, p, n);
        b->len += n;
    }
}

static void pb_build_client_req(PbBuf *out, uint64_t low, uint64_t high,
                                uint32_t msg_id, const uint8_t *payload, size_t payload_len) {
    PbBuf uid = {0}, cfg = {0}, body = {0};
    pb_tag(&uid, 1, 1); pb_fixed64(&uid, low);
    pb_tag(&uid, 2, 1); pb_fixed64(&uid, high);

    /* processor=APPS(1), delivery=NO_WAKEUP(1) so idle sensors do not wake s2idle. */
    pb_tag(&cfg, 1, 0); pb_varint(&cfg, 1);
    pb_tag(&cfg, 2, 0); pb_varint(&cfg, 1);

    if (payload && payload_len > 0)
        pb_bytes(&body, 2, payload, payload_len);

    out->len = 0;
    pb_bytes(out, 1, uid.data, uid.len);
    pb_tag(out, 2, 5); pb_fixed32(out, msg_id);
    pb_bytes(out, 3, cfg.data, cfg.len);
    pb_bytes(out, 4, body.data, body.len);
}

static bool pb_read_varint(const uint8_t *p, size_t n, size_t *off, uint64_t *val) {
    uint64_t r = 0;
    int shift = 0;
    while (*off < n && shift < 64) {
        uint8_t c = p[(*off)++];
        r |= (uint64_t)(c & 0x7fu) << shift;
        if (!(c & 0x80u)) { *val = r; return true; }
        shift += 7;
    }
    return false;
}

static bool pb_skip(const uint8_t *p, size_t n, size_t *off, uint32_t wire) {
    uint64_t v = 0;
    switch (wire) {
    case 0: return pb_read_varint(p, n, off, &v);
    case 1: if (*off + 8 > n) return false; *off += 8; return true;
    case 2: if (!pb_read_varint(p, n, off, &v) || *off + v > n) return false; *off += v; return true;
    case 5: if (*off + 4 > n) return false; *off += 4; return true;
    default: return false;
    }
}

static bool pb_parse_uid(const uint8_t *p, size_t n, uint64_t *low, uint64_t *high) {
    size_t off = 0;
    bool got1 = false, got2 = false;
    while (off < n) {
        uint64_t tag;
        if (!pb_read_varint(p, n, &off, &tag)) return false;
        uint32_t f = (uint32_t)(tag >> 3), w = (uint32_t)(tag & 7);
        if (f == 1 && w == 1 && off + 8 <= n) { *low = rd_le64(p + off); off += 8; got1 = true; }
        else if (f == 2 && w == 1 && off + 8 <= n) { *high = rd_le64(p + off); off += 8; got2 = true; }
        else if (!pb_skip(p, n, &off, w)) return false;
    }
    return got1 && got2;
}

static int pb_parse_vec3(const uint8_t *p, size_t n, float out[3]) {
    size_t off = 0;
    int cnt = 0;
    while (off < n) {
        uint64_t tag;
        if (!pb_read_varint(p, n, &off, &tag)) break;
        uint32_t f = (uint32_t)(tag >> 3), w = (uint32_t)(tag & 7);
        if (f == 1 && w == 2) {
            uint64_t len;
            if (!pb_read_varint(p, n, &off, &len) || off + len > n) break;
            for (size_t i = 0; i + 4 <= len && cnt < 3; i += 4) {
                uint32_t u = rd_le32(p + off + i);
                memcpy(&out[cnt++], &u, 4);
            }
            off += len;
        } else if (f == 1 && w == 5 && off + 4 <= n) {
            if (cnt < 3) {
                uint32_t u = rd_le32(p + off);
                memcpy(&out[cnt++], &u, 4);
            }
            off += 4;
        } else {
            if (!pb_skip(p, n, &off, w)) break;
        }
    }
    return cnt;
}

static bool parse_axis_map(const char *spec, AxisMap *m) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%s", spec);
    char *tok = strtok(buf, ",");
    for (int i = 0; i < 3; i++) {
        if (!tok) return false;
        while (*tok == ' ' || *tok == '\t') tok++;
        float s = 1.0f;
        if (*tok == '-') { s = -1.0f; tok++; }
        else if (*tok == '+') { tok++; }
        if (*tok == 'x' || *tok == 'X') m->idx[i] = 0;
        else if (*tok == 'y' || *tok == 'Y') m->idx[i] = 1;
        else if (*tok == 'z' || *tok == 'Z') m->idx[i] = 2;
        else return false;
        m->sign[i] = s;
        tok = strtok(NULL, ",");
    }
    return true;
}

static void apply_map(const AxisMap *m, const float in[3], float out[3]) {
    for (int i = 0; i < 3; i++) out[i] = m->sign[i] * in[m->idx[i]];
}

static int setup_uinput(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput"); return -1; }

    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_EVBIT, EV_SYN);
    ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_ACCELEROMETER);

    const int axes[6] = { ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ };
    for (int i = 0; i < 6; i++) {
        ioctl(fd, UI_SET_ABSBIT, axes[i]);
        struct uinput_abs_setup abs = {0};
        abs.code = axes[i];
        abs.absinfo.minimum = -32768;
        abs.absinfo.maximum = 32767;
        abs.absinfo.resolution = 100;
        if (ioctl(fd, UI_ABS_SETUP, &abs) < 0) { perror("UI_ABS_SETUP"); close(fd); return -1; }
    }

    struct uinput_setup us = {0};
    /* InputPlumber ignores virtual evdev devices outside its VIRT_DEVICE_WHITELIST. */
    snprintf(us.name, UINPUT_MAX_NAME_SIZE, "Sunshine gamepad (virtual) motion sensors");
    us.id.bustype = BUS_USB;
    us.id.vendor  = 0x2020;
    us.id.product = 0x3002;
    us.id.version = 1;
    if (ioctl(fd, UI_DEV_SETUP, &us) < 0) { perror("UI_DEV_SETUP"); close(fd); return -1; }
    if (ioctl(fd, UI_DEV_CREATE) < 0) { perror("UI_DEV_CREATE"); close(fd); return -1; }
    return fd;
}

static int quantize_imu_dither(double val, double *err, bool use_dither) {
    /* InputPlumber evdev translator scales raw ABS counts by 0.01 (rad/s and m/s^2). */
    double scaled = val * 100.0;
    int q;
    if (use_dither) {
        *err += scaled;
        if (*err > 32767.0) *err = 32767.0;
        if (*err < -32768.0) *err = -32768.0;
        q = (int)lrint(*err);
        *err -= (double)q;
    } else {
        *err = 0.0;
        q = (int)lrint(scaled);
    }
    if (q > 32767) q = 32767;
    if (q < -32768) q = -32768;
    return q;
}

static void emit_evdev_vec3(int c0, int c1, int c2, int v0, int v1, int v2) {
    if (g_app.uinput_fd < 0) return;
    struct input_event ev[4];
    memset(ev, 0, sizeof(ev));
    ev[0].type = EV_ABS; ev[0].code = c0; ev[0].value = v0;
    ev[1].type = EV_ABS; ev[1].code = c1; ev[1].value = v1;
    ev[2].type = EV_ABS; ev[2].code = c2; ev[2].value = v2;
    ev[3].type = EV_SYN; ev[3].code = SYN_REPORT; ev[3].value = 0;
    ssize_t r = write(g_app.uinput_fd, ev, sizeof(ev));
    (void)r;
}

static void process_gyro_sample(const float mapped[3]) {
    double v[3] = { mapped[0], mapped[1], mapped[2] };

    if (g_app.bias_cal) {
        double mag = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
        if (!g_app.bias_ready) {
            if (mag < 0.15) {
                for (int i = 0; i < 3; i++) g_app.bias_init_sum[i] += v[i];
                g_app.bias_init_n++;
                if (g_app.bias_init_n >= 40) {
                    for (int i = 0; i < 3; i++)
                        g_app.gyro_bias[i] = g_app.bias_init_sum[i] / g_app.bias_init_n;
                    g_app.bias_ready = true;
                    fprintf(stderr, "gyro bias calibrated: (%.5f, %.5f, %.5f) rad/s\n",
                            g_app.gyro_bias[0], g_app.gyro_bias[1], g_app.gyro_bias[2]);
                }
            } else {
                g_app.bias_ready = true;
            }
        } else {
            double d0 = v[0] - g_app.gyro_bias[0];
            double d1 = v[1] - g_app.gyro_bias[1];
            double d2 = v[2] - g_app.gyro_bias[2];
            double dmag = sqrt(d0*d0 + d1*d1 + d2*d2);
            if (dmag < 0.035) {
                g_app.still_ticks++;
                if (g_app.still_ticks > 100) {
                    for (int i = 0; i < 3; i++)
                        g_app.gyro_bias[i] = g_app.gyro_bias[i] * 0.995 + v[i] * 0.005;
                }
            } else {
                g_app.still_ticks = 0;
            }
        }
        for (int i = 0; i < 3; i++) v[i] -= g_app.gyro_bias[i];
    }

    for (int i = 0; i < 3; i++) g_app.gyro_accum[i] += v[i];
    g_app.gyro_accum_n++;
    if (g_app.gyro_accum_n < g_app.gyro_emit_div) return;

    double avg[3];
    for (int i = 0; i < 3; i++) {
        avg[i] = (g_app.gyro_accum[i] / g_app.gyro_accum_n) * (double)g_app.gyro_scale;
        g_app.gyro_accum[i] = 0.0;
    }
    g_app.gyro_accum_n = 0;

    int q[3];
    for (int i = 0; i < 3; i++) {
        if (fabs(avg[i]) < (double)g_app.gyro_deadzone) {
            g_app.gyro_err[i] = 0.0;
            q[i] = 0;
        } else {
            q[i] = quantize_imu_dither(avg[i], &g_app.gyro_err[i], g_app.use_dither);
        }
    }

    if (!g_app.last_gyro_valid ||
        q[0] != g_app.last_gyro_q[0] ||
        q[1] != g_app.last_gyro_q[1] ||
        q[2] != g_app.last_gyro_q[2]) {
        g_app.last_gyro_q[0] = q[0];
        g_app.last_gyro_q[1] = q[1];
        g_app.last_gyro_q[2] = q[2];
        g_app.last_gyro_valid = true;
        emit_evdev_vec3(ABS_RX, ABS_RY, ABS_RZ, q[0], q[1], q[2]);
    }
}

static void process_accel_sample(const float mapped[3]) {
    /* Scale proportionally below 2g so Deck HID per-axis clamping does not tilt gravity. */
    float m[3] = { mapped[0], mapped[1], mapped[2] };
    float peak = fmaxf(fabsf(m[0]), fmaxf(fabsf(m[1]), fabsf(m[2])));
    if (peak > 19.5f) {
        float sc = 19.5f / peak;
        m[0] *= sc; m[1] *= sc; m[2] *= sc;
    }
    /* Periodic 1-LSB refresh delivers gravity even if InputPlumber starts or restarts late. */
    uint64_t t_ms = now_ms();
    bool do_nudge = false, force_sync = false;
    if (g_app.accel_sync_restore) {
        g_app.accel_sync_restore = false;
        force_sync = true;
    } else if (g_app.last_accel_valid && t_ms - g_app.last_accel_sync_ms >= 5000) {
        g_app.last_accel_sync_ms = t_ms;
        g_app.accel_sync_restore = true;
        do_nudge = true;
        force_sync = true;
    }
    if (g_app.last_accel_valid && !force_sync) {
        float d0 = fabsf(m[0] - g_app.last_accel_mps2[0]);
        float d1 = fabsf(m[1] - g_app.last_accel_mps2[1]);
        float d2 = fabsf(m[2] - g_app.last_accel_mps2[2]);
        if (d0 < g_app.accel_deadband && d1 < g_app.accel_deadband && d2 < g_app.accel_deadband)
            return;
    }
    int q[3];
    double dummy = 0.0;
    for (int i = 0; i < 3; i++) q[i] = quantize_imu_dither(m[i], &dummy, false);
    if (do_nudge) {
        q[0] ^= 1; q[1] ^= 1; q[2] ^= 1;
    }
    if (force_sync || !g_app.last_accel_valid ||
        q[0] != g_app.last_accel_q[0] ||
        q[1] != g_app.last_accel_q[1] ||
        q[2] != g_app.last_accel_q[2]) {
        for (int i = 0; i < 3; i++) {
            g_app.last_accel_mps2[i] = m[i];
            g_app.last_accel_q[i] = q[i];
        }
        if (!g_app.last_accel_valid) g_app.last_accel_sync_ms = t_ms;
        g_app.last_accel_valid = true;
        emit_evdev_vec3(ABS_X, ABS_Y, ABS_Z, q[0], q[1], q[2]);
    }
}

static int send_qmi_ssc_control(const PbBuf *pb) {
    if (!g_app.ssc_found || g_app.qrtr_fd < 0) return -1;
    uint8_t frame[640];
    if (7 + 5 + pb->len + 4 > sizeof(frame)) return -1;

    uint16_t tlv1_len = (uint16_t)(2 + pb->len);
    uint16_t tlv_total = (uint16_t)((3 + tlv1_len) + 4);
    g_app.txn_id++;
    if (g_app.txn_id == 0) g_app.txn_id = 1;

    frame[0] = QMI_FLAG_REQUEST;
    wr_le16(frame + 1, g_app.txn_id);
    wr_le16(frame + 3, QMI_SSC_MSG_CONTROL);
    wr_le16(frame + 5, tlv_total);

    size_t off = 7;
    frame[off++] = 0x01;
    wr_le16(frame + off, tlv1_len); off += 2;
    wr_le16(frame + off, (uint16_t)pb->len); off += 2;
    memcpy(frame + off, pb->data, pb->len); off += pb->len;

    frame[off++] = 0x10;
    wr_le16(frame + off, 1); off += 2;
    frame[off++] = QMI_SSC_REPORT_TYPE_LARGE;

    struct sockaddr_qrtr dst = {
        .sq_family = AF_QIPCRTR,
        .sq_node = g_app.ssc_node,
        .sq_port = g_app.ssc_port,
    };
    ssize_t n = sendto(g_app.qrtr_fd, frame, off, 0, (struct sockaddr *)&dst, sizeof(dst));
    return (n == (ssize_t)off) ? 0 : -1;
}

static void send_suid_lookup(const char *dtype) {
    PbBuf payload = {0}, req = {0};
    pb_bytes(&payload, 1, (const uint8_t *)dtype, strlen(dtype));
    pb_tag(&payload, 2, 0); pb_varint(&payload, 0);
    pb_tag(&payload, 3, 0); pb_varint(&payload, 1);
    pb_build_client_req(&req, SUID_LOOKUP_LOW, SUID_LOOKUP_HIGH, SNS_SUID_MSGID_REQ,
                        payload.data, payload.len);
    send_qmi_ssc_control(&req);
}

static void send_enable_sensor(uint64_t low, uint64_t high, float hz) {
    PbBuf payload = {0}, req = {0};
    uint32_t fbits;
    memcpy(&fbits, &hz, 4);
    pb_tag(&payload, 1, 5); pb_fixed32(&payload, fbits);
    pb_build_client_req(&req, low, high, SNS_STD_SENSOR_MSGID_CONFIG, payload.data, payload.len);
    send_qmi_ssc_control(&req);
}

static void send_disable_sensor(uint64_t low, uint64_t high) {
    PbBuf req = {0};
    pb_build_client_req(&req, low, high, SNS_CLIENT_MSGID_DISABLE_REQ, NULL, 0);
    send_qmi_ssc_control(&req);
}

static void handle_suid_event(const uint8_t *p, size_t n) {
    size_t off = 0;
    char dtype[32] = {0};
    uint64_t low = 0, high = 0;
    bool got_uid = false;
    while (off < n) {
        uint64_t tag;
        if (!pb_read_varint(p, n, &off, &tag)) break;
        uint32_t f = (uint32_t)(tag >> 3), w = (uint32_t)(tag & 7);
        if (f == 1 && w == 2) {
            uint64_t len;
            if (!pb_read_varint(p, n, &off, &len) || off + len > n) break;
            size_t cpy = len < sizeof(dtype) - 1 ? len : sizeof(dtype) - 1;
            memcpy(dtype, p + off, cpy);
            dtype[cpy] = 0;
            off += len;
        } else if (f == 2 && w == 2) {
            uint64_t len;
            if (!pb_read_varint(p, n, &off, &len) || off + len > n) break;
            if (!got_uid && pb_parse_uid(p + off, len, &low, &high)) got_uid = true;
            off += len;
        } else {
            if (!pb_skip(p, n, &off, w)) break;
        }
    }
    if (!got_uid) return;
    if (strcmp(dtype, "gyro") == 0 && !g_app.gyro_opened) {
        g_app.has_gyro_uid = true; g_app.gyro_low = low; g_app.gyro_high = high;
        g_app.gyro_opened = true;
        fprintf(stderr, "gyro SUID %016llx:%016llx -> %.1f Hz (div=%d, scale=%.3f)\n",
                (unsigned long long)low, (unsigned long long)high,
                g_app.target_rate, g_app.gyro_emit_div, g_app.gyro_scale);
        send_enable_sensor(low, high, g_app.target_rate);
    } else if (strcmp(dtype, "accel") == 0 && !g_app.accel_opened) {
        g_app.has_accel_uid = true; g_app.accel_low = low; g_app.accel_high = high;
        g_app.accel_opened = true;
        fprintf(stderr, "accel SUID %016llx:%016llx -> %.1f Hz (deadband=%.3f)\n",
                (unsigned long long)low, (unsigned long long)high,
                g_app.accel_rate, g_app.accel_deadband);
        send_enable_sensor(low, high, g_app.accel_rate);
    }
}

static void handle_ssc_packet(const uint8_t *p, size_t n) {
    size_t off = 0, tmp = 0;
    uint64_t low = 0, high = 0;
    bool got_uid = false;

    while (tmp < n) {
        uint64_t tag;
        if (!pb_read_varint(p, n, &tmp, &tag)) break;
        uint32_t f = (uint32_t)(tag >> 3), w = (uint32_t)(tag & 7);
        if (f == 1 && w == 2) {
            uint64_t len;
            if (!pb_read_varint(p, n, &tmp, &len) || tmp + len > n) break;
            got_uid = pb_parse_uid(p + tmp, len, &low, &high);
            tmp += len;
        } else {
            if (!pb_skip(p, n, &tmp, w)) break;
        }
    }
    if (!got_uid) return;

    while (off < n) {
        uint64_t tag;
        if (!pb_read_varint(p, n, &off, &tag)) break;
        uint32_t f = (uint32_t)(tag >> 3), w = (uint32_t)(tag & 7);
        if (f == 2 && w == 2) {
            uint64_t blen;
            if (!pb_read_varint(p, n, &off, &blen) || off + blen > n) break;
            const uint8_t *bp = p + off;
            size_t boff = 0;
            uint32_t msg_id = 0;
            const uint8_t *mp = NULL;
            size_t mlen = 0;
            while (boff < blen) {
                uint64_t btag;
                if (!pb_read_varint(bp, blen, &boff, &btag)) break;
                uint32_t bf = (uint32_t)(btag >> 3), bw = (uint32_t)(btag & 7);
                if (bf == 1 && bw == 5 && boff + 4 <= blen) {
                    msg_id = rd_le32(bp + boff); boff += 4;
                } else if (bf == 3 && bw == 2) {
                    uint64_t len;
                    if (!pb_read_varint(bp, blen, &boff, &len) || boff + len > blen) break;
                    mp = bp + boff; mlen = len; boff += len;
                } else {
                    if (!pb_skip(bp, blen, &boff, bw)) break;
                }
            }
            if (mp && mlen > 0) {
                if (msg_id == SNS_SUID_MSGID_EVENT) {
                    handle_suid_event(mp, mlen);
                } else if (msg_id == SNS_STD_SENSOR_MSGID_EVENT) {
                    float raw[3] = {0}, mapped[3] = {0};
                    if (pb_parse_vec3(mp, mlen, raw) == 3) {
                        if (g_app.has_gyro_uid && low == g_app.gyro_low && high == g_app.gyro_high) {
                            g_app.gyro_count++;
                            apply_map(&g_app.gyro_map, raw, mapped);
                            if (g_app.test_mode && (g_app.gyro_count >= 26 && g_app.gyro_count <= 30)) {
                                printf("GYRO #%lu raw=(%.5f,%.5f,%.5f) mapped=(%.5f,%.5f,%.5f)\n",
                                       g_app.gyro_count, raw[0], raw[1], raw[2],
                                       mapped[0], mapped[1], mapped[2]);
                            }
                            /* Discard first 25 gyro frames to skip MEMS startup saturation. */
                            if (!g_app.test_mode && g_app.gyro_count > 25)
                                process_gyro_sample(mapped);
                        } else if (g_app.has_accel_uid && low == g_app.accel_low && high == g_app.accel_high) {
                            g_app.accel_count++;
                            apply_map(&g_app.accel_map, raw, mapped);
                            if (g_app.test_mode && g_app.accel_count <= 3) {
                                printf("ACCEL #%lu raw=(%.5f,%.5f,%.5f) mapped=(%.5f,%.5f,%.5f)\n",
                                       g_app.accel_count, raw[0], raw[1], raw[2],
                                       mapped[0], mapped[1], mapped[2]);
                            }
                            if (!g_app.test_mode)
                                process_accel_sample(mapped);
                        }
                    }
                }
            }
            off += blen;
        } else {
            if (!pb_skip(p, n, &off, w)) break;
        }
    }
}

static void handle_qmi_indication(const uint8_t *buf, size_t len) {
    if (len < 7) return;
    uint8_t flags = buf[0];
    uint16_t msg_id = rd_le16(buf + 3);
    uint16_t tlv_len = rd_le16(buf + 5);
    if (flags != QMI_FLAG_INDICATION) return;
    if (msg_id != QMI_SSC_MSG_REPORT_SMALL && msg_id != QMI_SSC_MSG_REPORT_LARGE) return;
    if (7 + (size_t)tlv_len > len) return;

    size_t off = 7, end = 7 + (size_t)tlv_len;
    while (off + 3 <= end) {
        uint8_t t = buf[off];
        uint16_t l = rd_le16(buf + off + 1);
        off += 3;
        if (off + l > end) break;
        if (t == 0x02 && l >= 2) {
            uint16_t dlen = rd_le16(buf + off);
            if (2 + (size_t)dlen <= l)
                handle_ssc_packet(buf + off + 2, dlen);
        }
        off += l;
    }
}

static int setup_qrtr(void) {
    int fd = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) { perror("socket AF_QIPCRTR"); return -1; }

    struct sockaddr_qrtr local = {0};
    socklen_t sl = sizeof(local);
    if (getsockname(fd, (struct sockaddr *)&local, &sl) < 0) {
        perror("getsockname AF_QIPCRTR");
        close(fd);
        return -1;
    }

    struct qrtr_ctrl_pkt pkt = {0};
    pkt.cmd = htole32(QRTR_TYPE_NEW_LOOKUP);
    pkt.server.service = htole32(QMI_SERVICE_SSC);
    pkt.server.instance = htole32(0);

    struct sockaddr_qrtr ctrl = {
        .sq_family = AF_QIPCRTR,
        .sq_node = local.sq_node,
        .sq_port = QRTR_PORT_CTRL,
    };
    if (sendto(fd, &pkt, sizeof(pkt), 0, (struct sockaddr *)&ctrl, sizeof(ctrl)) < 0) {
        perror("sendto QRTR_TYPE_NEW_LOOKUP");
        close(fd);
        return -1;
    }
    return fd;
}

static void reset_sensor_state(void) {
    g_app.has_gyro_uid = false;
    g_app.has_accel_uid = false;
    g_app.gyro_opened = false;
    g_app.accel_opened = false;
    g_app.gyro_count = 0;
    g_app.accel_count = 0;
    g_app.gyro_accum_n = 0;
    g_app.last_gyro_valid = false;
    g_app.last_accel_valid = false;
    g_app.accel_sync_restore = false;
    g_app.bias_ready = false;
    g_app.bias_init_n = 0;
    g_app.still_ticks = 0;
    memset(g_app.gyro_accum, 0, sizeof(g_app.gyro_accum));
    memset(g_app.gyro_err, 0, sizeof(g_app.gyro_err));
    memset(g_app.bias_init_sum, 0, sizeof(g_app.bias_init_sum));
}

int main(int argc, char **argv) {
    memset(&g_app, 0, sizeof(g_app));
    g_app.qrtr_fd = -1;
    g_app.uinput_fd = -1;
    g_app.target_rate = 200.0f;
    g_app.accel_rate = 25.0f;
    g_app.gyro_emit_div = 2;
    /* Compensates for InputPlumber TargetDriver writing extra HID packets on event wakeup. */
    g_app.gyro_scale = 0.73f;
    g_app.gyro_deadzone = 0.005f;
    g_app.accel_deadband = 0.05f;
    g_app.use_dither = true;
    g_app.bias_cal = true;

    parse_axis_map("-y,z,-x", &g_app.gyro_map);
    parse_axis_map("-y,z,-x", &g_app.accel_map);

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--test") == 0) g_app.test_mode = true;
        else if (strcmp(argv[i], "--no-dither") == 0) g_app.use_dither = false;
        else if (strcmp(argv[i], "--no-bias") == 0) g_app.bias_cal = false;
        else if (strcmp(argv[i], "--rate") == 0 && i + 1 < argc) g_app.target_rate = strtof(argv[++i], NULL);
        else if (strcmp(argv[i], "--accel-rate") == 0 && i + 1 < argc) g_app.accel_rate = strtof(argv[++i], NULL);
        else if (strcmp(argv[i], "--div") == 0 && i + 1 < argc) g_app.gyro_emit_div = atoi(argv[++i]);
        else if (strcmp(argv[i], "--scale") == 0 && i + 1 < argc) g_app.gyro_scale = strtof(argv[++i], NULL);
        else if (strcmp(argv[i], "--gyro-map") == 0 && i + 1 < argc) {
            if (!parse_axis_map(argv[++i], &g_app.gyro_map)) {
                fprintf(stderr, "invalid --gyro-map\n");
                return 2;
            }
        } else if (strcmp(argv[i], "--accel-map") == 0 && i + 1 < argc) {
            if (!parse_axis_map(argv[++i], &g_app.accel_map)) {
                fprintf(stderr, "invalid --accel-map\n");
                return 2;
            }
        }
    }
    if (g_app.gyro_emit_div < 1 || g_app.gyro_emit_div > 16) g_app.gyro_emit_div = 2;

    struct sigaction sa = {0};
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    g_app.qrtr_fd = setup_qrtr();
    if (g_app.qrtr_fd < 0) return 1;

    if (!g_app.test_mode) {
        g_app.uinput_fd = setup_uinput();
        if (g_app.uinput_fd < 0) {
            close(g_app.qrtr_fd);
            return 1;
        }
    }

    uint8_t *rxbuf = malloc(65536);
    if (!rxbuf) return 1;

    uint64_t start_ms = now_ms();
    uint64_t last_lookup_ms = 0;

    while (!g_stop) {
        if (g_app.test_mode && now_ms() - start_ms >= 1500) break;

        /* Retry SUID discovery if ADSP registers SSC before sensor drivers finish probing. */
        if (g_app.ssc_found && (!g_app.gyro_opened || !g_app.accel_opened)) {
            uint64_t t = now_ms();
            if (t - last_lookup_ms >= 2000) {
                if (!g_app.gyro_opened) send_suid_lookup("gyro");
                if (!g_app.accel_opened) send_suid_lookup("accel");
                last_lookup_ms = t;
            }
        }

        struct pollfd pfd = { .fd = g_app.qrtr_fd, .events = POLLIN };
        int timeout_ms = g_app.test_mode ? 200 : ((!g_app.gyro_opened || !g_app.accel_opened) ? 500 : 2000);
        int rc = poll(&pfd, 1, timeout_ms);
        if (rc < 0) {
            if (errno == EINTR) continue;
            perror("poll");
            break;
        }
        if (rc == 0) continue;

        struct sockaddr_qrtr src = {0};
        socklen_t srclen = sizeof(src);
        ssize_t n = recvfrom(g_app.qrtr_fd, rxbuf, 65536, 0, (struct sockaddr *)&src, &srclen);
        if (n <= 0) continue;

        if (src.sq_port == QRTR_PORT_CTRL && (size_t)n >= sizeof(struct qrtr_ctrl_pkt)) {
            struct qrtr_ctrl_pkt cp;
            memcpy(&cp, rxbuf, sizeof(cp));
            uint32_t cmd = le32toh(cp.cmd);
            uint32_t svc = le32toh(cp.server.service);
            if (cmd == QRTR_TYPE_NEW_SERVER && svc == QMI_SERVICE_SSC) {
                g_app.ssc_node = le32toh(cp.server.node);
                g_app.ssc_port = le32toh(cp.server.port);
                g_app.ssc_found = true;
                reset_sensor_state();
                fprintf(stderr, "discovered SSC service at qrtr %u:%u\n",
                        g_app.ssc_node, g_app.ssc_port);
                send_suid_lookup("gyro");
                send_suid_lookup("accel");
                last_lookup_ms = now_ms();
            } else if (cmd == QRTR_TYPE_DEL_SERVER && svc == QMI_SERVICE_SSC) {
                g_app.ssc_found = false;
                reset_sensor_state();
                fprintf(stderr, "SSC service went away, waiting for reconnect\n");
            }
        } else if (g_app.ssc_found && src.sq_node == g_app.ssc_node && src.sq_port == g_app.ssc_port) {
            handle_qmi_indication(rxbuf, (size_t)n);
        }
    }

    if (g_app.test_mode) {
        double secs = (double)(now_ms() - start_ms) / 1000.0;
        if (secs < 0.01) secs = 0.01;
        printf("SUMMARY (%.2fs): gyro=%lu (%.1f Hz), accel=%lu (%.1f Hz)\n",
               secs, g_app.gyro_count, g_app.gyro_count / secs,
               g_app.accel_count, g_app.accel_count / secs);
    }

    if (g_app.ssc_found) {
        if (g_app.gyro_opened) send_disable_sensor(g_app.gyro_low, g_app.gyro_high);
        if (g_app.accel_opened) send_disable_sensor(g_app.accel_low, g_app.accel_high);
    }
    if (g_app.uinput_fd >= 0) {
        ioctl(g_app.uinput_fd, UI_DEV_DESTROY);
        close(g_app.uinput_fd);
    }
    close(g_app.qrtr_fd);
    free(rxbuf);
    return 0;
}
