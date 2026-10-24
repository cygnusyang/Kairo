#!/usr/bin/env bash
# tools/sign_update_manifest.sh —— OTA 更新清单生成 + Ed25519 签名（docs/35 §6.1/§2.4）。
#
# 输入（环境变量，语义见 sign_update_manifest.swift）：
#   UPDATE_SIGNING_KEY_BASE64   必填，Ed25519 私钥原始种子（32 字节）base64（CI secret）
#   MF_VERSION / MF_MINIMUM_VERSION / MF_BUILD_TIME / MF_DOWNLOAD_URL / MF_CDHASH  必填
#   MF_SECURITY_CRITICAL / MF_NOTES / MF_SHA256  可选（MF_SHA256 = zip 的 SHA256
#     64 位 hex，v2.10.3 T1 下载完整性；缺省/空串不写入字段，向后兼容）
# 输出：完整 update-manifest.json（含 signature）写到 stdout；诊断走 stderr。
#
# ⚠️ 私钥纪律：只经环境变量传入（CI secret UPDATE_SIGNING_KEY_BASE64），本脚本与
# Swift helper 不打印、不回显、不落盘私钥。私钥缺失即 fail——**禁止未签名清单上架**。
#
# ⚠️ 密钥生成指导（一次生成、长期使用；公钥最终硬编码进组 A 的 Updater 常量）：
#   推荐用 CryptoKit 生成（直接产出本脚本期望的 raw 32 字节种子，无需转换）：
#     swift -e 'import CryptoKit; import Foundation;
#       let k = Curve25519.Signing.PrivateKey();
#       print("PRIVATE_BASE64=", k.rawRepresentation.base64EncodedString());
#       print("PUBLIC_BASE64 =", k.publicKey.rawRepresentation.base64EncodedString())'
#   ① 私钥 → GitHub secret UPDATE_SIGNING_KEY_BASE64（本脚本 + release.yml 读取）。
#   ② 公钥（PUBLIC_BASE64，raw 32 字节）→ 组 A 的 Updater 模块硬编码验签常量，
#      由集成轮 lead 协调组 A 接入。本组不把任何密钥落仓库。
#   注意：openssl genpkey -algorithm ED25519 产出 PKCS#8 DER，**不是** raw 种子，
#   需先解包成 32 字节才能用作本脚本输入；建议直接用 CryptoKit 生成。
#
# 用法：
#   UPDATE_SIGNING_KEY_BASE64=... MF_VERSION=2.7.0 MF_MINIMUM_VERSION=2.5.0 \
#     MF_BUILD_TIME=2026-10-10T00:00:00Z \
#     MF_DOWNLOAD_URL=https://github.com/cygnusyang/coffer/releases/download/v2.7.0/Coffer-v2.7.0.zip \
#     MF_CDHASH=<40hex> \
#     tools/sign_update_manifest.sh > macos/build/update-manifest.json
#
# 退出码：0 = 成功（stdout 为完整清单）；非 0 = 失败（stderr 为原因）。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_HELPER="${SCRIPT_DIR}/sign_update_manifest.swift"

if [ ! -f "$SWIFT_HELPER" ]; then
    echo "ERROR: 缺少签名 helper：${SWIFT_HELPER}（应随本脚本同在 tools/ 下）" >&2
    exit 1
fi

# 前置校验私钥 secret 存在（缺失即 fail，防未签名清单上架；值不回显）。
if [ -z "$(printenv UPDATE_SIGNING_KEY_BASE64)" ]; then
    echo "ERROR: 环境变量 UPDATE_SIGNING_KEY_BASE64 未设置（Ed25519 私钥 base64；生成指导见本脚本头部注释）" >&2
    exit 1
fi

# 必填字段快速失败（printenv 保证 bash/zsh 兼容；深层校验在 Swift helper 内）。
for v in MF_VERSION MF_MINIMUM_VERSION MF_BUILD_TIME MF_DOWNLOAD_URL MF_CDHASH; do
    if [ -z "$(printenv "$v")" ]; then
        echo "ERROR: 缺少必填环境变量 $v" >&2
        exit 1
    fi
done

# 调用 Swift helper（CryptoKit Ed25519 + canonical JSON）。私钥经环境变量透传，
# 不落盘、不回显。swift 脚本模式加载 CryptoKit 在本机与 macOS runner 均已实证
# （docs/35 §6.1 实证 swiftc 直编可行；本机 swift 解释器亦通过）。
if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: 未找到 swift（需要完整 Xcode / CLT 以加载 CryptoKit），请 xcode-select --install" >&2
    exit 1
fi

swift "$SWIFT_HELPER" || {
    echo "ERROR: sign_update_manifest.swift 执行失败（见其上 stderr；注意私钥绝不回显）" >&2
    exit 1
}
