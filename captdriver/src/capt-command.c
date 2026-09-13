/*
 * Copyright (C) 2013 Alexey Galakhov <agalakhov@gmail.com>
 *
 * Licensed under the GNU General Public License Version 3
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "capt-command.h"
#include "runtime.h"
#include "word.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <cups/cups.h>
#include <cups/sidechannel.h>

static uint8_t capt_iobuf[0x10000];
static size_t capt_iosize;

/* No raster or device payloads are logged: they can contain document data. */
static void capt_send_buf(void) {
    size_t offset = 0;
    const double deadline = capt_now() + 30.0;
    while (offset < capt_iosize) {
        capt_check_deadline(deadline, "USB output timed out");
        size_t n = capt_iosize - offset;
        if (n > 4096) n = 4096;
        if (fwrite(capt_iobuf + offset, 1, n, stdout) != n || fflush(stdout))
            capt_fail("cannot write to CUPS backend");
        offset += n;
        char data[128];
        int length = sizeof(data);
        cups_sc_status_t status = cupsSideChannelDoRequest(
            CUPS_SC_CMD_DRAIN_OUTPUT, data, &length, 1.0);
        /* The Apple USB backend can time out after already draining output. */
        if (status != CUPS_SC_STATUS_OK && status != CUPS_SC_STATUS_TIMEOUT)
            capt_fail("CUPS backend rejected output");
    }
}

/* Read one fragment, bounded by both the array and a transaction deadline. */
static void capt_recv_fragment(size_t wanted, double deadline) {
    capt_check_deadline(deadline, "printer reply timed out");
    if (!wanted || wanted > sizeof(capt_iobuf) - capt_iosize)
        capt_fail("invalid printer reply length");
    double remaining = deadline - capt_now();
    if (remaining <= 0) capt_fail("printer reply timed out");
    ssize_t n = cupsBackChannelRead((char *)capt_iobuf + capt_iosize, wanted, remaining);
    capt_check_cancel();
    if (n <= 0 || (size_t)n > wanted) capt_fail("short or missing printer reply");
    capt_iosize += (size_t)n;
}

const char *capt_identify(void) {
    const double deadline = capt_now() + 60.0;
    for (;;) {
        capt_check_deadline(deadline, "printer identification timed out");
        int length = sizeof(capt_iobuf) - 1;
        cups_sc_status_t status = cupsSideChannelDoRequest(
            CUPS_SC_CMD_GET_DEVICE_ID, (char *)capt_iobuf, &length, 5.0);
        if (status != CUPS_SC_STATUS_OK || length < 0 ||
            (size_t)length >= sizeof(capt_iobuf))
            capt_fail("invalid printer identification response");
        capt_iobuf[length] = '\0';
        if (length) return (const char *)capt_iobuf;
        capt_pause();
    }
}

static void capt_copy_cmd(uint16_t cmd, const void *buf, size_t size) {
    if ((!buf && size) || capt_iosize > sizeof(capt_iobuf) - 4 ||
        size > sizeof(capt_iobuf) - capt_iosize - 4 || size > UINT16_MAX - 4)
        capt_fail("invalid CAPT command length");
    if (size) memcpy(capt_iobuf + capt_iosize + 4, buf, size);
    capt_iobuf[capt_iosize] = LO(cmd);
    capt_iobuf[capt_iosize + 1] = HI(cmd);
    capt_iobuf[capt_iosize + 2] = LO(size + 4);
    capt_iobuf[capt_iosize + 3] = HI(size + 4);
    capt_iosize += size + 4;
}
void capt_send(uint16_t cmd, const void *buf, size_t size) {
    capt_check_cancel();
    capt_iosize = 0;
    capt_copy_cmd(cmd, buf, size);
    capt_send_buf();
}

/* *reply_size is the destination capacity on entry and PAYLOAD length on exit.
 * A short destination is an error, never a silently truncated success. */
void capt_sendrecv(uint16_t cmd, const void *buf, size_t size,
                   void *reply, size_t *reply_size) {
    if (reply && !reply_size) capt_fail("missing reply buffer capacity");
    capt_send(cmd, buf, size);
    capt_iosize = 0;
    const double deadline = capt_now() + 15.0;
    while (capt_iosize < 6) capt_recv_fragment(6 - capt_iosize, deadline);
    if (WORD(capt_iobuf[0], capt_iobuf[1]) != cmd)
        capt_fail("unexpected printer reply command");
    /* CAPT framed replies use a little-endian binary total length (SPECS 1.1).
     * Never infer BCD from read boundaries: a valid 56-byte LBP2900 reply
     * (38 00) may be fragmented at byte 38. No evidenced BCD exception is
     * registered; any future quirk must identify its model AND command.
     * See docs/PROTOCOL-LENGTHS.md and tests/fixtures. */
    size_t length = WORD(capt_iobuf[2], capt_iobuf[3]);
    if (length < 6) capt_fail("invalid printer packet length");
    if (reply && length - 4 > *reply_size)
        capt_fail("printer reply exceeds destination");
    while (capt_iosize < length)
        capt_recv_fragment(length - capt_iosize, deadline);
    size_t payload_length = capt_iosize - 4;
    if (reply) {
        if (payload_length > *reply_size) capt_fail("printer reply exceeds destination");
        memcpy(reply, capt_iobuf + 4, payload_length);
    }
    if (reply_size) *reply_size = payload_length;
}
void capt_multi_begin(uint16_t cmd) {
    capt_iosize = 0;
    capt_copy_cmd(cmd, NULL, 0);
}
void capt_multi_add(uint16_t cmd, const void *buf, size_t size) {
    capt_copy_cmd(cmd, buf, size);
}
void capt_multi_send(void) {
    if (capt_iosize > UINT16_MAX) capt_fail("combined CAPT command too long");
    capt_iobuf[2] = LO(capt_iosize);
    capt_iobuf[3] = HI(capt_iosize);
    capt_send_buf();
}
