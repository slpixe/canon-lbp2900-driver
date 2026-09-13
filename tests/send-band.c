/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "generic-ops.h"
#include "printer.h"
#include "capt-command.h"
#include "hiscoa-common.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned sends, basic, extended;
static const uint8_t *expected;
static size_t remaining;
void capt_wait_ready(void) { assert(sends == 1); ++basic; }
void capt_wait_xready_only(void) { assert(sends == 1); ++extended; }
void capt_send(uint16_t command,const void *data,size_t size) {
    assert(command == CAPT_PRINT_DATA);
    assert(data == expected && size == (remaining > 0xff00 ? 0xff00 : remaining));
    if (sends == 1) assert(basic + extended == 1);
    expected += size; remaining -= size; ++sends;
}
static void check(void (*send)(struct printer_state_s *,const void *,size_t),bool xstatus) {
    size_t size = 2*0xff00+1;
    uint8_t *data = calloc(1,size); assert(data);
    struct printer_state_s state = {.isend=14};
    sends=basic=extended=0;expected=data;remaining=size;
    send(&state,data,size);
    assert(sends==3 && state.isend==17 && remaining==0);
    assert(extended==(unsigned)xstatus && basic==(unsigned)!xstatus);
    free(data);
}
int main(void) {
    check(ops_send_band_hiscoa,false);
    check(ops_send_band_hiscoa_xstatus,true);
    puts("Transfer chunking and model-specific status polling checks passed");
    return 0;
}
