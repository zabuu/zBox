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

def image_bytes(address, size):
    for virtual_size, virtual, raw_size, raw in sections:
        if virtual <= address-0x400000 < virtual+raw_size:
            offset=raw+address-0x400000-virtual
            return data[offset:offset+size]
    raise AssertionError('Address outside image')

def instructions(address, size):
    return [(i.mnemonic,i.op_str) for i in decoder.disasm(image_bytes(address,size),address)]

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
ctm=instructions(0x611130,260)
assert ('mov','esi, ecx') in ctm and ('mov','edi, dword ptr [ebp + 0x10]') in ctm
assert ('mov','eax, dword ptr [ebp + 0x14]') in ctm and ('ret','0x10') in ctm
assert ('mov','dword ptr [0xc4d888], edx') in ctm
assert ('mov','dword ptr [0xc4d890], eax') in ctm
# Ordinary ground click dispatches mode 4, zero GUID and zero float, just as
# the narrow production helper does; no direct CTM-state writes are needed.
ground=instructions(0x6102B0,70)
assert ('push','4') in ground and ('call','0x611130') in ground
assert ('mov','dword ptr [ebp - 8], eax') in ground and ('push','eax') in ground
print('PASS: client image and GUID/NPC/heading/movement ABIs; native follow cancellation clears its GUID/state through the normal input-controller path')
# Native addon API accepts only group/guild chat types; whisper requires the
# ordinary chat envelope with a recipient and addon language (-1).
addon=instructions(0x49FA3C,40)
assert ('cmp','esi, 1') in addon and ('cmp','esi, 2') in addon and ('cmp','esi, 3') in addon
assert ('cmp','esi, 0x5c') in addon
assert ('push','0x95') in instructions(0x49FABC,30)
assert ('call','0x418190') in instructions(0x49FABC,30)
assert ('call','0x4181f0') in instructions(0x49FADD,14)
assert ('call','0x5ab630') in instructions(0x49FAF5,16)
assert ('mov','dword ptr [ebp - 4], 0') in instructions(0x49FAF5,16)
assert ('call','0x5379a0') in instructions(0x5AB630,25)
assert ('mov','edi, dword ptr [eax + 0x10]') in instructions(0x5379A0,32)
assert ('sub','edi, dword ptr [eax + 0x14]') in instructions(0x5379A0,32)
# This table stores the numeric chat type immediately before its name.
assert ('mov','dword ptr [ebp - 0x38], 6') in instructions(0x49F7F8,26)
assert ('mov','dword ptr [ebp - 0x34], 0x8441b8') in instructions(0x49F7F8,26)
assert image_bytes(0x8441B8,8)==b'WHISPER\0'
assert ('ret','4') in instructions(0x418190,90)
assert ('add','dword ptr [esi + 0x10], 4') in instructions(0x418190,90)
print('PASS: fixed chat-envelope opcode/u32 fields and synchronous caller-owned store sender; public addon API does not accept whispers')
# Incoming addon-language whispers still fire CHAT_MSG_ADDON, but the stock
# channel-name switch has no whisper case and returns UNKNOWN for type 6.
assert ('cmp','edi, -1') in instructions(0x49A89B,12)
assert ('jne','0x49a970') in instructions(0x49A89B,12)
assert image_bytes(0x49AFF4+6-1,1)==b'\x04'
assert struct.unpack('<I',image_bytes(0x49AFE0+4*4,4))[0]==0x49A934
assert ('mov','ecx, 0x838044') in instructions(0x49A934,5)
assert image_bytes(0x838044,8)==b'UNKNOWN\0'
assert ('push','0xe3') in instructions(0x49A955,16)
assert ('call','0x703f50') in instructions(0x49A955,16)
print('PASS: incoming addon whisper reaches the addon event with stock UNKNOWN channel label')
