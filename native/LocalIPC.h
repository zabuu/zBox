#pragma once
#include <Windows.h>
#include <bcrypt.h>
#include <Aclapi.h>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <string>
#include <vector>

// Same-logon-session, same-user, paired processes only. No sockets, window
// messages, worker-thread Lua, or game memory access. Every mutex wait is zero.
namespace ZBoxIPC {
constexpr uint32_t Magic=0x5A424C31, Layout=1, FrameLimit=4352, Capacity=32;
constexpr ULONGLONG PeerLease=2000, FrameLease=1000;
struct Frame { uint64_t sender, receiver, at; uint32_t length; char text[FrameLimit+1]; };
struct Ring { uint32_t head, tail; Frame frames[Capacity]; };
struct Slot {
  DWORD pid; uint64_t created, epoch, seen;
  uint32_t emergency; Frame stop; Ring high, low;
};
struct Shared { uint32_t magic, layout; Slot slots[2]; };

inline bool Name(const char *text) {
  if (!text || !*text || std::strlen(text)>48) return false;
  for (const char *p=text; *p; ++p)
    if (!((*p>='A' && *p<='Z') || (*p>='a' && *p<='z') || (p!=text && *p=='-'))) return false;
  return true;
}
inline std::string Lower(const char *text) {
  std::string out=text;
  for (char &c:out) if (c>='A' && c<='Z') c+=32;
  return out;
}
inline bool Identity(const char *realm,const char *own,const char *peer,const char *key,
                     int role,std::string &out) {
  if (!realm || !*realm || std::strlen(realm)>128 || !Name(own) || !Name(peer) ||
      !key || std::strlen(key)<8 || std::strlen(key)>32 || (role!=0 && role!=1)) return false;
  for (const char *p=key;*p;++p)
    if (!((*p>='A' && *p<='Z') || (*p>='a' && *p<='z') || (*p>='0' && *p<='9') || *p=='_' || *p=='-')) return false;
  std::string main=Lower(role==0?own:peer), alt=Lower(role==0?peer:own);
  if (main==alt) return false;
  BCRYPT_ALG_HANDLE algorithm=nullptr; BCRYPT_HASH_HANDLE hash=nullptr; uint8_t digest[32]{};
  if (BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) return false;
  bool ok=BCryptCreateHash(algorithm,&hash,nullptr,0,nullptr,0,0)>=0;
  const std::string fields[]={"zBox local IPC v1",realm,main,alt,key};
  for (const auto &field:fields) {
    uint32_t length=static_cast<uint32_t>(field.size());
    if (ok) ok=BCryptHashData(hash,reinterpret_cast<PUCHAR>(&length),sizeof(length),0)>=0 &&
      BCryptHashData(hash,reinterpret_cast<PUCHAR>(const_cast<char *>(field.data())),length,0)>=0;
  }
  if (ok) ok=BCryptFinishHash(hash,digest,sizeof(digest),0)>=0;
  if (hash) BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(algorithm,0);
  if (!ok) return false;
  out="Local\\zBox.IPC.v1.";
  for (uint8_t byte:digest) { char hex[3]{}; sprintf_s(hex,"%02x",byte);out+=hex; }
  return true;
}

class Security {
  PACL acl_=nullptr;
  SECURITY_DESCRIPTOR descriptor_{};
public:
  SECURITY_ATTRIBUTES attributes{};
  ~Security() { if (acl_) LocalFree(acl_); }
  bool Init() {
    HANDLE token=nullptr; DWORD length=0;
    if (!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) return false;
    GetTokenInformation(token,TokenUser,nullptr,0,&length);
    std::vector<uint8_t> user(length);
    const bool read=length && GetTokenInformation(token,TokenUser,user.data(),length,&length);
    CloseHandle(token); if (!read) return false;
    EXPLICIT_ACCESSA access{}; access.grfAccessPermissions=GENERIC_ALL;
    access.grfAccessMode=SET_ACCESS; access.grfInheritance=NO_INHERITANCE;
    BuildTrusteeWithSidA(&access.Trustee,reinterpret_cast<TOKEN_USER *>(user.data())->User.Sid);
    if (SetEntriesInAclA(1,&access,nullptr,&acl_)!=ERROR_SUCCESS ||
        !InitializeSecurityDescriptor(&descriptor_,SECURITY_DESCRIPTOR_REVISION) ||
        !SetSecurityDescriptorDacl(&descriptor_,TRUE,acl_,FALSE)) return false;
    attributes={sizeof(attributes),&descriptor_,FALSE}; return true;
  }
};

class Endpoint {
  HANDLE mutex_=nullptr, mapping_=nullptr;
  Shared *shared_=nullptr;
  std::string identity_;
  int role_=0; uint64_t epoch_=0;
  uint64_t sent_=0, received_=0;
  const char *error_="Local IPC closed";
  bool Lock() {
    if (!mutex_ || !shared_) { error_="Local IPC closed";return false; }
    const DWORD result=WaitForSingleObject(mutex_,0);
    if (result!=WAIT_OBJECT_0 && result!=WAIT_ABANDONED) { error_="Local IPC busy";return false; }
    if (result==WAIT_ABANDONED || shared_->magic!=Magic || shared_->layout!=Layout) {
      ZeroMemory(shared_,sizeof(*shared_)); shared_->magic=Magic;shared_->layout=Layout;
    }
    return true;
  }
  bool Own() const { return shared_->slots[role_].pid==GetCurrentProcessId() && shared_->slots[role_].epoch==epoch_; }
  bool Peer(uint64_t now) const {
    const Slot &s=shared_->slots[1-role_];
    return s.pid && s.pid!=GetCurrentProcessId() && s.epoch && now>=s.seen && now-s.seen<PeerLease;
  }
  static bool Alive(const Slot &s) {
    HANDLE process=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,s.pid);
    if (!process) return false;
    FILETIME created{},exited{},kernel{},user{};
    const bool alive=WaitForSingleObject(process,0)==WAIT_TIMEOUT && GetProcessTimes(process,&created,&exited,&kernel,&user) &&
      (static_cast<uint64_t>(created.dwHighDateTime)<<32|created.dwLowDateTime)==s.created;
    CloseHandle(process); return alive;
  }
  static void Reset(Ring &ring) { ring.head=ring.tail=0; }
  bool Valid(const Frame &frame,uint64_t now) const {
    if (frame.sender!=shared_->slots[1-role_].epoch || frame.receiver!=epoch_ ||
        !frame.length || frame.length>FrameLimit || frame.text[frame.length]!=0 ||
        now<frame.at || now-frame.at>FrameLease) return false;
    return true;
  }
public:
  Endpoint()=default;
  Endpoint(const Endpoint &)=delete;
  Endpoint &operator=(const Endpoint &)=delete;
  ~Endpoint() { Close(); }
  const char *Error() const { return error_; }
  void Close() {
    if (Lock()) {
      if (Own()) ZeroMemory(&shared_->slots[role_],sizeof(Slot));
      ReleaseMutex(mutex_);
    }
    if (shared_) UnmapViewOfFile(shared_);
    if (mapping_) CloseHandle(mapping_);
    if (mutex_) CloseHandle(mutex_);
    shared_=nullptr;mapping_=mutex_=nullptr;epoch_=0;identity_.clear();
  }
  // 1=opened, 0=retry without waiting, -1=invalid/unavailable.
  int Open(const char *realm,const char *own,const char *peer,const char *key,int role) {
    std::string identity;
    if (!Identity(realm,own,peer,key,role,identity)) { error_="Invalid local pairing";return -1; }
    if (shared_ && identity==identity_ && role==role_ && epoch_) return 1;
    Close(); role_=role;
    Security security; if (!security.Init()) { error_="Local IPC user access unavailable";return -1; }
    mutex_=CreateMutexA(&security.attributes,FALSE,(identity+".lock").c_str());
    if (!mutex_) { error_="Local IPC mutex unavailable";return -1; }
    mapping_=CreateFileMappingA(INVALID_HANDLE_VALUE,&security.attributes,PAGE_READWRITE,0,sizeof(Shared),(identity+".data").c_str());
    if (mapping_) shared_=static_cast<Shared *>(MapViewOfFile(mapping_,FILE_MAP_ALL_ACCESS,0,0,sizeof(Shared)));
    if (!shared_) { Close();error_="Local IPC mapping unavailable";return -1; }
    if (!Lock()) { Close();return 0; }
    Slot &slot=shared_->slots[role_];
    if (slot.pid && slot.pid!=GetCurrentProcessId() && Alive(slot)) {
      ReleaseMutex(mutex_);Close();error_="Another local client owns this pairing role";return -1;
    }
    FILETIME created{},exited{},kernel{},user{};
    uint64_t epoch=0;
    if (!GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user) ||
        BCryptGenRandom(nullptr,reinterpret_cast<PUCHAR>(&epoch),sizeof(epoch),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0 || !epoch) {
      ReleaseMutex(mutex_);Close();error_="Local IPC identity unavailable";return -1;
    }
    ZeroMemory(&slot,sizeof(slot));slot.pid=GetCurrentProcessId();slot.epoch=epoch;
    slot.created=static_cast<uint64_t>(created.dwHighDateTime)<<32|created.dwLowDateTime;
    slot.seen=GetTickCount64(); epoch_=epoch;identity_=identity;
    ReleaseMutex(mutex_);error_="Local IPC open";return 1;
  }
  int Info(uint64_t &peerEpoch,char (&detail)[160]) {
    if (!Lock()) return 0;
    if (!Own()) { ReleaseMutex(mutex_);error_="Local IPC identity lost";return -1; }
    const uint64_t now=GetTickCount64();shared_->slots[role_].seen=now;
    peerEpoch=Peer(now)?shared_->slots[1-role_].epoch:0;
    sprintf_s(detail,"Local DLL IPC; sent=%llu; received=%llu",sent_,received_);
    ReleaseMutex(mutex_);return 1;
  }
  void Discard() {
    if (!Lock()) return;
    if (Own()) { Slot &slot=shared_->slots[role_];slot.emergency=0;Reset(slot.high);Reset(slot.low); }
    ReleaseMutex(mutex_);
  }
  int Send(const char *text,int priority) {
    if (!text || priority<0 || priority>2) { error_="Invalid local frame";return -1; }
    const size_t length=std::strlen(text);
    if (length<2 || length>FrameLimit || text[0]!='2' || text[1]!='~') { error_="Invalid local frame";return -1; }
    for (size_t i=0;i<length;++i) if (text[i]<32 || static_cast<unsigned char>(text[i])>126 || text[i]=='|') { error_="Invalid local frame";return -1; }
    if (!Lock()) return 0;
    const uint64_t now=GetTickCount64();
    if (!Own() || !Peer(now)) { ReleaseMutex(mutex_);error_="Local peer unavailable";return -1; }
    shared_->slots[role_].seen=now;Slot &peer=shared_->slots[1-role_];Frame *frame=nullptr;
    if (priority==2) { Reset(peer.high);Reset(peer.low);peer.emergency=1;frame=&peer.stop; }
    else {
      Ring &ring=priority?peer.high:peer.low;
      if (ring.tail-ring.head>=Capacity) { ReleaseMutex(mutex_);error_="Local IPC queue full";return 0; }
      frame=&ring.frames[ring.tail%Capacity];++ring.tail;
    }
    frame->sender=epoch_;frame->receiver=peer.epoch;frame->at=now;frame->length=static_cast<uint32_t>(length);
    std::memcpy(frame->text,text,length+1);++sent_;
    ReleaseMutex(mutex_);return 1;
  }
  int Receive(char (&text)[FrameLimit+1]) {
    if (!Lock()) return 0;
    const uint64_t now=GetTickCount64();
    if (!Own()) { ReleaseMutex(mutex_);error_="Local IPC identity lost";return -1; }
    Slot &slot=shared_->slots[role_];slot.seen=now;
    Frame *found=nullptr;
    if (slot.emergency) { slot.emergency=0;if (Valid(slot.stop,now)) found=&slot.stop; }
    Ring *rings[]={&slot.high,&slot.low};
    for (Ring *ring:rings) {
      if (ring->tail-ring->head>Capacity) Reset(*ring);
      while (!found && ring->head!=ring->tail) {
        Frame &candidate=ring->frames[ring->head%Capacity];++ring->head;
        if (Valid(candidate,now)) found=&candidate;
      }
    }
    if (found) { std::memcpy(text,found->text,found->length+1);++received_; }
    ReleaseMutex(mutex_);return found?1:0;
  }
};
}
