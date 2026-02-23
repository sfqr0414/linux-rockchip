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

# 预先确保 O= 构建目录已准备（避免在 debian/rules 中触发交互式配置）
BUILD_DIR="../build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ ! -f "$BUILD_DIR/include/generated/autoconf.h" ]; then
    echo "准备: make O=$BUILD_DIR ARCH=arm64 olddefconfig && make O=$BUILD_DIR ARCH=arm64 prepare (非交互)"
    # 如果还没有配置文件，复制一个默认配置以避免交互式提示
    if [ ! -f "$BUILD_DIR/.config" ]; then
        echo "复制默认配置到 $BUILD_DIR/.config"
        cp debian.rockchip/config/config.common.ubuntu "$BUILD_DIR/.config" 2>/dev/null || true
    fi
    make O="$BUILD_DIR" ARCH=arm64 olddefconfig || { echo "olddefconfig 失败"; exit 1; }
    make O="$BUILD_DIR" ARCH=arm64 prepare || { echo "prepare 失败"; exit 1; }
fi

echo "执行: fakeroot debian/rules clean (non-interactive)"
DEBIAN_FRONTEND=noninteractive fakeroot debian/rules clean 2>&1 || { echo "clean 步骤失败"; exit 1; }

echo "执行: fakeroot debian/rules binary-headers binary-rockchip do_mainline_build=true (non-interactive)"
DEBIAN_FRONTEND=noninteractive \
DH_OPTIONS="--destdir=$BUILT_PACKAGES_ABS" \
fakeroot debian/rules binary-headers binary-rockchip do_mainline_build=true \
MAKEFLAGS="--silentoldconfig -j$(nproc)" 2>&1 < <(yes '') || {
    echo "编译内核失败";
    exit 1; 
}
cd -