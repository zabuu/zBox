# Native bridge

Version 0.1.4, capability contract 3, for the guarded WoW 1.12.1.5875 x86 image.
Contract 2 remains supported for the older action/movement features. NPC and
mirror controls require contract 3 on both clients.

The bridge permits fixed game API names with primitive argument validation.
It does not execute received code. Normal protected Lua calls use the scoped
binding context described in `ScopedInvoke.h` and restore it on every exit.

Contract 3 adds fixed NPC selections, one-off merchant purchases, training,
quest rewards, a read-only local movement/heading snapshot, and local heading
updates. NPC interaction resolves the supplied GUID, requires a loaded unit
(excluding players) within six yards, then uses the client's right-click path.
The addon additionally checks a living, non-hostile NPC before invoking it.

The new client calls were checked in the actual executable:

| Function | Address | Calling convention |
| --- | --- | --- |
| GUID lookup | `0x464870` | stdcall, 64-bit GUID on stack, callee pops 8 |
| Unit right-click | `0x60BEA0` | thiscall, unit in ECX, one stack argument, pops 4 |
| Movement facing | `0x7C6F30` | thiscall, player + `0x9A8` in ECX, float on stack, pops 4 |
| Send movement update | `0x600A30` | thiscall, player in ECX, timestamp/opcode/float/zero, pops 16 |
| Cancel follow/CTM | `0x60FB60` | thiscall, player in ECX, zero/stop flags, pops 8 |

The local object manager at `0xB41414` holds the player GUID at +`0xC0`.
Movement flags and heading are read at player +`0x9E8` and +`0x9C4`.
Heading updates use the ordinary `MSG_MOVE_SET_FACING` opcode (`0xDA`).
Follow cancellation uses the same function called by the normal movement-input
controller at `0x5146D6`. It clears the follow GUID at `0xC4D980` and switches the
movement state at `0xC4D888` to idle (12). `FollowUnit("player")` is rejected by
this executable and must not be used as a cancellation mechanism.

Independent reference declarations are in the original
[Interact project](https://github.com/vargv666/Interact/blob/main/Game.h) and
[ZzukBot function declarations](https://github.com/Zz9uk3/ZzukBot_V3/blob/master/ZzukBot_WPF/Mem/Functions.cs).
Only addresses and ABI facts were used; their implementation code is not bundled.
`tests/test_client_abi.py` checks the relevant instructions without running the
game. Offline fixtures cannot establish compatibility with every companion DLL
or substitute for an in-game test.

Build with `native/build.ps1`; run `tests/test_native.ps1` for scoped-call,
exception/reentry restoration, and unsupported-image rejection checks.
