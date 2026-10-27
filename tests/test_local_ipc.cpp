#include "../native/LocalIPC.h"
#include <cassert>
#include <algorithm>
#include <vector>

using namespace ZBoxIPC;
static const char *Key="native-test-code";
static HANDLE Event(const std::string &realm) { return CreateEventA(nullptr,TRUE,FALSE,("Local\\zBox.test."+realm).c_str()); }
static PROCESS_INFORMATION Spawn(const char *exe,const std::string &realm,const char *mode) {
  std::string command="\""+std::string(exe)+"\" --child "+realm+" "+mode;
  STARTUPINFOA startup{sizeof(startup)};PROCESS_INFORMATION process{};
  assert(CreateProcessA(nullptr,&command[0],nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process));
  CloseHandle(process.hThread);return process;
}
static void Finish(PROCESS_INFORMATION process) {
  assert(WaitForSingleObject(process.hProcess,10000)==WAIT_OBJECT_0);
  DWORD code=1;assert(GetExitCodeProcess(process.hProcess,&code) && code==0);CloseHandle(process.hProcess);
}
static uint64_t PeerEpoch(Endpoint &endpoint) {
  uint64_t epoch=0;char detail[160]{};int result=0;const auto until=GetTickCount64()+3000;
  do { result=endpoint.Info(epoch,detail);assert(result>=0 && GetTickCount64()<until);if (!result) Sleep(0); } while (!result);
  return epoch;
}
static bool Send(Endpoint &endpoint,const char *text,int priority=1) {
  int result=0;const auto until=GetTickCount64()+3000;
  do { result=endpoint.Send(text,priority);assert(result>=0 && GetTickCount64()<until);if (!result) Sleep(0); } while (!result);
  return result==1;
}
static int Open(Endpoint &endpoint,const std::string &realm,int role) {
  int result=0;const auto until=GetTickCount64()+3000;
  do {
    result=endpoint.Open(realm.c_str(),role?"Alt":"Main",role?"Main":"Alt",Key,role);
    assert(GetTickCount64()<until);if (!result) Sleep(0);
  } while (!result);
  return result;
}
static void WaitPeer(Endpoint &endpoint) {
  const auto until=GetTickCount64()+3000;
  while (!PeerEpoch(endpoint) && GetTickCount64()<until) Sleep(1);
  assert(PeerEpoch(endpoint));
}
static std::string Read(Endpoint &endpoint) {
  char text[FrameLimit+1]{};const auto until=GetTickCount64()+3000;
  for (;;) {
    const int result=endpoint.Receive(text);assert(result>=0);
    if (result==1) return text;
    assert(GetTickCount64()<until);Sleep(0);
  }
}
struct Held { HANDLE mutex,ready,release; };
static DWORD WINAPI Hold(void *context) {
  auto h=static_cast<Held *>(context);
  assert(WaitForSingleObject(h->mutex,1000)==WAIT_OBJECT_0);SetEvent(h->ready);
  WaitForSingleObject(h->release,1000);ReleaseMutex(h->mutex);return 0;
}

