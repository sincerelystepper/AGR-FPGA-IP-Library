#!/bin/bash
# Agrionics Fixed-Point AddSub - Verilator Build Script
# Usage: ./build.sh [--clean]

set -e

# Environment setup (MINGW64 for stable ABI, UCRT64 for Python3)
export PATH="/mingw64/bin:/ucrt64/bin:/usr/bin:/bin"

echo "========================================="
echo " Agrionics FXP AddSub - Verilator Build"
echo "========================================="

# Configuration
TOP_MODULE="tb_agr_fxp_addsub"
RTL="../rtl/agr_fxp_addsub.sv"
TB="../tb/tb_agr_fxp_addsub.sv"
SIM_MAIN="tb_agr_fxp_addsub.cpp"
BUILD_DIR="obj_dir"

# Clean if requested
if [ "$1" = "--clean" ]; then
    echo "Cleaning..."
    rm -rf ${BUILD_DIR} wave.vcd
fi

# Verilator compile
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC \
    -Wno-WIDTHEXPAND \
    -Wno-WIDTH \
    --top-module ${TOP_MODULE} \
    --cc ${RTL} ${TB} \
    --exe ${SIM_MAIN} \
    --build \
    -CFLAGS "-std=c++17 -O3"

echo "Build complete!"
echo "Run: ./obj_dir/Vtb_agr_fxp_addsub"
echo "Wave: gtkwave wave.vcd"
