/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "std.h"
#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>
volatile sig_atomic_t capt_cancelled;
_Noreturn void capt_fail(const char *message) {
    fprintf(stderr, "ERROR: CAPT: %s\n", message);
    exit(1);
}
void capt_check_cancel(void) {
    if (capt_cancelled) capt_fail("job cancelled");
}
double capt_now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) capt_fail("clock unavailable");
    return t.tv_sec + t.tv_nsec / 1000000000.0;
}
void capt_check_deadline(double deadline, const char *message) {
    capt_check_cancel();
    if (capt_now() >= deadline) capt_fail(message);
}
void capt_delay(unsigned milliseconds) {
    struct timespec t = { .tv_sec = milliseconds / 1000, .tv_nsec = (milliseconds % 1000) * 1000000L };
    capt_check_cancel();
    while (nanosleep(&t, &t) && errno == EINTR) capt_check_cancel();
    capt_check_cancel();
}

void capt_pause(void) { capt_delay(100); }
