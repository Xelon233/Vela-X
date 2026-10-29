// device_profile.h —— 由 tools/adapt.py 生成
// 来源：APIC.dsl, BGRT.dsl, CDIT.dsl, CRAT.dsl, DSDT.dsl, FACP.dsl, FACS.dsl, FIDT.dsl, FPDT.dsl, HPET.dsl, MCFG.dsl, MSDM.dsl, RSDT.dsl, SSDT-0.dsl, SSDT-1.dsl, SSDT-10.dsl, SSDT-11.dsl, SSDT-12.dsl, SSDT-13.dsl, SSDT-14.dsl, SSDT-15.dsl, SSDT-16.dsl, SSDT-17.dsl, SSDT-18.dsl, SSDT-19.dsl, SSDT-2.dsl, SSDT-20.dsl, SSDT-21.dsl, SSDT-22.dsl, SSDT-23.dsl, SSDT-24.dsl, SSDT-25.dsl, SSDT-26.dsl, SSDT-27.dsl, SSDT-28.dsl, SSDT-29.dsl, SSDT-3.dsl, SSDT-4.dsl, SSDT-5.dsl, SSDT-6.dsl, SSDT-7.dsl, SSDT-8.dsl, SSDT-9.dsl, TPM2.dsl, VFCT.dsl, WSMT.dsl
// EC 镜像：ec.bin
// 注意：这是候选值，未经实机验证前建议先用只读模式确认。

#define ASUS_EC_BANK_A       0xFE700600   // 转速/温度所在窗口
#define ASUS_EC_BANK_B       0xFE700B00   // 模式镜像窗口
#define ASUS_EC_BANK_C       0xFE700C00   // 曲线邮箱窗口
#define ASUS_TACH_CPU        0x02   // CPU 转速低字节偏移
#define ASUS_TACH_GPU        0x24   // GPU 转速低字节偏移
#define ASUS_FANM_OFF        0xF9   // 模式镜像偏移
#define ASUS_DEV_CURVE_CPU   0x00110024   // CPU 曲线 devid
#define ASUS_DEV_CURVE_GPU   0x00110025   // GPU 曲线 devid
#define ASUS_MB_FAN          0x58   // 邮箱：风扇 ID
#define ASUS_MB_ARG1         0x5C   // 邮箱：参数1
#define ASUS_MB_ARG2         0x60   // 邮箱：参数2
#define ASUS_MB_ARG3         0x64   // 邮箱：参数3
#define ASUS_MB_ARG4         0x68   // 邮箱：参数4
#define ASUS_MB_RESULT       0x6C   // 邮箱：结果缓冲区
#define ASUS_MB_BUSY         0x7C   // 邮箱：忙标志
#define ASUS_MB_OPCODE       0x7D   // 邮箱：操作码
