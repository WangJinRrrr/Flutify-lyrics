// helper3: 真调用 0x41e69c(完整帧) + 先验 store-read。
// 用法: helper3.exe <R1hex32> <IN_MID8hex16> <TAILFILE> <OUT_EXPECT32>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdint>
#include <vector>
static std::vector<uint8_t> hx(const char* s){ std::vector<uint8_t> o; for(size_t i=0;s[i]&&s[i+1];i+=2){ unsigned v=0; sscanf(s+i,"%2x",&v); o.push_back((uint8_t)v);} return o; }
static uint8_t G_OUT[32]; static int G_GOT=0;
static void mycb(void* a, void* out, void* r8){ memcpy(G_OUT,out,16); G_GOT=1; }
static uint64_t G_BASE=0;
static LONG WINAPI veh(EXCEPTION_POINTERS* p){
    printf("FAULT code=%lx rip=%llx rsp=%llx\n", p->ExceptionRecord->ExceptionCode, p->ContextRecord->Rip, p->ContextRecord->Rsp);
    uint64_t* sp=(uint64_t*)p->ContextRecord->Rsp;
    for(int i=0;i<64;i++){
        uint64_t v=0;
        if(!IsBadReadPtr(sp+i,8)) v=sp[i];
        if(v>G_BASE && v<G_BASE+0x3000000) printf("  stack[%d]=%llx (rva %llx)\n",i,v,v-G_BASE);
    }
    fflush(stdout); ExitProcess(3); return 0;
}
int main(int argc, char** argv){
    AddVectoredExceptionHandler(1, veh);
    printf("start\n"); fflush(stdout);
    if(argc<5){ printf("usage: helper3 <R1hex> <MID8hex> <TAILFILE> <OUTEXThex>\n"); return 1; }
    SetDllDirectoryW(L"C:\\Users\\ZhaoYunFeng\\AppData\\Roaming\\Spotify");
    HMODULE h=LoadLibraryW(L"C:\\Users\\ZhaoYunFeng\\AppData\\Roaming\\Spotify\\Spotify.dll");
    if(!h){ printf("LoadLibrary fail %lu\n", GetLastError()); return 2; }
    uint64_t B=(uint64_t)h; G_BASE=B; printf("base=%llx\n",B); fflush(stdout);
    auto R=[&](uint32_t rva){ return B+rva; };
    // 1) 槽位: 写入自制blob {ptr,seed}
    std::vector<uint8_t> blob; { FILE* f=fopen("D:\\Flutify\\SpotifyApi\\tmp\\slot_blob.bin","rb");
        if(!f){ printf("no slot_blob\n"); return 4; }
        uint8_t b[64]; size_t n=fread(b,1,64,f); fclose(f); blob.assign(b,b+n); }
    uint8_t* blobmem=(uint8_t*)VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    memcpy(blobmem,blob.data(),blob.size());
    uint32_t seed=0x12345678;
    uint64_t* slot=(uint64_t*)R(0x273abf8);
    slot[0]=(uint64_t)blobmem; *(uint32_t*)(slot+1)=0; *((uint32_t*)slot+2)=seed;
    printf("slot=%p blob=%p seed=%08x\n",slot,blobmem,seed); fflush(stdout);
    // 2) 真 store-read 验证
    uint8_t* outstr=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    typedef void*(*SR)(void*,void*);
    ((SR)R(0x169b008))((void*)slot,outstr);
    // MSVC string: size<=15 SSO? 16B -> heap: [0:8]=ptr
    printf("store string head: "); for(int i=0;i<32;i++)printf("%02x",outstr[i]); printf("\n");
    uint64_t dptr=0; memcpy(&dptr,outstr,8);
    printf("decoded key: "); for(int i=0;i<16;i++)printf("%02x",((uint8_t*)dptr)[i]); printf("\n"); fflush(stdout);
    // 3) 真 0x41e69c 调用
    uint8_t* ctx=(uint8_t*)VirtualAlloc(NULL,256,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* inner=(uint8_t*)VirtualAlloc(NULL,256,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    memset(ctx,0,256); memset(inner,0,256);
    memcpy(ctx+0x10,&inner,8);
    uint64_t cb=(uint64_t)&mycb; memcpy(inner+0x18,&cb,8);
    uint8_t* inb=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* scratch=(uint8_t*)VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    { FILE* f=fopen(argv[3],"rb"); size_t n=f?fread(scratch,1,4096,f):0; if(f)fclose(f); printf("tail %zuB\n",n); }
    std::vector<uint8_t> r1=hx(argv[1]), mid=hx(argv[2]);
    memcpy(inb,r1.data(),16); memcpy(inb+16,mid.data(),8); memcpy(inb+24,&scratch,8);
    typedef int(*E69)(void*,void*,void*,void*);
    G_GOT=0; memset(G_OUT,0,32);
    int ret=((E69)R(0x41e69c))(ctx,inb,(void*)1,(void*)1);
    printf("ret=%d got=%d out=",ret,G_GOT); for(int i=0;i<16;i++)printf("%02x",G_OUT[i]); printf("\n");
    std::vector<uint8_t> exp=hx(argv[4]);
    printf("exp="); for(auto b:exp)printf("%02x",b); printf("\n");
    printf(memcmp(G_OUT,exp.data(),16)==0?"MATCH\n":"DIFFER\n");
    return 0;
}
