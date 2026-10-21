#!/bin/bash
# Mydsh TestFlight 上传管线（改造自 LocalMind 的 tools/make_testflight.sh，2026-10-20）
#
# 前置（一次性，必须在网页做）：
#   1. App Store Connect → 我的 App → 新建 App
#        Bundle ID: com.jiachenglou.dshmobile
#        平台: iOS，名称/SKU 自定（SKU 不可改，建议 mydsh001）
#      —— App 记录不能经 API 创建（会 403），只能网页建。
#   2. 本机已有 ASC API Key（App Manager）：
#        ~/.appstoreconnect/private_keys/AuthKey_662DG54QFM.p8
#
# 用法：
#   cd dsh-mobile && ./scripts/make_testflight.sh          # 归档→导出→上传
#   ./scripts/make_testflight.sh --no-upload               # 只产出 IPA
#
# 已知坑（来自 LocalMind 记录，均已在脚本内规避）：
#   - ASC API JWT 必须带 aud: "appstoreconnect-v1"，且本机时钟快约 3 分钟，
#     iat 需回拨；否则 401 NOT_AUTHORIZED。（本脚本上传走 altool，JWT 由 altool 内部处理，
#     仅当用 --check-app 时调 API。）
#   - 上传必须用带 Distribution 证书的 IPA；xcodebuild -exportArchive 会自动重签。
#   - 每次上传 build 号必须递增，否则 ITMS-4238。

set -euo pipefail
cd "$(dirname "$0")/.."

# 以下标识均可通过环境变量覆盖，方便 fork 后用你自己的账号打包。
KEY_ID="${MYDSH_KEY_ID:-662DG54QFM}"
ISSUER="${MYDSH_ISSUER:-83c32535-8b3a-405e-a631-e80968b96c25}"
TEAM="${MYDSH_TEAM:-239B5T5LP3}"
BUNDLE="${MYDSH_BUNDLE:-com.jiachenglou.dshmobile}"
ARCHIVE=build/Mydsh.xcarchive
EXPORT=build/export
IPA=$(ls "$EXPORT"/*.ipa 2>/dev/null | head -1)

NO_UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --no-upload) NO_UPLOAD=1 ;;
    --check-app)
      python3 - "$KEY_ID" "$ISSUER" "$BUNDLE" <<'PY'
import base64, json, subprocess, sys, time, os
kid, issuer, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
key = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
b64u = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode()
h = b64u(json.dumps({"alg":"ES256","kid":kid}).encode())
p = b64u(json.dumps({"iss":issuer,"iat":int(time.time())-600,
                     "exp":int(time.time())+300,"aud":"appstoreconnect-v1"}).encode())
der = subprocess.run(["openssl","dgst","-sha256","-sign",key],
                     input=f"{h}.{p}".encode(), capture_output=True).stdout
r = s = None; i = 2
while i < len(der):
    tag, ln = der[i], der[i+1]; val = der[i+2:i+2+ln]
    if tag == 2:
        if r is None: r = int.from_bytes(val.lstrip(b"\x00"), "big")
        else: s = int.from_bytes(val.lstrip(b"\x00"), "big")
    i += 2 + ln
tok = f"{h}.{p}.{b64u(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}"
out = subprocess.run(["curl","-g","-s","-m","40",
    "https://api.appstoreconnect.apple.com/v1/apps?limit=200",
    "-H",f"Authorization: Bearer {tok}"], capture_output=True).stdout.decode()
try: data = json.loads(out)["data"]
except Exception: print("ASC API 异常:", out[:300]); raise SystemExit(1)
hit = [a for a in data if a["attributes"].get("bundleId") == bundle]
print(("✓ 已存在: " + hit[0]["attributes"]["name"] + " id=" + hit[0]["id"])
      if hit else "✗ 未找到 App 记录：" + bundle + "（请先在 ASC 网页创建）")
raise SystemExit(0 if hit else 2)
PY
      exit $? ;;
  esac
done

export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

MARKETING=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  DeepSeekHarnessMobile/Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  DeepSeekHarnessMobile/Resources/Info.plist)
echo "== 目标: $BUNDLE  version $MARKETING ($BUILD)  team $TEAM =="

echo "== ① 归档 (Release) =="
rm -rf "$ARCHIVE"
xcodebuild -project DeepSeekHarnessMobile.xcodeproj -scheme DeepSeekHarnessMobile \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive -quiet

echo "== ② 导出 IPA (app-store-connect) =="
rm -rf "$EXPORT" && mkdir -p build
cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>imize</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
python3 - <<'PY'
import plistlib, pathlib
p = pathlib.Path('build/ExportOptions.plist')
d = plistlib.loads(p.read_bytes()); d.pop('imize', None)
p.write_bytes(plistlib.dumps(d))
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist -exportPath "$EXPORT" \
  -allowProvisioningUpdates 2>&1 | tail -4

[ -f "$IPA" ] || { echo "✗ 未生成 IPA: $IPA"; ls -la "$EXPORT"; exit 1; }
echo "✓ IPA: $IPA ($(du -h "$IPA" | cut -f1))"
codesign -dvv "$IPA" 2>/dev/null | head -1 || true

if [ "$NO_UPLOAD" = "1" ]; then echo "== 跳过上传 (--no-upload) =="; exit 0; fi

echo "== ③ 上传 TestFlight =="
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | tail -8
echo "✓ 上传完成。到 App Store Connect → TestFlight 等待构建处理（通常 5-15 分钟）。"