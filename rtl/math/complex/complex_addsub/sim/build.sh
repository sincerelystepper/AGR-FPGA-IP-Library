#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR COMPLEX ADDSUB - Verilator Build ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD \
    --top-module tb_agr_complex_addsub \
    --cc ../rtl/agr_complex_addsub.sv ../tb/tb_agr_complex_addsub.sv \
    --exe tb_agr_complex_addsub.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
