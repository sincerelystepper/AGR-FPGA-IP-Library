#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR TWIDDLE ROM ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD \
    --top-module tb_agr_twiddle_rom \
    --cc ../rtl/agr_twiddle_rom.sv ../tb/tb_agr_twiddle_rom.sv \
    --exe tb_agr_twiddle_rom.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
