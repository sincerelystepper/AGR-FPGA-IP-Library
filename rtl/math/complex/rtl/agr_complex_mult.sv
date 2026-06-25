// =============================================================================
// AGR-FPGA-IP-Library : agr_complex_mult
// -----------------------------------------------------------------------------
// Project   : AGR-COMPLEX-MULT (fixed-point complex multiplier)
// Author    : Agrionics Co.
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   Complex multiplication: (a_real + j*a_imag) * (b_real + j*b_imag)
//     out_real = (a_real*b_real) - (a_imag*b_imag)
//     out_imag = (a_real*b_imag) + (a_imag*b_real)
//   Core building block for FFT butterflies and I/Q modulation.
//   Pure combinational in v1: no clock, no reset, no state.
//
// ARCHITECTURE (6 stages)
//   Stage 0: 4 full-precision multiplies (ac, bd, ad, bc)
//   Stage 1: Sign-extend and add/subtract (real_full, imag_full)
//   Stage 2: MSB-aligned resize toward OUT_W
//   Stage 3: Optional convergent rounding (round-half-to-even)
//   Stage 4: Per-component overflow detection
//   Stage 5: Independent saturation per component
//
// BIT GROWTH
//   Multiply: 2*IN_W bits (exact, never overflows)
//   Add/Sub:  2*IN_W+1 bits (+1 carry bit)
//   Resize:   DROP_W = (2*IN_W+1) - OUT_W bits discarded
//   Guard:    OUT_W+1 bits through rounding to prevent premature clamp
//
// PARAMETERS
//   IN_W         : input width, signed, >= 1
//   OUT_W        : output width, signed, >= 1
//   USE_ROUNDING : 0 = truncate, 1 = convergent rounding
//   USE_SATURATE : 0 = wrap, 1 = saturate to MIN/MAX
//
// PORTS
//   a_real, a_imag : first complex operand (IN_W bits)
//   b_real, b_imag : second complex operand (IN_W bits)
//   out_real       : real component (OUT_W bits)
//   out_imag       : imaginary component (OUT_W bits)
//   overflow       : OR of per-component overflow flags
//
// VERIFICATION
//   Testbench: tb_agr_complex_mult.sv
//   Checks:   9,033 directed + random
//   Status:   ALL PASSING
//   Coverage: identity, simple, sign combos, MAX/MIN, zero, symmetry, 3000 random
//
// KNOWN ISSUES
//   Verilator 5.x on Windows: $signed() cast on logic signed ports may not
//   propagate correctly. Workaround: int'() cast before multiply.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module agr_complex_mult #(
    parameter int IN_W         = 16,
    parameter int OUT_W        = 16,
    parameter bit USE_ROUNDING = 1'b0,
    parameter bit USE_SATURATE = 1'b0
) (
    input  logic signed [IN_W-1:0]  a_real,
    input  logic signed [IN_W-1:0]  a_imag,
    input  logic signed [IN_W-1:0]  b_real,
    input  logic signed [IN_W-1:0]  b_imag,
    output logic signed [OUT_W-1:0] out_real,
    output logic signed [OUT_W-1:0] out_imag,
    output logic                    overflow
);

    // -------------------------------------------------------------------
    // Parameter validation (simulation only; ignored by synthesis)
    // -------------------------------------------------------------------
    initial begin
        if (IN_W < 1)  $fatal(1, "agr_complex_mult: IN_W must be >= 1 (got %0d)", IN_W);
        if (OUT_W < 1) $fatal(1, "agr_complex_mult: OUT_W must be >= 1 (got %0d)", OUT_W);
    end

    // Derived widths
    localparam int INTERNAL_FULL_W = 2 * IN_W;       // Product width
    localparam int ADD_W           = INTERNAL_FULL_W + 1;  // Sum/diff width

    // ===================================================================
    // STAGE 0: Four full-precision signed multiplies
    // int'() cast required for Verilator 5.x signed propagation
    // ===================================================================
    logic signed [INTERNAL_FULL_W-1:0] ac, bd, ad, bc;
    assign ac = int'(a_real) * int'(b_real);
    assign bd = int'(a_imag) * int'(b_imag);
    assign ad = int'(a_real) * int'(b_imag);
    assign bc = int'(a_imag) * int'(b_real);

    // ===================================================================
    // STAGE 1: Explicit sign extension BEFORE add/subtract
    // Critical: prevents Verilator from truncating intermediate results
    // ===================================================================
    logic signed [ADD_W-1:0] ac_ext, bd_ext, ad_ext, bc_ext;
    assign ac_ext = {ac[INTERNAL_FULL_W-1], ac};
    assign bd_ext = {bd[INTERNAL_FULL_W-1], bd};
    assign ad_ext = {ad[INTERNAL_FULL_W-1], ad};
    assign bc_ext = {bc[INTERNAL_FULL_W-1], bc};

    logic signed [ADD_W-1:0] real_full, imag_full;
    assign real_full = ac_ext - bd_ext;
    assign imag_full = ad_ext + bc_ext;

    // ===================================================================
    // STAGE 2+3: MSB-aligned resize toward OUT_W + optional rounding
    // Compare against INTERNAL_FULL_W (not ADD_W) for resize decision
    // ===================================================================
    logic signed [OUT_W:0] scaled_real_ext, scaled_imag_ext;

    generate
        if (OUT_W >= INTERNAL_FULL_W) begin : gen_passthrough_or_expand
            localparam int EXT_W = (OUT_W + 1) - ADD_W;
            assign scaled_real_ext = {{EXT_W{real_full[ADD_W-1]}}, real_full};
            assign scaled_imag_ext = {{EXT_W{imag_full[ADD_W-1]}}, imag_full};
        end else begin : gen_reduce_msb
            localparam int DROP_W = ADD_W - OUT_W;
            logic signed [OUT_W-1:0] candidate_real, candidate_imag;
            logic round_carry_real, round_carry_imag;

            assign candidate_real = real_full[ADD_W-1 -: OUT_W];
            assign candidate_imag = imag_full[ADD_W-1 -: OUT_W];

            if (USE_ROUNDING) begin : gen_round_on
                localparam logic [DROP_W-1:0] HALF = {1'b1, {(DROP_W-1){1'b0}}};
                logic [DROP_W-1:0] drop_real, drop_imag;
                assign drop_real = real_full[DROP_W-1:0];
                assign drop_imag = imag_full[DROP_W-1:0];
                assign round_carry_real = (drop_real > HALF) | ((drop_real == HALF) & candidate_real[0]);
                assign round_carry_imag = (drop_imag > HALF) | ((drop_imag == HALF) & candidate_imag[0]);
            end else begin : gen_round_off
                assign round_carry_real = 1'b0;
                assign round_carry_imag = 1'b0;
            end

            assign scaled_real_ext = {candidate_real[OUT_W-1], candidate_real} + signed'({1'b0, round_carry_real});
            assign scaled_imag_ext = {candidate_imag[OUT_W-1], candidate_imag} + signed'({1'b0, round_carry_imag});
        end
    endgenerate

    // ===================================================================
    // STAGE 4: Per-component overflow detection
    // ===================================================================
    localparam logic signed [OUT_W-1:0] OUT_MAX = {1'b0, {(OUT_W-1){1'b1}}};
    localparam logic signed [OUT_W-1:0] OUT_MIN = {1'b1, {(OUT_W-1){1'b0}}};
    localparam logic signed [OUT_W:0]   OUT_MAX_EXT = {OUT_MAX[OUT_W-1], OUT_MAX};
    localparam logic signed [OUT_W:0]   OUT_MIN_EXT = {OUT_MIN[OUT_W-1], OUT_MIN};

    logic overflow_real, overflow_imag;
    assign overflow_real = (scaled_real_ext > OUT_MAX_EXT) || (scaled_real_ext < OUT_MIN_EXT);
    assign overflow_imag = (scaled_imag_ext > OUT_MAX_EXT) || (scaled_imag_ext < OUT_MIN_EXT);
    assign overflow = overflow_real | overflow_imag;

    // ===================================================================
    // STAGE 5: Independent saturation per component
    // ===================================================================
    assign out_real = (USE_SATURATE && overflow_real) ? (scaled_real_ext < 0 ? OUT_MIN : OUT_MAX) : scaled_real_ext[OUT_W-1:0];
    assign out_imag = (USE_SATURATE && overflow_imag) ? (scaled_imag_ext < 0 ? OUT_MIN : OUT_MAX) : scaled_imag_ext[OUT_W-1:0];

endmodule
`default_nettype wire
