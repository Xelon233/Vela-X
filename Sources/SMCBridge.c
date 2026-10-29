//
//  SMCBridge.c
//  AppleSMC 用户态访问实现
//
//  说明：AppleSMC 的 IOConnectCallStructMethod 结构体布局与 Apple 私有 SMC 协议一致。
//  已在本机（ROG Zephyrus G15 / VirtualSMC + AsusSMC + SMCAMDProcessor）实测：
//    - 读 TC0P 返回 sp78 温度
//    - #KEY 返回 108 个键
//    - 写 LKSB 返回 0xE00002C1 (kIOReturnNotPrivileged)，即需要 root
//

#include "SMCBridge.h"
#include <string.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCVers;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCPLimit;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} SMCKeyInfo;

typedef struct {
    UInt32 key;
    SMCVers vers;
    SMCPLimit pLimit;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    UInt8 bytes[32];
} SMCKeyData;

enum {
    KERNEL_INDEX_SMC = 2,
    SMC_CMD_READ_BYTES = 5,
    SMC_CMD_WRITE_BYTES = 6,
    SMC_CMD_READ_INDEX = 8,
    SMC_CMD_READ_KEYINFO = 9
};

static io_connect_t gConn = 0;
static int gOpen = 0;
static int gLastKern = 0;

static kern_return_t smc_call(SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t r = IOConnectCallStructMethod(gConn, KERNEL_INDEX_SMC,
                                                in, sizeof(SMCKeyData), out, &outSize);
    gLastKern = (int)r;
    return r;
}

static UInt32 key_to_u32(const char *k) {
    return ((UInt32)(unsigned char)k[0] << 24) | ((UInt32)(unsigned char)k[1] << 16) |
           ((UInt32)(unsigned char)k[2] << 8)  |  (UInt32)(unsigned char)k[3];
}

int smc_open(void) {
    if (gOpen) return 0;
    io_service_t dev = IOServiceGetMatchingService(kIOMainPortDefault,
                                                   IOServiceMatching("AppleSMC"));
    if (!dev) return -1;
    kern_return_t r = IOServiceOpen(dev, mach_task_self(), 0, &gConn);
    IOObjectRelease(dev);
    if (r != kIOReturnSuccess) { gLastKern = (int)r; return -2; }
    gOpen = 1;
    return 0;
}

int smc_last_kern_return(void) { return gLastKern; }

/* VirtualSMC 返回的 dataType 四字节字节序与 Apple 约定相反，这里反转成可读字符串 */
static void type_to_chars(UInt32 tp, char out[5]) {
    const unsigned char *p = (const unsigned char *)&tp;
    out[0] = (char)p[3];
    out[1] = (char)p[2];
    out[2] = (char)p[1];
    out[3] = (char)p[0];
    out[4] = 0;
}

static int read_key_info_u32(UInt32 key, UInt32 *size, UInt32 *type) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != kIOReturnSuccess) return -1;
    if (size) *size = out.keyInfo.dataSize;
    if (type) *type = out.keyInfo.dataType;
    return 0;
}

int smc_key_info(const char *key4, unsigned int *size, char type[5]) {
    if (smc_open() != 0) return -1;
    UInt32 sz = 0, tp = 0;
    if (read_key_info_u32(key_to_u32(key4), &sz, &tp) != 0) return -1;
    if (sz == 0 || sz > 32) return -1;
    if (size) *size = sz;
    if (type) { type_to_chars(tp, type); }
    return 0;
}

int smc_read(const char *key4, unsigned char *out, unsigned int *size, char type[5]) {
    if (smc_open() != 0) return -1;
    UInt32 key = key_to_u32(key4);
    UInt32 sz = 0, tp = 0;
    if (read_key_info_u32(key, &sz, &tp) != 0) return -1;
    if (sz == 0 || sz > 32) return -1;

    SMCKeyData in, outData;
    memset(&in, 0, sizeof(in));
    memset(&outData, 0, sizeof(outData));
    in.key = key;
    in.keyInfo.dataSize = sz;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&in, &outData) != kIOReturnSuccess) return -2;

    memcpy(out, outData.bytes, 32);
    if (size) *size = sz;
    if (type) { type_to_chars(tp, type); }
    return 0;
}

int smc_write(const char *key4, const unsigned char *data, unsigned int size) {
    if (smc_open() != 0) return -1;
    UInt32 key = key_to_u32(key4);
    UInt32 sz = 0;
    if (read_key_info_u32(key, &sz, NULL) != 0) return -1;
    if (size > sz || sz > 32) return -1;

    SMCKeyData in, outData;
    memset(&in, 0, sizeof(in));
    memset(&outData, 0, sizeof(outData));
    in.key = key;
    in.keyInfo.dataSize = sz;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, data, size);

    kern_return_t r = smc_call(&in, &outData);
    if (r == kIOReturnNotPrivileged || r == kIOReturnNotPermitted) return 1;
    if (r != kIOReturnSuccess) return -1;
    return 0;
}

int smc_key_count(void) {
    unsigned char b[32] = {0};
    unsigned int sz = 0;
    char t[5] = {0};
    if (smc_read("#KEY", b, &sz, t) != 0) return -1;
    return (int)(((UInt32)b[0] << 24) | ((UInt32)b[1] << 16) | ((UInt32)b[2] << 8) | b[3]);
}

int smc_key_at(int index, char out[5]) {
    if (smc_open() != 0) return -1;
    SMCKeyData in, outData;
    memset(&in, 0, sizeof(in));
    memset(&outData, 0, sizeof(outData));
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = (UInt32)index;
    if (smc_call(&in, &outData) != kIOReturnSuccess) return -1;
    /* VirtualSMC 返回的 key 字段字节序与 Apple 约定相反，这里反转回来 */
    const unsigned char *rb = (const unsigned char *)&outData.key;
    out[0] = (char)rb[3];
    out[1] = (char)rb[2];
    out[2] = (char)rb[1];
    out[3] = (char)rb[0];
    out[4] = 0;
    return 0;
}

// MARK: - 进程采样

#include <libproc.h>
#include <sys/proc_info.h>

int asus_proc_list(int32_t *pids, int maxCount) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(int32_t) * maxCount);
    if (bytes <= 0) return 0;
    return bytes / (int)sizeof(int32_t);
}

int asus_proc_info(int32_t pid, char *name, int nameLen,
                   unsigned long long *cpuNs, unsigned long long *rssBytes) {
    struct proc_taskinfo info;
    int r = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info));
    if (r != (int)sizeof(info)) return -1;
    if (name && nameLen > 0) {
        char tmp[64] = {0};
        if (proc_name(pid, tmp, sizeof(tmp)) <= 0) tmp[0] = 0;
        strncpy(name, tmp, (size_t)nameLen - 1);
        name[nameLen - 1] = 0;
    }
    if (cpuNs) *cpuNs = (unsigned long long)info.pti_total_user + info.pti_total_system;
    if (rssBytes) *rssBytes = (unsigned long long)info.pti_resident_size;
    return 0;
}
