"""Offline packet/header inventory. No network access or third-party packages.

Counts capture observations, not unique packets/requests. Socket ownership is
sampled and therefore only evidence of a possible process association.
"""
import argparse
import bisect
import collections
import csv
import datetime as dt
import ipaddress
import json
from pathlib import Path
import struct


def timestamp(value):
    return dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def utc(value):
    return dt.datetime.fromtimestamp(value, dt.timezone.utc).isoformat()


def packets(path, issues):
    """Read pcapng enhanced packet blocks, preserving timestamp resolution."""
    interfaces = []
    endian = '<'
    with path.open('rb') as stream:
        while header := stream.read(8):
            if len(header) != 8:
                raise ValueError(f'{path}: truncated block header')
            if header[:4] == b'\x0a\x0d\x0d\x0a':
                magic = stream.read(4)
                if magic not in (b'\x4d\x3c\x2b\x1a', b'\x1a\x2b\x3c\x4d'):
                    raise ValueError('Invalid pcapng byte order')
                endian = '<' if magic[0] == 0x4d else '>'
                prefix = magic
                interfaces = []
            else:
                prefix = b''
            kind, length = struct.unpack(endian+'II', header)
            if length < 12 or length % 4 or length > 64 * 1024 * 1024:
                raise ValueError('Invalid pcapng block length')
            body = prefix + stream.read(length - 8 - len(prefix))
            if len(body) != length-8 or struct.unpack(endian+'I', body[-4:])[0] != length:
                raise ValueError('Truncated or inconsistent pcapng block')
            body = body[:-4]
            if kind == 1:
                link, _, _ = struct.unpack_from(endian+'HHI', body)
                resolution, offset = 1e-6, 0
                pos = 8
                while pos + 4 <= len(body):
                    code, size = struct.unpack_from(endian+'HH', body, pos)
                    pos += 4
                    data = body[pos:pos+size]
                    if len(data) != size:
                        raise ValueError('Truncated interface option')
                    if code == 0:
                        break
                    if code == 9 and size == 1:
                        resolution = 2**-(data[0]&127) if data[0]&128 else 10**-data[0]
                    if code == 14 and size == 8:
                        offset = struct.unpack(endian+'q', data)[0]
                    pos += (size+3)//4*4
                interfaces.append((link, resolution, offset))
            elif kind == 6:
                interface, high, low, captured, original = struct.unpack_from(endian+'IIIII', body)
                if interface >= len(interfaces) or captured > len(body)-20:
                    raise ValueError('Invalid enhanced packet block')
                link, resolution, offset = interfaces[interface]
                yield (high*2**32+low)*resolution+offset, original, link, body[20:20+captured]
            elif kind not in (0x0a0d0d0a, 4, 5):
                issues[f'ignored_pcapng_block_{kind}'] += 1


def address(value):
    ip = ipaddress.ip_address(value.split('%')[0])
    return str(ip.ipv4_mapped or ip) if isinstance(ip, ipaddress.IPv6Address) else str(ip)


def decode(link, data):
    data = bytes(data)
    pos = 0
    if link == 1:
        if len(data) < 14:
            return None, 'short_ethernet'
        ether = int.from_bytes(data[12:14], 'big')
        pos = 14
        while ether in (0x8100, 0x88a8):
            if len(data) < pos+4:
                return None, 'short_vlan'
            ether = int.from_bytes(data[pos+2:pos+4], 'big'); pos += 4
        if ether not in (0x0800, 0x86dd):
            return None, 'non_ip'
    elif link not in (101, 228, 229):
        return None, f'unsupported_link_{link}'
    if len(data) <= pos:
        return None, 'short_ip'
    version = data[pos] >> 4
    start = pos
    if version == 4:
        if len(data) < pos+20:
            return None, 'short_ipv4'
        length = int.from_bytes(data[pos+2:pos+4], 'big')
        fragment = int.from_bytes(data[pos+6:pos+8], 'big')
        if fragment & 0x3fff:
            return None, 'fragmented_ipv4'
        proto = data[pos+9]
        src = str(ipaddress.ip_address(data[pos+12:pos+16]))
        dst = str(ipaddress.ip_address(data[pos+16:pos+20]))
        ihl = (data[pos] & 15)*4
        if ihl < 20:
            return None, 'invalid_ipv4_header'
        pos += ihl
    elif version == 6:
        if len(data) < pos+40:
            return None, 'short_ipv6'
        length = int.from_bytes(data[pos+4:pos+6], 'big')+40
        proto = data[pos+6]
        src = address(str(ipaddress.ip_address(data[pos+8:pos+24])))
        dst = address(str(ipaddress.ip_address(data[pos+24:pos+40])))
        pos += 40
        for _ in range(8):
            if proto not in (0, 43, 60, 51):
                break
            if len(data) < pos+2:
                return None, 'short_ipv6_extension'
            size = (data[pos+1]+2)*4 if proto == 51 else (data[pos+1]+1)*8
            proto = data[pos]; pos += size
        if proto == 44:
            return None, 'fragmented_ipv6'
    else:
        return None, 'unknown_ip_version'
    minimum = 20 if proto == 6 else 8
    if proto not in (6, 17):
        return None, f'ip_protocol_{proto}'
    if len(data) < pos+minimum:
        return None, 'short_transport'
    sport, dport = struct.unpack_from('!HH', data, pos)
    header = (data[pos+12] >> 4)*4 if proto == 6 else 8
    if header < minimum or length < pos-start+header:
        return None, 'invalid_transport_length'
    return {'protocol':'TCP' if proto == 6 else 'UDP', 'src':src, 'sport':sport,
            'dst':dst, 'dport':dport, 'payload_bytes':length-(pos-start)-header}, None


