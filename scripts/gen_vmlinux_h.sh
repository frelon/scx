#!/bin/bash

# Prerequisite
#
# * .config is ready in the linux repo
# * binary bpftool is installed
# * can `sudo apt install` cross-compile toolchains
#
# Example
#
# ./scripts/gen_vmlinux_h.sh /path/to/linux ./sched/include/arch/

LINUX_REPO="$1" # where the linux repo is located
pushd ${LINUX_REPO}
INCLUDE_TARGET=$2 # target directory, e.g., /path/to/scx/sched/include/arch/
HASH=$(git rev-parse HEAD)
SHORT_SHA=${HASH:0:12} # full SHA of the commit truncated to 12 chars
LINUX_VER=$(git describe --tags --abbrev=0)
: ${BPFTOOL:=/usr/bin/bpftool}

# List of architectures and their corresponding cross-compilers
declare -A ARCHS
ARCHS=(
    [x86]="x86_64-linux-gnu-"
    [arm]="arm-linux-gnueabi-"
    [arm64]="aarch64-linux-gnu-"
    [mips]="mips64-linux-gnu-"
    [powerpc]="powerpc64le-linux-gnu-"
    [riscv]="riscv64-linux-gnu-"
    [s390]="s390x-linux-gnu-"
)

# Detect and install cross-compile toolchains based on the package manager
install_toolchains() {
    echo "Installing cross-compile toolchains..."

    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y \
            gcc-aarch64-linux-gnu gcc-x86-64-linux-gnu \
            gcc-arm-linux-gnueabi gcc-mips64-linux-gnuabi64 \
            gcc-powerpc64le-linux-gnu gcc-riscv64-linux-gnu \
            gcc-s390x-linux-gnu
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y \
            gcc-aarch64-linux-gnu gcc-x86_64-linux-gnu \
            gcc-arm-linux-gnu gcc-mips64-linux-gnuabi64 \
            gcc-powerpc64-linux-gnu gcc-riscv64-linux-gnu \
            gcc-s390x-linux-gnu
    elif command -v yum &> /dev/null; then
        sudo yum install -y \
            gcc-aarch64-linux-gnu gcc-x86_64-linux-gnu \
            gcc-arm-linux-gnu gcc-mips64-linux-gnuabi64 \
            gcc-powerpc64-linux-gnu gcc-riscv64-linux-gnu \
            gcc-s390x-linux-gnu
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --noconfirm \
            aarch64-linux-gnu-gcc x86_64-linux-gnu-gcc \
            arm-linux-gnueabi-gcc mips64-linux-gnu-gcc \
            powerpc64le-linux-gnu-gcc riscv64-linux-gnu-gcc \
            s390x-linux-gnu-gcc
    elif command -v zypper &> /dev/null; then
        sudo zypper --non-interactive install \
            cross-aarch64-gcc14 gcc \
            cross-arm-gcc14 cross-mips-gcc14 \
            cross-ppc64le-gcc14 cross-riscv64-gcc14 \
            cross-s390x-gcc14
        ARCHS=(
            [x86]=""
            [arm]="arm-suse-linux-gnueabi-"
            [arm64]="aarch64-suse-linux-"
            [mips]="mips-suse-linux-"
            [powerpc]="powerpc64le-suse-linux-"
            [riscv]="riscv64-suse-linux-"
            [s390]="s390x-suse-linux-"
        )
    else
        echo "Unsupported package manager. Please install cross-compilers manually."
        exit 1
    fi
}

# Function to compile the kernel and generate vmlinux.h for a given architecture
generate_vmlinux_for_arch() {
    ARCH=$1
    CROSS_COMPILE=${ARCHS[$ARCH]}
    TARGET_DIR=${INCLUDE_TARGET}/${ARCH}
    OUTPUT_FILE="${TARGET_DIR}/vmlinux-${LINUX_VER}-g${SHORT_SHA}.h"
    mkdir -p ${TARGET_DIR}

    LOG="/tmp/${ARCH}.log"
    echo "" > ${LOG}
    echo "Writing compile logs to ${LOG}"

    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig 2>&1 >> ${LOG}
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc) vmlinux 2>&1 >> ${LOG}

    if [ -f ./vmlinux ]; then
        echo "Generating ${OUTPUT_FILE}..."
        if ${BPFTOOL} btf dump file ./vmlinux format c > "${OUTPUT_FILE}"; then
	    echo "${OUTPUT_FILE} generated successfully."
	fi
    else
        echo "Failed to generate vmlinux for ${ARCH}. Please check the compilation process."
    fi
}

if ! command -v ${BPFTOOL} &> /dev/null
then
    echo "bpftool could not be found. Please install it first."
    exit 1
fi

install_toolchains

echo "Start generating vmlinux.h for each arch: "
for ARCH in "${!ARCHS[@]}"; do
    echo "Processing architecture: $ARCH"
    generate_vmlinux_for_arch $ARCH
done

echo "All architectures processed."

popd
