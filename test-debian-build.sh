set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$DIR" || { echo "无法切换到脚本目录: $DIR"; exit 1; }

BUILT_PACKAGES_DIR="../built_packages"
rm -rf "$BUILT_PACKAGES_DIR"
mkdir -p "$BUILT_PACKAGES_DIR"
# 转换为绝对路径（避免内核打包脚本中相对路径解析错误）
BUILT_PACKAGES_ABS=$(realpath "$BUILT_PACKAGES_DIR")

# 编译前检查依赖
echo "===== 检查编译依赖 ====="
dpkg-architecture -aarm64 || { echo "dpkg-architecture 执行失败"; exit 1; }
which aarch64-linux-gnu-gcc || { echo "未找到 aarch64-linux-gnu-gcc"; exit 1; }
aarch64-linux-gnu-gcc --version

# 非交互式准备内核构建并打包
echo "===== 开始非交互式准备内核构建与打包 ====="
export DEBIAN_FRONTEND=noninteractive
export $(dpkg-architecture -aarm64)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=aarch64-linux-gnu-gcc
export LANG=C

BUILD_DIR="../build"
BUILD_DIR=$(realpath "$BUILD_DIR")

cleanup() {
    exit_code=${1:-$?}
    if [[ "$exit_code" -ne 0 ]]; then
        echo "❌ Script exited abnormally"
    else
        echo "✅ Script exited successfully"
    fi

    TARGET_DIR="$BUILD_DIR/build-rockchip"
    if mountpoint -q "$TARGET_DIR"; then
        sudo umount -l "$TARGET_DIR"
        if [ $? -eq 0 ]; then
            echo "成功卸载 $TARGET_DIR"
        else
            echo "卸载 $TARGET_DIR 失败（可能被进程占用）"
        fi
    fi
    exit "$exit_code"
}

trap 'cleanup $?' EXIT HUP INT TERM QUIT

export BUILD_DIR

echo "执行: fakeroot debian/rules clean (non-interactive)"
DEBIAN_FRONTEND=noninteractive fakeroot debian/rules clean 2>&1 || { echo "clean 步骤失败"; exit 1; }

mkdir -p "$BUILD_DIR/build-rockchip"
sudo mount -t tmpfs -o size=12G none "$BUILD_DIR/build-rockchip"

echo "执行: fakeroot debian/rules binary-headers binary-rockchip do_mainline_build=true (non-interactive)"
DEBIAN_FRONTEND=noninteractive \
DH_OPTIONS="--destdir=$BUILT_PACKAGES_ABS" \
fakeroot debian/rules binary-headers binary-rockchip do_mainline_build=true \
MAKEFLAGS="-j$(nproc) O=$BUILD_DIR" 2>&1 < <(yes '') || {
    echo "编译内核失败";
    exit 1; 
}
cd -