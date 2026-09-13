/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "hiscoa-compress.h"
#include "hiscoa-common.h"
#include "paper.h"
#include "hiscoa-decompress.h"
#include <cups/raster.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
static uint32_t seed = 7;
static uint8_t random_byte(void) { seed = seed * 1664525u + 1013904223u; return seed >> 24; }
int main(void) {
    unsigned widths[] = {1, 8, 17, 592, 1024}, rows[] = {1, 2, 70, 256};
    for (size_t w=0; w<5; w++) for (size_t r=0; r<4; r++) for (unsigned pattern=0;pattern<4;pattern++) {
        size_t n = widths[w] * rows[r], cap = 2*n+16;
        uint8_t *in=malloc(n), *out=calloc(1,cap), *decoded=calloc(1,n);
        assert(in && out && decoded);
        for (size_t i=0;i<n;i++) in[i] = pattern == 0 ? 0 : pattern == 1 ? 255 : pattern == 2 ? (i%2 ? 0xaa : 0x55) : random_byte();
        size_t size=hiscoa_compress_band(out,cap,in,widths[w],rows[r],0,&hiscoa_default_params);
        assert(size > 0 && size <= cap);
        const void *p=out; size_t remaining=size, result_size=n;
        assert(hiscoa_decompress_band(&p,&remaining,decoded,&result_size,widths[w],&hiscoa_default_params)==0);
        if (result_size!=n || remaining || memcmp(in,decoded,n)) {
            fprintf(stderr, "roundtrip failure width=%u rows=%u pattern=%u input=%zu output=%zu compressed=%zu remaining=%zu\n", widths[w],rows[r],pattern,n,result_size,size,remaining);
            for(size_t i=0;i<n;i++) if(in[i]!=decoded[i]) {fprintf(stderr,"first mismatch at %zu: %u != %u\n",i,in[i],decoded[i]);break;}
            return 1;
        }
        assert(hiscoa_compress_band(out,1,in,widths[w],rows[r],0,&hiscoa_default_params)==0);
        free(in); free(out); free(decoded);
    }
    uint8_t in=0,out=0;
    assert(!hiscoa_compress_band(&out,1,&in,0,1,0,&hiscoa_default_params));
    assert(!hiscoa_compress_band(&out,1,&in,1,0,0,&hiscoa_default_params));
    cups_page_header2_t h={0};
    h.cupsWidth=4736; h.cupsHeight=6900; h.PageSize[0]=595; h.PageSize[1]=842;
    h.cupsRowCount=70; h.cupsBitsPerPixel=h.cupsBitsPerColor=h.cupsNumColors=1;
    h.cupsColorSpace=CUPS_CSPACE_K; h.cupsColorOrder=CUPS_ORDER_CHUNKED;
    h.cupsBytesPerLine=592; h.HWResolution[0]=h.HWResolution[1]=600;
    assert(page_header_valid(&h));
    cups_page_header2_t good=h;
    h.cupsRowCount=0; assert(!page_header_valid(&h)); h=good;
    h.PageSize[0]=UINT32_MAX; assert(!page_header_valid(&h)); h=good;
    h.cupsBitsPerPixel=0; assert(!page_header_valid(&h)); h=good;
    h.cupsBytesPerLine=UINT32_MAX; assert(!page_header_valid(&h)); h=good;
    h.cupsHeight=UINT32_MAX; assert(!page_header_valid(&h)); h=good;
    memset(h.MediaType,'X',sizeof(h.MediaType));
    struct page_dims_s dims={0}; page_set_dims(&dims,&h);
    assert(dims.media_size[63]=='\0');
    puts("80 compressor round-trips and raster validation checks passed");
}
