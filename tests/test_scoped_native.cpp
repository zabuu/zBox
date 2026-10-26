#include <Windows.h>
#include <cassert>
#include <cstdio>
#include "../native/ScopedInvoke.h"
#include "../native/MovementObserver.h"
#include "../native/NativeMove.h"
#include "../native/NativeWhisper.h"

uint32_t context = 123, depth = 7, bindingExecuting = 0;
volatile LONG busy = 0;
int calls = 0, mode = 0;
int movementCalls = 0, movementResult = 77;
bool moveResult = true;
int moveCalls = 0;
bool __fastcall moveFixture(uintptr_t player, void *, uint32_t mode, const uint64_t *guid, const ZBoxPoint *point, float precision) {
  assert(player==0x1234 && mode==4 && *guid==0 && point->x==1.25f && point->y==-2.5f && point->z==3.0f && precision==0);
  assert(context==123 && depth==7 && bindingExecuting==7 && busy==0);
  ++moveCalls; return moveResult;
}
uint32_t expectedOpcode = 0;
int __fastcall movementFixture(uintptr_t mover, void *, uint32_t timestamp,
                               uint32_t opcode, float value, uint32_t extra) {
  assert(context == 123 && depth == 7 && bindingExecuting == 7 && busy == 0);
  assert(mover == 0x1234 && timestamp == 42 && opcode == expectedOpcode && value == 3.25f && extra == 99);
  ++movementCalls;
  return movementResult;
}
int __fastcall fixture(void *, int arguments, int results, int handler) {
  assert(context == 0 && depth == 8 && bindingExecuting == 1 && arguments == 2 && results == 0 && handler == 0);
  // Lua can stamp a scripted callee again. The real client permission helper
  // then tests manager+0xD8, so clearing only context (the old bridge) is not enough.
  context = 456;
  assert(bindingExecuting != 0);
  ++calls;
  if (mode == 1) return 2; // A protected Lua error.
  if (mode == 2) RaiseException(0xE0123456, 0, 0, nullptr);
  if (mode == 3) assert(ZBoxScopedInvoke(nullptr, fixture, 2, &context, &depth, &bindingExecuting, &busy) == -1);
  depth = 99;
  return 0;
}
int main(int argc, char **argv) {
  for (mode = 0; mode < 4; ++mode) {
    const int result = ZBoxScopedInvoke(nullptr, fixture, 2, &context, &depth, &bindingExecuting, &busy);
    assert(result == (mode == 1 ? 2 : mode == 2 ? -1 : 0));
    assert(context == 123 && depth == 7 && bindingExecuting == 0 && busy == 0);
  }
  assert(calls == 4);
  assert(ZBoxScopedInvoke(nullptr, nullptr, 2, &context, &depth, &bindingExecuting, &busy) == -1);
  assert(ZBoxScopedInvoke(nullptr, fixture, 2, nullptr, &depth, &bindingExecuting, &busy) == -1);
  assert(ZBoxScopedInvoke(nullptr, fixture, 2, &context, &depth, nullptr, &busy) == -1);
  mode = 0; bindingExecuting = 7;
  assert(ZBoxScopedInvoke(nullptr, fixture, 2, &context, &depth, &bindingExecuting, &busy) == 0);
  assert(bindingExecuting == 7 && context == 123 && depth == 7 && busy == 0);
  volatile LONG jumps = 0;
  auto sender = reinterpret_cast<ZBoxMovementSender>(&movementFixture);
  expectedOpcode = 0xDA;
  assert(ZBoxObserveMovement(sender, &jumps, 0x1234, 42, expectedOpcode, 3.25f, 99) == 77 && jumps == 0);
  expectedOpcode = 0xBB; movementResult = 0;
  assert(ZBoxObserveMovement(sender, &jumps, 0x1234, 42, expectedOpcode, 3.25f, 99) == 0 && jumps == 0);
  movementResult = 77;
  assert(ZBoxObserveMovement(sender, &jumps, 0x1234, 42, expectedOpcode, 3.25f, 99) == 77 && jumps == 1);
  jumps = -1;
  assert(ZBoxObserveMovement(sender, &jumps, 0x1234, 42, expectedOpcode, 3.25f, 99) == 77 && jumps == 0);
  assert(movementCalls == 4 && context == 123 && depth == 7 && bindingExecuting == 7 && busy == 0);
  static_assert(sizeof(ZBoxPoint)==12,"Native XYZ layout");
  auto mover=reinterpret_cast<ZBoxMoveTo>(&moveFixture);
  const ZBoxPoint point{1.25f,-2.5f,3.0f};
  assert(ZBoxSubmitMove(mover,0x1234,point));moveResult=false;
  assert(!ZBoxSubmitMove(mover,0x1234,point) && moveCalls==2);
  static_assert(sizeof(ZBoxChatStore)==24,"Client chat store layout");
  uint8_t chatBuffer[384]{}; ZBoxChatStore chat{};
  const char *frame="2~testcode123~session~1~1~1~PING~";
  assert(ZBoxBuildWhisper("OtherName",frame,reinterpret_cast<void *>(0x1234),chat,chatBuffer));
  uint32_t header[3]{};std::memcpy(header,chat.buffer,sizeof(header));
  assert(header[0]==0x95 && header[1]==6 && header[2]==0xFFFFFFFFu);
  assert(chat.buffer==chatBuffer && chat.base==0 && chat.allocation==384 && chat.read==0);
  assert(!std::strcmp(reinterpret_cast<char *>(chat.buffer+12),"OtherName"));
  const char *message=reinterpret_cast<char *>(chat.buffer+22);
  assert(!std::strncmp(message,"zBox2\t",6) && !std::strcmp(message+6,frame));
  assert(chat.size==12+10+6+std::strlen(frame)+1 && chat.size<sizeof(chatBuffer));
  assert(!ZBoxBuildWhisper("",frame,nullptr,chat,chatBuffer));
  assert(!ZBoxBuildWhisper("--",frame,nullptr,chat,chatBuffer));
  assert(!ZBoxBuildWhisper("Bad Name",frame,nullptr,chat,chatBuffer));
  assert(!ZBoxBuildWhisper("Other","ordinary chat",nullptr,chat,chatBuffer));
  assert(!ZBoxBuildWhisper("Other","2~bad|escape",nullptr,chat,chatBuffer));
  assert(!ZBoxBuildWhisper("Other","2~bad\nline",nullptr,chat,chatBuffer));
  char longest[250]{};std::memset(longest,'x',sizeof(longest)-1);longest[0]='2';longest[1]='~';
  assert(!ZBoxBuildWhisper("Other",longest,nullptr,chat,chatBuffer));
  longest[248]=0;assert(ZBoxBuildWhisper("Other",longest,nullptr,chat,chatBuffer));
  if (argc > 1) {
    HMODULE dll = LoadLibraryA(argv[1]);
    assert(dll);
    auto load = reinterpret_cast<DWORD(__cdecl *)()>(GetProcAddress(dll, "Load"));
    assert(load && load() == 2 && load() == 2); // This fixture is not WoW: reject its image, consistently.
    FreeLibrary(dll);
  }
  std::puts("PASS: full binding input context survives Lua restamping; context/depth/executing restored after success, Lua error, SEH, reentry and nested state; unsupported executable rejected");
  std::puts("PASS: native movement observer preserves thiscall arguments, return values and execution context; only completed jump sends increment the counter, including wrap");
  std::puts("PASS: native move submission preserves XYZ layout, fixed ground verb/zero GUID, thiscall arguments, boolean return and input context");
  std::puts("PASS: bounded caller-owned addon whisper envelope, fixed opcode/type/language/prefix, peer validation, printable packet/length checks and no engine allocation");
}
