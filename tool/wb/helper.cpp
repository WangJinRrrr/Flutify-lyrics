// helper: 在本进程真实执行 Spotify.dll 的白盒解包 core(0x41cf18)，复现已录制的 OUT。
// 步骤: 手工映射PE节 -> 应用重定位(沿用emu.py已验证的方式) -> 0x41afe4搭对象 -> core() -> 对比OUT。
// 用法: helper.exe <R1hex16> <IN_TAIL16hex> <OUT_EXPECT16hex>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
static std::vector<uint8_t> hx(const char* s){ std::vector<uint8_t> o; for(size_t i=0;s[i]&&s[i+1];i+=2){ unsigned v=0; sscanf(s+i,"%2x",&v); o.push_back((uint8_t)v);} return o; }
int main(int argc, char** argv){
    printf("start\n"); fflush(stdout);
    if(argc<4){ printf("usage: helper <R1hex> <IN_TAIL16hex> <OUT_EXPECT16hex>\n"); return 1; }
    const char* PATH="C:\\Users\\ZhaoYunFeng\\AppData\\Roaming\\Spotify\\Spotify.dll";
    FILE* f=fopen(PATH,"rb"); fseek(f,0,SEEK_END); long sz=ftell(f); fseek(f,0,SEEK_SET);
    std::vector<uint8_t> data(sz); fread(data.data(),1,sz,f); fclose(f);
    auto U32=[&](size_t o){ uint32_t v=0; memcpy(&v,data.data()+o,4); return v; };
    auto U16=[&](size_t o){ uint16_t v=0; memcpy(&v,data.data()+o,2); return v; };
    uint32_t pe=U32(0x3c); uint16_t nsec=U16(pe+6); uint16_t optsz=U16(pe+20);
    uint32_t opt=pe+24; uint64_t IB=0; memcpy(&IB,data.data()+opt+24,8);
    uint32_t so=opt+optsz;
    struct Sec{ std::string name; uint32_t va,vsize,raw,rawsize; };
    std::vector<Sec> secs;
    for(int i=0;i<nsec;i++){ uint32_t o=so+i*40; char nm[9]={0}; memcpy(nm,data.data()+o,8);
        Sec s{nm,U32(o+12),U32(o+8),U32(o+20),U32(o+16)}; secs.push_back(s); }
    uint64_t lo=~0ULL,hi=0;
    for(auto& s:secs){ uint64_t b=IB+s.va,e=b+(s.vsize>s.rawsize?s.vsize:s.rawsize); if(b<lo)lo=b; if(e>hi)hi=e; }
    for(auto& s:secs){ printf("sec %-8s va=%08x vsz=%08x raw=%08x rsz=%08x\n",s.name.c_str(),s.va,s.vsize,s.raw,s.rawsize); }
    printf("lo=%llx hi=%llx sz=%llu\n",lo,hi,hi-lo); fflush(stdout);
    lo&=~0xFFFULL; hi=(hi+0xFFF)&~0xFFFULL;
    void* mem=VirtualAlloc((LPVOID)lo,hi-lo,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE);
    if(!mem){ mem=VirtualAlloc(NULL,hi-lo,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE); printf("map anywhere %p (want %llx)\n",mem,lo); }
    else printf("map at IB %p\n",mem);
    uint64_t B=(uint64_t)mem+( (uint64_t)mem==lo?0:0 );
    // 注意: emu.py把节写到IB+va;若实际基址X!=IB,则重定位加X
    uint64_t X=(uint64_t)mem - lo + IB; // 使 IB+va 映射到 mem+(va-lo_off)... 简化:逐节写mem+(IB+s.va-lo)
    for(auto& s:secs){ memcpy((uint8_t*)mem+(IB+s.va-lo), data.data()+s.raw, s.rawsize); }
    uint64_t ADD = (uint64_t)mem + (IB - lo); // 文件裸值v -> 运行时R(v)=mem+(v+IB-lo)=v+ADD
    // .reloc
    int nfix=0;
    for(auto& s:secs) if(s.name==".reloc"){
        size_t i=s.raw, end=s.raw+s.rawsize;
        while(i+8<=end){ uint32_t prv=U32(i),bsz=U32(i+4); if(bsz<8)break;
            for(uint32_t j=8;j<bsz;j+=2){ uint16_t e=U16(i+j); int typ=e>>12,off=e&0xfff;
                uint64_t addr=(uint64_t)mem+(prv+off+IB-lo);
                if(typ==10){ uint64_t v=0; memcpy(&v,(void*)addr,8); v+=ADD; memcpy((void*)addr,&v,8); nfix++; }
                else if(typ==3){ uint32_t v=0; memcpy(&v,(void*)addr,4); v+=(uint32_t)ADD; memcpy((void*)addr,&v,4); nfix++; } }
            i+=bsz; }
    }
    printf("reloc %d\n",nfix); fflush(stdout);
    auto R=[&](uint32_t rva)->uint64_t{ return (uint64_t)mem+(rva+IB-lo); };
    // 对象+数组
    uint8_t* obj=(uint8_t*)VirtualAlloc(NULL,0x200,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint64_t* arr=(uint64_t*)VirtualAlloc(NULL,9*16,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint32_t vts[]={0x154a580,0x154a216,0x153a292,0x154a316,0x154a422,0x153a5be,0x153a6cb,0x153a7d8,0x153a8e5};
    for(int i=0;i<9;i++){ arr[i*2]=R(vts[i]); arr[i*2+1]=0; }
    memset(obj,0,0x200);
    typedef void(*CT)(void*,void*,int);
    ((CT)R(0x41afe4))(obj,arr,1);
    printf("obj: "); for(int i=0;i<16;i++)printf("%02x",obj[i]); printf("\n");
    // 输入
    std::vector<uint8_t> r1=hx(argv[1]), tail=hx(argv[2]), exp=hx(argv[3]);
    uint8_t* ib=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* kb=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* ob=(uint8_t*)VirtualAlloc(NULL,64,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    uint8_t* scratch=(uint8_t*)VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    memset(scratch,0,4096);
    memcpy(ib,r1.data(),16); memcpy(ib+16,tail.data(),16);
    // KEY: devkey + u64零 + ptr->scratch(模拟上下文指针)
    std::vector<uint8_t> dev=hx("5da465b8839ee9448a032eb488926122");
    memcpy(kb,dev.data(),16); memset(kb+16,0,8); memcpy(kb+24,&scratch,8);
    memset(ob,0,64);
    // IN+24 原始是堆指针,指向录制的tailderef;先用零scratch(测是否崩/OUT如何)
    //  variant由环境变量选: HELPER_TAIL=recorded 时把录制内容拷入scratch(第二个参数给文件)
    const char* tf=getenv("HELPER_TAILFILE");
    if(tf){ FILE* tfp=fopen(tf,"rb"); if(tfp){ size_t n=fread(scratch,1,4096,tfp); fclose(tfp); printf("tailfile %s %zuB\n",tf,n);} }
    memcpy(ib+24,&scratch,8); // 注意:这会覆盖tail后8B;若需保留原始tail ptr语义,改用+32? 先按u64+ptr结构处理
    typedef int(*CF)(void*,void*,void*,void*);
    int ret=((CF)R(0x41cf18))(obj,ib,ob,kb);
    printf("ret=%d out=",ret); for(int i=0;i<16;i++)printf("%02x",ob[i]); printf("\n");
    printf("exp="); for(auto b:exp)printf("%02x",b); printf("\n");
    printf(memcmp(ob,exp.data(),16)==0?"MATCH\n":"DIFFER\n");
    return 0;
}
