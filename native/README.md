# Native bridge

Version 0.1.9, capability contract 8, for the guarded WoW 1.12.1.5875 x86 image.
Contracts 2 and 3 remain supported for their older action/movement features.
The controller requires contract 4 for Mirror mode's passive jump observation.
Contract 5 includes those features and adds point movement and unit geometry.
Contract 6 also adds directed addon whispers for pairing without a party.
Contract 7 adds same-computer IPC through user-restricted named shared memory.
Contract 8 adds fixed, argument-free linked activity refresh.

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

Contract 5 adds `MoveTo(x,y,z)`, `MoveState`, and `CombatGeometry(guid)`. Point
movement calls the ordinary ground-click function with fixed mode 4, a zero GUID,
an XYZ structure and final float 0.0. The bridge validates finite coordinates and
limits destinations to 120 yards horizontally and 35 vertically from the player.
The addon handles native completion, no-progress fallback and final correction.
No CTM globals, framerate limits or movement constants are patched.

Combat geometry resolves a loaded unit and reads positions, facing and combined
combat reach. The unit-field pointer is at +`0x110`; combat reach is at field
offset `0x1F0` (`0x1F4` is display ID). The returned approach radius is bounded
to 1.5-15 yards. Lua additionally checks hostility, life, floor and clear corridors.
The fixed Lua API allowlist adds non-toggling `StartAttack`/`StopAttack` and
`CastSpellNoToggle` restricted to spell ID 75 (Auto Shot), provided by ClassicAPI.

Contract 6 adds `Whisper(pairedName, packet)`. The stock 1.12 addon API only
accepts party, raid, guild and battleground channels. This helper sends the
ordinary `CMSG_MESSAGECHAT` whisper envelope with addon language `0xFFFFFFFF`,
the fixed prefix `zBox2`, and a bounded printable zBox protocol frame. The
recipient and frame are validated; arbitrary opcodes, chat types and languages
cannot be supplied. Lua still checks the configured sender, realm, pairing
code and session on receipt. Server whisper restrictions remain in force.
There is no local-network service or regular-chat fallback.
Stock 1.12's addon-event channel map labels incoming whisper type 6 `UNKNOWN`;
Lua accepts that label on the direct route, along with `WHISPER` from client
mods. Group-channel messages cannot enter a direct pairing. The same sender,
code and session checks apply to both accepted labels.

The caller-owned 24-byte `CDataStore` and bounded 384-byte buffer stay alive
through the synchronous sender. The normal addon sender frees its own store
immediately after the same call. Transport requests do not overwrite the last
game-input diagnostic. These paths need live verification on the target server;
offline fixtures validate the envelope, not the server's configuration.

Contract 7 adds `LocalOpen(realm, ownName, peerName, key, role)`, `LocalInfo`,
`LocalSend(frame, priority)`, `LocalRead`, `LocalDiscard` and `LocalClose`.
`LocalIPC.h` contains the implementation; it has no game-memory dependencies.
The `Local\\` object name contains a SHA-256 digest of the length-delimited realm,
ordered/canonical character names and pairing code. The mapping and mutex DACL
grant access only to the current Windows user. No plaintext code is in the
object name, no process handles are inherited, and no socket is opened.

Two role slots hold process IDs, creation times, fresh random 64-bit epochs and
heartbeats. Live duplicate role owners are rejected. Every frame names both
process epochs, expires after one second and is bounded to 4352 bytes. A peer
lease expires after two seconds without DLL polling. Each recipient has separate
32-frame high/bulk rings and one reserved emergency slot. Emergency sends discard
older queued traffic. Every mutex acquisition uses a zero timeout; contention or
a full queue returns retry status 0, never blocks Lua. An abandoned mutex resets
both claims before further messages may be read.

Lua polls on the game thread at a minimum 10 ms interval, executes only its
existing fixed operations, and retains name/realm/code/session/replay checks.
Network-style game input is never invoked by a worker thread. Route changes,
new peer epochs, loading/logout, revocation and UI reload retire stale sessions.
Local frames use larger body chunks while the whisper framing/throttle remains
unchanged for remote clients. `LocalInfo` exposes counters without replacing
the last game-input diagnostic. Windows supplies bcrypt and advapi32; no new
companion DLL download is needed.

`tests/test_local_ipc.ps1` compiles a standalone x86 fixture from this same header
and uses real child processes to test round trips, priority/backpressure, Stop,
contention, generations, duplicate roles, stale frames, peer leases and abandoned
locks. `tests/test_local_transport.py` covers actual Lua routing and frame polling,
including loss/reconnect, fallback, snapshots and protected cast sequencing.

The new client calls were checked in the actual executable:

| Function | Address | Calling convention |
| --- | --- | --- |
| GUID lookup | `0x464870` | stdcall, 64-bit GUID on stack, callee pops 8 |
| Unit right-click | `0x60BEA0` | thiscall, unit in ECX, one stack argument, pops 4 |
| Movement facing | `0x7C6F30` | thiscall, player + `0x9A8` in ECX, float on stack, pops 4 |
| Send movement update | `0x600A30` | thiscall, player in ECX, timestamp/opcode/float/zero, pops 16 |
| Cancel follow/CTM | `0x60FB60` | thiscall, player in ECX, zero/stop flags, pops 8 |
| Ground point movement | `0x611130` | thiscall, player in ECX, mode/GUID pointer/XYZ pointer/float, pops 16 |
| Chat packet send | `0x5AB630` | thiscall, caller-owned CDataStore in ECX, no stack arguments |

The local object manager at `0xB41414` holds the player GUID at +`0xC0`.
Movement flags and heading are read at player +`0x9E8` and +`0x9C4`.
Heading updates use the ordinary `MSG_MOVE_SET_FACING` opcode (`0xDA`).
Follow cancellation uses the same function called by the normal movement-input
controller at `0x5146D6`. It clears the follow GUID at `0xC4D980` and switches the
movement state at `0xC4D888` to idle (12). `FollowUnit("player")` is rejected by
this executable and must not be used as a cancellation mechanism.
The normal ground-click dispatch at `0x6102B0` supplies mode 4 and zero GUID.
CTM state 4 is point movement; its destination is at `0xC4D890/894/898`.

`RefreshActivity` (contract 8) takes no arguments and writes the client clock
from `0x42C010` to the normal UI input timestamp at `0xCF0BC8`, only in world.
The actual executable's idle check at `0x482EBE` subtracts this timestamp from
that same clock and compares against 300000 ms. Normal UI input writes the same
field at `0x765F34`. `Activity.lua` permits a refresh every 30 seconds only on a
live linked agent, and stops its lease on loss/loading/revocation. No input
hooks, synthetic movement, resident timer, execution-context changes or client
clock overrides are involved. `Activity.h` fixtures cover world/null guards and
32-bit timestamp wrap; the read-only ABI fixture checks these client instructions.

Independent reference declarations are in the original
[Interact project](https://github.com/vargv666/Interact/blob/main/Game.h) and
[ZzukBot function declarations](https://github.com/Zz9uk3/ZzukBot_V3/blob/master/ZzukBot_WPF/Mem/Functions.cs).
Only addresses and ABI facts were used; their implementation code is not bundled.
`tests/test_client_abi.py` checks the relevant instructions without running the
game. Offline fixtures cannot establish compatibility with every companion DLL
or substitute for an in-game test.

Build with `native/build.ps1`; run `tests/test_native.ps1` for scoped-call,
exception/reentry restoration, movement observer argument/context/counter checks,
native point-move and addon-whisper envelope/layout checks, and unsupported-image rejection checks.
