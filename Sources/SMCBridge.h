//
//  SMCBridge.h
//  AppleSMC 用户态访问桥（读/写/枚举）
//  仅依赖 IOKit，无需 root 即可读取；写入需要 root 权限。
//

#ifndef SMC_BRIDGE_H
#define SMC_BRIDGE_H

#include <stdint.h>

/// 打开与 AppleSMC 的连接。返回 0 表示成功。
int smc_open(void);

/// 读取键的值。key4 为 4 字符键名。
/// 返回 0 成功；-1 无此键；-2 读失败。
int smc_read(const char *key4, unsigned char *out, unsigned int *size, char type[5]);

/// 只查询键的元信息（不读值）。返回 0 表示键存在。
int smc_key_info(const char *key4, unsigned int *size, char type[5]);

/// 写入键。需要 root。返回 0 成功；1 = 权限不足；-1 = 失败。
int smc_write(const char *key4, const unsigned char *data, unsigned int size);

/// SMC 键总数（#KEY）。
int smc_key_count(void);

/// 按下标取键名，out 至少 5 字节。返回 0 成功。
int smc_key_at(int index, char out[5]);

/// 最近一次调用的 IOKit 返回码（调试用）。
int smc_last_kern_return(void);

// MARK: - 进程采样（libproc，无需 root）

/// 列出所有 pid，返回写入数量
int asus_proc_list(int32_t *pids, int maxCount);

/// 读取单个进程的累计 CPU 时间（纳秒）与常驻内存（字节）
/// 返回 0 成功，-1 表示该进程不可读（系统进程/僵尸）
int asus_proc_info(int32_t pid, char *name, int nameLen,
                   unsigned long long *cpuNs, unsigned long long *rssBytes);

#endif /* SMC_BRIDGE_H */
