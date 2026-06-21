#!/bin/bash
# Quick synthesis run script
yosys synth.ys 2>&1 | tee yosys_out.txt
echo ""
echo "=== Cell Count ==="
grep -A10 "Printing statistics" yosys_out.txt | grep -E "SB_|Number of cells" | tail -10
