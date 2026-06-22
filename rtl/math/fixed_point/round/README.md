
# agr_fxp_round — Fixed-Point Rounding Module

## Overview

`agr_fxp_round` is a parameterized fixed-point rounding module that reduces bit width while minimizing quantization bias. It replaces simple truncation with mathematically correct rounding strategies and is a **critical component for accurate DSP pipelines**.

---

## Why This Module Matters

After resizing operations:

wide result → resize → truncated result

Simple truncation introduces:

- Bias toward zero
- Accumulated numerical error
- Unstable DSP behavior (FFT, FIR, MAC)

`agr_fxp_round` solves this by applying controlled rounding.

---

## Features

- Signed 2’s complement arithmetic
- Multiple rounding modes:
  - TRUNCATE
  - ROUND TO NEAREST
  - ROUND HALF UP
  - CONVERGENT (round-to-even)
- MSB-aligned rounding (primary DSP use)
- LSB-aligned fallback (no rounding applied)
- Explicit:
  - `overflow` detection
  - `precision_loss` reporting
- Fully combinational (zero latency)

---

## Parameters

| Parameter | Description |
|----------|------------|
| IN_W     | Input width |
| OUT_W    | Output width |
| MODE     | 0=TRUNCATE, 1=NEAREST, 2=HALF_UP, 3=CONVERGENT |
| ALIGN    | 0=LSB-aligned, 1=MSB-aligned |

---

## Interface

```systemverilog
input  logic signed [IN_W-1:0]  in_val;

output logic signed [OUT_W-1:0] out_val;

output logic overflow;
output logic precision_loss;
```

## Functional Behavior

### Expansion / Pass-through (OUT_W ≥ IN_W)

No rounding applied. Output is sign-extended or unchanged.

out_val = in_val
overflow = 0
precision_loss = 0

### Reduction (OUT_W < IN_W)

Only MSB-aligned mode applies rounding.

#### Rounding Modes

1. TRUNCATE (MODE = 0)
   - Drop lower bits
   - Fast, zero overhead
   - Introduces bias

2. ROUND TO NEAREST (MODE = 1)
   - round if dropped bits ≥ half
   - Improves accuracy over truncation
   - Still slightly biased

3. ROUND HALF UP (MODE = 2)
   - ties (0.5) always round upward
   - Simple behavior
   - Introduces positive bias

4. CONVERGENT (MODE = 3)
   - ties round to EVEN result

Example:
2.5 → 2  
3.5 → 4

 Eliminates statistical bias
 Best choice for DSP pipelines

#### Alignment Behavior

MSB-Aligned (ALIGN = 1)

- Keeps upper bits
- Drops lower bits
- Rounding applies to fractional portion

 Primary DSP usage

LSB-Aligned (ALIGN = 0)

- Keeps lower bits
- Drops upper bits

 Rounding is disabled (not meaningful in this mode)

## Output Signals

### overflow

Indicates a true range violation:

Output cannot represent the rounded value
Only meaningful in LSB-aligned mode

### precision_loss

Indicates information loss:

- Bits were discarded
- Value changed due to rounding

## Latency

OperationCyclesCombinational0

## Verification

This module is verified using:

- 64-bit golden reference model
- Directed tests:
  - tie cases (0.5 boundaries)
  - sign transitions
  - edge values

Convergent rounding validation
Random regression (15,000+ checks)

 All tests pass
 Bias behavior validated

## Example

### MSB-Aligned Convergent Rounding

Input  = 2.5
Mode   = CONVERGENT

→ Output = 2  (even)

### Truncation vs Rounding

Raw value: 0.75

TRUNCATE → 0
ROUND    → 1

## Role in DSP Pipeline

mult → resize → round → MAC → FFT

This module ensures:

- Numerical stability
- Reduced bias
- Accurate accumulation

## Design Notes

- No implicit casting
- Explicit bit control
- Synthesizable across FPGA toolchains
- DSP-friendly architecture

## Future Extensions

- Pipeline version (1+ stages)
- Saturating rounding
- Block floating-point support

## Status

 Production-ready
 Fully verified
 Critical numerical control block
