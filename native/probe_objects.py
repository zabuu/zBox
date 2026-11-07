"""Read-only check of the addresses zBoxBridge 0.1.12 adds for game objects.
Run: python probe_objects.py <path to WoW.exe>. Prints evidence; exits 1 on a mismatch.
Needs no extra packages and never runs or modifies the game."""
import struct, sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
pe = struct.unpack_from('<I', data, 60)[0]
ok = data[pe:pe+4] == b'PE\0\0' and struct.unpack_from('<I', data, pe+8)[0] == 0x4510B6DB
print('client 1.12.1.5875 image:', ok)
count = struct.unpack_from('<H', data, pe+6)[0]
opt = struct.unpack_from('<H', data, pe+20)[0]
sections = [struct.unpack_from('<IIII', data, pe+24+opt+i*40+8) for i in range(count)]
def raw(address):
    for vsize, virtual, rsize, rawptr in sections:
        if virtual <= address-0x400000 < virtual+rsize: return rawptr+address-0x400000-virtual
def va(offset):
    for vsize, virtual, rsize, rawptr in sections:
        if rawptr <= offset < rawptr+rsize: return offset-rawptr+virtual+0x400000
def at(address, n): o = raw(address); return data[o:o+n]

failures = []
# 1. Object right-click handler: thiscall, keeps ECX, one stack argument (ret 4).
head = at(0x5F8660, 16)
print('0x5F8660 starts:', head.hex(' '))
body = at(0x5F8660, 0x400)
ret4 = body.find(b'\xC2\x04\x00')
print('  first "ret 4" at +0x%X' % ret4 if ret4 >= 0 else '  no "ret 4" in the first 1 KB')
if not head.startswith(b'\x55\x8B\xEC'): failures.append('0x5F8660 is not a normal function start')
if ret4 < 0: failures.append('0x5F8660 does not return with ret 4')
if b'\x8B\xF1' not in body[:64] and b'\x8B\xF9' not in body[:64] and b'\x8B\xD9' not in body[:64]:
    failures.append('0x5F8660 does not keep ECX (this) early')
# Callers: who calls it (a world-click dispatcher should).
target = 0x5F8660
callers = []
for i in range(len(data)-5):
    if data[i] == 0xE8:
        rel = struct.unpack_from('<i', data, i+1)[0]
        v = va(i)
        if v and v+5+rel == target: callers.append(v)
print('  called from:', ', '.join('0x%X' % c for c in callers[:12]) or 'nowhere (maybe via vtable)')
# Unit right-click for comparison (already used by InteractNPC).
print('0x60BEA0 starts:', at(0x60BEA0, 8).hex(' '))
# 2. Mouseover GUID global: code must read it, and the "mouseover" unit token should use it.
needle = struct.pack('<I', 0xB4E2C8)
refs = []
start = 0
while True:
    i = data.find(needle, start)
    if i < 0: break
    v = va(i)
    if v: refs.append((v, data[i-2:i].hex(' ')))
    start = i+1
print('references to 0xB4E2C8:', len(refs))
for v, pre in refs[:15]: print('  0x%X  (bytes before: %s)' % (v, pre))
if not refs: failures.append('nothing references 0xB4E2C8')
# The neighbouring target GUID (0xB4E2D8) should be referenced too if the block is right.
print('references to 0xB4E2D8 (target GUID):', data.count(struct.pack('<I', 0xB4E2D8)))
print('RESULT:', 'OK' if not failures else 'MISMATCH: ' + '; '.join(failures))
sys.exit(1 if failures else 0)
