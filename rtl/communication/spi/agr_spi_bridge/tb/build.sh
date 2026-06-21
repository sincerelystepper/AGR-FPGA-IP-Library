#!/bin/bash
echo "Using Verilator: $(verilator --version)"
verilator -Wall --trace --trace-structs \
  -Wno-UNUSEDSIGNAL \
  -Wno-CASEINCOMPLETE \
  --cc ../rtl/agr_spi_bridge.sv \
  --exe tb.cpp \
  --build \
  -CFLAGS "-std=c++17"
echo "Build complete!"
