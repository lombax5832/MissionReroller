"""List the native widgets of the galactic map screen, read through Memory Explorer.

Development tool. The game must be running with the Memory Explorer addon,
the galactic map open, and no other Memory Explorer client connected. Only
reads are made, through the addon's bridge.

The map screen is one large native object. Know Your Constellation reads two
of its widgets by fixed offset (the planet frame at 349072, a second frame at
280528); this survey scans the whole object for records with the same shape
and prints where each visible one sits on screen, so the widget that draws
the bottom-left BACK hint can be found and its offset pinned in
src/prediction_dialog_runtime.lua. Positions are in screen pixels with the
origin at the bottom-left corner, as the engine's Gui reports them.
"""
import os
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'MemoryExplorer/server'))
import memory_mcp as mcp

MANAGER, REGISTRY, KIND = 0x3326e68, 25224, 226
SCREENS, STACK = 0x347ce28, 0x429c
RECORD, LIMIT, PAGE = 164, 1 << 20, 4096


def main(bottom='0.25', left='0.5'):
    bottom, left = float(bottom), float(left)
    bridge = mcp.Bridge(Path(os.environ['LOCALAPPDATA']) / 'CowboyBingus/Helldivers2/Logs')
    bridge.acquire()
    session = bridge.call('status')['session']
    modules = {m['name']: int(m['base'], 16) for m in bridge.call('modules')['modules']}
    game = modules['game.dll']

    def read(address, size):
        reply = mcp.call_tool(bridge, 'hd2_read', {'session': session, 'address': hex(address), 'size': size})
        data = bytes.fromhex(reply['hex'])
        assert len(data) == size, 'short read'
        return data

    def pointer(address):
        value = struct.unpack('<Q', read(address, 8))[0]
        assert 0x10000 <= value < 0x800000000000, 'missing pointer at %x' % address
        return value

    stack = read(pointer(game + SCREENS) + STACK, 24)
    depth = struct.unpack_from('<I', stack, 20)[0]
    top = struct.unpack_from('<I', stack, 4 * (depth - 1))[0] if 1 <= depth <= 5 else None
    print('screen stack depth=%s top=%s (15 is the galactic map)' % (depth, top))
    if top != 15:
        raise SystemExit('Open the galactic map first')
    entry = read(pointer(game + MANAGER) + REGISTRY, 24)
    count, kind = struct.unpack_from('<I', entry, 0)[0], struct.unpack_from('<I', entry, 16)[0]
    assert count == 1 and kind == KIND, 'map screen registry not as expected: count=%d kind=%d' % (count, kind)
    owner = struct.unpack_from('<Q', entry, 8)[0]
    print('map screen object at %#x' % owner)

    # Read the object in large chunks, then page by page once a chunk fails,
    # until a page is unreadable or the limit ends.
    data, chunk = bytearray(), 65536
    while len(data) < LIMIT:
        try:
            data += read(owner + len(data), chunk)
        except Exception as error:  # noqa: BLE001 - the first unreadable page ends the object
            if chunk > PAGE:
                chunk = PAGE
                continue
            print('stopped reading at +%d: %s' % (len(data), error))
            break
    print('scanned %d bytes' % len(data))

    def widget(offset):
        record = data[offset:offset + RECORD]
        if len(record) < RECORD:
            return None
        flags = struct.unpack_from('<I', record, 0)[0]
        w, h = struct.unpack_from('<ff', record, 36)
        local_opacity, opacity = struct.unpack_from('<f', record, 68)[0], struct.unpack_from('<f', record, 84)[0]
        sx, sy = struct.unpack_from('<f', record, 100)[0], struct.unpack_from('<f', record, 140)[0]
        x, y = struct.unpack_from('<f', record, 148)[0], struct.unpack_from('<f', record, 156)[0]
        values = (w, h, local_opacity, opacity, sx, sy, x, y)
        if any(v != v for v in values):
            return None
        if not (0.3 <= sx <= 4 and abs(sx - sy) <= 0.01):
            return None
        if not (2 <= w <= 4096 and 2 <= h <= 4096 and 0 <= x <= 8192 and 0 <= y <= 8192):
            return None
        if not (0 <= local_opacity <= 1.01 and 0 <= opacity <= 1.01):
            return None
        return {'offset': offset, 'visible': bool(flags & 0x10), 'opacity': opacity,
                'x': x, 'y': y, 'w': w * sx, 'h': h * sy, 'scale': sx}

    found = [w for w in (widget(o) for o in range(0, len(data) - RECORD, 4)) if w]
    known = {349072: 'KYC planet frame', 280528: 'KYC second frame', 526048: 'KYC preview'}
    print('%d widget-shaped records, %d visible' % (len(found), sum(w['visible'] for w in found)))
    # Widgets are nested: a child record lies inside its parent, so a hit at
    # every 4 bytes is normal. The extent of the visible ones bounds the screen.
    width = max((w['x'] + w['w'] for w in found if w['visible']), default=0)
    height = max((w['y'] + w['h'] for w in found if w['visible']), default=0)
    print('visible extent suggests a %.0f x %.0f screen' % (width, height))
    print()
    print('Visible widgets in the bottom %.0f%% and left %.0f%% of the screen, lowest first:' % (bottom * 100, left * 100))
    print('%9s %8s %8s %8s %8s %6s  %s' % ('offset', 'x', 'y', 'w', 'h', 'scale', 'note'))
    corner = [w for w in found if w['visible'] and w['opacity'] > 0.5
              and w['y'] + w['h'] <= height * bottom and w['x'] <= width * left]
    for w in sorted(corner, key=lambda w: (w['y'], w['x'])):
        print('%9d %8.1f %8.1f %8.1f %8.1f %6.3f  %s' % (w['offset'], w['x'], w['y'], w['w'], w['h'], w['scale'],
                                                        known.get(w['offset'], '')))
    print()
    print('Known Know Your Constellation offsets for comparison:')
    for offset, note in known.items():
        w = widget(offset)
        print('%9d %s: %s' % (offset, note, 'x=%.1f y=%.1f w=%.1f h=%.1f visible=%s' % (
            w['x'], w['y'], w['w'], w['h'], w['visible']) if w else 'no widget-shaped record'))
    out = ROOT / 'artifacts' / 'map-widgets.txt'
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open('w', encoding='ascii') as file:
        for w in sorted(found, key=lambda w: w['offset']):
            file.write('%d %d %.3f %.1f %.1f %.1f %.1f %.3f\n' % (
                w['offset'], w['visible'], w['opacity'], w['x'], w['y'], w['w'], w['h'], w['scale']))
    print('all records written to %s' % out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(*sys.argv[1:]))
