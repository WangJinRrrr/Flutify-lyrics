// helper2: LoadLibrary 真装载 Spotify.dll(系统loader处理重定位+IAT),复现白盒core调用。
// 用法: helper2.exe <R1hex32> <OUT_EXPECT32>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdint>
#include <vector>
static std::vector<uint8_t> hx(const char* s){ std::vector<uint8_t> o; for(size_t i=0;s[i]&&s[i+1];i+=2){ unsigned v=0; sscanf(s+i,"%2x",&v); o.push_back((uint8_t)v);} return o; }
static LONG WINAPI veh(EXCEPTION_POINTERS* p){
    printf("FAULT code=%lx rip=%llx\n", p->ExceptionRecord->ExceptionCode, p->ContextRecord->Rip);
    printf("rax=%llx rbx=%llx rcx=%llx rdx=%llx rsi=%llx rdi=%llx r8=%llx r9=%llx rsp=%llx\n",
      p->ContextRecord->Rax,p->ContextRecord->Rbx,p->ContextRecord->Rcx,p->ContextRecord->Rdx,
      p->ContextRecord->Rsi,p->ContextRecord->Rdi,p->ContextRecord->R8,p->ContextRecord->R9,
      p->ContextRecord->Rsp);
    fflush(stdout); ExitProcess(3); return 0;
}
int main(int argc, char** argv){
    AddVectoredExceptionHandler(1, veh);
    printf("start\n"); fflush(stdout);
    if(argc<3){ printf("usage: helper2 <R1hex> <OUT_EXPECThex>\n"); return 1; }
    SetDllDirectoryW(L"C:\\Users\\ZhaoYunFeng\\AppData\\Roaming\\Spotify");
    HMODULE h=LoadLibraryW(L"C:\\Users\\ZhaoYunFeng\\AppData\\Roaming\\Spotify\\Spotify.dll");
    if(!h){ printf("LoadLibrary fail %lu\n", GetLastError()); return 2; }
    uint64_t B=(uint64_t)h;
    printf("base=%llx\n",B); fflush(stdout);
    auto R=[&](uint32_t rva){ return B+rva; };
    uint8_t* obj=(uint8_t*)VirtualAlloc(NULL,0x200,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint64_t* arr=(uint64_t*)VirtualAlloc(NULL,9*16,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint32_t vts[]={0x154a580,0x154a216,0x153a292,0x154a316,0x154a422,0x153a5be,0x153a6cb,0x153a6cb,0x153a7d8};
    // 注意第6/7槽: emu用 0x153a5be,0x153a6cb,0x153a7d8,0x153a8e5 (9个)
    uint32_t vts9[]={0x154a580,0x154a216,0x153a292,0x154a316,0x154a422,0x153a5be,0x153a6cb,0x153a7d8,0x153a8e5};
    for(int i=0;i<9;i++){ arr[i*2]=R(vts9[i]); arr[i*2+1]=0; }
    memset(obj,0,0x200);
    typedef void(*CT)(void*,void*,int);
    ((CT)R(0x41afe4))(obj,arr,1);
    printf("obj: "); for(int i=0;i<16;i++)printf("%02x",obj[i]); printf("\n"); fflush(stdout);
    std::vector<uint8_t> r1=hx(argv[1]), exp=hx(argv[2]);
    uint8_t* ib=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* kb=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* ob=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* scratch=(uint8_t*)VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    memset(scratch,0,4096);
    const char* tf=getenv("HELPER_TAILFILE");
    if(tf){ FILE* fp=fopen(tf,"rb"); if(fp){ size_t n=fread(scratch,1,4096,fp); fclose(fp); printf("tailfile %zuB\n",n);} }
    memcpy(ib,r1.data(),16);
    // IN mid8: 用录制的常量 965da8f4e1a80000(多组出现); ptr->scratch
    uint8_t mid8[]={0x96,0x5d,0xa8,0xf4,0xe1,0xa8,0x00,0x00};
    memcpy(ib+16,mid8,8); memcpy(ib+24,&scratch,8);
    std::vector<uint8_t> dev=hx("5da465b8839ee9448a032eb488926122");
    memcpy(kb,dev.data(),16); memset(kb+16,0,8); memcpy(kb+24,&scratch,8);
    memset(ob,0,64);
    typedef int(*CF)(void*,void*,void*,void*);
    int ret=((CF)R(0x41cf18))(obj,ib,ob,kb);
    printf("ret=%d out=",ret); for(int i=0;i<16;i++)printf("%02x",ob[i]); printf("\n");
    printf("exp="); for(auto b:exp)printf("%02x",b); printf("\n");
    printf(memcmp(ob,exp.data(),16)==0?"MATCH\n":"DIFFER\n");
    return 0;
}
