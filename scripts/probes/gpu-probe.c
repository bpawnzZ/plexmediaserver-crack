#include <stdio.h>
#include <dlfcn.h>
typedef int (*cuInit_t)(unsigned);
typedef int (*cuDeviceGetCount_t)(int*);
typedef int (*cuDeviceGet_t)(int*, int);
typedef int (*cuDeviceGetName_t)(char*, int, int);
typedef int (*cuDeviceGetPCIBusId_t)(char*, int, int);

int main(void){
  const char* libs[]={"libcuda.so.1","libnvidia-encode.so.1","libnvidia-ml.so.1","libnvcuvid.so.1",NULL};
  for(int i=0;libs[i];i++){
    void*h=dlopen(libs[i],RTLD_NOW|RTLD_GLOBAL);
    printf("%-26s dlopen=%-4s %s\n",libs[i],h?"OK":"FAIL",h?"":dlerror());
  }
  void*h=dlopen("libcuda.so.1",RTLD_NOW|RTLD_GLOBAL);
  if(!h){puts("cuda unavailable");return 1;}
  cuInit_t cuInit=(cuInit_t)dlsym(h,"cuInit");
  cuDeviceGetCount_t c=(cuDeviceGetCount_t)dlsym(h,"cuDeviceGetCount");
  cuDeviceGet_t g=(cuDeviceGet_t)dlsym(h,"cuDeviceGet");
  cuDeviceGetName_t gn=(cuDeviceGetName_t)dlsym(h,"cuDeviceGetName");
  cuDeviceGetPCIBusId_t gp=(cuDeviceGetPCIBusId_t)dlsym(h,"cuDeviceGetPCIBusId");
  printf("syms: cuInit=%p cuDeviceGetCount=%p cuDeviceGet=%p name=%p pci=%p\n",
     (void*)cuInit,(void*)c,(void*)g,(void*)gn,(void*)gp);
  int rc=cuInit(0); printf("cuInit(0)=%d\n",rc);
  if(rc) return 1;
  int n=0; rc=c( &n); printf("cuDeviceGetCount=%d n=%d\n",rc,n);
  for(int i=0;i<n;i++){ int d=0; char nm[256]={0}, pci[64]={0};
    g(&d,i); gn(nm,256,d); gp(pci,64,d);
    printf("  dev%d name=%s pci=%s\n",i,nm,pci); }
  // NVENC
  void*e=dlopen("libnvidia-encode.so.1",RTLD_NOW|RTLD_GLOBAL);
  if(e){ void*s=dlsym(e,"NvEncodeAPICreateInstance"); void*v=dlsym(e,"NvEncodeAPIGetMaxSupportedVersion");
         printf("encode: CreateInstance=%p GetMaxSupportedVersion=%p\n",s,v); }
  return 0;
}
