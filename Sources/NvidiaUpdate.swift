//
//  NvidiaUpdate.swift
//  NVIDIA（NullMoth）驱动版本检测
//
//  已安装版本来自本地：
//    1. /Library/NullMoth/driver-version      （1401 安装器写入，最直接）
//    2. /Library/Extensions/NVRM.kext 的 CFBundleShortVersionString
//    3. kmutil showloaded 里的 com.nullmoth.NVRM (x.y.z)
//
//  最新版本有两个来源，优先用不耗配额的那个：
//    · GET https://github.com/nullmoth/nvidia-macos-driver/releases/latest
//      它是 302 跳到 /releases/tag/v2.6.2。这里拦下重定向，从 Location 里取版本号，
//      连接 0 字节正文、不消耗 GitHub API 配额（未登录配额只有 60 次/小时/出口 IP）。
//    · 只有在「版本号变了」的时候才额外查一次 API，拿发布说明和发布时间。
//

import Foundation
import CFNetwork

struct NvidiaRelease {
    var tag: String            // 2.6.2（去掉前缀 v）
    var name: String
    var published: Date?
    var pageURL: String
    var notes: String

    var publishedText: String {
        guard let published else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: published)
    }
}

enum NvidiaUpdateState: Equatable {
    case unknown                 // 还没查过
    case notInstalled            // 没有装 NullMoth
    case checking
    case upToDate(installed: String, latest: String)
    case available(installed: String, latest: String)
    case failed(installed: String, message: String)

    var installedVersion: String? {
        switch self {
        case .upToDate(let i, _), .available(let i, _), .failed(let i, _): return i
        default: return nil
        }
    }

    var latestVersion: String? {
        switch self {
        case .upToDate(_, let l), .available(_, let l): return l
        default: return nil
        }
    }

    var hasUpdate: Bool {
        if case .available = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unknown: return "未检查"
        case .notInstalled: return "未安装"
        case .checking: return "检查中…"
        case .upToDate: return "已是最新"
        case .available(_, let latest): return "有新版本 \(latest)"
        case .failed: return "检查失败"
        }
    }
}

enum NvidiaUpdate {

    static let repo = "nullmoth/nvidia-macos-driver"
    static let releasesURL = "https://github.com/nullmoth/nvidia-macos-driver/releases"
    private static let latestURL = "https://github.com/nullmoth/nvidia-macos-driver/releases/latest"
    private static let apiURL = "https://api.github.com/repos/nullmoth/nvidia-macos-driver/releases/latest"

    /// 自动检查的最小间隔（手动点按钮不受限）
    static let autoCheckInterval: TimeInterval = 6 * 3600

    // MARK: - 网络环境（诊断用）

    /// 系统代理（Clash 之类）——URLSession 会自动使用，这里只是把它显示出来
    static var systemProxyText: String {
        guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return "未设置（直连）"
        }
        var parts: [String] = []
        func add(_ enableKey: CFString, _ hostKey: CFString, _ portKey: CFString, _ name: String) {
            let enabled = (dict[enableKey as String] as? Int) ?? 0
            guard enabled == 1,
                  let host = dict[hostKey as String] as? String, !host.isEmpty,
                  let port = dict[portKey as String] as? Int else { return }
            parts.append("\(name) \(host):\(port)")
        }
        add(kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort, "HTTPS")
        add(kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort, "HTTP")
        if let pac = dict[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String, !pac.isEmpty {
            parts.append("PAC \(pac)")
        }
        return parts.isEmpty ? "未设置（直连）" : parts.joined(separator: " · ")
    }

    // MARK: - 本地已安装版本

