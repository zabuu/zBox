#include <Windows.h>
#include <cassert>
#include <cstdio>
#include "../native/ScopedInvoke.h"
#include "../native/MovementObserver.h"

uint32_t context = 123, depth = 7, bindingExecuting = 0;
volatile LONG busy = 0;
int calls = 0, mode = 0;
int movementCalls = 0, movementResult = 77;
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
  if (argc > 1) {
    HMODULE dll = LoadLibraryA(argv[1]);
    assert(dll);
    auto load = reinterpret_cast<DWORD(__cdecl *)()>(GetProcAddress(dll, "Load"));
    assert(load && load() == 2 && load() == 2); // This fixture is not WoW: reject its image, consistently.
    FreeLibrary(dll);
  }
  std::puts("PASS: full binding input context survives Lua restamping; context/depth/executing restored after success, Lua error, SEH, reentry and nested state; unsupported executable rejected");
  std::puts("PASS: native movement observer preserves thiscall arguments, return values and execution context; only completed jump sends increment the counter, including wrap");
}
