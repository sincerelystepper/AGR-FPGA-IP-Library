# agr_fxp_resize — Fixed-Point Width and Scaling Control

## Overview

`agr_fxp_resize` is a core numerical control module used to adapt signed fixed-point values between different bit widths in a deterministic and mathematically correct way.

It provides:

- Controlled truncation or saturation
- Explicit MSB and LSB alignment modes
- Accurate overflow detection
- Explicit precision loss tracking

This module is **essential for building stable and predictable DSP pipelines**.

---

## Motivation

In fixed-point DSP systems, arithmetic operations introduce bit growth.

Example:
`16-bit × 16-bit → 32-bit result`

This expanded result cannot be directly fed into subsequent stages without adjustment.

Without controlled resizing:

-  Overflow may occur silently  
-  Precision may be lost unpredictably  
-  Numerical behavior becomes non-deterministic  
-  DSP pipelines (FIR, FFT, MAC) become unstable  

`agr_fxp_resize` enforces **explicit, consistent numerical behavior** during width conversion.

---

## Features

- Signed 2’s complement arithmetic
- Configurable width adaptation:
  - Expansion (sign extension)
  - Reduction (truncate or saturate)
- Alignment control:
  - **MSB-aligned** (scaling behavior)
  - **LSB-aligned** (narrowing behavior)
- Configurable operation modes:
  - **TRUNCATE**
  - **SATURATE**
- Explicit status outputs:
  - `overflow` (range violation)
  - `precision_loss` (information discarded)

---

## Parameters

| Parameter | Description |
|----------|------------|
| IN_W     | Input width (≥ 1) |
| OUT_W    | Output width (≥ 1) |
| MODE     | 0 = TRUNCATE, 1 = SATURATE |
| ALIGN    | 0 = LSB-aligned, 1 = MSB-aligned |

---

## Interface

```systemverilog
input  logic signed [IN_W-1:0]  in_val;

output logic signed [OUT_W-1:0] out_val;

output logic overflow;
output logic precision_loss;
