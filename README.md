# zBox

A compact control panel for a second **WoW 1.12.1.5875** character on your own
private test server. Control account 2 from account 1: remote action bars,
spellbook, follow, movement, click-to-move, bags, equipment and talents.

**Addon 0.2.1 | Native bridge 0.1.3 | Windows x86**

## Install with OctoWoW Launcher's addon manager

In **Addons**, add this Git repository:

```text
https://github.com/zabuu/zBox
```

The manager installs it into **Interface\AddOns\zBox** and handles addon updates.
The folder and its `zBox.toc` use the same name, as the launcher requires.
No separate installer is needed.

### Enable the bundled native bridge

The installed OctoLauncher **1.4.3** treats Git addons and DLL mods separately.
Its addon-install operation clones the repository into AddOns; it does not move
DLLs into the game root, run install scripts or register them in `dlls.txt`.

After installing the addon:

1. Close the WoW clients using this game folder.
2. In the launcher, open **Mods > Add DLL**.
3. Select the bundled file:

   ```text
   <game folder>\Interface\AddOns\zBox\bin\zBoxBridge.dll
   ```

4. Enable it if necessary and click **Apply**.
5. Start both clients and enable **zBox** for both characters.

The launcher's custom-DLL operation copies the selected file into the game
folder; Apply registers it in `dlls.txt`. This is a one-time bridge setup per
client folder, not a step required whenever you launch WoW. If both accounts
share a game folder, do it once. If they have separate game folders, do it for
each folder.

When a later release changes **the bridge DLL**, close the clients and repeat
**Mods > Add DLL** using the updated bundled copy, then Apply and restart.
The addon manager updates `bin/zBoxBridge.dll` in the addon checkout; it does
not update the separate copy in the game root automatically. A `/reload` cannot
replace a DLL already loaded by WoW.

If you already have bridge **0.1.3** installed and enabled, keep using it. Addon
updates that leave the bridge unchanged do not require repeating its setup.

