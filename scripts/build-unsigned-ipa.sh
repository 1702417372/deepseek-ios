#!/usr/bin/env bash
# 在 macOS 上编译「未签名」.ipa。
# 未签名 ipa 不能直接安装，需要用 Sideloadly / AltStore 用自己的 Apple ID 重签名后安装。
# 用法：在项目根目录执行  bash scripts/build-unsigned-ipa.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -project DeepSeekClone.xcodeproj \
  -scheme DeepSeekClone \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

rm -rf Payload DeepSeekClone-unsigned.ipa
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/DeepSeekClone.app Payload/
rm -rf Payload/DeepSeekClone.app/_CodeSignature
zip -qry DeepSeekClone-unsigned.ipa Payload

echo ""
echo "✅ 已生成：$(pwd)/DeepSeekClone-unsigned.ipa"
echo "下一步：用 Sideloadly / AltStore 拖入 ipa，用你自己的 Apple ID 重签名后安装到 iPhone。"
