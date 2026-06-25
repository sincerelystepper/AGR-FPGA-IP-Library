# AGR Complex Multiplier RTL

## Overview

`agr_complex_mult` is a fixed-point, signed complex multiplier implemented in SystemVerilog. It computes:

- `out_real = a_real * b_real - a_imag * b_imag`
- `out_imag = a_real * b_imag + a_imag * b_real`

This module is designed as a pure combinational core with no clock, reset, or internal state. It is suitable for FPGA signal-processing building blocks such as FFT butterflies and I/Q modulation.

## Key Features

- Fixed-point signed complex multiply
- Parameterized input/output widths
- Optional convergent rounding
- Optional per-component saturation
- Overflow detection output
- Fully combinational datapath

## Parameters

- `IN_W` : Input width for each real/imag component. Signed. Minimum 1.
- `OUT_W` : Output width for each real/imag component. Signed. Minimum 1.
- `USE_ROUNDING` : `0` = truncate, `1` = convergent round-half-to-even.
- `USE_SATURATE` : `0` = wrap on overflow, `1` = saturate to signed min/max.

## Ports

- `input logic signed [IN_W-1:0] a_real`
- `input logic signed [IN_W-1:0] a_imag`
- `input logic signed [IN_W-1:0] b_real`
- `input logic signed [IN_W-1:0] b_imag`
- `output logic signed [OUT_W-1:0] out_real`
- `output logic signed [OUT_W-1:0] out_imag`
- `output logic overflow`

## Datapath Pipeline

The RTL is logically described in six stages:

1. Four full-precision signed multiplies
2. Sign-extended add/subtract for real and imaginary outputs
3. MSB-aligned resize toward `OUT_W`
4. Optional convergent rounding
5. Per-component overflow detection
6. Optional saturation per component

## Behavioral Notes

- Multiply results use full `2*IN_W` precision.
- Add/subtract operations use `2*IN_W + 1` bits to carry sign and overflow.
- If `OUT_W` is smaller than the internal width, the module discards low-order bits and optionally rounds.
- Overflow is asserted when either component is out of the signed representable range.
- When `USE_SATURATE == 1`, outputs clip to the signed maximum or minimum.

## Verification

- Testbench: `tb_agr_complex_mult.sv`
- Simulation harness: `sim/build.sh`
- Verified cases include:
  - identity vectors
  - simple signed arithmetic
  - sign combinations
  - min/max saturation boundaries
  - zero inputs
  - component symmetry
  - 3000 random vectors

## Files

- `rtl/agr_complex_mult.sv` — RTL implementation
- `tb/tb_agr_complex_mult.sv` — SystemVerilog testbench
- `sim/build.sh` — simulation build driver
- `sim/wave.vcd` — example waveform output from simulation

## Usage

Instantiate the module with the desired bit widths and rounding/saturation mode:

```systemverilog
agr_complex_mult #(
    .IN_W(16),
    .OUT_W(16),
    .USE_ROUNDING(1'b1),
    .USE_SATURATE(1'b1)
) u_complex_mult (
    .a_real(a_real),
    .a_imag(a_imag),
    .b_real(b_real),
    .b_imag(b_imag),
    .out_real(out_real),
    .out_imag(out_imag),
    .overflow(overflow)
);
```

## Integration Guidelines

- This module is purely combinational; do not attach clock or reset signals directly to it.
- Place it inside a clocked pipeline stage or within a clocked wrapper if timing control is required.
- Ensure the input data path provides stable operands during the same cycle and respect downstream timing requirements.
- Use the `overflow` signal to detect out-of-range results when `USE_SATURATE` is disabled, or to verify saturation behavior when enabled.
- Match `IN_W` and `OUT_W` to the surrounding fixed-point format. If `OUT_W < 2*IN_W+1`, keep in mind the core will truncate or round low-order bits.
- For synthesis, no special vendor primitives are required; the design uses standard signed arithmetic and parameterized widths.
- If the design is part of an FFT or DSP chain, align operand formats and sign conventions across all stages for consistent results.

## Notes

- The RTL uses `int'()` casts on signed operands to ensure correct signed multiplication behavior in Verilator 5.x on Windows.
- `default_nettype none` is used to avoid implicit nets and enforce explicit signal declarations.
