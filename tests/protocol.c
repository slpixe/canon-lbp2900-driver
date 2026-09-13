/* SPDX-License-Identifier: GPL-3.0-or-later
 * In-memory CUPS backend double. Never contacts a printer or print service. */
#include "capt-command.h"
#include "capt-status.h"
#include "runtime.h"
#include <cups/cups.h>
#include <cups/sidechannel.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static unsigned char packet[65535];
static size_t packet_size, offset, fragment = 3, split;
static int bad_id;
ssize_t cupsBackChannelRead(char *out, size_t n, double timeout) {
    assert(timeout > 0 && timeout <= 15.0);
    if (offset == packet_size) return 0;
    if (n > fragment) n = fragment;
    if (split && offset < split && n > split - offset) n = split - offset;
    if (n > packet_size - offset) n = packet_size - offset;
    memcpy(out, packet + offset, n); offset += n;
    return (ssize_t)n;
}
cups_sc_status_t cupsSideChannelDoRequest(cups_sc_command_t command,
                                          char *data, int *length, double timeout) {
    (void)timeout;
    if (command == CUPS_SC_CMD_GET_DEVICE_ID) {
        if (bad_id) *length = -1;
        else { strcpy(data, "MFG:Canon;MDL:LBP2900;"); *length = (int)strlen(data); }
    }
    return CUPS_SC_STATUS_OK;
}
static void make_packet(size_t n) {
    packet_size = n; offset = 0;
    memset(packet, 0x5a, n);
    packet[0] = 0xa8; packet[1] = 0xa0;
    packet[2] = n & 255; packet[3] = n >> 8;
}
int main(int argc, char **argv) {
    assert(argc == 2);
    if (!strcmp(argv[1], "status")) {
        struct capt_status_s s = {0}, before = {0};
        unsigned char bytes[64] = {0};
        for (size_t n=0;n<40;n++) {
            assert(!capt_decode_status(&s, bytes, n, true));
            assert(!memcmp(&s, &before, sizeof(s)));
        }
        for (size_t n=0;n<40;n++)
            assert(capt_decode_status(&s, bytes, n, false) == (n == 2 || n == 10));
        bytes[14] = 7; bytes[35] = 1;
        assert(capt_decode_status(&s, bytes, 40, true));
        assert(s.page_decoding == 7 && s.page_received == 256);
        assert(capt_decode_status(&s, bytes, 2, false));
        assert(s.page_decoding == 7); /* retain extended counters on basic update */
        return 0;
    }
    if (!strcmp(argv[1], "identify")) { assert(strstr(capt_identify(), "LBP2900")); return 0; }
    if (!strcmp(argv[1], "bad-id")) { bad_id=1; capt_identify(); return 2; }
    if (!strcmp(argv[1], "cancel")) { capt_cancelled=1; capt_check_cancel(); return 2; }
    if (!strcmp(argv[1], "deadline")) { capt_check_deadline(capt_now()-1, "test timeout"); return 2; }
    if (!strcmp(argv[1], "fragmentation")) {
        unsigned char fixture[56], out[64];
        FILE *f = fopen("tests/fixtures/lbp2900-ident.hex", "r"); assert(f);
        for (size_t i=0;i<sizeof(fixture);i++) { unsigned x; assert(fscanf(f, "%x", &x)==1 && x<=255); fixture[i]=(unsigned char)x; }
        fclose(f);
        /* Every two-fragment split, plus every fixed read size. A second reply
         * makes early acceptance visible as unread bytes, not just bad payload. */
        for (size_t mode=0;mode<2;mode++) for (size_t n=1;n<=56;n++) {
            memcpy(packet,fixture,56);
            memcpy(packet+56,"\xa1\xa1\x06\x00\x00\x00",6);
            packet_size=62; offset=0; split=mode==0?n:0; fragment=mode==1?n:65535;
            size_t capacity=sizeof(out);
            capt_sendrecv(CAPT_IDENT,NULL,0,out,&capacity);
            assert(capacity==52 && offset==56 && !memcmp(out,fixture+4,52));
            capacity=sizeof(out); split=0;
            capt_sendrecv(CAPT_IDENT,NULL,0,out,&capacity);
            assert(capacity==2 && offset==62);
        }
        return 0;
    }
    make_packet(44);
    unsigned char out[65535]; memset(out, 0xcc, sizeof(out));
    size_t capacity = sizeof(out);
    if (!strcmp(argv[1], "short")) packet_size = 12;
    if (!strcmp(argv[1], "wrong-command")) packet[0] = 0;
    if (!strcmp(argv[1], "bad-length")) packet[2] = 3;
    if (!strcmp(argv[1], "small-buffer")) capacity = 8;
    if (!strcmp(argv[1], "max")) { make_packet(65535); fragment = 65535; }
    if (!strcmp(argv[1], "bcd")) { make_packet(40); packet[2] = 0x40; fragment = 65535; }
    if (!strcmp(argv[1], "missing-capacity")) {
        capt_sendrecv(CAPT_CHKXSTATUS, NULL, 0, out, NULL); return 2;
    }
    capt_sendrecv(CAPT_CHKXSTATUS, NULL, 0, out, &capacity);
    assert(capacity == packet_size - 4);
    assert(out[capacity] == 0xcc);
    for (size_t i=0;i<capacity;i++) assert(out[i] == 0x5a);
    return 0;
}
