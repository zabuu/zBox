#pragma once
#include <cstdint>

struct ZBoxPoint { float x, y, z; };
using ZBoxMoveTo = bool(__thiscall *)(uintptr_t, uint32_t, const uint64_t *, const ZBoxPoint *, float);

// Same fixed move verb and arguments as the client's ground-click path.
// GUID zero means a location, never an interaction with another unit.
inline bool ZBoxSubmitMove(ZBoxMoveTo move, uintptr_t player, const ZBoxPoint &point) {
  const uint64_t noUnit = 0;
  return move(player, 4, &noUnit, &point, 0.0f);
}
