/* SPDX-License-Identifier: GPL-3.0-or-later
 * Exercise adapter buffer contracts under ASan/UBSan using real CUPS raster I/O.
 */
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
void *lbp_raster_open(int);
void lbp_raster_close(void *);
int lbp_raster_header(void *,uint32_t *,size_t,uint8_t *,size_t);
int lbp_raster_line(void *,uint8_t *,size_t);
int lbp_device_id(uint8_t *,size_t);
int lbp_back_read(uint8_t *,size_t,double);
int lbp_write(const uint8_t *,size_t);
int lbp_timestamp(uint16_t *,size_t);
int main(int argc,char **argv) {
    assert(argc==2);
    int fd=open(argv[1],O_RDONLY); assert(fd>=0);
    void *r=lbp_raster_open(fd);assert(r);
    struct {uint32_t before,values[20],after;} v={0xdeadbeef,{0},0x12345678};
    struct {uint8_t before,bytes[64],after;} media={0x12,{0},0x34};
    assert(lbp_raster_header(r,v.values,19,media.bytes,64)==-1);
    assert(lbp_raster_header(r,v.values,20,media.bytes,63)==-1);
    assert(lbp_raster_header(r,v.values,20,media.bytes,64)==1);
    assert(v.before==0xdeadbeef && v.after==0x12345678 && media.before==0x12 && media.after==0x34);
    assert(v.values[0]==8 && v.values[1]==2 && v.values[2]==1 && v.values[4]==70);
    assert(v.values[5]==1 && v.values[6]==1 && v.values[7]==0 && v.values[8]==3);
    assert(v.values[10]==1 && v.values[11]==600 && v.values[15]==28);
    assert(!memcmp(media.bytes,"A4",2));
    uint8_t row[3]={0xaa,0,0xbb};
    assert(lbp_raster_line(r,row+1,0)==-1);
    assert(lbp_raster_line(r,row+1,1025)==-1);
    assert(lbp_raster_line(r,row+1,1)==0 && row[1]==0);
    assert(lbp_raster_line(r,row+1,1)==0 && row[1]==17);
    assert(row[0]==0xaa && row[2]==0xbb);
    assert(lbp_raster_header(r,v.values,20,media.bytes,64)==0);
    lbp_raster_close(r);
    assert(fcntl(fd,F_GETFD)>=0); /* Raster close must not close caller's fd. */
    close(fd);
    uint8_t data[1]={0};uint16_t timestamp[6];
    assert(lbp_device_id(data,1)==-1);
    assert(lbp_back_read(data,0,1)==-1);
    assert(lbp_back_read(data,1,0)==-1);
    assert(lbp_write(data,1)==-1);
    assert(lbp_timestamp(timestamp,5)==-1);
    assert(lbp_timestamp(timestamp,6)==0);
    puts("PASS adapter buffer/ownership contracts under sanitizers");
    return 0;
}