int main(int argc,char **argv) {
  if (argc==4 && !std::strcmp(argv[1],"--child")) {
    const std::string realm=argv[2];const char *mode=argv[3];
    if (!std::strcmp(mode,"abandon")) {
      std::string identity;assert(Identity(realm.c_str(),"Main","Alt",Key,0,identity));
      HANDLE mutex=OpenMutexA(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,(identity+".lock").c_str());
      assert(mutex && WaitForSingleObject(mutex,1000)==WAIT_OBJECT_0);ExitProcess(0);
    }
    Endpoint agent;
    if (!std::strcmp(mode,"duplicate")) {
      assert(Open(agent,realm,0)==-1);return 0;
    }
    assert(Open(agent,realm,1)==1);
    HANDLE go=Event(realm);assert(go);
    assert(WaitForSingleObject(go,5000)==WAIT_OBJECT_0);CloseHandle(go);
    if (!std::strcmp(mode,"restart")) { agent.Close();assert(Open(agent,realm,1)==1); }
    assert(Send(agent,"2~ready"));
    const auto until=GetTickCount64()+15000;
    for (;;) {
      assert(GetTickCount64()<until);
      uint64_t peer=0;char detail[160]{};const int status=agent.Info(peer,detail);assert(status>=0);
      char text[FrameLimit+1]{};const int result=agent.Receive(text);assert(result>=0);
      if (result==1) {
        if (!std::strcmp(text,"2~quit")) break;
        int sent=0;do { sent=agent.Send(text,1);if (!sent) Sleep(0); } while (!sent);
        assert(sent==1);
      } else Sleep(0);
    }
    return 0;
  }
  std::string a,b,c;
  assert(Identity("realm","MAIN","alt",Key,0,a));assert(Identity("realm","ALT","main",Key,1,b) && a==b);
  assert(Identity("realm","Alt","Main",Key,0,c) && a!=c);
  assert(Identity("other","MAIN","alt",Key,0,c) && a!=c);
  assert(Identity("realm","MAIN","alt","another-code",0,c) && a!=c);
  assert(a.find(Key)==std::string::npos);
  assert(!Identity("realm","Main","Main",Key,0,c) && !Identity("realm","bad name","Alt",Key,0,c));
  assert(!Identity("realm","Main","Alt","short",0,c));
  char exe[MAX_PATH]{};assert(GetModuleFileNameA(nullptr,exe,MAX_PATH));
  const std::string realm="zbox-"+std::to_string(GetCurrentProcessId())+"-"+std::to_string(GetTickCount64());
  Endpoint main;assert(main.Open(realm.c_str(),"Main","Alt",Key,0)==1);
  assert(!PeerEpoch(main) && main.Send("2~nopeer",1)==-1);
  HANDLE go=Event(realm);auto child=Spawn(exe,realm,"echo");WaitPeer(main);
  Finish(Spawn(exe,realm,"duplicate"));
  assert(main.Send("ordinary chat",1)==-1 && main.Send("2~bad|pipe",1)==-1);
  std::string oversized="2~"+std::string(FrameLimit,'x');assert(main.Send(oversized.c_str(),1)==-1);
  // A full low-priority ring cannot consume the command lane or Stop slot.
  for (unsigned i=0;i<Capacity;++i) assert(main.Send("2~bulk",0)==1);
  assert(main.Send("2~full",0)==0 && main.Send("2~command",1)==1);
  assert(main.Send("2~STOP",2)==1);
  SetEvent(go);assert(Read(main)=="2~ready" && Read(main)=="2~STOP");
  char empty[FrameLimit+1]{};assert(main.Receive(empty)==0);
  // Actual cross-process round trips through the production implementation.
  LARGE_INTEGER frequency{};QueryPerformanceFrequency(&frequency);std::vector<double> samples;
  std::string payload="2~"+std::string(4000,'x');
  for (int i=0;i<200;++i) {
    LARGE_INTEGER start{},end{};QueryPerformanceCounter(&start);
    assert(Send(main,payload.c_str()) && Read(main)==payload);
    QueryPerformanceCounter(&end);samples.push_back((end.QuadPart-start.QuadPart)*1000.0/frequency.QuadPart);
  }
  std::sort(samples.begin(),samples.end());
  std::printf("PASS: 200 real x86 process round trips, 4002-byte frames; median %.3f ms, p95 %.3f ms (native IPC only)\n",samples[100],samples[190]);
  // Contention must return promptly on the game thread, never wait for the holder.
  std::string identity;assert(Identity(realm.c_str(),"Main","Alt",Key,0,identity));
  Held held{OpenMutexA(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,(identity+".lock").c_str()),CreateEventA(nullptr,TRUE,FALSE,nullptr),CreateEventA(nullptr,TRUE,FALSE,nullptr)};
  HANDLE thread=CreateThread(nullptr,0,Hold,&held,0,nullptr);assert(thread);
  assert(WaitForSingleObject(held.ready,1000)==WAIT_OBJECT_0);
  const auto before=GetTickCount64();assert(main.Send("2~busy",1)==0 && GetTickCount64()-before<100);
  SetEvent(held.release);assert(WaitForSingleObject(thread,1000)==WAIT_OBJECT_0);
  CloseHandle(thread);CloseHandle(held.mutex);CloseHandle(held.ready);CloseHandle(held.release);
  assert(Send(main,"2~quit"));Finish(child);CloseHandle(go);
  // New process/slot generations cannot consume old queued commands.
  const std::string restartRealm=realm+"restart";main.Close();assert(main.Open(restartRealm.c_str(),"Main","Alt",Key,0)==1);
  go=Event(restartRealm);child=Spawn(exe,restartRealm,"restart");WaitPeer(main);const auto old=PeerEpoch(main);
  assert(main.Send("2~old-command",1)==1);SetEvent(go);assert(Read(main)=="2~ready");
  assert(PeerEpoch(main)!=old);assert(Send(main,"2~fresh") && Read(main)=="2~fresh");
  assert(main.Receive(empty)==0);assert(Send(main,"2~quit"));Finish(child);CloseHandle(go);
  // Stale frames expire even if a paused client returns before the peer lease.
  const std::string staleRealm=realm+"stale";main.Close();assert(main.Open(staleRealm.c_str(),"Main","Alt",Key,0)==1);
  go=Event(staleRealm);child=Spawn(exe,staleRealm,"echo");WaitPeer(main);
  assert(main.Send("2~stale",1)==1);Sleep(1100);SetEvent(go);assert(Read(main)=="2~ready");
  assert(Send(main,"2~fresh") && Read(main)=="2~fresh" && main.Receive(empty)==0);
  assert(Send(main,"2~quit"));Finish(child);CloseHandle(go);
  // A crashed lock holder invalidates both claims; it cannot leave partial data executable.
  Finish(Spawn(exe,staleRealm,"abandon"));uint64_t peer=0;char detail[160]{};
  assert(main.Info(peer,detail)==-1);main.Close();assert(main.Open(staleRealm.c_str(),"Main","Alt",Key,0)==1 && !PeerEpoch(main));
  const std::string pausedRealm=realm+"paused";main.Close();assert(main.Open(pausedRealm.c_str(),"Main","Alt",Key,0)==1);
  go=Event(pausedRealm);child=Spawn(exe,pausedRealm,"echo");WaitPeer(main);
  Sleep(static_cast<DWORD>(PeerLease+100));assert(!PeerEpoch(main) && main.Send("2~expired",1)==-1);
  SetEvent(go);assert(Read(main)=="2~ready");assert(Send(main,"2~quit"));Finish(child);CloseHandle(go);
  std::puts("PASS: name/realm/code/role isolation, user-restricted objects, bounded lanes/backpressure, reserved Stop, nonblocking contention, fresh epochs, stale-frame expiry, duplicate-role refusal and abandoned-mutex recovery");
}
