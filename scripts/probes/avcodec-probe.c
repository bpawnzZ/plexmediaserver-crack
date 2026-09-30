/* dlopen the Plex libavcodec and check whether h264_nvenc/hevc_nvenc exist */
#include <stdio.h>
#include <dlfcn.h>
typedef const void* (*find_enc_t)(const char*);
typedef const void* (*find_dec_t)(const char*);
typedef void (*av_log_set_level_t)(int);
int main(int argc,char**argv){
  const char* lib = argc>1? argv[1] : "/usr/lib/plexmediaserver/lib/libavcodec.so.60";
  void*h=dlopen(lib,RTLD_NOW|RTLD_GLOBAL);
  if(!h){printf("dlopen(%s) FAIL: %s\n",lib,dlerror());return 1;}
  printf("dlopen(%s) OK\n",lib);
  av_log_set_level_t lvl=(av_log_set_level_t)dlsym(h,"av_log_set_level");
  if(lvl) lvl(16);
  find_enc_t fe=(find_enc_t)dlsym(h,"avcodec_find_encoder_by_name");
  find_dec_t fd=(find_dec_t)dlsym(h,"avcodec_find_decoder_by_name");
  const char* encs[]={"h264_nvenc","hevc_nvenc","h264_vaapi","hevc_vaapi","libx264",NULL};
  const char* decs[]={"h264_nvdec","hevc_nvdec","h264_cuvid",NULL};
  for(int i=0;encs[i];i++) printf("  encoder %-12s -> %s\n", encs[i], fe&&fe(encs[i])?"FOUND":"MISSING");
  for(int i=0;decs[i];i++) printf("  decoder %-12s -> %s\n", decs[i], fd&&fd(decs[i])?"FOUND":"MISSING");
  return 0;
}
