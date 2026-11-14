#!/usr/bin/env python3
"""Inject the built arm64 patch into the supplied, decrypted Turrit IPA."""
import argparse
import hashlib
import plistlib
import struct
import zipfile
from pathlib import Path

BASE_SHA256 = 'd4424474abf9c7933b146a4a5ef6deda48d30ccf69675dd08eede0bb67ec6df8'


def inject(data, install_name):
    data = bytearray(data)
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin arm64 Mach-O'
    ncmds, sizeofcmds = struct.unpack_from('<II', data, 16)
    end = 32 + sizeofcmds
    first_section = len(data)
    offset = 32
    for _ in range(ncmds):
        command, size = struct.unpack_from('<II', data, offset)
        if command in (0x21, 0x2c):
            assert struct.unpack_from('<I', data, offset + 16)[0] == 0, 'Encrypted input is unsupported'
        if command == 0x19:
            for i in range(struct.unpack_from('<I', data, offset + 64)[0]):
                section = offset + 72 + i * 80
                file_offset = struct.unpack_from('<I', data, section + 48)[0]
                if file_offset:
                    first_section = min(first_section, file_offset)
        if command in (0xc, 0x80000018, 0x8000001f):
            start = offset + struct.unpack_from('<I', data, offset + 8)[0]
            assert data[start:data.index(0, start)].decode() != install_name, 'Already patched'
        offset += size
    name = install_name.encode() + b'\0'
    size = (24 + len(name) + 7) & ~7
    assert end + size <= first_section, 'Insufficient Mach-O load-command padding'
    assert not any(data[end:end + size]), 'Header padding is not empty'
    data[end:end + size] = struct.pack('<IIIIII', 0xc, size, 24, 0, 0x10000, 0x10000) + name + bytes(size - 24 - len(name))
    struct.pack_into('<II', data, 16, ncmds + 1, sizeofcmds + size)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('dylib', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert hashlib.sha256(args.ipa.read_bytes()).hexdigest() == BASE_SHA256, 'This patch targets the supplied Turrit 1.5.5 IPA only'
    library = args.dylib.read_bytes()
    assert library[:4] == b'\xcf\xfa\xed\xfe', 'Build the arm64 iOS dylib first'
    with zipfile.ZipFile(args.ipa) as src, zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as dst:
        app = 'Payload/Turrit.app/'
        main_info = plistlib.loads(src.read(app + 'Info.plist'))
        share = app + 'PlugIns/TurritShareExtension.appex/'
        share_info = plistlib.loads(src.read(share + 'Info.plist'))
        executables = {
            app + main_info['CFBundleExecutable']: '@executable_path/Frameworks/AccessiGram.dylib',
            share + share_info['CFBundleExecutable']: '@executable_path/../../Frameworks/AccessiGram.dylib',
        }
        for entry in src.infolist():
            if '/_CodeSignature/' in entry.filename or entry.filename.endswith('/embedded.mobileprovision'):
                continue
            data = src.read(entry)
            if entry.filename in executables:
                data = inject(data, executables[entry.filename])
            if entry.filename in (app + 'Info.plist', share + 'Info.plist'):
                info = plistlib.loads(data)
                info['CFBundleDisplayName'] = 'Accessi gram'
                info['CFBundleName'] = 'Accessi gram'
                info['AccessiGramPatchVersion'] = '0.2.6'
                data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
            # A localized InfoPlist name takes precedence over the main plist.
            if entry.filename.startswith(app) and entry.filename.endswith('/InfoPlist.strings') and '/PlugIns/' not in entry.filename:
                if data.startswith(b'bplist'):
                    localized = plistlib.loads(data)
                    for key in ('CFBundleDisplayName', 'CFBundleName'):
                        if key in localized:
                            localized[key] = 'Accessi gram'
                    data = plistlib.dumps(localized, fmt=plistlib.FMT_BINARY)
            dst.writestr(entry, data)
        dst.writestr(app + 'Frameworks/AccessiGram.dylib', library)
    print(f'{args.output}: unsigned IPA; re-sign the app, frameworks and extensions before installation')


if __name__ == '__main__':
    main()
