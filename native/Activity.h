#pragma once
#include <cstdint>

// Same timestamp consumed by the supported client's ordinary AFK/idle check.
// A live Lua pairing lease controls invocation; there is no resident timer.
inline bool ZBoxRefreshActivity(bool inWorld, uint32_t *lastInput, uint32_t now) {
  if (!inWorld || !lastInput) return false;
  *lastInput=now;
  return true;
}
