/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once
#include <signal.h>
extern volatile sig_atomic_t capt_cancelled;
void capt_check_cancel(void);
_Noreturn void capt_fail(const char *message);
double capt_now(void);
void capt_check_deadline(double deadline, const char *message);
void capt_delay(unsigned milliseconds);
void capt_pause(void);
