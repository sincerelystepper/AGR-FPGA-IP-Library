#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR FFT RADIX-2 ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM \
    -Wno-UNOPTFLAT \
    --top-module tb_agr_fft_radix2 \
    --cc ../rtl/agr_fft_radix2.sv ../tb/tb_agr_fft_radix2.sv \
    --exe tb_agr_fft_radix2.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