    static func installedVersion() -> String? {
        // 1) 安装器写的版本文件
        if let s = try? String(contentsOfFile: "/Library/NullMoth/driver-version", encoding: .utf8) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        // 2) kext 的 Info.plist
        for name in ["NVRM", "NVAccel", "NVRMFB"] {
            let path = "/Library/Extensions/\(name).kext/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let v = dict["CFBundleShortVersionString"] as? String, !v.isEmpty {
                return v
            }
        }
        // 3) 已加载的 kext
        let out = SystemProbe.kextList
        for line in out.split(separator: "\n") where line.contains("com.nullmoth.NVRM") {
            if let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
               open < close {
                return String(line[line.index(after: open)..<close])
            }
        }
        return nil
    }

    // MARK: - 驱动组件（NVRM / NVAccel / NVRMFB / NVRMAGDC）

    struct Component: Identifiable {
        let name: String
        let version: String
        let present: Bool
        let loaded: Bool
        var id: String { name }
        var path: String { "/Library/Extensions/\(name).kext" }
        var bundleID: String { "com.nullmoth.\(name)" }
    }

    static func components() -> [Component] {
        let loaded = SystemProbe.kextList
        return ["NVRM", "NVAccel", "NVRMFB", "NVRMAGDC"].map { name in
            let plist = "/Library/Extensions/\(name).kext/Contents/Info.plist"
            let dict = NSDictionary(contentsOfFile: plist) as? [String: Any]
            let version = (dict?["CFBundleShortVersionString"] as? String) ?? "—"
            return Component(name: name,
                             version: version,
                             present: FileManager.default.fileExists(atPath: plist),
                             loaded: loaded.contains("com.nullmoth.\(name) ("))
        }
    }

    // MARK: - 版本比较

    /// "2.6.10" > "2.6.9"：逐段按数字比，缺位补 0
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 缓存

    private enum Keys {
        static let tag = "nvidia.latestTag"
        static let name = "nvidia.latestName"
        static let page = "nvidia.latestPage"
        static let notes = "nvidia.latestNotes"
        static let published = "nvidia.latestPublished"
        static let checkedAt = "nvidia.checkedAt"
    }

    static var lastChecked: Date? {
        guard let s = Prefs.string(Keys.checkedAt) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    static var cachedRelease: NvidiaRelease? {
        guard let tag = Prefs.string(Keys.tag), !tag.isEmpty else { return nil }
        var published: Date?
        if let s = Prefs.string(Keys.published) {
            published = ISO8601DateFormatter().date(from: s)
        }
        return NvidiaRelease(tag: tag,
                             name: Prefs.string(Keys.name) ?? "",
                             published: published,
                             pageURL: Prefs.string(Keys.page) ?? releasesURL,
                             notes: Prefs.string(Keys.notes) ?? "")
    }

    private static func save(_ release: NvidiaRelease) {
        Prefs.set(release.tag, for: Keys.tag)
        Prefs.set(release.name, for: Keys.name)
        Prefs.set(release.pageURL, for: Keys.page)
        Prefs.set(release.notes, for: Keys.notes)
        let iso = ISO8601DateFormatter()
        Prefs.set(release.published.map { iso.string(from: $0) } ?? "", for: Keys.published)
        Prefs.set(iso.string(from: Date()), for: Keys.checkedAt)
    }

    /// 用缓存 + 本地版本算出当前状态（不发网络请求）
    static func stateFromCache() -> NvidiaUpdateState {
        guard let installed = installedVersion() else { return .notInstalled }
        guard let release = cachedRelease else { return .unknown }
        return isNewer(release.tag, than: installed)
            ? .available(installed: installed, latest: release.tag)
            : .upToDate(installed: installed, latest: release.tag)
    }

    static var needsAutoCheck: Bool {
        guard let last = lastChecked else { return true }
        return Date().timeIntervalSince(last) > autoCheckInterval
    }

    // MARK: - 网络

    /// 拦截 302，只取 Location，不下载正文
    private final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
        var location: String?
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            location = request.url?.absoluteString
            completionHandler(nil)
        }
    }

    /// 从 ".../releases/tag/v2.6.2" 里取出 "2.6.2"
    static func tag(from urlString: String?) -> String? {
        guard let urlString, let range = urlString.range(of: "/releases/tag/") else { return nil }
        var tag = String(urlString[range.upperBound...])
        if let q = tag.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            tag = String(tag[..<q])
        }
        if tag.hasPrefix("v") { tag.removeFirst() }
        return tag.isEmpty ? nil : tag
    }

    /// 第一步：拿最新版本号（0 字节、不耗 API 配额）
    private static let debug = ProcessInfo.processInfo.environment["ASUS_NET_DEBUG"] != nil
    private static func log(_ msg: String) {
        if debug { FileHandle.standardError.write(Data("[net] \(msg)\n".utf8)) }
    }

    private static func fetchTag(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: latestURL) else {
            completion(.failure(NSError(domain: "nvidia", code: 1)))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("AsusControl/1.8", forHTTPHeaderField: "User-Agent")

        let catcher = RedirectCatcher()
        let session = URLSession(configuration: .default, delegate: catcher, delegateQueue: nil)
        log("GET \(latestURL)")
        session.dataTask(with: request) { _, response, error in
            log("resp status=\((response as? HTTPURLResponse)?.statusCode ?? -1) location=\(catcher.location ?? "nil") err=\(error?.localizedDescription ?? "-")")
            defer { session.finishTasksAndInvalidate() }

            // 正常情况：302 → Location 里有 tag
            if let tag = tag(from: catcher.location) {
                completion(.success(tag))
                return
            }
            // 某些网络下不跳转，最终 URL 就是 tag 页
            if let finalURL = response?.url?.absoluteString, let tag = tag(from: finalURL) {
                completion(.success(tag))
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(.failure(NSError(domain: "nvidia", code: code,
                                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])))
        }.resume()
    }

    /// 第二步（可选）：只有版本号变了才查 API，补充发布说明与时间
    private static func fetchDetail(tag: String, completion: @escaping (NvidiaRelease?) -> Void) {
        guard let url = URL(string: apiURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AsusControl/1.8", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            log("detail status=\((response as? HTTPURLResponse)?.statusCode ?? -1) err=\(error?.localizedDescription ?? "-")")
            guard error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            var published: Date?
            if let s = obj["published_at"] as? String {
                published = ISO8601DateFormatter().date(from: s)
            }
            let body = (obj["body"] as? String) ?? ""
            let notes = body
                .split(separator: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""

            completion(NvidiaRelease(tag: tag,
                                     name: (obj["name"] as? String) ?? tag,
                                     published: published,
                                     pageURL: (obj["html_url"] as? String)
                                        ?? "https://github.com/\(repo)/releases/tag/v\(tag)",
                                     notes: notes))
        }.resume()
    }

    /// 异步：查最新版本，写缓存，回调在主线程。
    /// 版本号一拿到就回调（这是用户真正关心的部分），发布说明留到后台慢慢补。
    static func fetchLatest(deliverOnMain: Bool = true,
                            completion: @escaping (Result<NvidiaRelease, Error>) -> Void,
                            onEnrich: ((NvidiaRelease) -> Void)? = nil) {
        // CLI 里主线程正被信号量阻塞，不能往 main 投递，否则永远等不到
        func deliver(_ block: @escaping () -> Void) {
            if deliverOnMain { DispatchQueue.main.async(execute: block) } else { block() }
        }
        fetchTag { tagResult in
            switch tagResult {
            case .failure(let error):
                deliver { completion(.failure(error)) }

            case .success(let tag):
                // 版本没变就直接复用缓存里的说明，省掉一次 API 调用
                if let cached = cachedRelease, cached.tag == tag {
                    save(cached)   // 只刷新检查时间
                    deliver { completion(.success(cached)) }
                    return
                }

                let pageURL = "https://github.com/\(repo)/releases/tag/v\(tag)"
                let basic = NvidiaRelease(tag: tag, name: tag, published: nil,
                                          pageURL: pageURL, notes: "")
                save(basic)
                deliver { completion(.success(basic)) }

                // 后台补发布说明：API 走不通也不影响版本判断
                guard let onEnrich else { return }
                fetchDetail(tag: tag) { detail in
                    guard let detail else { return }
                    save(detail)
                    deliver { onEnrich(detail) }
                }
            }
        }
    }

    /// 同步版本（CLI 用）
    static func fetchLatestSync(timeout: TimeInterval = 10) -> Result<NvidiaRelease, Error> {
        var outcome: Result<NvidiaRelease, Error> = .failure(
            NSError(domain: "nvidia", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "请求超时"]))
        let sem = DispatchSemaphore(value: 0)
        fetchLatest(deliverOnMain: false) { result in
            outcome = result
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        return outcome
    }
}

