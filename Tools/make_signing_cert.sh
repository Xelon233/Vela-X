#!/bin/bash
#
#  make_signing_cert.sh
#  生成一把自签名的本地代码签名证书，让「输入监控」授权在重新编译后不失效。
#
#  背景：build.sh 默认用 ad-hoc 签名（codesign --sign -）。ad-hoc 没有 Team ID，
#  macOS 的 TCC 只能用 **cdhash** 认人 —— 每重新编译一次，cdhash 就变，
#  系统设置里那个勾选看起来还在，实际已经对不上，于是「已授权却一直说没权限」。
#  换成固定证书后，TCC 的记录变成「identifier + 证书」，重建也认得出是同一个人。
#
#  用法：
#     ./Tools/make_signing_cert.sh              # 创建/确认证书
#     ./build.sh                                # 之后会自动用它签名
#
#  证书存放在独立钥匙串 ~/Library/Keychains/asuscontrol-signing.keychain-db，
#  不碰 login 钥匙串；卸载的话删掉这个文件和「钥匙串访问」里的同名证书即可。
#

set -euo pipefail

IDENTITY_NAME="${1:-ASUS Control Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/asuscontrol-signing.keychain-db"
KEYCHAIN_PASS="asuscontrol-signing"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "证书已存在：$IDENTITY_NAME"
  echo "build.sh 会自动使用它签名。"
  exit 0
fi

echo "==> 生成自签名代码签名证书：$IDENTITY_NAME"

cat > "$WORK_DIR/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions     = ext
prompt              = no

[ dn ]
CN = ASUS Control Local Signing

[ ext ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
  -days 3650 -config "$WORK_DIR/openssl.cnf" 2>/dev/null

# 合成带私钥的 p12，供 security import 使用。
# 注意：OpenSSL 3 默认用 AES-256-CBC/PBKDF2 导出 p12，macOS 的 `security import`
# 解析不了，会出现「证书导入了但私钥丢了」→ find-identity 报 0 valid identities。
# 必须显式指定旧式 PBE-SHA1-3DES 才有最好的兼容性。
openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
  -out "$WORK_DIR/identity.p12" -passout pass:"$KEYCHAIN_PASS" -name "$IDENTITY_NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> 建立独立钥匙串"
if security list-keychains -d user | grep -q "asuscontrol-signing"; then
  echo "    钥匙串已存在，复用"
else
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
fi
security set-keychain-settings -t 36000 -u "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

echo "==> 导入证书"
security import "$WORK_DIR/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# 允许 codesign 无提示访问私钥
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1 || true

# 把证书标为「始终信任」，否则 find-identity -p codesigning 会因为
# CSSMERR_TP_NOT_TRUSTED 而认为身份无效（自签证书默认不被信任）。
security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$WORK_DIR/cert.pem" >/dev/null 2>&1 || true

# 加进搜索列表，codesign 才找得到
if ! security list-keychains -d user | grep -q "asuscontrol-signing"; then
  EXISTING=$(security list-keychains -d user | tr -d '"' | xargs)
  security list-keychains -d user -s $EXISTING "$KEYCHAIN"
fi

echo
echo "完成。可用身份："
security find-identity -v -p codesigning | grep "$IDENTITY_NAME" || true
echo
echo "现在直接 ./build.sh 就会用这把证书签名。"
echo "TCC 授权将按「identifier + 证书」记录，重新编译不再失效。"
echo "注意：这是自签证书，系统不信任它；本程序依旧要右键 → 打开，GATEKEEPER 行为与 ad-hoc 相同。"
