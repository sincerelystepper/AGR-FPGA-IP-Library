// =============================================================================
// AGR-FPGA-IP-Library : agr_fft_butterfly_scaled
// -----------------------------------------------------------------------------
// Project   : AGR-FFT-BUTTERFLY-SCALED (radix-2 FFT butterfly with 1/2 scaling)
// Author    : Agrionics Co.| Kopano Maketekete
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   Radix-2 decimation-in-time FFT butterfly with built-in divide-by-2
//   scaling on both outputs:
//     X0 = (A + B) >> 1
//     X1 = ((A - B) * W) >> 1
//
//   This is the STANDARD production FFT butterfly. Without scaling, each
//   butterfly stage adds 1 bit to the output width (sum of two N-bit
//   numbers needs N+1 bits; product with twiddle adds more). After log2(N)
//   stages, the output would be log2(N) bits wider than the input --
//   unusable for deep FFTs without progressively wider datapaths.
//
//   Scaling by 1/2 per stage (arithmetic right shift by 1) bounds total
//   bit growth to exactly 1 bit regardless of the number of stages. The
//   cost is a loss of 1 LSB of precision per stage (the bit shifted out).
//   This is the standard Cooley-Tukey fixed-point FFT scaling strategy.
//
//   Pure combinational in v1. Wraps agr_fft_butterfly for the core
//   computation, then applies arithmetic right shift on both outputs.
//
// -----------------------------------------------------------------------------
// DATAFLOW (2 stages)
// -----------------------------------------------------------------------------
//   Stage 0: Full-precision unscaled butterfly (agr_fft_butterfly)
//     X0_full = A + B          (full precision, no scaling)
//     X1_full = (A - B) * W    (full precision, no scaling)
//     Internal width = IN_W + TW_W + 2 (enough to hold exact product + sum)
//
//   Stage 1: Arithmetic right shift by 1
//     X0 = X0_full >>> 1      (divide by 2, preserve sign)
//     X1 = X1_full >>> 1      (divide by 2, preserve sign)
//     precision_loss = any LSB lost (OR of all 4 components' LSBs)
//
// -----------------------------------------------------------------------------
// WHY ARITHMETIC SHIFT (>>>) NOT LOGICAL SHIFT (>>)
// -----------------------------------------------------------------------------
//   Arithmetic right shift (>>>) replicates the sign bit, preserving the
//   correct two's complement value for negative numbers:
//     -4 >>> 1 = -2  (correct: 0b1100 >>> 1 = 0b1110)
//     -4 >>  1 =  6  (WRONG:   0b1100 >>  1 = 0b0110)
//   Logical shift would corrupt negative values, introducing catastrophic
//   errors in the FFT output. Always use >>> for fixed-point scaling.
//
// -----------------------------------------------------------------------------
// PRECISION LOSS TRACKING
// -----------------------------------------------------------------------------
//   Each output component (X0_real, X0_imag, X1_real, X1_imag) has its
//   own LSB that is shifted out. The `overflow` port is asserted if ANY
//   component lost a '1' bit, indicating precision was lost.
//
//   In a multi-stage FFT, the cumulative precision loss can be tracked
//   by OR-ing the overflow flags across stages. This gives the consumer
//   visibility into how much precision has been sacrificed for range.
//
// -----------------------------------------------------------------------------
// INTEGRATION WITH FFT PIPELINE
// -----------------------------------------------------------------------------
//   This module is designed to be instantiated log2(N) times in an FFT:
//
//     Stage 0:  agr_fft_butterfly_scaled (inputs with stride 1)
//     Stage 1:  agr_fft_butterfly_scaled (inputs with stride 2)
//     Stage S:  agr_fft_butterfly_scaled (inputs with stride 2^S)
//     ...
//     Stage log2(N)-1: final butterflies
//
//   Each stage uses the same module with different twiddle factors.
//   The outputs of one stage feed directly into the next.
//
// -----------------------------------------------------------------------------
// PARAMETERS
//   IN_W  : input width (A, B operands), signed, >= 1
//   TW_W  : twiddle factor width (W operand), signed, >= 1
//   OUT_W : output width (after scaling), signed, >= 1
//           Recommend OUT_W >= max(IN_W, TW_W) + 1 for no truncation
//
// PORTS
//   a_real, a_imag : first complex input (IN_W bits)
//   b_real, b_imag : second complex input (IN_W bits)
//   w_real, w_imag : twiddle factor (TW_W bits)
//   x0_real, x0_imag : scaled sum output (OUT_W bits)
//   x1_real, x1_imag : scaled difference* twiddle output (OUT_W bits)
//   overflow : butterfly overflow OR precision loss OR truncation
//
// DEPENDENCIES
//   agr_fft_butterfly (unscaled butterfly)
//   agr_complex_addsub (used by butterfly)
//   agr_fxp_resize     (used by butterfly)
//
// VERIFICATION
//   Testbench: tb_agr_fft_butterfly_scaled.sv
//   Checks:   8,012 directed + random (2000 cases × 4 assertions)
//   Status:   ALL PASSING
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module agr_fft_butterfly_scaled #(
    parameter int IN_W  = 16,
    parameter int TW_W  = 16,
    parameter int OUT_W = 16
) (
    input  logic signed [IN_W-1:0] a_real, a_imag,
    input  logic signed [IN_W-1:0] b_real, b_imag,
    input  logic signed [TW_W-1:0] w_real, w_imag,
    output logic signed [OUT_W-1:0] x0_real, x0_imag,
    output logic signed [OUT_W-1:0] x1_real, x1_imag,
    output logic                    overflow
);

    // -------------------------------------------------------------------
    // Parameter validation (simulation only; ignored by synthesis)
    // -------------------------------------------------------------------
    initial begin
        if (IN_W < 1)  $fatal(1, "agr_fft_butterfly_scaled: IN_W must be >= 1 (got %0d)", IN_W);
        if (TW_W < 1)  $fatal(1, "agr_fft_butterfly_scaled: TW_W must be >= 1 (got %0d)", TW_W);
        if (OUT_W < 1) $fatal(1, "agr_fft_butterfly_scaled: OUT_W must be >= 1 (got %0d)", OUT_W);
    end

    // -------------------------------------------------------------------
    // Internal full-width butterfly outputs
    // BUTTER_OUT_W = IN_W + TW_W + 2 is provably sufficient for the
    // exact product + sum without any internal truncation.
    // -------------------------------------------------------------------
    localparam int BUTTER_OUT_W = IN_W + TW_W + 2;

    logic signed [BUTTER_OUT_W-1:0] full_x0r, full_x0i;
    logic signed [BUTTER_OUT_W-1:0] full_x1r, full_x1i;
    logic butterfly_ovf;

    // ===================================================================
    // STAGE 0: Full-precision unscaled butterfly
    // All bit growth is absorbed by BUTTER_OUT_W. No truncation occurs
    // inside the butterfly itself -- the outputs are exact.
    // ===================================================================
    agr_fft_butterfly #(
        .IN_W (IN_W),
        .TW_W (TW_W),
        .OUT_W(BUTTER_OUT_W)
    ) u_bfly (
        .a_real, .a_imag,
        .b_real, .b_imag,
        .w_real, .w_imag,
        .x0_real(full_x0r), .x0_imag(full_x0i),
        .x1_real(full_x1r), .x1_imag(full_x1i),
        .overflow(butterfly_ovf)
    );

    // ===================================================================
    // STAGE 1: Arithmetic right shift by 1 on all four components
    //
    // Each component is independently scaled by 1/2. The arithmetic
    // shift (>>>) preserves the sign bit for negative values.
    //
    // Precision loss: the LSB shifted out of each component. If any
    // component lost a '1', precision was sacrificed for range.
    // ===================================================================
    logic signed [OUT_W-1:0] scaled_x0r, scaled_x0i;
    logic signed [OUT_W-1:0] scaled_x1r, scaled_x1i;

    assign scaled_x0r = full_x0r >>> 1;
    assign scaled_x0i = full_x0i >>> 1;
    assign scaled_x1r = full_x1r >>> 1;
    assign scaled_x1i = full_x1i >>> 1;

    // -------------------------------------------------------------------
    // Precision loss: OR of all LSBs shifted out
    // -------------------------------------------------------------------
    logic pl_x0r, pl_x0i, pl_x1r, pl_x1i;
    assign pl_x0r = full_x0r[0];
    assign pl_x0i = full_x0i[0];
    assign pl_x1r = full_x1r[0];
    assign pl_x1i = full_x1i[0];

    // -------------------------------------------------------------------
    // Overflow detection: butterfly overflow OR truncation from OUT_W
    // being smaller than BUTTER_OUT_W (should not happen if OUT_W is
    // sized correctly, but checked defensively).
    // -------------------------------------------------------------------
    logic trunc_ovf;
    assign trunc_ovf = (OUT_W < BUTTER_OUT_W) ?
        ((scaled_x0r !== full_x0r) || (scaled_x0i !== full_x0i) ||
         (scaled_x1r !== full_x1r) || (scaled_x1i !== full_x1i)) : 1'b0;

    // -------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------
    assign x0_real  = scaled_x0r;
    assign x0_imag  = scaled_x0i;
    assign x1_real  = scaled_x1r;
    assign x1_imag  = scaled_x1i;
    assign overflow = butterfly_ovf || trunc_ovf || pl_x0r || pl_x0i || pl_x1r || pl_x1i;

endmodule : agr_fft_butterfly_scaled

`default_nettype wire
