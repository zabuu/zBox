#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <cstdio>
#include "MinHook.h"
#include "ScopedInvoke.h"

namespace {
uintptr_t base = 0;
volatile LONG initialized = 0, busy = 0;
volatile LONG installDone = 0, installResult = 1;
using CFunction = int(__fastcall *)(void *);
using Register = void(__fastcall *)(const char *, CFunction);
using Type = int(__fastcall *)(void *, int);
using Top = int(__fastcall *)(void *);
using SetTop = void(__fastcall *)(void *, int);
using ToString = const char *(__fastcall *)(void *, int);
using ToNumber = double(__fastcall *)(void *, int);
using PushString = void(__fastcall *)(void *, const char *);
using PushNumber = void(__fastcall *)(void *, double);
using PushValue = void(__fastcall *)(void *, int);
using GetTable = void(__fastcall *)(void *, int);
Register originalRegister = nullptr;
unsigned long calls = 0;
char lastCommand[48] = "none";
int lastResult = -1;

template<class T> T at(uintptr_t address) {
  return reinterpret_cast<T>(base + address - 0x00400000);
}
int type(void *L, int index) { return at<Type>(0x006F3400)(L, index); }
const char *str(void *L, int index) { return at<ToString>(0x006F3690)(L, index); }
bool number(void *L, int index, int low, int high) {
  if (type(L, index) != 3) return false;
  const double n = at<ToNumber>(0x006F3620)(L, index);
  return std::isfinite(n) && std::floor(n) == n && n >= low && n <= high;
}
bool unit(void *L, int index) {
  if (type(L, index) != 4) return false;
  const char *value = str(L, index);
  if (!value || !*value || std::strlen(value) > 48) return false;
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(value); *p; ++p)
    if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
          (*p >= '0' && *p <= '9') || *p == '-')) return false;
  return true;
}