// MARK: - 一键下载并安装（自动执行 install.sh）

/// 安装流程的阶段，供 UI 展示进度
enum DriverInstallPhase: Equatable {
    case idle
    case downloading(progress: Double)
    case extracting
    case authorizing                    // 已经弹出管理员密码框，等用户输入
    case installing(elapsed: Int)       // 后台以 root 跑 install.sh，秒数用于显示耗时
    case succeeded
    case failed(String)

    var label: String {
        switch self {
        case .idle:               return "未开始"
        case .downloading(let p): return "下载中 \(Int(p * 100))%"
        case .extracting:         return "解压中…"
        case .authorizing:        return "等待管理员授权…"
        case .installing(let s):  return "安装中… 已用 \(DriverInstallPhase.timeText(s))"
        case .succeeded:          return "安装完成，请重启一次"
        case .failed(let m):      return "失败：\(m)"
        }
    }

    static func timeText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(String(format: "%02d", seconds % 60)) 秒"
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// 下载 / 解压 / 授权 / 安装进行中
    var isBusy: Bool {
        switch self {
        case .idle, .succeeded, .failed: return false
        default: return true
        }
    }
}

/// 下载最新驱动手动包（nullmoth-nvidia-<tag>.tar.gz），解压后以管理员权限执行其中的 install.sh。
///
/// install.sh 要求 euid == 0（脚本里 `[ "$(id -u)" -eq 0 ] || die "run with sudo"`），
/// 所以必须整段以 root 运行，而不是在脚本里调 sudo（`do shell script` 没有 TTY，sudo 等不到密码）。
///
/// 关键点（v2.1.0 修）：AppleScript 的字符串是**双引号**字面量，早先这里用 shell 单引号拼
/// `do shell script '...'`，osascript 直接报 -2741 语法错误 —— 既不弹授权框，也立刻失败。
/// 现在改成一个独立 runner 脚本 + `quoted form of "路径"`，两层引号各管一层，也不再需要
/// 把整条命令塞进 AppleScript 字符串。
///
/// 另外：安装要跑 kmutil 构建内核集合，可能几分钟到十几分钟。若让 `do shell script` 一直等，
/// 会撞上 AppleEvent 超时（-1712）。所以 runner 用 nohup 把安装丢到后台就返回，授权框马上消失，
/// 进度改由 App 轮询日志回显。
struct DriverInstaller {
    /// 安装日志写在临时目录里，失败时把尾部几行展示出来
    static let logName = "install.log"

