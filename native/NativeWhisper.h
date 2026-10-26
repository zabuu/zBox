#pragma once
#include <cstdint>
#include <cstring>

struct ZBoxChatStore {
  void *vtable;
  uint8_t *buffer;
  uint32_t base, allocation, size, read;
};
using ZBoxChatSend = void(__thiscall *)(ZBoxChatStore *);

// CMSG_MESSAGECHAT is a u32 opcode followed by u32 type/language. A whisper
// adds the recipient string before the message. This fixed envelope uses the
// ordinary addon language and zBox prefix, not a visible player-chat message.
inline bool ZBoxBuildWhisper(const char *peer, const char *frame, void *vtable,
                            ZBoxChatStore &store, uint8_t (&buffer)[384]) {
  if (!peer || !frame || !*peer) return false;
  const size_t peerLength=std::strlen(peer), frameLength=std::strlen(frame);
  if (peerLength>48 || frameLength<2 || frameLength>248 || frame[0]!='2' || frame[1]!='~') return false;
  if (!((peer[0]>='A' && peer[0]<='Z') || (peer[0]>='a' && peer[0]<='z'))) return false;
  for (size_t i=0;i<peerLength;++i)
    if (!((peer[i]>='A' && peer[i]<='Z') || (peer[i]>='a' && peer[i]<='z') || peer[i]=='-')) return false;
  for (size_t i=0;i<frameLength;++i)
    if (static_cast<unsigned char>(frame[i])<32 || static_cast<unsigned char>(frame[i])>126 || frame[i]=='|') return false;
  const uint32_t header[3]={0x95,6,0xFFFFFFFFu};
  size_t size=sizeof(header);
  std::memcpy(buffer,header,size);
  std::memcpy(buffer+size,peer,peerLength+1); size+=peerLength+1;
  std::memcpy(buffer+size,"zBox2\t",6); size+=6;
  std::memcpy(buffer+size,frame,frameLength+1); size+=frameLength+1;
  // The normal sender consumes the caller-owned store synchronously; normal
  // chat callers free it immediately afterwards. A bounded stack buffer avoids
  // the game's allocator and requires no engine destructor/free call.
  // Chat writers use read=0xFFFFFFFF while constructing, then reset it to 0
  // immediately before submission. NetClient subtracts read from size.
  store={vtable,buffer,0,sizeof(buffer),static_cast<uint32_t>(size),0};
  return true;
}
