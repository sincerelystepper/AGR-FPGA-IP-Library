# AGR Complex Add/Sub RTL

## Overview

`agr_complex_addsub` is a fixed-point signed complex adder/subtractor implemented in SystemVerilog. It supports both complex addition and subtraction as a single combinational core:

- `sub = 0`: `out = A + B`
- `sub = 1`: `out = A - B`

This module is designed for DSP pipelines and FFT butterfly stages. It is a pure combinational block with no clock, reset, or internal state.

## Key Features

- Signed complex add/sub operation
- Parameterized input/output widths
- Optional per-component saturation
- Overflow detection output
- Pure combinational datapath
- FFT butterfly friendly when paired with `agr_complex_mult`

## Parameters

- `IN_W` : Input width for each real/imag component. Signed. Minimum 1.
- `OUT_W` : Output width for each real/imag component. Signed. Minimum 1.
- `USE_SATURATE` : `0` = wrap on overflow, `1` = saturate to signed min/max.

## Ports

- `input logic signed [IN_W-1:0] a_real`
- `input logic signed [IN_W-1:0] a_imag`
- `input logic signed [IN_W-1:0] b_real`
- `input logic signed [IN_W-1:0] b_imag`
- `input logic sub`
- `output logic signed [OUT_W-1:0] out_real`
- `output logic signed [OUT_W-1:0] out_imag`
- `output logic overflow`

## Datapath Stages

1. Sign-extend inputs from `IN_W` to `IN_W+1` bits.
2. Perform addition or subtraction at full `IN_W+1` precision.
3. Resize results toward `OUT_W` with MSB-aligned sign handling.
4. Detect overflow and optionally saturate each component independently.

## Behavioral Notes

- Internal arithmetic operates at `IN_W+1` bits to cover the worst-case carry/borrow.
- No internal wrap-around occurs before resize.
- If `OUT_W < IN_W+1`, the module drops low-order bits using MSB-aligned truncation.
- `overflow` is asserted when either output component exceeds the signed `OUT_W` range.
- Saturation is applied per component; real and imaginary results clamp independently.

## Verification

- Testbench: `tb_agr_complex_addsub.sv`
- Verified cases cover:
  - addition and subtraction
  - zero input cases
  - identity checks (`A - A == 0`)
  - sign combinations
  - max/min boundaries
  - symmetry (`A + B == B + A`)
  - 3000 random input pairs

## Files

- `rtl/agr_complex_addsub.sv` — RTL implementation
- `tb/tb_agr_complex_addsub.sv` — SystemVerilog testbench

## Usage

Instantiate the module with the desired bit widths and saturation mode:

```systemverilog
agr_complex_addsub #(
    .IN_W(16),
    .OUT_W(16),
    .USE_SATURATE(1'b1)
) u_complex_addsub (
    .a_real(a_real),
    .a_imag(a_imag),
    .b_real(b_real),
    .b_imag(b_imag),
    .sub(sub),
    .out_real(out_real),
    .out_imag(out_imag),
    .overflow(overflow)
);
```

## Integration Guidelines

- This core is combinational; do not connect clocks or resets directly.
- Use it inside a registered pipeline stage or latency-controlled wrapper when timing is required.
- Ensure operands are stable before sampling the output in the next clock domain.
- Use `overflow` to detect out-of-range arithmetic results, especially when `USE_SATURATE` is disabled.
- Match `IN_W` and `OUT_W` to the surrounding fixed-point format to preserve dynamic range.
- When used in an FFT butterfly, pair `agr_complex_addsub` with `agr_complex_mult` for twiddle-factor multiplication.

## Notes

- `default_nettype none` is used in the RTL to prevent implicit nets.
