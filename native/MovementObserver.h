#pragma once
#include <Windows.h>
#include <cstdint>

using ZBoxMovementSender = int(__thiscall *)(uintptr_t, uint32_t, uint32_t, float, uint32_t);

// Observe completed native jumps without entering Lua or changing its execution
// context. Preserve every argument and the original return value. Ordinary
// movement, heading updates and failed sends never create a jump event.
inline int ZBoxObserveMovement(ZBoxMovementSender original, volatile LONG *jumps,
                              uintptr_t mover, uint32_t timestamp, uint32_t opcode,
                              float value, uint32_t extra) {
  const int result = original(mover, timestamp, opcode, value, extra);
  if (opcode == 0xBB && result != 0) InterlockedIncrement(jumps);
  return result;
}
