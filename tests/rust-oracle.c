/* SPDX-License-Identifier: GPL-3.0-or-later
 * Test-only C reference; never linked into the Rust filter.
 */
#include "hiscoa-compress.h"
#include "hiscoa-common.h"
#include "capt-status.h"
#include "capt-command.h"
#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void capt_sendrecv(uint16_t c,const void *b,size_t n,void *r,size_t *s) {(void)c;(void)b;(void)n;(void)r;(void)s;abort();}
int main(int argc,char **argv) {
    if (argc!=4) return 2;
    unsigned width=(unsigned)strtoul(argv[1],NULL,10),rows=(unsigned)strtoul(argv[2],NULL,10),last=(unsigned)strtoul(argv[3],NULL,10);
    if (!width || width>1024 || !rows || rows>256 || last>1) return 2;
    size_t n=(size_t)width*rows,capacity=2*n+16;
    uint8_t *input=calloc(1,n),*output=calloc(1,capacity);
    if (!input || !output || fread(input,1,n,stdin)!=n || getchar()!=EOF) return 2;
    size_t size=hiscoa_compress_band(output,capacity,input,width,rows,last,&hiscoa_default_params);
    if (!size || fwrite(output,1,size,stdout)!=size) return 1;
    free(input);free(output);return 0;
}
