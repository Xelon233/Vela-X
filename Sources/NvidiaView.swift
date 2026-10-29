//
//  NvidiaView.swift
//  「NVIDIA 驱动」页：版本状态、驱动组件、显卡信息、更新步骤
//

import SwiftUI
import AppKit

struct NvidiaView: View {
    @EnvironmentObject var store: SensorStore
    @State private var components: [NvidiaUpdate.Component] = []
    @State private var installPhase: DriverInstallPhase = .idle
    /// 安装过程中回显的最后一行日志
    @State private var installLog: String = ""

    private var state: NvidiaUpdateState { store.nvidiaUpdate }

    private var statusColor: Color {
        switch state {
        case .upToDate: return Palette.ok
        case .available: return Palette.warn
        case .failed: return Palette.bad
        case .checking: return Palette.accent2
        default: return Palette.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "NVIDIA 驱动更新", trailing: "nullmoth/nvidia-macos-driver")
            heroCard

            SectionTitle(text: "驱动组件", trailing: "\(components.filter(\.loaded).count)/4 已加载")
            componentsCard

            SectionTitle(text: "显卡")
            gpuCard

            SectionTitle(text: "怎么更新")
            howToCard
        }
        .onAppear { components = NvidiaUpdate.components() }
        .onChange(of: store.nvidiaUpdate) { _ in
            components = NvidiaUpdate.components()
        }
    }

    // MARK: - 版本对照

    private var heroCard: some View {
        Card(padding: 18, accent: statusColor, glow: state.hasUpdate) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 22) {
                    versionBlock(title: "已安装",
                                 version: state.installedVersion ?? "—",
                                 sub: state.installedVersion == nil
                                     ? "未检测到 NullMoth"
                                     : "NullMoth · /Library/Extensions",
                                 color: Palette.text)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 16)

                    versionBlock(title: "GitHub 最新",
                                 version: state.latestVersion ?? store.nvidiaRelease?.tag ?? "—",
                                 sub: publishedText,
                                 color: state.hasUpdate ? Palette.warn : Palette.text)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                                .shadow(color: statusColor.opacity(0.9), radius: 4)
                            Text(state.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }
                        if state.isChecking {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }

                if let notes = store.nvidiaRelease?.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                if case .failed(_, let message) = state {
                    Text("检查失败：\(message)。版本号取自本地，不影响驱动本身。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.bad.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    // 有更新时主按钮直接就是「下载并安装」，「检查更新」让位成次要的「重新检查」，
                    // 免得看到新版本还要再点一次才知道下一步做什么
                    if state.hasUpdate {
                        Button {
                            beginInstall()
                        } label: {
                            Text(installPhase.isBusy
                                 ? installPhase.label
                                 : "下载并安装 \(state.latestVersion ?? "")")
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        .disabled(installPhase.isBusy)

                        Button {
                            store.checkNvidiaUpdate()
                        } label: {
                            Text(state.isChecking ? "检查中…" : "重新检查")
                        }
                        .buttonStyle(GrayButtonStyle())
                        .disabled(state.isChecking || installPhase.isBusy)
                    } else {
                        Button {
                            store.checkNvidiaUpdate()
                        } label: {
                            Text(state.isChecking ? "检查中…" : "检查更新")
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        .disabled(state.isChecking || installPhase.isBusy)
                    }

                    Button {
                        open(store.nvidiaRelease?.pageURL ?? NvidiaUpdate.releasesURL)
                    } label: {
                        Text("打开发布页")
                    }
                    .buttonStyle(GrayButtonStyle())

                    Spacer()

                    Text(checkTimeText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
                }

                if installPhase != .idle {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if installPhase.isBusy { ProgressView().controlSize(.small) }
                            Text(installPhase.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(installPhase.isFailed ? Palette.bad : Palette.textSecondary)
                        }
                        if !installLog.isEmpty {
                            Text(installLog)
                                .font(.system(size: 9.5).monospaced())
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if case .installing = installPhase {
                            Text("安装过程要构建内核集合，可能需要几分钟，期间请勿关机。日志：/tmp/asuscontrol-nvidia-install.log")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func versionBlock(title: String, version: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
            Text(version)
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.4), radius: 10)
            Text(sub)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(minWidth: 118, alignment: .leading)
    }

    private var publishedText: String {
        guard let date = store.nvidiaRelease?.published else { return "来自 GitHub 最新 release" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "发布于 " + f.string(from: date)
    }

    private var checkTimeText: String {
        guard let last = NvidiaUpdate.lastChecked else { return "每 6 小时自动检查" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "上次检查 \(f.string(from: last)) · 每 6 小时自动检查"
    }

    // MARK: - 组件

    private var componentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.loaded ? Palette.ok : (item.present ? Palette.warn : Palette.textTertiary))
                            .frame(width: 6, height: 6)
                            .shadow(color: item.loaded ? Palette.ok.opacity(0.9) : .clear, radius: 4)

                        Text(item.name)
                            .font(.system(size: 11.5, weight: .medium).monospaced())
                            .frame(width: 78, alignment: .leading)

                        Text(item.bundleID)
                            .font(.system(size: 10.5).monospaced())
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 190, alignment: .leading)

                        Text(item.version)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Palette.text)

                        Spacer()

                        Text(item.loaded ? "已加载" : (item.present ? "未加载" : "缺失"))
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                .fill((item.loaded ? Palette.ok : Palette.textTertiary).opacity(0.13)))
                            .foregroundStyle(item.loaded ? Palette.ok : Palette.textTertiary)
                    }
                    .padding(.vertical, 6)

                    if index < components.count - 1 { Divider().opacity(0.35) }
                }
            }
        }
    }

    // MARK: - 显卡

    private var gpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                if let gpu = store.hardware.gpus.first(where: { $0.vendor == "NVIDIA" }) {
                    LabelValue(label: "型号", value: gpu.name, mono: false)
                    LabelValue(label: "驱动", value: gpu.driver, mono: false)
                    LabelValue(label: "PCI 路径", value: gpu.pciPath.isEmpty ? "—" : gpu.pciPath)
                    LabelValue(label: "Metal 加速",
                               value: gpu.accelerated ? "已启用" : "未启用",
                               mono: false,
                               color: gpu.accelerated ? Palette.ok : Palette.warn)
                } else {
                    Text("没有检测到 NVIDIA 显卡")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text("驱动版本取自 IORegistry 与 /Library/NullMoth，不依赖 1401 应用是否还在")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - 更新步骤

    private var howToCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                step(1, "打开发布页，下载 `1401-Mac-<版本>.dmg`",
                     "同一个 release 里也有 `nullmoth-nvidia-<版本>.tar.gz` 手动包")
                step(2, "运行 1401，它会找到你的 OpenCore 并备份配置",
                     "每一步改动都会先列出来，确认后才写入 EFI")
                step(3, "重启一次即可生效",
                     "2.6.0 起更新只需重启一次；首次安装还需要在「隐私与安全性」里允许扩展")
                Text("更新前确认 boot-args 里没有 `-nvoff`（那是救援用的临时禁用开关）。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func step(_ index: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).fill(Palette.accent.opacity(0.18)))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: - 一键下载安装

    /// 点「下载并安装」：有版本号就直接装，没有就先查一次最新版本再装
    private func beginInstall() {
        guard !installPhase.isBusy else { return }
        if let tag = store.nvidiaRelease?.tag {
            runInstall(tag: tag)
        } else {
            NvidiaUpdate.fetchLatest { result in
                switch result {
                case .success(let release):
                    runInstall(tag: release.tag)
                case .failure(let error):
                    installPhase = .failed("获取最新版本号失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func runInstall(tag: String) {
        installLog = ""
        DriverInstaller.install(tag: tag) { phase in
            installPhase = phase
            if case .succeeded = phase {
                // 装完刷新一次状态，版本号立即更新
                store.checkNvidiaUpdate()
            }
        } onLog: { line in
            installLog = line
        }
    }
}
