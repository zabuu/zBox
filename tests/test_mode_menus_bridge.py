"""Movement/pet-approach dropdowns, and bridge 0.1.11 with a failed jump hook keeps its other features."""
from test_zbox import endpoint

lua = endpoint("Main", "Alt", True, independent=True)
lua.execute('''
zBoxNative=function(cmd) if cmd=="capabilities" then return 1,"zBoxBridge 0.1.11",3 end;return 1 end
zBox.bridgeInfo=nil
local i=zBox:GetBridgeInfo()
assert(i.ready and i.nativeMove and i.localIPC and i.multiLocal and i.trade and i.unstuck and not i.jumpEvents)
assert(zBox:SetMovementMode("pet"))
local ok,why=zBox:SetMovementMode("mirror");assert(not ok and string.find(why,"jump hook did not load"))
''')
print('PASS: bridge 0.1.11 whose jump hook failed still enables Pet, local IPC and trades; Mirror explains the real cause')

lua.execute('''
local u=zBox.UI
u:ShowSetup()
u.modeButton.scripts.OnClick();local m=u.choiceMenu
assert(m:IsShown() and m.rows[1].text:GetText()=="Follow" and m.rows[3]:IsShown() and not m.rows[4]:IsShown())
this=m.rows[3];m.rows[3].scripts.OnClick()
assert(zBox:MovementMode()=="pet" and not m:IsShown())
u.petStyleButton.scripts.OnClick();assert(m:IsShown() and m.rows[1].text:GetText()=="Auto (class)")
this=m.rows[2];m.rows[2].scripts.OnClick();assert(zBox.db.petStyle=="melee")
this=u.followButton;arg1="RightButton";u.followButton.scripts.OnClick()
assert(m:IsShown() and m.anchor==u.followButton and m.rows[3].check:IsShown())
this=m.rows[1];m.rows[1].scripts.OnClick();assert(zBox:MovementMode()=="follow")
''')
print('PASS: movement mode, pet approach and the Follow button right-click open dropdowns')

