/* SPDX-License-Identifier: GPL-3.0-or-later
 * System ABI adapter only. No CAPT parsing, compression or printer state.
 * Built against installed CUPS headers rather than reproducing their layout.
 */
#include <cups/cups.h>
#include <cups/raster.h>
#include <cups/sidechannel.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static volatile sig_atomic_t cancelled;
static void cancel_handler(int sig) { (void)sig; cancelled = 1; }
int lbp_cancelled(void) { return cancelled != 0; }
int lbp_initialize(void) {
    struct sigaction action = {0};
    sigemptyset(&action.sa_mask);
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL)) return -1;
    action.sa_handler = cancel_handler;
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)) return -1;
    int flags = fcntl(STDOUT_FILENO, F_GETFL);
    if (flags < 0 || fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK)) return -1;
    return 0;
}
void *lbp_raster_open(int fd) { return cupsRasterOpen(fd, CUPS_RASTER_READ); }
void lbp_raster_close(void *raster) { cupsRasterClose(raster); }
int lbp_raster_header(void *raster, uint32_t *values, size_t count, uint8_t *media, size_t capacity) {
    if (!raster || !values || count != 20 || !media || capacity != 64) return -1;
    cups_page_header2_t h = {0};
    if (!cupsRasterReadHeader2(raster, &h)) {
        const char *error = cupsRasterErrorString();
        return error && *error ? -1 : 0;
    }
    /* Index order shared with page::Header. Color enums are normalized here. */
    const uint32_t v[20] = {h.cupsWidth,h.cupsHeight,h.PageSize[0],h.PageSize[1],
        h.cupsRowCount,h.cupsBitsPerPixel,h.cupsBitsPerColor,
        h.cupsColorOrder == CUPS_ORDER_CHUNKED ? 0 : UINT32_MAX,
        h.cupsColorSpace == CUPS_CSPACE_K ? 3 : UINT32_MAX,
        h.cupsNumColors,h.cupsBytesPerLine,h.HWResolution[0],h.HWResolution[1],
        h.cupsMediaType,h.cupsInteger[0],h.cupsInteger[1],h.cupsInteger[2],
        h.Margins[0],h.Margins[1],0};
    memcpy(values,v,sizeof(v)); memcpy(media,h.MediaType,64);
    return 1;
}
int lbp_raster_line(void *raster, uint8_t *data, size_t size) {
    if (!raster || !data || !size || size > 1024) return -1;
    return cupsRasterReadPixels(raster,data,(unsigned)size) == size ? 0 : -1;
}
int lbp_device_id(uint8_t *data, size_t capacity) {
    if (!data || capacity != 4097) return -1;
    int size = (int)capacity;
    cups_sc_status_t status = cupsSideChannelDoRequest(CUPS_SC_CMD_GET_DEVICE_ID,(char *)data,&size,1.0);
    if (status == CUPS_SC_STATUS_TIMEOUT) return -2;
    if (status != CUPS_SC_STATUS_OK || size < 0 || size > 4096) return -1;
    return size;
}
int lbp_back_read(uint8_t *data, size_t capacity, double timeout) {
    if (!data || !capacity || capacity > UINT16_MAX || timeout <= 0 || timeout > 1.0) return -1;
    ssize_t size = cupsBackChannelRead((char *)data,capacity,timeout);
    if (size < 0 && errno == EINTR) return -2;
    if (size < 0 || (size_t)size > capacity) return -1;
    return (int)size;
}
static double now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC,&t)) return -1;
    return (double)t.tv_sec+(double)t.tv_nsec/1e9;
}
int lbp_write(const uint8_t *data, size_t size) {
    if (!data || size < 4 || size > UINT16_MAX) return -1;
    double start = now(); if (start < 0) return -1;
    double deadline = start+30.0; size_t offset = 0;
    while (offset < size) {
        double current = now();
        if (current < 0) return -1;
        if (cancelled) return -3;
        if (current >= deadline) return -2;
        struct pollfd fd = {STDOUT_FILENO,POLLOUT,0};
        int ready = poll(&fd,1,100);
        if (ready < 0) { if (errno == EINTR) continue; return -1; }
        if (!ready) continue;
        if (fd.revents & (POLLERR|POLLHUP|POLLNVAL)) return -1;
        size_t wanted = size-offset; if (wanted > 4096) wanted = 4096;
        ssize_t n = write(STDOUT_FILENO,data+offset,wanted);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0 || (size_t)n > wanted) return -1;
        offset += (size_t)n;
        char scratch[128] = {0}; int length = sizeof(scratch);
        cups_sc_status_t status = cupsSideChannelDoRequest(CUPS_SC_CMD_DRAIN_OUTPUT,scratch,&length,1.0);
        if (length < 0 || length > (int)sizeof(scratch)) return -1;
        /* Match the Apple USB backend timeout tolerance in the C driver. */
        if (status != CUPS_SC_STATUS_OK && status != CUPS_SC_STATUS_TIMEOUT) return -1;
    }
    if (cancelled) return -3;
    double end = now();
    return end < 0 ? -1 : end >= deadline ? -2 : 0;
}
int lbp_timestamp(uint16_t *out, size_t count) {
    if (!out || count != 6) return -1;
    time_t t = time(NULL); struct tm local;
    if (t == (time_t)-1 || !localtime_r(&t,&local) || local.tm_year < 0 || local.tm_year > UINT16_MAX) return -1;
    out[0]=(uint16_t)local.tm_year; out[1]=(uint16_t)local.tm_mon; out[2]=(uint16_t)local.tm_mday;
    out[3]=(uint16_t)local.tm_hour; out[4]=(uint16_t)local.tm_min; out[5]=(uint16_t)local.tm_sec;
    return 0;
}
