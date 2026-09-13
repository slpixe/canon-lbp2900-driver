/* SPDX-License-Identifier: GPL-3.0-or-later
 * Synthetic raster fixture generator using real system CUPS, no printer.
 */
#include <cups/raster.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv) {
    if (argc!=4) return 2;
    unsigned width=(unsigned)strtoul(argv[1],NULL,10),height=(unsigned)strtoul(argv[2],NULL,10),pages=(unsigned)strtoul(argv[3],NULL,10);
    if (!width || width>8192 || !height || height>12000 || !pages || pages>10) return 2;
    cups_raster_t *r=cupsRasterOpen(STDOUT_FILENO,CUPS_RASTER_WRITE);
    if (!r) return 1;
    cups_page_header2_t h={0};h.cupsWidth=width;h.cupsHeight=height;
    h.PageSize[0]=(width+7)/8;h.PageSize[1]=842;h.cupsRowCount=70;
    h.cupsBitsPerPixel=h.cupsBitsPerColor=h.cupsNumColors=1;
    h.cupsColorSpace=CUPS_CSPACE_K;h.cupsColorOrder=CUPS_ORDER_CHUNKED;
    h.cupsBytesPerLine=(width+7)/8;h.HWResolution[0]=h.HWResolution[1]=600;
    h.cupsInteger[1]=28;strcpy(h.MediaType,"A4");
    unsigned char row[1024];
    for (unsigned p=0;p<pages;p++) {
        if (!cupsRasterWriteHeader2(r,&h)) return 1;
        for (unsigned y=0;y<height;y++) {
            for (unsigned x=0;x<h.cupsBytesPerLine;x++) row[x]=(unsigned char)((x+y*17+p*29)%256);
            if (cupsRasterWritePixels(r,row,h.cupsBytesPerLine)!=h.cupsBytesPerLine) return 1;
        }
    }
    cupsRasterClose(r);return 0;
}
