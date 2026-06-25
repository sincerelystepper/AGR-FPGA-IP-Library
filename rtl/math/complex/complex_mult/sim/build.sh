#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR COMPLEX MULT - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD -Wno-CMPCONST \
    --top-module tb_agr_complex_mult \
    --cc ../rtl/agr_complex_mult.sv ../tb/tb_agr_complex_mult.sv \
    --exe tb_agr_complex_mult.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