uint32_t *bindingFlag() {
  // Both the real binding dispatcher and permission helper 0x494A50 use +0xD8.
  const uintptr_t manager = *at<uintptr_t *>(0x00B71290);
  if (!manager || manager > UINTPTR_MAX - 0xDC) return nullptr;
  MEMORY_BASIC_INFORMATION region{};
  const uintptr_t address = manager + 0xD8;
  if (!VirtualQuery(reinterpret_cast<void *>(address), &region, sizeof(region)) ||
      region.State != MEM_COMMIT || (region.Protect & (PAGE_GUARD | PAGE_NOACCESS)) ||
      (region.Protect & (PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) == 0 ||
      address + sizeof(uint32_t) > reinterpret_cast<uintptr_t>(region.BaseAddress) + region.RegionSize) return nullptr;
  return reinterpret_cast<uint32_t *>(address);
}

int validate(void *L, const char *name) {
  const char *noArgs[] = { "MoveForwardStart", "MoveForwardStop", "MoveBackwardStart", "MoveBackwardStop",
    "TurnLeftStart", "TurnLeftStop", "TurnRightStart", "TurnRightStop", "StrafeLeftStart", "StrafeLeftStop",
    "StrafeRightStart", "StrafeRightStop", "Jump", "SpellStopCasting", "SpellStopTargeting", "AttackTarget", "ClearTarget" };
  for (const char *allowed : noArgs) if (!std::strcmp(name, allowed)) return 0;
  if (!std::strcmp(name, "TargetUnit") || !std::strcmp(name, "FollowUnit") || !std::strcmp(name, "AssistUnit"))
    return unit(L, 2) ? 1 : -1;
  if (!std::strcmp(name, "UseAction"))
    return number(L, 2, 1, 120) && number(L, 3, 0, 0) &&
      (type(L, 4) == 0 || number(L, 4, 1, 1)) ? 3 : -1;
  if (!std::strcmp(name, "CastSpell"))
    return number(L, 2, 1, 960) && type(L, 3) == 4 && !std::strcmp(str(L, 3), "spell") ? 2 : -1;
  if (!std::strcmp(name, "PickupContainerItem") || !std::strcmp(name, "UseContainerItem"))
    return number(L, 2, 0, 4) && number(L, 3, 1, 36) ? 2 : -1;
  if (!std::strcmp(name, "EquipCursorItem") || !std::strcmp(name, "PickupInventoryItem"))
    return number(L, 2, 0, 19) ? 1 : -1;
  if (!std::strcmp(name, "LearnTalent"))
    return number(L, 2, 1, 3) && number(L, 3, 1, 40) ? 2 : -1;
  return -1;
}

int response(void *L, bool ok, const char *detail) {
  at<PushNumber>(0x006F3810)(L, ok ? 1 : 0);
  at<PushString>(0x006F3890)(L, detail);
  return 2;
}

int __fastcall bridge(void *L) {
  if (type(L, 1) != 4) return response(L, false, "Expected a fixed API command");
  const char *name = str(L, 1);
  if (!std::strcmp(name, "version")) return response(L, true, "zBoxBridge 0.1.3");
  if (!std::strcmp(name, "capabilities")) {
    response(L, true, "zBoxBridge 0.1.3");
    at<PushNumber>(0x006F3810)(L, 2);
    return 3;
  }
  if (!std::strcmp(name, "status")) {
    char detail[180]{};
    sprintf_s(detail, "zBoxBridge 0.1.3; calls=%lu; last=%s; result=%d", calls, lastCommand, lastResult);
    return response(L, true, detail);
  }
  const int arguments = validate(L, name);
  if (arguments < 0) return response(L, false, "API or arguments are not allowed");
  if (*at<uint8_t *>(0x00B4B424) == 0) return response(L, false, "Player is not in the world");
  uint32_t *executing = bindingFlag();
  if (!executing) return response(L, false, "Client input manager is unavailable");
  const int oldTop = at<Top>(0x006F3070)(L);
  at<PushString>(0x006F3890)(L, name);
  at<GetTable>(0x006F3A40)(L, -10001); // Lua 5.0 GLOBALS_INDEX
  if (type(L, -1) != 6) {
    at<SetTop>(0x006F3080)(L, oldTop);
    return response(L, false, "API function is unavailable");
  }
  for (int i = 0; i < arguments; ++i) at<PushValue>(0x006F3350)(L, i + 2);
  strncpy_s(lastCommand, name, _TRUNCATE);
  ++calls;
  const int result = ZBoxScopedInvoke(L, at<ZBoxPCall>(0x006F41A0), arguments,
    at<uint32_t *>(0x00CEEAC0), at<uint32_t *>(0x00CEEAC4), executing, &busy);
  lastResult = result;
  if (result > 0 && type(L, -1) == 4) {
    // Preserve the Lua error as a result, then remove the internal stack entries.
    char error[320]{};
    strncpy_s(error, str(L, -1), _TRUNCATE);
    at<SetTop>(0x006F3080)(L, oldTop);
    return response(L, false, error);
  }
  at<SetTop>(0x006F3080)(L, oldTop);
  return response(L, result == 0, result == 0 ? "Requested" : "Native input failed or reentered");
}

void __fastcall registerHook(const char *name, CFunction function) {
  originalRegister(name, function);
  if (name && !std::strcmp(name, "UnitXP")) originalRegister("zBoxNative", &bridge);
}

bool compatible() {
  __try {
    auto dos = reinterpret_cast<IMAGE_DOS_HEADER *>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 0x100000) return false;
    auto nt = reinterpret_cast<IMAGE_NT_HEADERS32 *>(base + dos->e_lfanew);
    return nt->Signature == IMAGE_NT_SIGNATURE && nt->FileHeader.Machine == IMAGE_FILE_MACHINE_I386 &&
      nt->FileHeader.TimeDateStamp == 0x4510B6DB && nt->OptionalHeader.SizeOfImage == 0x0092B000;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

DWORD install() {
  base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  if (!compatible()) return 2;
  if (MH_Initialize() != MH_OK) return 3;
  void *entry = at<void *>(0x00704120);
  if (MH_CreateHook(entry, reinterpret_cast<void *>(&registerHook),
      reinterpret_cast<void **>(&originalRegister)) != MH_OK) return 4;
  if (MH_EnableHook(entry) != MH_OK) return 5;
  return 0;
}
DWORD ensureInstalled() {
  if (InterlockedCompareExchange(&initialized, 1, 0) == 0) {
    installResult = static_cast<LONG>(install());
    InterlockedExchange(&installDone, 1);
  } else {
    while (InterlockedCompareExchange(&installDone, 0, 0) == 0) Sleep(1);
  }
  return static_cast<DWORD>(installResult);
}
DWORD WINAPI worker(void *) { return ensureInstalled(); }
}

extern "C" DWORD Load() { return ensureInstalled(); }
BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(module);
    if (GetModuleHandleW(L"VfPatcher.dll") == nullptr) {
      HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
      if (thread) CloseHandle(thread);
    }
  }
  return TRUE;
}
