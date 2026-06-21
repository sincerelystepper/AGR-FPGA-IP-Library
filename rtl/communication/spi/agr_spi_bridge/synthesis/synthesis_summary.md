# Synthesis Summary - agr_spi_bridge

**Date**: 2026-06-21
**Tool**: Yosys 0.56 (MSYS2 UCRT64)
**Target**: iCE40 (Lattice iCE40 FPGA)

## Cell Count

| Cell Type | Count | Description |
|-----------|-------|-------------|
| SB_LUT4   | 41    | 4-input Look-Up Table |
| SB_DFFE   | 48    | DFF with Enable |
| SB_DFFER  | 43    | DFF with Enable and Reset |
| SB_DFFR   | 10    | DFF with Reset |
| SB_DFFS   | 3     | DFF with Set |
| SB_CARRY  | 1     | Carry chain |
| **TOTAL** | **146** | |

## Resource Breakdown

- **LUT4 (combinational)**: 41
  - 1-LUT: 1
  - 2-LUT: 8
  - 3-LUT: 21
  - 4-LUT: 11
  - Average: 3.05 inputs/LUT

- **Flip-Flops (sequential)**: 104
  - With reset: 53
  - With enable: 48
  - Plain: 3

## Lint Findings (Free)

| Finding | Severity | Notes |
|---------|----------|-------|
| `rx_shift[7]` unused | Info | MSB dropped during byte assembly, harmless |
| `cmd_commit[6:0]` unused | Info | Only bit 7 checked for R/W decision |
| `read_buffer` dead code | Warning | Written but never read; TX uses `tx_data_reg` |
| `case(state)` non-exhaustive | Info | Yosys marked as `full_case`, `cs_rise` self-heals |

## Timing

- Max logic depth: 5 levels
- Max LUT depth: 2 levels (post-mapping)
- Estimated Fmax: ~50 MHz (iCE40)

## Files

- `synth.ys` - Yosys synthesis script
- `yosys_out.txt` - Full synthesis log
- `agr_spi_bridge_synth.v` - Gate-level netlist
- `synthesis_summary.md` - This file
