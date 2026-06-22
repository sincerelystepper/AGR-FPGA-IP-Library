# agr_fxp_mult — Fixed-Point Multiplier

## Overview

`agr_fxp_mult` is a parameterized signed fixed-point multiplier designed for production DSP pipelines.

It provides:

- Full-precision product output (no loss of information)
- Configurable width reduction
- Explicit control over truncation alignment
- Accurate overflow and precision tracking

This module is a **core arithmetic primitive** in the AGR-FPGA-IP-Library.

---

## Features

- Signed 2’s complement multiplication
- Full-precision output (`result_full`)
- Configurable reduced-width output (`result`)
- MSB/LSB truncation modes
- Distinction between:
  - **overflow** (range error)
  - **precision loss** (information loss)

- DSP inference-friendly implementation
- Fully combinational (zero-latency)

---

## Parameters

| Parameter       | Description |
|----------------|------------|
| IN_A_W          | Width of input `a` |
| IN_B_W          | Width of input `b` |
| OUT_W           | Width of truncated output |
| SIGNED          | Must be 1 (signed mode) |
| TRUNCATE_MSB    | 1 = MSB-aligned, 0 = LSB-aligned |

---

## Interface

```systemverilog
input  logic signed [IN_A_W-1:0]   a;
input  logic signed [IN_B_W-1:0]   b;

output logic signed [IN_A_W+IN_B_W-1:0] result_full;
output logic signed [OUT_W-1:0]         result;
output logic                            overflow;
