# Native bridge

Version 0.1.5, capability contract 4, for the guarded WoW 1.12.1.5875 x86 image.
Contracts 2 and 3 remain supported for their older action/movement features.
The controller requires contract 4 for Mirror mode's passive jump observation.

The bridge permits fixed game API names with primitive argument validation.
It does not execute received code. Normal protected Lua calls use the scoped
binding context described in `ScopedInvoke.h` and restore it on every exit.

Contract 3 adds fixed NPC selections, one-off merchant purchases, training,
quest rewards, a read-only local movement/heading snapshot, and local heading
updates. NPC interaction resolves the supplied GUID, requires a loaded unit
(excluding players) within six yards, then uses the client's right-click path.
The addon additionally checks a living, non-hostile NPC before invoking it.

Contract 4 adds a fourth `inputs` result: a wrapping unsigned 32-bit completed
jump sequence. A native detour of the movement sender at `0x600A30` forwards
every argument unchanged and preserves its result. Only a successful send with
`MSG_MOVE_JUMP` (`0xBB`) increments the sequence. The observer never enters Lua
or changes its execution context; no Lua Jump wrapper or post-hook is installed.
If observer installation fails, the bridge retains contract 3 controls and
reports `observer=ready/status` through `status` for diagnostics.

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
exception/reentry restoration, movement observer argument/context/counter checks,
and unsupported-image rejection checks.
