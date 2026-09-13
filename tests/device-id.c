/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "printer.h"
#include <assert.h>
#include <string.h>
static const char *identifier;
const char *capt_identify(void) { return identifier; }
int main(int argc, char **argv) {
    assert(argc == 2);
    static const struct printer_ops_s ops = {0};
    __printer_register_ops("LBP2900", &ops, WORKS);
    identifier = argv[1];
    assert(printer_detect() == &ops);
    return 0;
}
