//
//  AdvancedView.swift
//  高级功能页：目前包含「开启 HiDPI」（参考 xzhih/one-key-hidpi）
//

import SwiftUI

struct AdvancedView: View {
    @State private var displays: [HiDPIDisplay] = HiDPI.displays()
    @State private var busyID: CGDirectDisplayID?
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("高级功能")
                    .font(.system(size: 22, weight: .bold))
                Text("面向进阶用户的系统级调整，操作需要管理员授权，请谨慎使用。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
            }

            SectionTitle(text: "HiDPI 显示器缩放", trailing: "one-key-hidpi")
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("通过向 /Library/Displays 写入显示器 Override 配置，为外接 / 内建显示器开启 HiDPI 缩放档位。仅改动用户数据区，不修改系统卷，卸载本程序后配置仍在。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if displays.isEmpty {
                        Text("未检测到可用显示器。外接显示器请先唤醒后点「刷新显示器」重试。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(displays) { d in
                                displayRow(d)
                                if d.id != displays.last?.id {
                                    Divider().overlay(Palette.hairline)
                                }
                            }
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(messageIsError ? Palette.bad : Palette.ok)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button("刷新显示器") { reload() }
                            .buttonStyle(GrayButtonStyle())
                        Spacer()
                        Text("修改后需注销 / 重启才生效")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }

            SectionTitle(text: "说明")
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("配置写入 /Library/Displays/Contents/Resources/Overrides，需要管理员授权；取消授权则不做任何改动。")
                    bullet("开启后到「系统设置 → 显示器」选择新出现的 HiDPI 缩放档位；部分机型需重启后才出现。")
                    bullet("「关闭 / 还原」会删除本程序为该显示器写入的 Override 文件，恢复默认缩放。")
                    bullet("若开启后画面异常，可在「恢复模式」或另一台显示器下删除该文件，或在安全模式中还原。")
                }
            }
        }
        .onAppear { reload() }
    }

    // MARK: - 子视图

    private func displayRow(_ d: HiDPIDisplay) -> some View {
        let enabled = HiDPI.isEnabled(d)
        let isBusy = busyID == d.id
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 15))
                .foregroundStyle(enabled ? Palette.ok : Palette.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(d.name)
                        .font(.system(size: 12.5, weight: .medium))
                    Pill(text: enabled ? "已开启" : "未开启",
                         color: enabled ? Palette.ok : Palette.textSecondary)
                }
                Text("原生 \(d.nativeText) · VID 0x\(d.vendorHex.uppercased()) · PID 0x\(d.productHex.uppercased())")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView().controlSize(.mini)
            } else if enabled {
                Button("关闭 / 还原") { apply(enable: false, d: d) }
                    .buttonStyle(GrayButtonStyle())
            } else {
                Button("开启 HiDPI") { apply(enable: true, d: d) }
                    .buttonStyle(GrayButtonStyle())
            }
        }
        .padding(.vertical, 7)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func reload() {
        displays = HiDPI.displays()
    }

    private func apply(enable: Bool, d: HiDPIDisplay) {
        busyID = d.id
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let err = enable ? HiDPI.enable(d) : HiDPI.disable(d)
            DispatchQueue.main.async {
                busyID = nil
                messageIsError = (err != nil)
                if let err {
                    message = err
                } else {
                    message = enable
                        ? "已写入 HiDPI 配置，请到「系统设置 → 显示器」选择新的缩放档位（必要时重启）。"
                        : "已移除该显示器的 HiDPI 配置。"
                }
                displays = HiDPI.displays()
            }
        }
    }
}
