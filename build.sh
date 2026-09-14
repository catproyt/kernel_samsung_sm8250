#!/usr/bin/env bash

SECONDS=0 # builtin bash timer

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEVICE="r8q"
AK3_REPO="https://github.com/notkernel-oss/AnyKernel3"
AK3_BRANCH="$DEVICE"

ZIPNAME="Sora-Kernel-A17-$(date '+%Y%m%d').zip"
TC_DIR="$(pwd)/tc/clang"
DEFCONFIG="vendor/kona-perf_defconfig vendor/samsung/kona-sec-common.config vendor/samsung/$DEVICE.config"

OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTS_DIR="$BOOT_DIR/dts/vendor/qcom"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8)-$DEVICE.zip"
fi

export PATH="$TC_DIR/bin:$PATH"

if ! [ -d "$TC_DIR" ]; then
    echo -e "${YELLOW}Descargando Toolchain Clang...${NC}"
    mkdir -p "$TC_DIR"

    ASSET_URL=$(
        curl -fsSL https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest |
        jq -r '.assets[]
            | select(.name | endswith(".tar.zst"))
            | .browser_download_url' |
        head -n1
    )

    if [ -z "$ASSET_URL" ]; then
        echo -e "${RED}Error al obtener Neutron Clang!${NC}"
        exit 1
    fi

    if ! curl -L "$ASSET_URL" | tar --zstd -x -C "$TC_DIR" --strip-components=1; then
        echo -e "${RED}Fallo la descompresion del compilador!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Toolchain Clang lista!${NC}"
fi

mkdir -p out
echo -e "${YELLOW}Configurando defconfig: $DEFCONFIG${NC}"

make O=out ARCH=arm64 $DEFCONFIG
make O=out ARCH=arm64 olddefconfig

echo -e "\n${YELLOW}Compilando kernel Sora por Catpro...${NC}\n"

make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 dtbo.img

make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 Image

if [ -f "$BOOT_DIR/Image" ]; then
    echo -e "${GREEN}Kernel Image compilado con exito!${NC}"
    
    if [ -d "$DTS_DIR" ]; then
        echo -e "${BLUE}Generando archivo dtb consolidado...${NC}"
        cat $(find "$DTS_DIR" -type f -name "*.dtb" | sort) > "$BOOT_DIR/dtb"
        
        if [ ! -f "$BOOT_DIR/dtb" ]; then
            echo -e "${RED}Fallo al generar dtb!${NC}"
            exit 1
        fi
    fi
else
    echo -e "\n${RED}Fallo la compilacion: Image no encontrado.${NC}"
    exit 1
fi

rm -rf AnyKernel3
echo "[*] Clonando AnyKernel3 para $DEVICE"
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

echo -e "Empaquetando zip flasheable...\n"

cp "$BOOT_DIR/dtbo.img" AnyKernel3/dtbo.img
cp "$BOOT_DIR/Image" AnyKernel3/Image
cp "$BOOT_DIR/dtb" AnyKernel3/dtb

cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..

echo -e "\n${GREEN}Compilacion finalizada con exito!${NC}"
echo -e "${GREEN}Archivo generado: $ZIPNAME${NC}"