    static func install(tag: String,
                        onPhase: @escaping (DriverInstallPhase) -> Void,
                        onLog: @escaping (String) -> Void = { _ in }) {
        let emit: (DriverInstallPhase) -> Void = { p in
            DispatchQueue.main.async { onPhase(p) }
        }
        let emitLog: (String) -> Void = { line in
            DispatchQueue.main.async { onLog(line) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("asuscontrol-nvidia-\(tag)")
            try? fm.removeItem(at: work)
            guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else {
                emit(.failed("无法创建临时目录")); return
            }

            // 1) 下载手动包（走系统代理，Clash 等无需额外配置）
            let asset = "nullmoth-nvidia-\(tag).tar.gz"
            guard let url = URL(string: "https://github.com/\(NvidiaUpdate.repo)/releases/download/v\(tag)/\(asset)") else {
                emit(.failed("无法构造下载地址")); return
            }
            let archive = work.appendingPathComponent(asset)
            let group = DispatchGroup()
            var moveError: String?
            group.enter()
            let task = URLSession.shared.downloadTask(with: url) { tmpURL, response, err in
                defer { group.leave() }
                if let err {
                    moveError = err.localizedDescription
                    return
                }
                if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 {
                    moveError = "下载失败（HTTP \(code)），检查网络或代理"
                    return
                }
                guard let tmpURL else { moveError = "下载未返回文件"; return }
                do { try fm.moveItem(at: tmpURL, to: archive) }
                catch { moveError = error.localizedDescription }
            }
            let obs = task.progress.observe(\.fractionCompleted) { obj, _ in
                emit(.downloading(progress: obj.fractionCompleted))
            }
            task.resume()
            group.wait()
            _ = obs
            if let moveError { emit(.failed(moveError)); return }

            // 2) 解压
            emit(.extracting)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xzf", archive.path, "-C", work.path]
            do {
                try tar.run(); tar.waitUntilExit()
                if tar.terminationStatus != 0 {
                    emit(.failed("解压失败（退出码 \(tar.terminationStatus)）")); return
                }
            } catch {
                emit(.failed("解压出错：\(error.localizedDescription)")); return
            }
            try? fm.removeItem(at: archive)   // 252 MB 的包留着没用

            // 3) 找到 install.sh
            guard let script = findInstallScript(in: work) else {
                emit(.failed("解压包里没有找到 install.sh")); return
            }
            let payload = script.deletingLastPathComponent()
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            // 4) 写 runner：cd 进 payload 后 exec install.sh，输出全部进日志。
            //    用 exec 而不是后台 &：Do shell script 结束时会把同一个进程组里的
            //    子进程一起收掉（实测日志只留下第一行），所以安装必须在前台跑完。
            let logURL = work.appendingPathComponent(logName)
            let runner = work.appendingPathComponent("run-install.sh")
            let runnerBody = """
            #!/bin/bash
            export LOG=\(sh(logURL.path))
            cd \(sh(payload.path)) || {
              printf '   STOP: 无法进入安装目录\\n' > "$LOG"
              exit 2
            }
            : > "$LOG"
            printf '== Vela X：开始安装 %s\\n' "$(date)" >> "$LOG"
            exec /bin/bash ./install.sh >> "$LOG" 2>&1
            """
            do {
                try runnerBody.write(to: runner, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)
            } catch {
                emit(.failed("无法写入安装脚本：\(error.localizedDescription)")); return
            }

            // 5) 弹管理员授权并执行。AppleScript 外面套 with timeout：
            //    do shell script 默认受 2 分钟 AppleEvent 超时限制（-1712），
            //    而 kmutil 构建内核集合经常超过这个时间。
            emit(.authorizing)
            let result = runWithAdminPrivileges(executable: runner.path,
                                                logURL: logURL,
                                                deadline: 30 * 60) { elapsed, line in
                emit(.installing(elapsed: elapsed))
                if let line { emitLog(line) }
            }

            if result.timedOut {
                let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                copyLog(text)
                emit(.failed("安装超过 30 分钟仍未结束，已中断等待（可查看 /tmp/asuscontrol-nvidia-install.log）"))
                return
            }

            let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            if result.ok {
                copyLog(logText)
                try? fm.removeItem(at: work)
                emit(.succeeded)
            } else {
                copyLog(logText)
                try? fm.removeItem(at: work)
                emit(.failed(failureText(log: logText, osascriptOutput: result.output)))
            }
        }
    }

    /// 在目录（含多层子目录）里找 install.sh
    private static func findInstallScript(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for item in items where item.lastPathComponent == "install.sh" { return item }
        for item in items where item.hasDirectoryPath {
            if let found = findInstallScript(in: item) { return found }
        }
        return nil
    }

    // MARK: - 日志解析

    /// install.sh 的 die() 都打 `STOP: ...`
    private static func stopReason(in text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let stop = lines.last(where: { $0.contains("STOP:") }),
              let range = stop.range(of: "STOP:") else { return nil }
        return String(stop[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// 失败原因按可信度排序：用户取消 > 脚本自己的 STOP > 日志最后一行 > osascript 报错
    private static func failureText(log: String, osascriptOutput: String) -> String {
        if isCancelled(osascriptOutput) { return "已取消授权" }
        if let stop = stopReason(in: log) { return stop }
        if let last = lastMeaningfulLine(in: log), !last.hasPrefix("== Vela X") {
            return "安装中断：\(last)"
        }
        if osascriptOutput.isEmpty {
            return "安装失败（没有更多信息，可查看 /tmp/asuscontrol-nvidia-install.log）"
        }
        return "安装失败：\(osascriptOutput)"
    }

    private static func isCancelled(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("-128") || lowered.contains("cancel") || lowered.contains("取消")
    }

    private static func lastMeaningfulLine(in text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty && !$0.hasPrefix("EXIT=") })
    }

    private static func copyLog(_ text: String) {
        try? text.write(toFile: "/tmp/asuscontrol-nvidia-install.log", atomically: true, encoding: .utf8)
    }

    // MARK: - shell / AppleScript 引号

    /// shell 单引号字面量
    private static func sh(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript 双引号字面量：只要转义反斜杠和双引号
    private static func applescript(_ s: String) -> String {
        "\"" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 以管理员权限执行某个可执行文件；执行期间每 1.2 秒回调一次（已用秒数 + 日志新增的最后一行）。
    ///
    /// AppleScript 用 `quoted form of "路径"` 让系统负责 shell 转义，不再手工拼命令 ——
    /// 早先正是把 shell 单引号塞进了 AppleScript 字符串，osascript 报 -2741 语法错，
    /// 于是既不弹授权框、又立刻失败。
    private static func runWithAdminPrivileges(executable path: String,
                                               logURL: URL,
                                               deadline: TimeInterval,
                                               onTick: @escaping (Int, String?) -> Void)
        -> (ok: Bool, timedOut: Bool, output: String) {

        let script = """
        with timeout of 3600 seconds
        \tdo shell script (quoted form of \(applescript(path))) with administrator privileges
        end timeout
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]

        // 用临时文件而不是 Pipe：Pipe 写满缓冲会卡死，且 waitUntilExit 之前读不到内容
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asuscontrol-osascript-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            return (false, false, "无法建立临时输出文件")
        }
        p.standardOutput = handle
        p.standardError = handle
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: tmp)
        }

        do {
            try p.run()
        } catch {
            return (false, false, error.localizedDescription)
        }

        let started = Date()
        var lastLine: String?
        while p.isRunning {
            if Date().timeIntervalSince(started) > deadline {
                p.terminate()
                return (false, true, "")
            }
            let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let line = lastMeaningfulLine(in: text)
            let elapsed = Int(Date().timeIntervalSince(started))
            if line != lastLine {
                lastLine = line
                onTick(elapsed, line)        // 有新行才回传，避免每 1.2 秒刷一次 UI
            } else {
                onTick(elapsed, nil)
            }
            Thread.sleep(forTimeInterval: 1.2)
        }
        p.waitUntilExit()

        let data = (try? Data(contentsOf: tmp)) ?? Data()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus == 0, false, out)
    }
}