def owners(packet, sockets, game_pid):
    matches = set()
    for entry in sockets:
        if entry['protocol'] != packet['protocol']:
            continue
        for direction, local, port, remote, remote_port in (
            ('out', packet['src'], packet['sport'], packet['dst'], packet['dport']),
            ('in', packet['dst'], packet['dport'], packet['src'], packet['sport'])):
            if int(entry['port']) != port or address(entry['local']) not in (local, '0.0.0.0', '::'):
                continue
            if entry['protocol'] == 'TCP' and (address(entry['remote']) != remote or int(entry['remote_port']) != remote_port):
                continue
            matches.add((int(entry['pid']), direction))
    game = {(pid, direction) for pid, direction in matches if pid == game_pid}
    if not game:
        return 'unattributed', '-'
    if len(matches) != 1:
        return 'ambiguous', '-'
    return 'game_candidate', next(iter(game))[1]


def analyze(folder):
    events = [json.loads(line) for line in (folder/'events.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
    meta = next(e for e in events if e['type'] == 'metadata')
    samples = sorted((e for e in events if e['type'] == 'sockets'), key=lambda e: e['utc'])
    sample_times = [timestamp(e['utc']) for e in samples]
    phases = [(timestamp(e['utc']), e['phase']) for e in events if e['type'] == 'phase']
    ends = [timestamp(e['utc']) for e in events if e['type'] == 'end']
    issues = collections.Counter()
    flows = collections.defaultdict(lambda: [0, 0, 0])
    near = []
    for event in events:
        if event['type'] == 'mod_log' and event['text'].startswith('RESEED '):
            near.append({'earliest':event['earliest'], 'observed':event['utc'], 'event':event['text'].split(' active=')[0],
                         'game_candidate_out':0, 'game_candidate_in':0, 'other_observations':0})
    files = sorted(folder.glob('*.pcapng'))
    if not files:
        raise ValueError('No pcapng files. Convert the ETL segments with pktmon etl2pcap first.')
    count = 0
    for file in files:
        for when, original, link, data in packets(file, issues):
            count += 1
            packet, problem = decode(link, data)
            if problem:
                issues[problem] += 1
                continue
            phase = next((name for begin, name in reversed(phases) if when >= begin), 'outside')
            if ends and when > max(ends):
                phase = 'outside'
            index = bisect.bisect_left(sample_times, when)
            candidates = [i for i in (index-1,index) if 0 <= i < len(samples)]
            closest = min(candidates, key=lambda i: abs(sample_times[i]-when)) if candidates else None
            association, direction = 'unattributed', '-'
            if closest is not None and abs(sample_times[closest]-when) <= 3:
                association, direction = owners(packet, samples[closest]['sockets'], int(meta['game_pid']))
            else:
                issues['packet_without_nearby_socket_sample'] += 1
            key = (phase, association, direction, packet['protocol'], packet['src'], packet['sport'], packet['dst'], packet['dport'])
            values = flows[key]; values[0] += 1; values[1] += original; values[2] += packet['payload_bytes']
            for event in near:
                if timestamp(event['earliest'])-2 <= when <= timestamp(event['observed'])+2:
                    field = f'game_candidate_{direction}' if association == 'game_candidate' else 'other_observations'
                    event[field] += 1
    with (folder/'flows.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['phase','association','direction','protocol','src','src_port','dst','dst_port','observations','observed_wire_bytes','transport_payload_bytes'])
        for key, values in sorted(flows.items()):
            writer.writerow([*key,*values])
    (folder/'reroll-windows.json').write_text(json.dumps(near, indent=2), encoding='utf-8')
    lines = ['# Network observation report', '',
             '**Verdict: inconclusive about requests to official servers.**', '',
             'This is a timing and endpoint inventory, not decrypted HTTP or proof of causation.',
             'A game candidate is a tuple matching a sampled game socket within three seconds.',
             'Short-lived sockets may be missed; UDP port sharing, relays/proxies and NIC/offload',
             'duplication limit attribution. Endpoint ownership is unclassified, including every IP below.',
             'The capture covers all NIC traffic, not exclusively the game. Zero candidates is not proof of no game traffic.', '',
             f'Packet observations: {count}. Reseed log events observed: {len(near)}.',
             f'Clean timed completion: {any(e["type"] == "end" and e.get("completed") for e in events)}.', '',
             '| Phase | Duration (s) | Game candidate out | Game candidate in | Other TCP/UDP |',
             '|---|---:|---:|---:|---:|']
    for i, (begin, phase) in enumerate(phases):
        end = phases[i+1][0] if i+1 < len(phases) else (max(ends) if ends else begin)
        out = sum(v[0] for k,v in flows.items() if k[:3] == (phase,'game_candidate','out'))
        incoming = sum(v[0] for k,v in flows.items() if k[:3] == (phase,'game_candidate','in'))
        other = sum(v[0] for k,v in flows.items() if k[0] == phase and k[1] != 'game_candidate')
        lines.append(f'| {phase} | {end-begin:.1f} | {out} | {incoming} | {other} |')
    lines += ['', '## Capture/decoder limitations', '', '```json', json.dumps(issues, indent=2), '```', '',
              'Review pktmon.txt for capture errors/loss and components.json for adapter coverage.',
              'Review flows.csv for destinations and reroll-windows.json for observations within',
              'two seconds of each log observation interval (overlapping windows double-count).',
              'DNS snapshots are hints only; shared hosting does not establish an official service.',
              'The log timestamps describe when the collector read the line, not the exact native call time.',
              'Repeat idle/reroll comparisons before drawing even a correlation. Neither packet presence',
              'nor absence establishes application request content or server acceptance.', '']
    (folder/'report.md').write_text('\n'.join(lines), encoding='utf-8')
    return folder/'report.md'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    print(analyze(parser.parse_args().directory.resolve()))
