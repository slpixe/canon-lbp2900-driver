"""Inspect an expanded development package; never run Installer."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parent.parent
version = (root/'VERSION').read_text().strip()
package = root/'dist'/f'canon-lbp2900-driver-{version}-UNSIGNED.pkg'
with tempfile.TemporaryDirectory(dir=root/'build') as temporary:
    expanded = Path(temporary)/'expanded'
    subprocess.run(['pkgutil', '--expand-full', str(package), str(expanded)], check=True)
    distribution = ET.parse(expanded/'Distribution').getroot()
    assert distribution.find('options').get('hostArchitectures') == 'arm64'
    assert distribution.find('volume-check/allowed-os-versions/os-version').get('min') == '15.0'
    assert not list(expanded.rglob('Scripts'))
    payloads = list(expanded.rglob('Payload'))
    assert len(payloads) == 1
    payload = payloads[0]
    files = sorted(str(p.relative_to(payload)) for p in payload.rglob('*') if p.is_file())
    assert files == ['Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Slpixe.ppd', 'usr/libexec/cups/filter/rastertocapt-lbp2900'], files
    for p in payload.rglob('*'): assert not p.is_symlink(), p
    assert (payload/files[0]).stat().st_mode & 0o777 == 0o644
    assert (payload/files[1]).stat().st_mode & 0o777 == 0o755
print('Package has exactly the two intended files, expected modes, no scripts, OS/CPU gating')

payload = root/'build/LBP2900Progress.app/Contents/Resources/DriverPayload'
assert sorted(p.name for p in payload.iterdir()) == ['CanonLBP2900-Slpixe.ppd', 'install-driver.sh', 'rastertocapt-lbp2900']
assert (payload/'install-driver.sh').read_bytes() == (root/'scripts/install-driver.sh').read_bytes()
assert (payload/'rastertocapt-lbp2900').read_bytes() == (root/'build/rastertocapt-lbp2900').read_bytes()
print('Setup app contains only fresh C payload and reviewed helper; no stale Rust payload')
