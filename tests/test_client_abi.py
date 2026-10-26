"""Read-only ABI checks against the supported client image; does not run WoW."""
from pathlib import Path
import struct
import sys
import capstone

client = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[4] / "WoW.exe"
data = client.read_bytes()
pe = struct.unpack_from('<I', data, 60)[0]
assert data[pe:pe+4] == b'PE\0\0'
assert struct.unpack_from('<H', data, pe+4)[0] == 0x14c
assert struct.unpack_from('<I', data, pe+8)[0] == 0x4510B6DB
assert struct.unpack_from('<I', data, pe+24+56)[0] == 0x92B000
count = struct.unpack_from('<H', data, pe+6)[0]
opt = struct.unpack_from('<H', data, pe+20)[0]
sections = [struct.unpack_from('<IIII', data, pe+24+opt+i*40+8) for i in range(count)]
decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)

def instructions(address, size):
    for virtual_size, virtual, raw_size, raw in sections:
        if virtual <= address-0x400000 < virtual+raw_size:
            offset=raw+address-0x400000-virtual
            return [(i.mnemonic,i.op_str) for i in decoder.disasm(data[offset:offset+size],address)]
    raise AssertionError('Address outside image')

lookup=instructions(0x464870,30)
assert ('mov','eax, dword ptr [ebp + 8]') in lookup
assert ('mov','ecx, dword ptr [ebp + 0xc]') in lookup
assert ('ret','8') in lookup
right=instructions(0x60BEA0,100)
assert ('mov','edi, ecx') in right
assert ('ret','4') in instructions(0x60C25F,12)
facing=instructions(0x7C6F30,60)
assert ('mov','esi, ecx') in facing
assert ('fld','dword ptr [esi + 0x1c]') in facing
assert ('fsubr','dword ptr [ebp + 8]') in facing
assert ('ret','4') in facing
send=instructions(0x600A30,150)
assert ('mov','esi, ecx') in send
assert ('mov','eax, dword ptr [ebp + 0x14]') in send
assert ('mov','ecx, dword ptr [ebp + 0x10]') in send
assert ('mov','ebx, dword ptr [ebp + 8]') in send
assert ('mov','eax, dword ptr [ebp + 0xc]') in send
assert ('ret','0x10') in send
# The normal Jump path reaches the movement-event dispatcher, which sends the
# actual jump through the observed native sender after permission/physics checks.
assert ('call','0x60dea0') in instructions(0x513CB1,150)
assert ('call','0x617930') in instructions(0x60DEA0,200)
assert ('push','0xbb') in instructions(0x615ED1,10)
assert ('call','0x60e0a0') in instructions(0x6163C5,20)
assert ('call','0x600a30') in instructions(0x60E235,20)
assert ('mov','ecx, dword ptr [0xb41414]') in instructions(0x468550,28)
assert ('mov','eax, dword ptr [ecx + 0xc0]') in instructions(0x468550,28)
cancel=instructions(0x60FB60,228)
assert ('mov','esi, ecx') in cancel
assert ('mov','al, byte ptr [ebp + 8]') in cancel
assert ('cmp','byte ptr [ebp + 0xc], bl') in cancel
assert ('mov','dword ptr [0xc4d888], 0xc') in cancel
assert ('mov','dword ptr [0xc4d980], ebx') in cancel
assert ('ret','8') in cancel
assert ('call','0x60fb60') in instructions(0x514640,160)
print('PASS: client image and GUID/NPC/heading/movement ABIs; native follow cancellation clears its GUID/state through the normal input-controller path')
