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

#include "capt-status.h"

#include "std.h"
#include "word.h"
#include "capt-command.h"
#include "runtime.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static struct capt_status_s status;

static inline char bit(enum capt_flags flag)
{
	return FLAG(&status, flag) ? '1' : '0';
}

static void print_status(void)
{
	fprintf(stderr, "DEBUG: CAPT: printer status P1=%c P2=%c B=%c B0=%c B1=%c nE=%c\n",
		bit(CAPT_FL_NOPAPER1), bit(CAPT_FL_NOPAPER2),
		bit(CAPT_FL_BUTTON_ON),
		bit(CAPT_FL_BUTTON), bit(CAPT_FL_BUTTON1),
		bit(CAPT_FL_nERROR)
	);
	fprintf(stderr, "DEBUG: CAPT: pages %u/%u/%u/%u\n",
		status.page_decoding,
		status.page_printing,
		status.page_out,
		status.page_completed
	);
}

bool capt_decode_status(struct capt_status_s *out, const uint8_t *s,
                        size_t size, bool extended) {
    if (!out || !s || (extended ? size < 40 : (size != 2 && size != 10)))
        return false;
    /* Basic records update only fields actually present. Extended records
     * require the complete layout before any field is read. */
    out->status[0] = WORD(s[0], s[1]);
    if (size == 2) return true;
    out->status[1] = WORD(s[8], s[9]);
    if (!extended) return true;
    out->status[2] = WORD(s[10], s[11]);
    out->status[3] = WORD(s[12], s[13]);
    out->page_decoding = WORD(s[14], s[15]);
    out->page_printing = WORD(s[16], s[17]);
    out->page_out = WORD(s[18], s[19]);
    out->page_completed = WORD(s[20], s[21]);
    out->page_received = WORD(s[34], s[35]);
    out->status[4] = WORD(s[24], s[25]);
    out->status[5] = WORD(s[30], s[31]);
    out->status[6] = WORD(s[38], s[39]);
    return true;
}

static void download_status(uint16_t cmd)
{
	uint8_t buf[0x10000];
	size_t size = sizeof(buf);
	capt_sendrecv(cmd, NULL, 0, buf, &size);
	if (!capt_decode_status(&status, buf, size, cmd == CAPT_CHKXSTATUS))
        capt_fail("truncated or unsupported printer status record");
}

void capt_init_status(void)
{
	memset(&status, 0, sizeof(status));
}

const struct capt_status_s *capt_get_status(void)
{
	download_status(CAPT_CHKSTATUS);
	return &status;
}

const struct capt_status_s *capt_get_xstatus_only(void)
{
	download_status(CAPT_CHKXSTATUS);
	print_status();
	/*
	if (FLAG(&status, CAPT_FL_JOBSTAT_CHNG)) {
	   capt_sendrecv(CAPT_CHKJOBSTAT, NULL, 0, NULL, 0);
	   print_status();
	}
	*/

	return &status;
}

const struct capt_status_s *capt_get_xstatus(void)
{
	download_status(CAPT_CHKSTATUS);
	if (FLAG(&status, CAPT_FL_XSTATUS_CHNG))
		capt_get_xstatus_only();
	return &status;
}

static void wait_ready(const struct capt_status_s *(*get_status)(void)) {
    const double deadline = capt_now() + 30.0;
    for (;;) {
        capt_check_deadline(deadline, "printer remained busy");
        const struct capt_status_s *s = get_status();
        capt_check_deadline(deadline, "printer remained busy");
        if (!FLAG(s, CAPT_FL_BUSY)) return;
        capt_pause();
    }
}
void capt_wait_ready(void) { wait_ready(capt_get_status); }
void capt_wait_xready(void) { wait_ready(capt_get_xstatus); }
void capt_wait_xready_only(void) { wait_ready(capt_get_xstatus_only); }
