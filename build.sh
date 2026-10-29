#!/bin/bash
#
# 构建 Vela X.app（无需 Xcode，只用 Command Line Tools）
#   ./build.sh            构建通用二进制（x86_64 + arm64，可用的架构才编）
#   ./build.sh x86_64     只编指定架构
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Vela X.app"
MACOS_MIN="13.0"

# 参数解析：--dmg 表示编译完顺带打安装包，其余参数仍按架构处理
#   ./build.sh                 只编译
#   ./build.sh --dmg           编译 + 打包 dmg
#   ./build.sh x86_64 --dmg    只编 x86_64 + 打包
WANT_DMG=0
ARCH_ARGS=()
for a in "$@"; do
  case "$a" in
    --dmg) WANT_DMG=1 ;;
    *) ARCH_ARGS+=("$a") ;;
  esac
done
[ "${ASUS_DMG:-0}" = "1" ] && WANT_DMG=1
if [ ${#ARCH_ARGS[@]} -eq 0 ]; then
  ARCHS=(x86_64 arm64)
else
  ARCHS=("${ARCH_ARGS[@]}")
fi

mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 清理旧产物"
rm -f "$BUILD"/AsusControl_* "$BUILD"/SMCBridge_*.o
rm -rf "$APP/Contents/MacOS/AsusControl"

SOURCES=("$ROOT/Sources/"*.swift)

BUILT=()
for ARCH in ${ARCHS[@]}; do
  echo "==> 编译 $ARCH"
  if ! clang -c -O2 -arch "$ARCH" -o "$BUILD/SMCBridge_$ARCH.o" "$ROOT/Sources/SMCBridge.c" 2>/dev/null; then
    echo "    跳过 ${ARCH}（该架构不可用）"
    continue
  fi
  if swiftc -O -swift-version 5 \
        -target "$ARCH-apple-macos$MACOS_MIN" \
        -import-objc-header "$ROOT/Sources/SMCBridge.h" \
        "${SOURCES[@]}" "$BUILD/SMCBridge_$ARCH.o" \
        -o "$BUILD/AsusControl_$ARCH" \
        -framework IOKit -framework AppKit -framework SwiftUI -framework Combine 2> "$BUILD/$ARCH.log"; then
    BUILT+=("$BUILD/AsusControl_$ARCH")
  else
    echo "    编译失败，日志：$BUILD/$ARCH.log"
    tail -30 "$BUILD/$ARCH.log"
    exit 1
  fi
done

if [ ${#BUILT[@]} -eq 0 ]; then
  echo "没有可用的架构，构建中止"; exit 1
fi

if [ ${#BUILT[@]} -gt 1 ]; then
  lipo -create "${BUILT[@]}" -output "$APP/Contents/MacOS/AsusControl"
else
  cp "${BUILT[0]}" "$APP/Contents/MacOS/AsusControl"
fi

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# 其余资源（图标、ROG 品牌标等）整目录带进 bundle
for res in "$ROOT/Resources/"*; do
  name=$(basename "$res")
  [ "$name" = "Info.plist" ] && continue
  cp "$res" "$APP/Contents/Resources/$name"
done

# 签名：优先用本地自签证书（TCC 授权不会被重新编译打断），否则退回 ad-hoc
#
# 重要：必须用证书的 SHA-1 指纹而不是名字来指定身份。
# 钥匙串里可能存在多张同名证书，用名字匹配会命中第一张（可能不是 TCC 记录里那张），
# 导致「签名成功但 TCC 不认」——表现为明明勾选了输入监控，程序还是说没权限。
SIGN_ID="${ASUS_SIGN_ID:-}"
SIGN_KEYCHAIN="${ASUS_SIGN_KEYCHAIN:-$HOME/Library/Keychains/asuscontrol-signing.keychain-db}"
if [ -z "$SIGN_ID" ]; then
  # 取钥匙串里该身份的第一张证书指纹（SHA-1）
  TMP_CERT="$(mktemp -t asussign)"
  if security find-certificate -a -c "ASUS Control Local Signing" -p "$SIGN_KEYCHAIN" > "$TMP_CERT" 2>/dev/null; then
    SIGN_ID=$(openssl x509 -in "$TMP_CERT" -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//;s/://g' || true)
  fi
  rm -f "$TMP_CERT"
  if [ -z "$SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "ASUS Control Local Signing"; then
    SIGN_ID="ASUS Control Local Signing"
  fi
fi

if [ -n "$SIGN_ID" ]; then
  echo "==> 签名：$SIGN_ID"
  codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KEYCHAIN" "$APP" >/dev/null 2>&1 \
    || codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KEYCHAIN" --deep "$APP" >/dev/null 2>&1 \
    || { echo "    签名失败，退回 ad-hoc"; codesign --force --sign - "$APP" >/dev/null 2>&1 || true; }
else
  echo "==> 签名为 ad-hoc（重新编译会让「输入监控」授权失效）"
  echo "    想要稳定授权：先运行 ./Tools/make_signing_cert.sh"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

# 打印最终生效的签名，方便确认 TCC 记录对得上
echo "==> 最终签名信息"
codesign -d -r- "$APP" 2>&1 | grep -E "designated" | sed 's/^/    /' || true

# 便捷 CLI 入口（vela 是新的名字，asuscontrol 保留做兼容）
ln -sf "$APP/Contents/MacOS/AsusControl" "$BUILD/asuscontrol"
ln -sf "$APP/Contents/MacOS/AsusControl" "$BUILD/vela"

echo ""
echo "完成：$APP"
echo "命令行：$BUILD/vela status（或 asuscontrol）"

if [ "$WANT_DMG" -eq 1 ]; then
  echo ""
  "$ROOT/Tools/make_dmg.sh"
fi
