#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR FXP SHIFT - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD \
    --top-module tb_agr_fxp_shift \
    --cc ../rtl/agr_fxp_shift.sv ../tb/tb_agr_fxp_shift.sv \
    --exe tb_agr_fxp_shift.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
