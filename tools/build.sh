#!/usr/bin/env bash
# 编译 Kairo（Release）并打包 macOS 应用 Kairo.app。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="Kairo"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
BINARY_PRODUCT="KairoMacApp"

usage() {
  cat <<USAGE
用法: $(basename "$0") [选项]

选项:
  -c, --configuration <debug|release>  构建配置（默认: release）
  -o, --output <dir>                   输出目录（默认: dist/）
  --skip-gate                          跳过核心与呈现层平台绑定门禁
  -h, --help                           显示帮助
USAGE
}

SKIP_GATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--configuration)
      CONFIGURATION="${2:?}"
      shift 2
      ;;
    -o|--output)
      DIST_DIR="${2:?}"
      APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
      shift 2
      ;;
    --skip-gate)
      SKIP_GATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "配置必须是 debug 或 release，收到: $CONFIGURATION" >&2
    exit 2
    ;;
esac

if [[ "$SKIP_GATE" -eq 0 ]]; then
  bash "$ROOT/tools/gate-core.sh"
fi

echo "==> swift build -c $CONFIGURATION (warnings as errors)"
# 告警一律视为失败，避免带 warning 的产物进入 dist/
swift build -c "$CONFIGURATION" -Xswiftc -warnings-as-errors

BUILD_DIR="$ROOT/.build/$CONFIGURATION"
SRC_BIN="$BUILD_DIR/$BINARY_PRODUCT"
if [[ ! -x "$SRC_BIN" ]]; then
  echo "未找到可执行文件: $SRC_BIN" >&2
  exit 1
fi

echo "==> 打包 ${APP_NAME}.app → $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# 构建时间戳：写入 CFBundleVersion，「关于」面板与 Finder 显示编译版本
BUILD_STAMP="$(date +%Y%m%d.%H%M)"

# 可执行文件名与 CFBundleExecutable 一致
cp "$SRC_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 一并放出 CLI / MCP，方便脚本与插件引用
cp "$BUILD_DIR/KairoCLI" "$DIST_DIR/KairoCLI"
cp "$BUILD_DIR/KairoMCP" "$DIST_DIR/KairoMCP"
chmod +x "$DIST_DIR/KairoCLI" "$DIST_DIR/KairoMCP"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>app.kairo.macos</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.8.5</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_STAMP}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Kairo Project</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>app.kairo.project</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>kairo</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>app.kairo.project</string>
      <key>UTTypeDescription</key>
      <string>Kairo Project</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
        <string>public.content</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>kairo</string>
        </array>
      </dict>
    </dict>
  </array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>Kairo Deep Link</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>kairo</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# App icon
ICNS_SRC="$ROOT/design/icons/app/AppIcon.icns"
if [[ -f "$ICNS_SRC" ]]; then
  cp "$ICNS_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  # CFBundleIconFile without extension
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$APP_BUNDLE/Contents/Info.plist"
fi

# Menubar template icons (for future NSStatusItem)
MENUBAR_SRC="$ROOT/design/icons/menubar"
if [[ -d "$MENUBAR_SRC" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources"
  cp "$MENUBAR_SRC/kairo-menubarTemplate.png" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
  cp "$MENUBAR_SRC/diana.k@example.org" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# 本地化资源（F-0700 主路径 B，docs/features/06-localization.md §7）
# .xcstrings 只作源，编译成 .lproj 后拷进 Contents/Resources；必须早于 codesign，
# 否则资源不在签名覆盖内（R4）。缺 Catalog 或任一语言目录一律失败，不静默回退。
LPROJ_DIR="$DIST_DIR/lproj"
echo "==> 编译本地化资源 → $LPROJ_DIR"
if ! bash "$ROOT/tools/i18n-compile.sh" "$LPROJ_DIR"; then
  echo "本地化资源编译失败，停止打包（需要 Xcode 命令行工具与 $ROOT/Apps/macos/Resources/Localizable.xcstrings）" >&2
  exit 1
fi
for LANG_ID in en zh-Hans; do
  if [[ ! -d "$LPROJ_DIR/$LANG_ID.lproj" ]]; then
    echo "缺少本地化目录：$LPROJ_DIR/${LANG_ID}.lproj（Catalog 未提供 ${LANG_ID}）" >&2
    exit 1
  fi
  cp -R "$LPROJ_DIR/$LANG_ID.lproj" "$APP_BUNDLE/Contents/Resources/"
done

# 本地 ad-hoc 签名，避免 Gatekeeper 拦住未签名包
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

cat > "$DIST_DIR/README.txt" <<NOTE
Kairo 构建产物
==============
- ${APP_NAME}.app     macOS 应用（可 open 或拖到 /Applications）
- KairoCLI            命令行
- KairoMCP            MCP 服务（stdio）

安装应用:
  bash tools/install.sh
NOTE

echo "==> 完成"
echo "    App:  $APP_BUNDLE"
echo "    CLI:  $DIST_DIR/KairoCLI"
echo "    MCP:  $DIST_DIR/KairoMCP"
