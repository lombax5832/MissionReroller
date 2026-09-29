"""Synthetic evidence only; never opens a socket or starts a capture."""
import collections
import importlib.util
import ipaddress
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('network', Path(__file__).resolve().parents[1]/'scripts/analyze_network.py')
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)


def block(kind, body, endian='<'):
    body += b'\0' * (-len(body) % 4)
    return struct.pack(endian+'II', kind, len(body)+12) + body + struct.pack(endian+'I', len(body)+12)


def capture(data, endian='<'):
    section = block(0x0a0d0d0a, struct.pack(endian+'IHHq', 0x1a2b3c4d, 1, 0, -1), endian)
    interface = block(1, struct.pack(endian+'HHI', 1, 0, 128), endian)
    ticks = 1_000_000
    packet = block(6, struct.pack(endian+'IIIII', 0, 0, ticks, len(data), len(data))+data, endian)
    return section+interface+packet


def ipv4_tcp():
    ip = bytearray(20); ip[0]=0x45; ip[2:4]=struct.pack('!H',43); ip[9]=6
    ip[12:16]=ipaddress.ip_address('192.0.2.1').packed
    ip[16:20]=ipaddress.ip_address('198.51.100.1').packed
    tcp=bytearray(20); tcp[:4]=struct.pack('!HH',50000,443); tcp[12]=0x50
    return b'\0'*12+b'\x08\x00'+ip+tcp+b'abc'


class NetworkTests(unittest.TestCase):
    def test_endian_and_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'a.pcapng'
            for endian in ('<','>'):
                path.write_bytes(capture(ipv4_tcp(),endian))
                records=list(network.packets(path,collections.Counter()))
                self.assertEqual(records[0][0],1)
                self.assertEqual(records[0][3],ipv4_tcp())
            path.write_bytes(capture(ipv4_tcp())[:-1])
            with self.assertRaises(ValueError):
                list(network.packets(path,collections.Counter()))

    def test_decode_and_ownership(self):
        packet, issue=network.decode(1,ipv4_tcp())
        self.assertIsNone(issue)
        self.assertEqual(packet['payload_bytes'],3)
        socket={'protocol':'TCP','pid':123,'local':'192.0.2.1','port':50000,'remote':'198.51.100.1','remote_port':443}
        self.assertEqual(network.owners(packet,[socket],123),('game_candidate','out'))
        self.assertEqual(network.owners(packet,[socket,dict(socket,pid=456)],123),('ambiguous','-'))
        self.assertEqual(network.owners(dict(packet,sport=50001),[socket],123),('unattributed','-'))
        self.assertEqual(network.decode(999,b'')[1],'unsupported_link_999')

    def test_ipv6_udp_and_fragments(self):
        ip=bytearray(40); ip[0]=0x60; ip[4:6]=struct.pack('!H',8); ip[6]=17
        ip[8:24]=ipaddress.ip_address('2001:db8::1').packed
        ip[24:40]=ipaddress.ip_address('2001:db8::2').packed
        udp=struct.pack('!HHHH',50000,443,8,0)
        packet,issue=network.decode(101,ip+udp)
        self.assertIsNone(issue)
        self.assertEqual(packet['dst'],'2001:db8::2')
        self.assertEqual(packet['payload_bytes'],0)
        ip[6]=44
        self.assertEqual(network.decode(101,ip+udp)[1],'fragmented_ipv6')

    def test_report_preserves_uncertainty(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            events=[{'type':'metadata','game_pid':123},
                    {'type':'phase','utc':network.utc(0),'phase':'baseline'},
                    {'type':'phase','utc':network.utc(.5),'phase':'reroll'},
                    {'type':'sockets','utc':network.utc(1),'sockets':[{'protocol':'TCP','pid':123,'local':'192.0.2.1','port':50000,'remote':'198.51.100.1','remote_port':443}]},
                    {'type':'mod_log','earliest':network.utc(.5),'utc':network.utc(1),'text':'RESEED 1 before_seed=7 active=private'},
                    {'type':'end','utc':network.utc(2),'completed':True}]
            (root/'events.jsonl').write_text('\n'.join(map(json.dumps,events)),encoding='utf-8')
            (root/'traffic.pcapng').write_bytes(capture(ipv4_tcp()))
            report=network.analyze(root).read_text()
            self.assertIn('inconclusive',report)
            self.assertIn('| reroll | 1.5 | 1 | 0 | 0 |',report)
            windows=json.loads((root/'reroll-windows.json').read_text())
            self.assertEqual(windows[0]['game_candidate_out'],1)
            self.assertNotIn('private',json.dumps(windows))
            # No socket evidence must never turn into a no-network conclusion.
            events=[e for e in events if e['type']!='sockets']
            (root/'events.jsonl').write_text('\n'.join(map(json.dumps,events)),encoding='utf-8')
            report=network.analyze(root).read_text()
            self.assertIn('inconclusive',report)
            self.assertIn('packet_without_nearby_socket_sample',report)


if __name__=='__main__':
    unittest.main()
