"""Inspect/dry-run installation policy without privilege or system writes."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parent.parent
for command in [ ['./setup.sh'], ['./install.sh', '--driver', '--dry-run'], ['./install.sh', '--menubar', '--dry-run'], ['./uninstall.sh', '--driver', '--dry-run'] ]:
    r = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, (command, r.stderr)
    assert 'sudo' not in r.stderr.lower()
for uri in ['usb://Other/Printer', 'ipp://example.invalid/printer', 'usb://Canon/LBP2900?serial=a\nother']:
    r = subprocess.run(['./install.sh', '--driver', '--uri', uri, '--dry-run'], cwd=root, capture_output=True, timeout=10)
    assert r.returncode != 0, uri
for path in [*root.glob('*.sh'), *root.glob('scripts/*.sh'), *root.glob('menubar/*.sh')]:
    content = path.read_text()
    assert 'com.apple.quarantine' not in content, path
    assert 'LaunchDaemons' not in content or path.name == 'doctor.sh', path
    assert 'csrutil' not in content and 'spctl --master-disable' not in content, path
assert not list((root/'prebuilt').rglob('rastertocapt'))
assert 'rastertocapt-lbp2900' in (root/'ppd/CanonLBP-2900-3000.ppd').read_text()
print('Installer choices, rejection and policy checks passed (no installation)')
