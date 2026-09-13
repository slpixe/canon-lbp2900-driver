"""Bounded offline regression tests. No printer, CUPS server or root access."""
import os
import subprocess
from pathlib import Path
os.environ['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1'
os.environ['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
positive = ['fragmented', 'max', 'bcd', 'identify', 'status']
negative = ['short', 'wrong-command', 'bad-length', 'small-buffer', 'missing-capacity', 'bad-id', 'cancel', 'deadline']
for case in positive + negative:
    result = subprocess.run(['build/tests/protocol', case], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == (0 if case in positive else 1), (case, result.returncode, result.stderr.decode())
    assert b'Sanitizer' not in result.stderr, (case, result.stderr)
    print('PASS', case)
with open('build/tests/codec.log', 'wb') as log:
    result = subprocess.run(['build/tests/codec'], stdout=subprocess.PIPE, stderr=log, timeout=60)
assert result.returncode == 0, Path('build/tests/codec.log').read_text()[-4000:]
print(result.stdout.decode().strip())

for identifier, expected in [('MFG:Canon;MDL:LBP2900;', 0), ('  MODEL:LBP2900;  ', 0), ('', 1), ('   \t  ', 1), ('MFG:Other;', 1), ('MDL:' + 'X'*500, 1)]:
    result = subprocess.run(['build/tests/device-id', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == expected and b'Sanitizer' not in result.stderr, (identifier, result.stderr)
print('Device identification regression checks passed')
