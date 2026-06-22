#!/bin/bash
set -e
export PATH="/mingw64/bin:/ucrt64/bin:/usr/bin:/bin"

echo "=== AGR FXP MULT - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC \
    -Wno-WIDTHEXPAND \
    -Wno-WIDTH \
    -Wno-UNUSEDSIGNAL \
    --top-module tb_agr_fxp_mult \
    --cc ../rtl/agr_fxp_mult.sv ../tb/tb_agr_fxp_mult.sv \
    --exe tb_agr_fxp_mult.cpp \
    --build -CFLAGS "-std=c++17 -O3"

echo "Build complete! Run: ./obj_dir/Vtb_agr_fxp_mult"
