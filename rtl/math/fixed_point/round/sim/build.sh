#!/bin/bash
set -e
export PATH="/mingw64/bin:/ucrt64/bin:/usr/bin:/bin"

echo "=== AGR FXP ROUND - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH \
    -Wno-UNUSEDSIGNAL -Wno-GENUNNAMED \
    --top-module tb_agr_fxp_round \
    --cc ../rtl/agr_fxp_round.sv ../tb/tb_agr_fxp_round.sv \
    --exe tb_agr_fxp_round.cpp \
    --build -CFLAGS "-std=c++17 -O3"

echo "Build complete! Run: ./obj_dir/Vtb_agr_fxp_round"
