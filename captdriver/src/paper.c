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

#include "paper.h"
#include <cups/raster.h>
#include <stdio.h>
#include <string.h>
#include "runtime.h"

bool page_header_valid(const struct cups_page_header2_s *h) {
    return h && h->cupsWidth > 0 && h->cupsWidth <= 8192 &&
        h->cupsHeight > 0 && h->cupsHeight <= 12000 &&
        h->PageSize[0] > 0 && h->PageSize[0] <= 1024 &&
        h->PageSize[1] > 0 && h->PageSize[1] <= 1440 &&
        h->cupsRowCount > 0 && h->cupsRowCount <= 256 &&
        h->cupsBitsPerPixel == 1 && h->cupsBitsPerColor == 1 &&
        h->cupsColorOrder == CUPS_ORDER_CHUNKED && h->cupsColorSpace == CUPS_CSPACE_K &&
        h->cupsNumColors == 1 && h->cupsBytesPerLine == (h->cupsWidth + 7) / 8 &&
        h->HWResolution[0] == 600 && h->HWResolution[1] == 600 &&
        h->cupsMediaType <= 6 && h->cupsInteger[0] <= 1 &&
        h->cupsInteger[1] <= 63 && h->cupsInteger[2] <= 1 &&
        h->Margins[0] <= 65535 && h->Margins[1] <= 65535;
}

void page_set_dims(struct page_dims_s *dims, const struct cups_page_header2_s *header)
{
	if (!page_header_valid(header)) capt_fail("unsupported raster dimensions or format");
	dims->media_type = header->cupsMediaType;
	memcpy(dims->media_size, header->MediaType, sizeof(dims->media_size) - 1);
    dims->media_size[sizeof(dims->media_size) - 1] = '\0';
	dims->paper_width  = header->cupsWidth;  //header->PageSize[0] * header->HWResolution[0] / 72;
	dims->paper_height = header->cupsHeight; //header->PageSize[1] * header->HWResolution[1] / 72;
	dims->toner_save = header->cupsInteger[0];
	dims->ink_k = header->cupsInteger[1];
	dims->manual_duplex = header->cupsInteger[2];
	dims->line_size = header->PageSize[0];
	dims->num_lines = header->cupsHeight;
	dims->band_size = header->cupsRowCount;
	dims->margin_height = header->Margins[0];
	dims->margin_width = header->Margins[1];

	if (header->HWResolution[1] == 400)
	  dims->media_adapt  = 0x81;
	else
	  dims->media_adapt  = 0x11;
}
