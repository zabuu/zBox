# zBox

A compact control panel for additional **WoW 1.12.1.5875** characters on your own
private test server. Control account 2 from account 1: remote action bars,
spellbook, follow, movement, click-to-move, bags, equipment, talents, quests and NPCs.
Choose Follow, Mirror movement, or Pet controls with explicit Follow/Assist/Attack.

**Addon 0.10.1 | Native bridge 0.1.11 | Windows x86**

Update zBox on the driver and every follower. **Bridge 0.1.10 is required for
trade/item destruction and multiple simultaneous local DLL connections.** Close
all clients sharing a game folder, add the updated bundled DLL through the
launcher's **Mods > Add DLL**, Apply, then restart. `/reload` cannot load a new
DLL. Different computers continue to pair through code-based addon whispers.

### Multiple followers

In Setup, use **+** to add follower names (up to 16), enter one shared code and
press **Control** on the driver. Each follower enters only the driver's name and
the same code, then presses **Allow**. No party is required. Click the character
name in the dock to select the next follower; hover it to see connection status.
Movement, Follow/Pet orders, Mirror, click-to-move, Jump and STOP control all
followers. Skills, bags, gear, NPCs, quests and trades use the selected follower.
Each follower has an independent session, queues, caches and cooldown watches.
Older bridges use whisper transport for a roster with several followers.

### Unstuck all linked characters

Type **`/unstuck`** (or `/zbox unstuck`) on the driver to invoke **`Stuck()`**,
equivalent to `/script Stuck();`, on this character and every connected follower.
This uses a fixed protocol action; script text and chat commands are never sent.
Requests go out immediately, then local recovery runs. Mirror/held movement,
follow, pet orders and casting are stopped so they do not interrupt recovery.
Disconnected followers are skipped and do not receive a delayed request when
they reconnect. Without a link, the command affects only the local character.
Normal client/server unstuck restrictions still apply. **Follower Unstuck requires bridge 0.1.11.** The client checks protected input
inside its spell dispatcher: a direct background `Stuck()` call can return
without doing anything. Update zBox on every client, close all clients sharing
the game folder, update the game-root bridge DLL through Mods > Add DLL, Apply,
and fully restart. `/reload` alone cannot load the DLL. Older follower bridges
report a required-update error rather than acknowledging a silent no-op.

### Bags and trades

Right-click a bag item for **Use / Equip**, **Trade** or **Destroy...**. Trade uses
the driver's friendly player target, or the driver when no valid other player
is selected. The recipient must be loaded and within 10 yards of the follower;
the normal client/server trade rules still apply. The whole selected stack is
placed in the first empty traded slot. An existing trade with someone else is
never replaced. Destroy opens a 20-second confirmation naming the character,
item and stack count, then rechecks the exact item/slot/count on the follower.

When your normal trade window is trading a connected follower, **Accept
follower** requests acceptance on that character. It appears only for that
specific connection. Changes to either offer invalidate stale requests. A
follower trading someone else opens an independent, class-bordered preview
with both offers, money, acceptance state and Accept/Cancel controls.

### Independent action bars and bindings

The dock now starts with **fresh blank zBox slots**, independent of WoW's action
bars. Open More > Spells on a linked character and drag skills into the dock;
switch the selected character and drag more skills to combine several owners on
one bar. You can also drag a spell from the driver's own spellbook. Normal
spells are saved by name/rank, so changing a source action bar or spellbook slot
does not change the assigned skill. Source macros remain validated references to
their owner's original action slot. Standard and SuperMacro mouseover macros are
identified in tooltips; their source text is never transmitted for evaluation.

Each selected linked character has its own saved ten-page bar, bindings and cast
target mode, keyed by character and realm on the driver. Reconnecting that
character restores its layout. Slots remember their original skill owner even
when the bar contains several characters. Page arrows wrap **10 -> 1** and
**1 -> 10**. Shift-drag swaps/moves entries; Shift-right-click removes an entry;
Escape cancels a drag. For friendly-target skills such as heals and buffs,
**left-click targets the driver (account 1)**, regardless of the cast-target
mode; **right-click or Alt-click targets the skill's owner**. A normal keybind
uses the left-click behavior. Hostile skills keep the selected target mode.
Self-only spells keep their normal behavior. Update and reload zBox on every
linked client for these click rules; bridge 0.1.11 does not need replacing.

Click **Bind**, hover a slot and press a key, modified click, side mouse button
or wheel. Backspace/Delete clears its binding; Escape or Done finishes. Bindings
apply to that bar position on every page. They are stored in zBox and use
ClassicAPI's temporary override layer: **WoW's saved hotkeys are never rewritten
or saved**. A shared key temporarily goes to zBox while linked, and its original
WoW action returns when the link is disabled or the profile changes. The tooltip
shows conflicts. Bindings keep working while zBox is minimized. The existing
Keys window remains the movement/utility binding editor; Bind belongs to the
independent action bar.

