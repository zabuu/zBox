#pragma once
#include "LocalIPC.h"
#include <memory>
#include <cstring>
#include <cctype>
namespace ZBoxIPC {
class Bank {
  struct Slot { char name[49]{}; std::unique_ptr<Endpoint> endpoint; };
  Slot slots[16]; unsigned current=0;
public:
  bool Select(const char *name) {
    if (!name || !*name || std::strlen(name)>48) return false;
    char key[49]{};unsigned n=0;
    for (;name[n];++n) {
      const auto c=static_cast<unsigned char>(name[n]);
      if (!std::isalpha(c) && c!='-') return false;
      key[n]=static_cast<char>(std::tolower(c));
    }
    for(unsigned i=0;i<16;++i) if(!std::strcmp(slots[i].name,key)) {current=i;return true;}
    for(unsigned i=0;i<16;++i) if(!*slots[i].name) {
      std::strcpy(slots[i].name,key);slots[i].endpoint.reset(new Endpoint);current=i;return true;
    }
    return false;
  }
  Endpoint &Current() {
    if(!slots[current].endpoint) slots[current].endpoint.reset(new Endpoint);
    return *slots[current].endpoint;
  }
  void CloseAll() {
    for(auto &slot:slots) {slot.endpoint.reset();slot.name[0]=0;}
    current=0;
  }
};
}
