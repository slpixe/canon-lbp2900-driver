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

#include "std.h"
#include "runtime.h"
#include "printer.h"
#include "paper.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

#include <cups/raster.h>


struct cached_page_s {
	struct page_dims_s dims;
	struct band_list_s *bands;
};

struct band_list_s {
	struct band_list_s *next;
	size_t size;
	uint8_t data[];
};

/* printer and job state */
/* Job state is local to do_print; signal handlers never touch it. */

/* compressor state */
static uint8_t *linebuf = NULL;
static uint8_t *bandbuf = NULL;
static uint8_t *compbuf = NULL;

static inline size_t sizeof_struct_band_list_s(size_t size)
	{ return sizeof(struct band_list_s) + size; }

static size_t center_pixels(size_t small, size_t large, unsigned bpp)
{
	unsigned small_p;
	unsigned large_p;
	unsigned bypp;
	while (bpp % 8)
		bpp *= 2;
	bypp = bpp / 8;
	small_p = small / bypp;
	large_p = large / bypp;
	return bypp * ((large_p - small_p) / 2);
}

static void free_state(struct printer_state_s *state, const struct printer_ops_s *ops)
{
	if (state) {
		if (ops && ops->free_state)
			ops->free_state(state);
		else
			free(state);
	}
}

static void free_buffers(void)
{
	if (compbuf) {
		free(compbuf);
		compbuf = NULL;
	}
	if (bandbuf) {
		free(bandbuf);
		bandbuf = NULL;
	}
	if (linebuf) {
		free(linebuf);
		linebuf = NULL;
	}
}

static void compress_page_data(struct printer_state_s *state,
		struct cached_page_s *page,
		cups_raster_t *raster,
		const struct cups_page_header2_s *header)
{
	if (page->bands) capt_fail("page already has compressed data");
	const struct page_dims_s *dims = &page->dims;
	const size_t compsize = 2 * (size_t)dims->line_size * dims->band_size + 16;

	struct band_list_s *last_band = NULL;
	unsigned i;
	unsigned iband;

	unsigned shiftb = 0;
	unsigned shiftl = 0;
	unsigned csize = header->cupsBytesPerLine;


	if (header->cupsBytesPerLine < dims->line_size) {
		csize = header->cupsBytesPerLine;
		shiftb = center_pixels(header->cupsBytesPerLine, dims->line_size,
				header->cupsBitsPerPixel);
	}

	if (dims->line_size < header->cupsBytesPerLine) {
		csize = dims->line_size;
		shiftl = center_pixels(dims->line_size, header->cupsBytesPerLine,
				header->cupsBitsPerPixel);
	}

	if (header->cupsBytesPerLine > dims->line_size)
		fprintf(stderr, "INFO: cutting line from %u to %u bytes\n",
				header->cupsBytesPerLine, dims->line_size);

	if (header->cupsHeight > dims->num_lines)
		fprintf(stderr, "INFO: cutting image from %u to %u lines\n",
				header->cupsHeight, dims->num_lines);

	linebuf = calloc(1, header->cupsBytesPerLine);
	if (! linebuf)
		abort();
	bandbuf = calloc(dims->line_size, dims->band_size);
	if (! bandbuf)
		abort();
	compbuf = calloc(1, compsize);
	if (! compbuf)
		abort();

	for (iband = 0; iband * dims->band_size < dims->num_lines; ++iband) {
        capt_check_cancel();
		struct band_list_s *new_band;
		unsigned start = iband * dims->band_size;
		unsigned nlines = dims->band_size;
		unsigned iline;
		size_t size;
		memset(bandbuf, 0, dims->line_size * dims->band_size);
		if (nlines + start >= dims->num_lines)
			nlines = dims->num_lines - start;
		for (iline = 0; iline < nlines; ++iline) {
			if (iline + start < header->cupsHeight) {
				if (cupsRasterReadPixels(raster, linebuf, header->cupsBytesPerLine)
								!= header->cupsBytesPerLine) {
					fprintf(stderr, "ERROR: CAPT: broken raster file\n");
					exit(1);
				}
			} else {
				memset(linebuf, 0, header->cupsBytesPerLine);
			}
			memcpy(bandbuf + iline * dims->line_size + shiftb, linebuf + shiftl, csize);
		}
		size = state->ops->compress_band(state, compbuf, compsize, bandbuf, dims->line_size, nlines);
		if (!size || size > compsize) capt_fail("compression failed");
		new_band = calloc(1, sizeof_struct_band_list_s(size));
		if (! new_band)
			abort();
		new_band->size = size;
		if (size)
			memcpy(new_band->data, compbuf, size);
		if (last_band)
			last_band->next = new_band;
        else
            page->bands = new_band;
		last_band = new_band;
	}

	/* discard end of image, if any */
	for (i = dims->num_lines; i < header->cupsHeight; ++i)
		if (cupsRasterReadPixels(raster, linebuf, header->cupsBytesPerLine) != header->cupsBytesPerLine)
            capt_fail("truncated raster stream");

	free_buffers();
}

static void send_page_data(struct printer_state_s *state, const struct cached_page_s *page)
{
	const struct band_list_s *band;

	state->isend = 0;
	state->iband = 0;

	for (band = page->bands; band; band = band->next, ++state->iband)
		state->ops->send_band(state, band->data, band->size);
}

