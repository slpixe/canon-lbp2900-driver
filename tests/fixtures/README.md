# Protocol evidence

`lbp2900-ident.hex` is the 56-byte LBP2900 response to command 0xA1A1, from the CC0/public-domain database compiled by Moses Chong, submitted by @freesun78. It contains capability data, no document contents or USB serial.

Source: https://github.com/mounaiban/studycapt/blob/422fa8423c3595e5f67f600387eece03497a0494/docs/a1a1.py
Original report: https://github.com/agalakhov/captdriver/issues/7#issuecomment-649788191

The length field `38 00` means 56 bytes in little-endian binary, not 38 decimal. This is a published device fixture, not a new local capture. Tests must accept every fragmentation of it and consume the full reply before a following reply. Other generated test packets are synthetic.
