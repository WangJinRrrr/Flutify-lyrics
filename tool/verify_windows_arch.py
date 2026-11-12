"""Reject mislabeled Windows packages, including wrong-architecture native DLLs."""
import argparse
from pathlib import Path
import struct


def machine_type(path):
    with path.open('rb') as binary:
        if binary.read(2) != b'MZ':
            raise ValueError(f'{path.name}: missing DOS header')
        binary.seek(0x3C)
        offset = struct.unpack('<I', binary.read(4))[0]
        binary.seek(offset)
        if binary.read(4) != b'PE\0\0':
            raise ValueError(f'{path.name}: missing PE header')
        return struct.unpack('<H', binary.read(2))[0]


def verify(directory, architecture):
    expected = {'x64': 0x8664, 'arm64': 0xAA64}[architecture]
    binaries = sorted(p for p in directory.rglob('*') if p.suffix.lower() in {'.exe', '.dll'})
    if not any(p.suffix.lower() == '.exe' for p in binaries):
        raise ValueError(f'No executable found in {directory}')
    if not any(p.name.lower() == 'libmpv-2.dll' for p in binaries):
        raise ValueError('libmpv-2.dll is missing')
    errors = []
    for binary in binaries:
        actual = machine_type(binary)
        if actual != expected:
            errors.append(f'{binary.relative_to(directory)}: 0x{actual:04X}, expected 0x{expected:04X}')
    if errors:
        raise ValueError('\n'.join(errors))
    print(f'Verified {len(binaries)} Windows {architecture} EXE/DLL files.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('architecture', choices=['x64', 'arm64'])
    args = parser.parse_args()
    verify(args.directory, args.architecture)