/* Async-signal-safe: all I/O, deallocation and protocol work stays outside
 * the handler. Cancellation exits the filter; CUPS owns resource cleanup. */
static void do_cancel(int signal_number) {
    (void)signal_number;
    capt_cancelled = 1;
}

static void do_print(int fd)
{
	bool in_job = false;
    unsigned page_retries = 0;
	const struct printer_ops_s *ops = printer_detect();
    struct printer_state_s *state;
    struct cached_page_s *cached_page = NULL;
    cups_raster_t *raster;

	if (ops->alloc_state)
		state = ops->alloc_state();
	else
		state = calloc(1, sizeof(struct printer_state_s));
	if (!state) capt_fail("out of memory allocating printer state");
	state->ops = ops;
	state->ipage = 0;

	raster = cupsRasterOpen(fd, CUPS_RASTER_READ);
    if (!raster) capt_fail("cannot open raster stream");

	fprintf(stderr, "DEBUG: CAPT: rastertocapt is rendering\n");

	while (1) {
        capt_check_cancel();
		bool page_printed = false;

		if (! cached_page) {
			struct cups_page_header2_s header;

			if (! cupsRasterReadHeader2(raster, &header)) {
                const char *error = cupsRasterErrorString();
                if (error && *error) capt_fail("invalid raster header");
				break; /* clean end of stream */
            }

			cached_page = calloc(1, sizeof(struct cached_page_s));
			if (! cached_page)
				abort();

			state->ipage += 1;
            page_retries = 0;

			page_set_dims(&cached_page->dims, &header);

			ops->page_setup(state, &cached_page->dims,
					header.cupsWidth, header.cupsHeight);

			compress_page_data(state, cached_page, raster, &header);
		}

		if (! in_job) {
			fprintf(stderr, "DEBUG: CAPT: rastertocapt: start job\n");
			if (ops->job_prologue)
				ops->job_prologue(state);
			in_job = true;
		}

		fprintf(stderr, "DEBUG: CAPT: rastertocapt: start page %u\n", state->ipage);
		if (ops->page_prologue) {
			if (cached_page->dims.manual_duplex && state->ipage > 1) {
				fprintf(stderr, "DEBUG: CAPT: rastertocapt: manual duplex: press button to continue\n");
				ops->wait_user(state);
			}
			bool ok = ops->page_prologue(state, &cached_page->dims);
			if (! ok) {
				fprintf(stderr, "DEBUG: CAPT: rastertocapt: can't start page\n");
				ops->wait_user(state);
				if (in_job) {
					fprintf(stderr, "DEBUG: CAPT: rastertocapt: retry job\n");
					if (ops->job_epilogue)
						ops->job_epilogue(state);
					in_job = false;
				}
				continue;
			}
		}

		fprintf(stderr, "DEBUG: CAPT: rastertocapt: sending page data\n");
		/* PAGE: silently drives CUPS job-media-sheets-completed, which
		 * progress.sh reads for an accurate live page count. We deliberately
		 * do NOT emit an INFO: "Printing page N" string: on the macOS app print
		 * path (Word/Excel etc.) PrintCore writes its own "N of M" text into the
		 * same job-printer-state-message, so a second writer just produces a
		 * jumbled, flickering status line. */
		/* Report a page only after its completion handshake. */
		send_page_data(state, cached_page);

		fprintf(stderr, "DEBUG: CAPT: rastertocapt: end page %u\n", state->ipage);
		if (ops->page_epilogue) {
			bool ok = ops->page_epilogue(state, &cached_page->dims);
			if (! ok) {
				if (++page_retries > 3) capt_fail("page retry limit exceeded");
                fprintf(stderr, "DEBUG: CAPT: rastertocapt: page not printed\n");
				ops->wait_user(state);
				continue;
			}
		}

		fprintf(stderr, "PAGE: %u 1\n", state->ipage);
		page_printed = true;

		if (page_printed) {
			while (cached_page->bands) {
				void *p = cached_page->bands;
				cached_page->bands = cached_page->bands->next;
				free(p);
			}
			free(cached_page);
			cached_page = NULL;
		}
	}

	if (in_job) {
		fprintf(stderr, "DEBUG: CAPT: rastertocapt: end job\n");
		if (ops->job_epilogue)
			ops->job_epilogue(state);
	}

	if (! state->ipage) capt_fail("no pages in job");

	cupsRasterClose(raster);
	free_state(state, ops);
}


int main(int argc, char *argv[])
{

    struct sigaction action = {0};
    sigemptyset(&action.sa_mask);
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL)) capt_fail("cannot configure SIGPIPE");
    action.sa_handler = do_cancel;
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL))
    { capt_fail("cannot configure cancellation"); }

	int fd = 0;

	if (argc < 6 || argc > 7) {
		fprintf(stderr, "Usage: %s job-id user title copies options [file]\n", argv[0]);
		return 1;
	}

	if (argc == 7) {
		fd = open(argv[6], O_RDONLY);
		if (fd < 0) {
			fprintf(stderr, "ERROR: unable to open %s: %s\n", argv[6], strerror(errno));
			return 1;
		}
	}

	fprintf(stderr, "DEBUG: CAPT: rastertocapt started\n");
	do_print(fd);
	fprintf(stderr, "DEBUG: CAPT: rastertocapt finished\n");

	if (argc == 7)
		close(fd);

	return 0;
}
