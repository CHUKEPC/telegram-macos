import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--derived-data', type=Path, required=True)
parser.add_argument('--rnoise', type=Path)
args = parser.parse_args()
repo = args.repo.resolve()
source = Path(__file__).resolve().parents[3]
for relative in [
    'packages/StarsUI/Sources/StarsUI/StarTransactionTabsRowItem.swift',
    'packages/TGUIKit/Sources/GlassSegmentView.swift',
]:
    if (repo / relative).read_bytes() != (source / relative).read_bytes():
        raise SystemExit(f'Integrate the changed source before testing: {relative}')

tests = repo / 'packages/ChatUI/Tests/ChatUITests'
if not (tests / 'UITestBootstrap.swift').is_file():
    raise SystemExit('The populated checkout must include the existing ChatUITests offscreen bootstrap')
flags = ['-lbz2', '-liconv']
if args.rnoise:
    flags.append(str(args.rnoise.resolve()))
for relative in [
    'libvpx/build/libvpx/lib',
    'ffmpeg/build/ffmpeg/lib',
    'libopus/build/libopus/lib',
    'libwebp/build/libwebp/lib',
    'Mozjpeg/build',
    'openssl/build/openssl/lib',
    'webrtc/build/webrtc',
    'OpenH264/build/output/lib',
    'dav1d/build/dav1d/lib',
    'tde2e/build/tde2e/lib',
]:
    libraries = sorted((repo / 'core-xprojects' / relative).glob('*.a'))
    if not libraries:
        raise SystemExit(f'Missing native libraries: {relative}')
    flags.extend(str(path) for path in libraries)

fixture = tests / 'StarTransactionTabsTests.swift'
previous = fixture.read_bytes() if fixture.exists() else None
try:
    fixture.write_bytes(Path(__file__).with_name(fixture.name).read_bytes())
    result = subprocess.run([
        'xcodebuild', 'test',
        '-workspace', str(repo / 'Telegram-Mac.xcworkspace'),
        '-scheme', 'ChatUITests',
        '-destination', 'platform=macOS,arch=arm64',
        '-derivedDataPath', str(args.derived_data.resolve()),
        '-parallel-testing-enabled', 'NO',
        '-only-testing:ChatUITests/StarTransactionTabsTests',
        'OTHER_LDFLAGS=$(inherited) ' + ' '.join(flags),
        'CODE_SIGN_IDENTITY=', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=NO',
    ], cwd=repo)
finally:
    if previous is None:
        fixture.unlink()
    else:
        fixture.write_bytes(previous)
raise SystemExit(result.returncode)