The old pfUI-slot adapter is no longer installed automatically. Existing exported
macros are preserved for compatibility. No existing bars are imported into the
new layouts. Action-bar snapshots are requested only while browsing the source
Actions view; the independent dock watches cooldowns for its assigned skills.
The installed ClassicAPI provides SetOverrideBindingClick/ClearOverrideBindings.
Update zBox and `/reload` on **every client**. Bridge **0.1.11 is unchanged**.

### Targeting and quiet feedback

Cast modes are Main's target, Main character, Skill owner, Owner's target and
Mouseover. For detected mouseover macros, zBox briefly supplies the driver's
mouseover (or the selected cast target) to the owner client and restores its
previous mouseover afterward. This needs SetMouseoverUnit from Nampower/SuperWoW.
Absent/unloaded units are rejected before a cast. Macro edits invalidate stale
buttons rather than silently executing a changed macro.

Ungrouped Pet target tracking uses authenticated driver target snapshots, rather
than invalid raw-GUID-plus-target unit strings. Passive failed unit lookups no
longer turn into relayed game-error spam. This upgrade resets feedback to quiet;
`/zbox feedback verbose` still enables throttled diagnostic chat across followers.

### Companion addon integration

Update **zNameplates to 2.2.1** for two 2-pixel bars under each connected follower's
friendly name: green health and a resource-colored power bar, at 70% of the
original (name width + 8 pixels) width. Nameplate visibility follows your existing zNP settings. zBox
provides fresh authorized vitals; zNP owns drawing. Update **zDNumbers to 1.0.3**
for pet damage anchoring across multiple followers; zDNumbers still owns numbers.
Both integrations are optional.

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

This release needs bridge **0.1.10** for trade/item controls and multi-peer local IPC.
Bridge 0.1.9 supports background activity.
Bridge 0.1.8 on both clients supports local DLL communication.
Bridge 0.1.7 supports pairing without a party through addon whispers.
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

On both characters, reproduce the failure and run `/zbox diag`. Version 0.7.0
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

Log both characters into the **same realm**, with addon 0.7.0 and bridge 0.1.8
loaded on both. They may run on the same computer or different computers.
They do **not** need a shared party, raid or guild. No IP addresses or ports
need configuring. Clients on the same computer, Windows user and login session
automatically prefer direct DLL communication. Different computers use directed
addon whispers through the game server.

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
bridge 0.1.8, matching local clients exchange messages through Windows shared
memory restricted to the current user. Otherwise, bridge 0.1.7+ sends them to
the selected character through addon whispers, without appearing as ordinary
chat. Keep the code private; it is a pairing secret, not encrypted authentication.

For different computers, the server must permit addon whispers between the characters. Normal whisper
restrictions, including ignores and faction rules, still apply. Follow, Assist,
targeting and the character preview require the other character/target to be
loaded nearby; a working remote connection does not extend world visibility.

Bridges before 0.1.7 retain party/raid transport and require grouping. Update both
bridges together: a direct-whisper client cannot pair with a group-only client.
The diagnostic report includes the selected transport.

### Same-computer low-latency transport

Keep the same pairing names and code. With bridge 0.1.8 loaded in both clients,
the dock reads **Local DLL** and `/zbox diag` reports **transport=LOCAL**. No
party, network address, listening port, firewall change or extra program is needed.
Both clients must run as the same Windows user in the same login session.

Local commands are sent immediately, bypassing the 16-packet-per-second addon
message throttle. The addon polls local input about every **10 ms**, limited by
the receiving client's actual frame rate. Bulk UI snapshots use 4096-byte chunks
and a separate lane from commands. Stop has a reserved slot; busy/full queues
retry without blocking the game thread or duplicating commands. Local Mirror
movement/heading updates can run at about 30 ms intervals rather than 120 ms.

Native IPC-only round trips measured below a millisecond in a two-process x86
fixture. This is not an in-game latency promise: foreground/background frame
rates, stopping before cast-time spells, game-server latency, the global cooldown
and spell rules still apply. `/zbox diag` includes the most recent command
acknowledgement round trip, including addon scheduling and command handling.

Transport discovery and a new peer process trigger a fresh pairing session and
stop owned movement. Old process generations, expired frames, old sessions and
incorrect names/codes cannot issue commands through the new link. A local-peer
loss reconnects through addon messages; normal input leases and connection
timeouts still stop abandoned movement.

