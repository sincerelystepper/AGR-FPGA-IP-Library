#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR FFT BUTTERFLY ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM \
    --top-module tb_agr_fft_butterfly \
    --cc ../rtl/agr_fft_butterfly.sv \
        ../../agr_complex_addsub/rtl/agr_complex_addsub.sv \
        ../../agr_fxp_resize/rtl/agr_fxp_resize.sv \
        ../tb/tb_agr_fft_butterfly.sv \
    --exe tb_agr_fft_butterfly.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
