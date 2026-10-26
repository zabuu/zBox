# zBox

A compact control panel for a second **WoW 1.12.1.5875** character on your own
private test server. Control account 2 from account 1: remote action bars,
spellbook, follow, movement, click-to-move, bags, equipment, talents, quests and NPCs.
Choose Follow, Mirror movement, or Pet controls with explicit Follow/Assist/Attack.

**Addon 0.6.0 | Native bridge 0.1.7 | Windows x86**

Update the addon and **game-root bridge DLL on both computers/client folders**,
then fully restart both clients. Bridge 0.1.7 adds direct addon whispers for
pairing without a party; `/reload` alone cannot load it.

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

This release needs bridge **0.1.7 on both clients** for pairing without a party.
Bridge 0.1.6 supports native click-to-move and Pet controls while grouped.
Bridge 0.1.5 supports Mirror mode's jump observation. Bridge
0.1.4 supports NPC interactions and older movement controls; 0.1.3 supports the
earlier action controls. Fully restart both clients after updating the DLL.

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

The Git addon download and release ZIP bundle **only zBoxBridge.dll**. They do
not install the following companion DLLs. Install and enable them through the
launcher's **Mods** tab in every game folder used by the two characters:

- [**UnitXP_SP3.dll**](https://github.com/allfoxwy/UnitXP_SP3/releases): required
  for bridge registration and the zAPI registration path.
- [**SuperWoW / SuperWoWhook.dll**](https://github.com/balakethelock/SuperWoW/releases):
  the tested GUID-capable unit API. zBox reads and targets raw `0x...` unit GUIDs;
  the client's unit APIs must recognize them. Merely obtaining GUID strings
  through another addon is insufficient.
- [**zAPI.dll 1.6+**](https://github.com/zabuu/z_DNumbers/blob/main/native/zAPI/build/zAPI.dll):
  the custom zAPI used by this setup, for world positions, camera projection and
  terrain traces. This is a separate download; the zBox bridge does not replace
  it. Its [source and documentation](https://github.com/zabuu/z_DNumbers/tree/main/native/zAPI)
  are available in the same repository.
- [**ClassicAPI.dll**](https://github.com/brues-code/ClassicAPI/releases): supplies
  facing, spell metadata and action helpers used by the full feature set.
- The working development client also loads
  [**nampower.dll**](https://github.com/brues-code/nampower). Current versions
  extend unit-token/GUID parsing too. It is not established as a hard zBox
  dependency; match the working client-mod versions when diagnosing differences.
- **SuperMacro** is optional. Existing macros on account 2's bars work through
  its remote action slots. **SuperAPI** and **NampowerSettings** are companion
  addons; installing them alone does not load their respective DLLs.

DLLs must be beside `WoW.exe`, enabled in the launcher's Mods list and registered
in `dlls.txt`. Addon-manager installation only populates `Interface/AddOns`.
Fully close and restart both clients after installing or changing a DLL. If
both accounts use one game folder, one enabled copy of each DLL serves both.

### Troubleshoot "Unknown unit"

Connected status confirms pairing and addon messages; it does not test every
required native API. **Native inputs 0.1.6** confirms the bridge loaded, but does
not confirm that another DLL's GUID parser is working.

"Unknown unit" is consistent with a unit-taking API rejecting the supplied
unit/GUID, including a missing, old or conflicting client mod. It cannot identify
the exact missing dependency from a screenshot. Check the components above and
their loaded versions before reinstalling zBox's bridge.

On both characters, reproduce the failure and run `/zbox diag`. Version 0.6.0
reports UnitXP presence, zAPI/SuperWoW/ClassicAPI/Nampower versions when available,
facing/spell-info availability, and a read-only **GUID lookup** probe. `FAILED`
means the local player's GUID could not be resolved through `UnitExists`; this
does not change targets. `ok` verifies reads, not every targeting/casting API.
The report also retains the last game error and the zBox call that emitted it,
even if later movement or Follow calls succeed. Errors outside a synchronous
zBox input call are labeled **between zBox calls**.

Only zBox's own bridge is bundled. Existing zAPI, UnitXP, ClassicAPI and other
DLLs are preserved. The bridge rejects unsupported executable images. This
project provides no public-server compatibility or ban guarantee.

## Pair the characters

Log both characters into the **same realm**, with addon 0.6.0 and bridge 0.1.7
loaded on both. They may run on the same computer or different computers.
They do **not** need a shared party, raid or guild. No IP addresses or ports
need configuring: directed addon whispers travel through the game server.

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
peer and supported operations; received text is never executed as Lua. With
bridge 0.1.7, messages go only to that character using the addon whisper channel,
without appearing as ordinary chat. Keep the code private; it is a pairing
secret, not encrypted authentication.

The server must permit addon whispers between the characters. Normal whisper
restrictions, including ignores and faction rules, still apply. Follow, Assist,
targeting and the character preview require the other character/target to be
loaded nearby; a working remote connection does not extend world visibility.

Older bridges retain party/raid transport and require grouping. Update both
bridges together: a direct-whisper client cannot pair with a group-only client.
The diagnostic report includes the selected transport.

## Compact controls

The panel is **496 x 110** at **85% scale** by default, approximately 422 x 94 UI
units before the game's UI scale. Drag its background to move it. Status
messages appear briefly below the panel instead of occupying a permanent row.
While linked, **-** minimizes the dock to a persistent **zBox +** button; click
it to restore. Escape and the panel keybinding also keep that restore button
available. Once unlinked, **x** can close the panel completely.

- **More** opens actions, spells, bags, gear, talents, quests and NPCs on demand.
  Popouts open below the dock when space above is insufficient. They scale to
  the available vertical space if neither side can fit them at full size.
- **Keys** binds click-to-move, forward/backward, turning, strafing, follow,
  assist, pet attack, jump, stop and the panel. Movement supports combined directions and
  works while the panel is hidden. Click a binding, then press a key combination
  or mouse button/wheel. A temporary full-screen input surface captures the
  next press even over other controls. Alt/Ctrl/Shift combinations work.
  Escape cancels and Backspace clears it. If the client rejects a reserved
  mouse button, the old binding stays intact; choose another button or modifier.
- **Setup > Panel scale** changes size in 5% steps. `/zbox scale 0.75` sets 75%;
  `/zbox scale reset` restores 85%. Settings are saved per character.
- **Follow** follows the main. Cast-time spells cancel native follow, release
  every movement direction, then wait for account 2 to stop before casting.
  Follow resumes after casting and after both characters leave combat, if it
  was active before the cast. Stop, manual movement and NPC controls cancel
  this resumption. Unknown macro cast times use the same stopping behavior.
- **Move** arms a terrain click. Right-click or Escape cancels; a missed terrain
  trace keeps the picker open. **More > Move pad** has held direction buttons.
  The picker prefers zAPI's refreshed native ground cursor when it matches the
  screen cursor, with the calibrated terrain ray as fallback. Account 2 uses
  WoW's native point movement, followed by a precise correction if it stops short.
- **STOP** cancels owned movement, follow and casting. It takes priority over
  previously queued commands. `/zbox stop` does the same.

Click the cast-target button to cycle between account 1's target, account 1,
account 2, and account 2's current target. Right-click a skill to target account 2.

### Put remote skills on your own bars

Drag an active action or a spell from **More > Spells** onto account 1's action
bars. Shift-click is an alternative way to pick one up. zBox
creates a character macro with its icon. Click that macro, or use its normal
bar keybinding, to request the skill on account 2. Hold Alt when using the macro
to target account 2; otherwise it uses the selected zBox target mode.

Each export uses one of Vanilla's eighteen character macro slots. Dragging the
same remote slot again reuses its macro. Existing macros are never deleted or
overwritten to make room. Exported skill macros show account 2's cooldown swipe
and countdown on **pfUI and standard Blizzard action bars**, including paged and
side bars. Account 2 reports cooldown changes for exported actions and spellbook
skills even when they are used directly in its own client. Timers work with the
zBox dock minimized and count down locally between updates. Other bar addons
need their own adapter. The zBox strip retains remote usability information.

If account 2 rearranges an action slot or its spellbook, re-drag the skill to
refresh the saved action stamp. Macros remain tied to the paired character and
realm across reloads. Dragging a skill never casts it.

### Pet controls and control macros

Right-click **Follow** to cycle Follow / Mirror / Pet, or choose **Pet controls**
in Setup. Pet mode shows **Follow**, **Assist** and **Attack** in the same compact
dock. **Setup > Pet approach** selects Auto (class), Melee, or Ranged for hybrids.
Hunters always use their ranged attack behavior.

- **Follow** recalls account 2, stops its owned attack and follows the main.
- **Attack** sends account 2 to account 1's selected enemy. Melee continuously
  adjusts its approach and auto-attack range as the enemy moves or turns. It
  tries to stay behind while the enemy targets someone else, including during
  combat; when the enemy targets account 2 it holds range without circling.
  An unknown enemy target during combat also skips rear positioning. Casters approach to about 25
  yards when needed and face the enemy while you choose spells. Hunters approach
  or retreat to range and start learned Auto Shot.
- **Assist** attacks the selected enemy and stays armed to use the main's target
  during combat. With no enemy selected it follows until the main enters combat.
  It does not pull a newly selected target while both characters are idle.

After both characters leave combat, account 2 automatically follows again.
Assist remains armed. During an active Attack or Assist order, selecting another
loaded attackable enemy on the main switches the chase to it. Looking at a
friendly unit or clearing your target keeps the current enemy. Once recalled or
returned to Follow, Attack does not pull a newly selected enemy; Assist can
resume when the main enters combat. A target's death ends its chase.
Cast-time spells stop movement and hold facing until the cast finishes. STOP,
manual account-2 movement, NPC interaction and a mode change cancel the order.

**Drag or Shift-click Follow, Assist, Attack, Move, or STOP** to put its macro on
account 1's action bars. Export Follow while in Pet mode for a Pet Follow macro;
Pet Follow/Assist/Attack macros select Pet mode when used, even after switching
modes. They use the same saved pairing checks and character macro slots as
remote skills. Exporting a button does not issue its command.

For macros you create yourself, use one command per macro:

| Control | Macro body |
| --- | --- |
| Pet Follow | `/zbox pet follow` |
| Pet Assist | `/zbox pet assist` |
| Pet Attack | `/zbox pet attack` |
| Click-to-move picker | `/zbox move` |
| Stop | `/zbox stop` |

Unlike exported macros, handwritten slash commands use the currently configured
pairing rather than storing a particular character and realm.

### Bags, gear and talents

**Bags** opens each bag as a separate four-column window. Use its bag button to
open/close it; drag the window background to move it. Positions are saved per
character. Open bags refresh in turn. Item borders show quality and selection.

In **Bags**, left-click an item, open **Gear**, and click its destination slot.
Right-click a bag item to use it. Right-click equipped gear to unequip into an
empty backpack slot. Equipment changes require leaving combat. Binding dialogs
may still need confirmation in account 2's window.
Shift-left-click remains an alternative for unequipping.

**Gear** places equipment around a character model, with weapons below it. The
preview uses the paired character visible to account 1; bring account 2 into
view if it is unavailable. **Spells** uses two book columns and retains spell
dragging. **Talents** places each talent at its real tier and column over the
class tree background, with rank counters on its icon.

In **Talents**, use the page arrows to choose a tree. Each click requests one
rank. Wait for the updated rank before spending again. Normal prerequisites,
points and server rules apply.

### Quests and NPCs

**More > Quests** shows account 2's quests and objectives with account 1's progress
alongside them. Select a quest on the left to read its objectives and comparison
on the right; long details scroll. **Main only** lists questlines
account 2 does not have; **Alt quests** returns to the remote log. Collapsed
quest headers and the selected quest are restored after reading the log.

For **More > NPC**, target a living friendly NPC on account 1, move account 2
within six yards, then click **Talk**. Gossip choices, available/current quests,
quest acceptance, completion and reward choices appear in the panel. Account 2
must have the NPC loaded and remain within its normal interaction range.
The parchment shows the NPC's actual gossip, greeting, quest, progress or reward
text, followed by the available choices. Use the mouse wheel or arrows to scroll
long conversations. Vendor and trainer entries keep their prices and confirmation.

On linked account 2, zBox pauses **_LazyPig** auto-gossip and quest replay/acceptance.
Automatic junk selling and repair remain enabled. Account 1 keeps its normal behavior. These
guards act on the addon's own routines and leave protected game APIs and saved
preferences unchanged; normal behavior returns when the link ends. Diagnostics
reports the adapter status. Other automation addons need their own integration.

Vendor offers show the price and number of items. Each purchase buys **one
offer**, including its normal bundle size. Trainer services show cost and
availability. Click a purchase, training service or reward once to review and
again within eight seconds to confirm. Stale dialogs, changed prices, duplicate
requests and insufficient money reject the action. There is no automatic buying,
training, quest acceptance or reward selection. Vendors currently support buying;
selling, buyback and repair controls are not included.

### Mirror movement and mouse heading

Right-click **Follow** to cycle Follow / Mirror / Pet, or
choose the mode in **Setup**. In Mirror mode, left-click the same button to pause
or resume. `/zbox mirror`, `/zbox mirror pause` and `/zbox mirror off` provide the
same controls. Mirror starts paused after reconnecting; click to resume.

The bridge reads account 1's actual movement flags and character heading. This
captures WASD, strafing, right-mouse turning and mouse-button movement without
changing your bindings. The bridge records successful native jumps; the addon
mirrors those events through account 2's normal Jump API. Account 1's Jump
function and execution context are untouched. Rotating
the camera with left mouse alone does not turn the character, so it does not turn
account 2 either. Absolute heading updates keep camera-driven movement aligned.

Start with the characters together and facing the same direction. Mirror mode
sends movement and heading, not positions: latency, unequal movement speeds,
collisions and obstacles can cause drift. Reposition them when needed. A cast-time
spell holds account 2 still. Hostile casts face their enemy before casting and
retain that enemy's heading through movement, heading changes and cast delays.
Current mirrored inputs resume after the actual cast or channel ends. Follow
is not invoked. STOP pauses mirroring until resumed; direct account-2 movement,
Follow and NPC controls also pause it. The panel may remain hidden.

## Limits and diagnostics

- Native click-to-move and its correction use straight travel, with no pathfinding
  mesh. A stalled native move falls back to precise steering; 3.5 seconds without
  progress stops movement. Select clear routes. No framerate settings are changed.
  Destinations must be in the same zone, within 120 yards and 35 yards vertically.
- Pet rear positioning follows zPet's floor/corridor validation approach. zPet's
  custom Take Position command moves actual pets on the server; it cannot move
  another player character. Rear goals refresh at a bounded rate; blocked rear
  positions fall back to an ordinary approach and are retried later. Moving
  goals do not renew the physical no-progress timeout. An active, progressing
  chase can last beyond the ordinary point-move timeout. Obstacles can still
  require manual positioning.
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
The expected bridge label is **Native inputs 0.1.7**. An old/missing bridge
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
python tests\test_hotfix.py
python tests\test_cast_facing.py
python tests\test_character_views.py
python tests\test_linked_controls.py
python tests\test_pet_mode.py
python tests\test_melee_cooldowns.py
python tests\test_mouse_dependencies.py
python tests\test_ungrouped.py
python tests\test_client_abi.py "<game folder>\WoW.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File native\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_native.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Build-Package.ps1
```

`bin/zBoxBridge.dll` is the distributed bridge checked by the offline fixtures; its checksum
is in `bin/SHA256SUMS.txt`. Local compilation writes `native/build/zBoxBridge.dll`
and does not silently change the distributed DLL or an installed game client.

The Lua fixtures cover isolated paired clients, replay/spoof rejection, casting,
items/talents, 160 camera/viewport/UI-scale cases, movement leases, actual XML
key-up bindings, remote macro exports, compact layouts, quest comparisons, NPC
dialogs, one-off spending, cast pauses and movement/heading mirroring. Native
point movement, final correction, rear approach, combat-end follow, hunter Auto
Shot and control macro exports are also covered by paired fixtures. Action-bar
cooldown subscriptions, remote timer updates and melee movement/aggro
transitions have dedicated fixtures. Native
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