`/zbox transport whisper` on either client disables the local fast path for
comparison. `/zbox transport auto` restores it. If no matching local peer exists,
pairing continues through whispers with the same code. Direct internet DLL
communication using only a code would need a rendezvous/relay service; this
release opens no network service and includes no such remote transport.

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
  this resumption. Unknown macro cast times do not stop movement speculatively;
  actual cast/channel start events still acquire a movement hold.
- **Move** arms a terrain click. Right-click or Escape cancels; a missed terrain
  trace keeps the picker open. **More > Move pad** has held direction buttons.
  The picker prefers zAPI's refreshed native ground cursor when it matches the
  screen cursor, with the calibrated terrain ray as fallback. Account 2 uses
  WoW's native point movement, followed by a precise correction if it stops short.
- **STOP** cancels owned movement, follow and casting. It takes priority over
  previously queued commands. `/zbox stop` does the same.

Click the cast-target button to cycle between account 1's target, account 1,
account 2, and account 2's current target. Friendly-target skills left-click the
driver; right-click targets the character casting that skill.

### Place skills on zBox bars

Use the independent dock and Bind button described above. Skills can be mixed
across linked owners, and saved layouts return with the selected linked character.
Previously exported macros on WoW/pfUI bars remain usable; new skill drags go to
zBox's own slots without consuming macro slots or rewriting WoW's bindings.

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

**Drag or Shift-click Follow, Assist, Attack, Move, Talk, Stack, or STOP** to put its macro on
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
| Talk to NPC | `/zbox talk` |
| Mirror Stack toggle | `/zbox stack` |

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

Target a living friendly NPC and press **Talk** directly on the dock or next to
the minimized restore button. No expansion or tab navigation is needed. Drag
Talk onto your bars to create a macro, use `/zbox talk`, or bind **Talk to NPC**
in Keys. Account 2 must have the NPC loaded and be within six yards.

Account 2's conversation opens automatically in an independent, movable window,
including while the dock is minimized. It uses the stock dialogue templates,
scrollbar and font styles. With the stock/pfUI dialogue skin installed, it uses
pfUI's public skin helpers and matches the main's window scale and dialogue
fonts. Its border uses account 2's class colour. Both conversations can remain
open. The main's dialogue widgets, scripts and protected quest APIs are untouched.
Other replacement dialogue addons may need a separate skin adapter.

The window shows the NPC's actual gossip, greeting, description, objectives,
progress and reward text, required items and offered rewards. Gossip/quest lists
scroll together; vendor and trainer lists have page controls. Accept/Continue
use the normal bottom button. Select a quest reward, then click Complete Quest.
You can still open the remote conversation from **More > NPC**.

**Linked quest pickup and turn-in are enabled by default.** When account 1's
quest log confirms an acceptance or reward turn-in at an NPC, zBox asks account
2 to do the same quest at that NPC. It checks range, combat, current quest and
live dialogue eligibility. Missing prerequisites or incomplete objectives do not
get bypassed. No/one-choice rewards complete automatically; multiple reward
choices remain open for you to choose separately. Closing account 1's quest
dialogue without accepting/completing does not issue a quest action. STOP or a
new manual NPC order cancels a pending linked quest. `/zbox quests off` on the
controller disables this feature; `/zbox quests on` restores it.

With **pfQuest** enabled, its tooltip progress keeps account 1's original lines
and adds account 2's independently reported objectives below, labelled by name.
Only quests currently shared by both characters appear. Quest IDs are preferred
when available, with level/title matching on stock APIs. Quest logs sync while
linked even if neither quest panel is open; removals and completion update the
cached remote progress. Unrelated questlines are not added to these tooltips.

On linked account 2, zBox pauses **_LazyPig** auto-gossip and quest replay/acceptance.
Automatic junk selling and repair remain enabled. Account 1 keeps its normal behavior. These
guards act on the addon's own routines and leave protected game APIs and saved
preferences unchanged; normal behavior returns when the link ends. Diagnostics
reports the adapter status. Other automation addons need their own integration.

Vendor offers show the price and number of items. Each purchase buys **one
offer**, including its normal bundle size. Trainer services show cost and
availability. Click a purchase or training service once to review and
again within eight seconds to confirm. Stale dialogs, changed prices, duplicate
requests and insufficient money reject the action. There is no automatic buying,
training or choice between multiple quest rewards. Vendors currently support buying;
selling, buyback and repair controls are not included.

### Background activity

While account 2 has a live pairing, bridge **0.1.9** refreshes the supported
client's idle timestamp every 30 seconds on the game thread. This prevents the
background client entering AFK without moving, jumping or changing its camera.
An already-set AFK flag is cleared only if the unit API positively reports it.
The lease stops on disconnect, loading, logout or pairing revocation. Account 1
is unaffected. `/zbox awake off` on account 2 disables it; `awake on` restores it.
An older DLL leaves the other features available and reports the required update
in `/zbox diag`. Restarting alone cannot replace an old game-root DLL: update it
through the launcher after closing both clients.

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

