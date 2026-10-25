#pragma once
#include <Windows.h>
#include <cstdint>

// Used only after the caller selected a fixed API name and checked primitive
// argument types/ranges. No received Lua, macro text or function pointer enters.
using ZBoxPCall = int(__fastcall *)(void *, int, int, int);
inline int ZBoxScopedInvoke(void *L, ZBoxPCall pcall, int arguments,
                           uint32_t *context, uint32_t *depth,
                           uint32_t *bindingExecuting, volatile LONG *busy) {
  if (!pcall || !context || !depth || !bindingExecuting || !busy ||
      InterlockedCompareExchange(busy, 1, 0) != 0) return -1;
  int result = -1;
  __try {
    const uint32_t savedContext = *context;
    const uint32_t savedDepth = *depth;
    const uint32_t savedExecuting = *bindingExecuting;
    __try {
      // Mirror the real key-binding dispatcher, not just the context pointer.
      // Entering Lua can restore a script stamp. The client's input permission
      // helper then also checks the binding manager at +0xD8.
      *depth = savedDepth + 1;
      *context = 0;
      *bindingExecuting = 1;
      result = pcall(L, arguments, 0, 0);
    } __finally {
      *bindingExecuting = savedExecuting;
      *context = savedContext;
      *depth = savedDepth;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    result = -1;
  }
  InterlockedExchange(busy, 0);
  return result;
}
