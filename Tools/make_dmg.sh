#!/bin/bash
#
#  make_dmg.sh —— 把 build/Vela X.app 打成可分发的 dmg 安装包
#
#  用法：
#    ./Tools/make_dmg.sh            # → dist/Vela X-<版本>.dmg
#    ./build.sh --dmg               # 编译完直接打包（推荐）
#
#  产物规格（与 1.12.2 首发 dmg 一致）：
#    UDZO / zlib 压缩 / 只读；卷内放 Vela X.app + Applications 快捷方式 + 卷图标，
#    用户把 app 拖到 Applications 即可安装。
#
#  dmg 本身不签名（首发版也是）：Gatekeeper 检查的是卷内的 app，
#  而 app 已经用本地证书签好，行为与直接分发 .app 相同 —— 首次打开仍需右键「打开」。
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Vela X.app"
OUT_DIR="$ROOT/dist"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP —— 先跑 ./build.sh"
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/Resources/Info.plist" 2>/dev/null || true)"
VERSION="${VERSION//[[:space:]]/}"
if [ -z "$VERSION" ]; then
  echo "读不到版本号（Resources/Info.plist 的 CFBundleShortVersionString）"
  exit 1
fi

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/Vela X-$VERSION.dmg"
VOLNAME="Vela X $VERSION"

# 上一版留个底，免得覆盖之后没有能回滚的
if [ -f "$OUT" ]; then
  mv -f "$OUT" "$OUT_DIR/Vela X-$VERSION.prev.dmg"
fi

WORK="$(mktemp -d)"
MNT="$WORK/mnt"
mkdir -p "$MNT"
# 退出时务必先卸载再清临时目录，否则会留下一个挂载点
trap 'hdiutil detach "$MNT" -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
SRC="$WORK/src"
mkdir -p "$SRC"

echo "==> 组装卷内容"
cp -R "$APP" "$SRC/Vela X.app"
ln -s /Applications "$SRC/Applications"
cp "$ROOT/Resources/AppIcon.icns" "$SRC/.VolumeIcon.icns"

# 先建一个读写镜像，挂载到工作区内的目录，拷完再转成压缩只读镜像。
# 不走 `hdiutil create -srcfolder`：那条路径会在 /Volumes 下建临时卷，
# 在受限环境里会被拦下来（file-delete 被拒）。
SIZE_MB=$(( $(du -sm "$SRC" | cut -f1) + 20 ))
rm -f "$OUT"
echo "==> 创建读写镜像（${SIZE_MB} MB）"
# 不带 -format 时默认就是 UDRW（UDIF 读写），显式写 -format UDRW 反而会报错
hdiutil create -size "${SIZE_MB}m" -fs HFS+ -volname "$VOLNAME" \
  "$WORK/rw.dmg" >/dev/null
hdiutil attach "$WORK/rw.dmg" -mountpoint "$MNT" -nobrowse -quiet >/dev/null

echo "==> 写入内容"
ditto "$SRC" "$MNT"
# 让 Finder 拿 .VolumeIcon.icns 当卷图标
SetFile -a C "$MNT" 2>/dev/null || true

hdiutil detach "$MNT" -quiet >/dev/null

echo "==> 压缩为只读镜像（UDZO / zlib）"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "==> 校验镜像完整性"
hdiutil verify "$OUT" >/dev/null && echo "    校验通过"
SIZE="$(du -h "$OUT" | cut -f1 | tr -d ' ')"
SIG="$(codesign -d -r- "$APP" 2>/dev/null | grep -o 'certificate leaf = H"[a-f0-9]*"' || true)"

echo
echo "完成：${OUT}（${SIZE}）"
echo "版本号：${VERSION}"
[ -n "$SIG" ] && echo "卷内 app 的签名：${SIG}"