**Stack OFF / Stack ON** appears beside the Mirror button. Turn it on to pulse
account 2 toward account 1's live XY position every two seconds. It is off by
default and the preference is saved per character. Each correction runs for at
most one second, facing the main and running forward to close the gap, then restores the main's
heading and ordinary Mirror inputs once aligned or the pulse ends. Small drift is left alone once
within the input frame's arrival tolerance, avoiding jitter around the goal.
Standing still briefly gives the closest overlap; moving clients, latency and
different movement speeds can still leave a small gap.

Stack operates within 40 yards on the same floor, requires a loaded paired
character and checks the straight route for obstructions. Blocked or stalled
corrections stop their pulse. Cast-time/channel holds suspend correction without
changing cast-facing behavior. Mirror pause, STOP, manual account-2 orders,
NPC interaction, mode changes, loading and connection loss suspend centering.
Reconnect and reload still start Mirror paused, even with Stack saved ON.

Drag or Shift-click Stack to export its paired macro, or bind **Mirror Stack
toggle** in Keys. `/zbox stack` toggles it; `/zbox stack on` and `/zbox stack off`
set it explicitly. Both characters need addon 0.8.1; no additional DLL update is
required for Stack.

## Limits and diagnostics

Remote combat errors stay in the dock and `/zbox diag` by default, including
range, facing and resource failures. Repeated game errors are coalesced before
relaying, and the dock limits repeated feedback. Failed command acknowledgements
also stay out of chat. `/zbox feedback verbose` enables limited diagnostic chat;
`/zbox feedback quiet` restores the default.

Instant melee abilities keep Pet pursuit, Follow, Mirror movement and held
directions running. Resource/unusable-action checks happen before movement
changes. Known positive cast times stop movement before casting; instant and
unknown actions do not stop speculatively. An actual cast/channel start still
holds movement. Failed instant abilities create no cast hold. Held-key renewals
pause during real casts; explicitly changing movement can still interrupt them.

### Account 2 damage through zDNumbers

Enable **zDNumbers 1.0.2+ on both characters**, alongside zBox 0.7.1+. zBox relays
account 2's outgoing damage/result metadata and identifies its GUID as a pet
source. **zBox creates no damage text or frames.** zDNumbers and its embedded
MSBT create, merge, filter and render the numbers using account 1's pet styles.
Normal damage, crits, DoTs and attack results retain target GUIDs, spell icons,
school and result flags. Unlinked characters cannot supply damage events.

Existing zDNumbers pet options apply. With splitting off, the numbers share the
target stream. With **Split pet damage** enabled and **Over the pet** selected,
they anchor over account 2; your actual pet keeps a separate source record.
The target-side option uses account 2's position for its own pet-facing geometry.
Off-screen/unavailable sources use the normal MSBT Pet Outgoing fallback.
No remote fonts/styles or executable text are sent. Diagnostics reports adapter
availability and sent/received counts. Account 2's own pet is not relayed by
this player-source adapter.

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
The expected bridge label is **Native inputs 0.1.11**. An old/missing bridge
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
python tests\test_local_transport.py
python tests\test_feedback_damage.py
python tests\test_companion_convenience.py
python tests\test_mirror_stack.py
python tests\test_roster_trade_bars.py
python tests\test_independent_bars.py
python tests\test_unstuck.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_local_bank.ps1
python tests\test_client_abi.py "<game folder>\WoW.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File native\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_native.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_local_ipc.ps1
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
Convenience fixtures cover agent-only activity leases, stock/pfUI NPC windows,
Talk macros while minimized, independent shared quest progress, and confirmed
linked quest flows with range/eligibility/reward-choice/cancel safeguards. When
the sibling pfQuest is installed, its actual tooltip builder is tested too.
Mirror Stack fixtures exercise varied headings/frame rates over local IPC and
addon messages, pulse timing, live positions, casts, obstacles, manual override,
disconnect/reload, metadata validation, compact layout and paired toggle macros.

`python tests/render_ui.py` renders widget layouts with placeholder icons for
inspection. They are fixture previews, not live game captures. The layout takes
cues from [ShaguController](https://github.com/shagu/ShaguController) and
[Bartender4](https://www.wowace.com/projects/bartender4); no code or artwork from
those projects is included.

## License

zBox is MIT licensed. MinHook and HDE retain their BSD-style licenses in
`native/vendor/minhook/LICENSE.txt` and `native/MINHOOK-LICENSE.txt`. No game
executable, game assets or companion DLLs are distributed.
