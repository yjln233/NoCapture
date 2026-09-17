#!/bin/bash
#
# 一键构建脚本
#
# 用法:
#   ./build.sh                # 默认构建
#   ./build.sh FINALPACKAGE=1 # 正式包(去掉调试符号)
#
# 工程目录若含空格,Theos 无法就地构建,脚本会先复制到 /tmp 的无空格目录再构建,
# 产物再拷回 packages/;目录不含空格时直接就地构建。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$PROJECT_DIR" == *" "* ]]; then
    BUILD_DIR="$(mktemp -d /tmp/nocapture.XXXXXX)"
    echo "==> 工程路径含空格,复制到 $BUILD_DIR 构建"
    rsync -a --exclude '.git' --exclude 'packages' --exclude '.theos' "$PROJECT_DIR/" "$BUILD_DIR/"
    SOURCE_DIR="$BUILD_DIR"
else
    SOURCE_DIR="$PROJECT_DIR"
fi

export THEOS="${THEOS:-$HOME/theos}"
# 沙箱/容器环境下 clang 默认的模块缓存目录可能不可写,统一切到 /tmp
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/nocapture-clang-modules}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

cd "$SOURCE_DIR"

# 构建前自动同步版本:把 control 的 Version 写进 bundle 的 Info.plist,
# 避免出现 control / Info.plist / deb 三者版本漂移(这个坑踩过)。
VERSION="$(awk '/^Version: /{print $2}' "$SOURCE_DIR/control")"
python3 - "$SOURCE_DIR/prefs/resources/Info.plist" "$VERSION" <<'PYEOF'
import plistlib, sys
path, version = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    data = plistlib.load(f)
data["CFBundleShortVersionString"] = version
data["CFBundleVersion"] = version
with open(path, "wb") as f:
    plistlib.dump(data, f)
print("同步 bundle 版本 ->", version)
PYEOF

make package "$@"

# 注意:工程目录不含空格时 SOURCE_DIR 就等于 PROJECT_DIR,此时把 packages/*.deb 拷到
# 自己的目录属于"自复制",macOS 的 cp 会以 "are identical" 返回 1;在 set -e 下脚本会
# 直接在这里退出,后面的裸 dylib 导出就再也不会执行(踩过这个坑)。所以必须跳过。
SRC_DEB_DIR="$SOURCE_DIR/packages"
DST_DEB_DIR="$PROJECT_DIR/packages"
mkdir -p "$DST_DEB_DIR"
if [[ "$SRC_DEB_DIR" != "$DST_DEB_DIR" ]]; then
    cp -v "$SRC_DEB_DIR"/*.deb "$DST_DEB_DIR/"
fi

echo
echo "==> 产物:"
ls -lh "$DST_DEB_DIR/"
