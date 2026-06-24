#!/bin/bash
set -e
export PATH="/mingw64/bin:/ucrt64/bin:/usr/bin:/bin"
echo "=== AGR FXP MAC - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-GENUNNAMED \
    --top-module tb_agr_fxp_mac \
    --cc ../rtl/agr_fxp_mac.sv ../tb/tb_agr_fxp_mac.sv \
    --exe tb_agr_fxp_mac.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
