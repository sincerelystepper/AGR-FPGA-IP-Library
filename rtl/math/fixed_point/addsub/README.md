# AGR Fixed-Point Add/Subtract (agr_fxp_addsub)

## Description
Parameterized fixed-point add/subtract module with optional saturation.

## Features
- Signed 2’s complement arithmetic
- Add and subtract support
- Saturation control (SATURATE parameter)
- Overflow detection
- Configurable input/output widths

## Parameters

| Parameter | Description |
|----------|------------|
| IN_W     | Input width |
| OUT_W    | Output width |
| SATURATE | 1 = saturate, 0 = wrap |

## Interface

```systemverilog
input  add_sub  // 0 = add, 1 = subtract
input  a, b     // signed inputs
output result   // signed output
output overflow // overflow flag
