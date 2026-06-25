#!/bin/bash
set -e
export PATH="/ucrt64/bin:/mingw64/bin:/usr/bin:/bin"
echo "=== AGR FFT BUTTERFLY SCALED ==="
verilator -Wall --trace --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-WIDTH -Wno-UNUSEDSIGNAL \
    -Wno-GENUNNAMED -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM \
    --top-module tb_agr_fft_butterfly_scaled \
    --cc ../rtl/agr_fft_butterfly_scaled.sv \
        ../../agr_fft_butterfly/rtl/agr_fft_butterfly.sv \
        ../../agr_complex_addsub/rtl/agr_complex_addsub.sv \
        ../../agr_fxp_resize/rtl/agr_fxp_resize.sv \
        ../tb/tb_agr_fft_butterfly_scaled.sv \
    --exe tb_agr_fft_butterfly_scaled.cpp \
    --build -CFLAGS "-std=c++17 -O3"
echo "Build complete!"