The prebuilt bridge is also available separately under
[Releases](https://github.com/zabuu/zBox/releases/latest). Its checksum is in
`bin/SHA256SUMS.txt`. Existing companion DLLs are not replaced.

This layout was checked against the installed OctoLauncher 1.4.3 addon and
custom-DLL handlers. It does not add zBox to the server's curated catalog;
use the custom Git repository option. Fully automatic addon-plus-DLL deployment
would require additional support in the launcher itself.

## Requirements

Use the supported **32-bit WoW 1.12.1.5875** executable and a loader supporting
`dlls.txt` (the tested setup uses VanillaFixes).

Install these companion components separately:

- **UnitXP_SP3.dll**, enabled in `dlls.txt`: required for bridge registration.
- **SuperWoW**: GUID-capable unit targeting.
- **zAPI 1.6+**: world positions, camera projection and terrain traces.
- **ClassicAPI**, exposing `GetPlayerFacing`: steering towards world points.
- **SuperMacro** is optional. Existing macros on account 2's bars work through
  its remote action slots. The development client also uses Nampower.

Only zBox's own bridge is bundled. Existing zAPI, UnitXP, ClassicAPI and other
DLLs are preserved. The bridge rejects unsupported executable images. This
project provides no public-server compatibility or ban guarantee.

## Pair the characters

Group both characters in the same party or raid on the same realm.

On account 2:

```text
/zbox allow MainName mypaircode123
```

On account 1:

```text
/zbox control AltName mypaircode123
/zbox
```

Use actual character names and the same 8-32 character code. **Setup** provides
the same controls and a code generator. `/zbox off` revokes control.

Pairing is saved per character and realm. Commands are restricted to the chosen
peer and supported operations; received text is never executed as Lua. Addon
messages are visible to group members. The code prevents accidental control;
it is not encrypted authentication against a hostile group member.

## Compact controls

The panel is **496 x 110** at **85% scale** by default, approximately 422 x 94 UI
units before the game's UI scale. Drag its background to move it. Status
messages appear briefly below the panel instead of occupying a permanent row.

- **More** opens actions, spells, bags, gear and talents on demand.
- **Keys** binds click-to-move, forward/backward, turning, strafing, follow,
  assist, jump, stop and the panel. Movement supports combined directions and
  works while the panel is hidden. Click a binding, then press a key combination
  or middle/extra mouse button; Escape cancels and Backspace clears it.
- **Setup > Panel scale** changes size in 5% steps. `/zbox scale 0.75` sets 75%;
  `/zbox scale reset` restores 85%. Settings are saved per character.
- **Follow** follows the main. Casting stops account 2's follow and movement
  first, so account 1 can keep moving. Follow stays off until requested again.
- **Move** arms a terrain click. Right-click or Escape cancels; a missed terrain
  trace keeps the picker open. **More > Move pad** has held direction buttons.
- **STOP** cancels owned movement, follow and casting. It takes priority over
  previously queued commands. `/zbox stop` does the same.

Click the cast-target button to cycle between account 1's target, account 1,
account 2, and account 2's current target. Right-click a skill to target account 2.

### Put remote skills on your own bars

Drag an active action or spell from zBox onto account 1's action bars. zBox
creates a character macro with its icon. Click that macro, or use its normal
bar keybinding, to request the skill on account 2. Hold Alt when using the macro
to target account 2; otherwise it uses the selected zBox target mode.

Each export uses one of Vanilla's eighteen character macro slots. Dragging the
same remote slot again reuses its macro. Existing macros are never deleted or
overwritten to make room. Native bars show the macro icon; the zBox strip shows
remote cooldown and usability information.

If account 2 rearranges an action slot or its spellbook, re-drag the skill to
refresh the saved action stamp. Macros remain tied to the paired character and
realm across reloads. Dragging a skill never casts it.

### Bags, gear and talents

In **Bags**, left-click an item, open **Gear**, and click its destination slot.
Right-click a bag item to use it. Shift-click equipped gear to unequip into an
empty backpack slot. Equipment changes require leaving combat. Binding dialogs
may still need confirmation in account 2's window.

In **Talents**, use the page arrows to choose a tree. Each click requests one
rank. Wait for the updated rank before spending again. Normal prerequisites,
points and server rules apply.

## Limits and diagnostics

- Click-to-move uses straight-line steering, with no pathfinding mesh. It stops
  near the point or after 3.5 seconds without progress. Select clear routes.
  Destinations must be in the same zone, within 120 yards and 35 yards vertically.
- A four-second connection timeout stops owned movement. Held directions have
  a further 0.8-second input lease. This cannot recover a hung/crashed client.
- Normal spell range, line of sight, cooldowns and target rules apply. Remote
  ground-targeted spell placement is not implemented.
- The panel does not stream account 2's screen, rearrange its bars, or change
  server-side appearance/transmog. Equipping gear changes its normal appearance.
- Large snapshots may take several seconds. A request acknowledgement is not
  proof that the game completed the action; cast events and refreshed state
  provide separate feedback.

**Setup > Diagnostics**, or `/zbox diag`, reports addon/bridge versions, the last
input request, cast feedback and terrain-picking failures on both characters.
The expected bridge label is **Native inputs 0.1.3**. An old/missing bridge
reports an update error for protected casts and movement.

Tests run offline fixtures, not a live two-client integration environment. The
user has tested the addon in-game, but every feature/client combination is not
independently certified.

## Build and test

Source includes the native bridge and vendored MinHook; no sibling addon checkout
is needed. Building requires Visual Studio Build Tools with the C++ x86/x64
workload. The scripts locate it with `vswhere`.

```powershell
python -m pip install -r tests\requirements.txt
python tests\test_zbox.py
powershell -NoProfile -ExecutionPolicy Bypass -File native\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_native.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Build-Package.ps1
```

`bin/zBoxBridge.dll` is the distributed, previously tested bridge; its checksum
is in `bin/SHA256SUMS.txt`. Local compilation writes `native/build/zBoxBridge.dll`
and does not silently change the distributed DLL or an installed game client.

The Lua fixtures cover isolated paired clients, replay/spoof rejection, casting,
items/talents, 160 camera/viewport/UI-scale cases, movement leases, actual XML
key-up bindings, remote macro exports, compact layouts and bindings. Native
fixtures verify input-context restoration after success, Lua errors, Windows
exceptions and reentry, and reject an unsupported executable.

`python tests/render_ui.py` renders widget layouts with placeholder icons for
inspection. They are fixture previews, not live game captures. The layout takes
cues from [ShaguController](https://github.com/shagu/ShaguController) and
[Bartender4](https://www.wowace.com/projects/bartender4); no code or artwork from
those projects is included.

## License

zBox is MIT licensed. MinHook and HDE retain their BSD-style licenses in
`native/vendor/minhook/LICENSE.txt` and `native/MINHOOK-LICENSE.txt`. No game
executable, game assets or companion DLLs are distributed.
