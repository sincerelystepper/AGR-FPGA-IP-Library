// =============================================================================
// AGR-FPGA-IP-Library : agr_fft_butterfly
// -----------------------------------------------------------------------------
// Project   : AGR-FFT-BUTTERFLY (radix-2 FFT butterfly)
// Author    : Agrionics Co.
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   Radix-2 decimation-in-time FFT butterfly:
//     X0 = A + B
//     X1 = (A - B) * W
//   Pure combinational in v1. Uses agr_complex_addsub, agr_complex_mult,
//   and agr_fxp_resize from the AGR DSP library.
//
// DATAFLOW
//   Stage 0: Complex add (X0) and subtract (X1_pre) via agr_complex_addsub
//   Stage 1: Complex multiply X1_pre * W via agr_complex_mult
//   Stage 2: Resize X0 to OUT_W via agr_fxp_resize
//
// PARAMETERS
//   IN_W  : input width (A, B operands)
//   TW_W  : twiddle factor width (W operand)
//   OUT_W : output width (X0, X1)
//
// NOTE: For exact results without truncation, set OUT_W >= IN_W + TW_W + 2.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module agr_fft_butterfly #(
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

    initial begin
        if (IN_W < 1)  $fatal(1, "IN_W must be >= 1");
        if (TW_W < 1)  $fatal(1, "TW_W must be >= 1");
        if (OUT_W < 1) $fatal(1, "OUT_W must be >= 1");
    end

    localparam int SUM_W = IN_W + 1;
    localparam int PROD_W = SUM_W + TW_W;
    localparam int FULL_W = PROD_W + 1;

    // Stage 0: Complex add and subtract
    logic signed [SUM_W-1:0] sum_real, sum_imag;
    logic signed [SUM_W-1:0] diff_real, diff_imag;
    logic unused1, unused2;

    agr_complex_addsub #(.IN_W(IN_W), .OUT_W(SUM_W))
    u_add (.a_real, .a_imag, .b_real, .b_imag, .sub(0),
           .out_real(sum_real), .out_imag(sum_imag), .overflow(unused1));

    agr_complex_addsub #(.IN_W(IN_W), .OUT_W(SUM_W))
    u_sub (.a_real, .a_imag, .b_real, .b_imag, .sub(1),
           .out_real(diff_real), .out_imag(diff_imag), .overflow(unused2));

    // Stage 1: Complex multiply with correct bit widths
    logic signed [PROD_W-1:0] ac, bd, ad, bc;
    assign ac = int'(diff_real) * int'(w_real);
    assign bd = int'(diff_imag) * int'(w_imag);
    assign ad = int'(diff_real) * int'(w_imag);
    assign bc = int'(diff_imag) * int'(w_real);

    logic signed [FULL_W-1:0] real_full, imag_full;
    assign real_full = {ac[PROD_W-1], ac} - {bd[PROD_W-1], bd};
    assign imag_full = {ad[PROD_W-1], ad} + {bc[PROD_W-1], bc};

    // MSB-aligned resize
    logic signed [OUT_W-1:0] mult_real, mult_imag;
    generate
        if (OUT_W >= FULL_W) begin : gen_expand
            localparam int PAD = OUT_W - FULL_W;
            assign mult_real = {{PAD{real_full[FULL_W-1]}}, real_full};
            assign mult_imag = {{PAD{imag_full[FULL_W-1]}}, imag_full};
        end else begin : gen_reduce
            assign mult_real = real_full[FULL_W-1 -: OUT_W];
            assign mult_imag = imag_full[FULL_W-1 -: OUT_W];
        end
    endgenerate

    // Stage 2: Resize sum to OUT_W
    logic x0_ovf_r, x0_ovf_i, pl1, pl2;
    logic mult_ovf;
    assign mult_ovf = (OUT_W < FULL_W) ? ((real_full > {1'b0,{(OUT_W-1){1'b1}}}) || (real_full < {1'b1,{(OUT_W-1){1'b0}}}) || (imag_full > {1'b0,{(OUT_W-1){1'b1}}}) || (imag_full < {1'b1,{(OUT_W-1){1'b0}}})) : 1'b0;

    agr_fxp_resize #(.IN_W(SUM_W), .OUT_W(OUT_W))
    u_res_r (.in_val(sum_real), .out_val(x0_real), .overflow(x0_ovf_r), .precision_loss(pl1));
    agr_fxp_resize #(.IN_W(SUM_W), .OUT_W(OUT_W))
    u_res_i (.in_val(sum_imag), .out_val(x0_imag), .overflow(x0_ovf_i), .precision_loss(pl2));

    assign x1_real  = mult_real;
    assign x1_imag  = mult_imag;
    assign overflow = x0_ovf_r | x0_ovf_i | mult_ovf;

endmodule
`default_nettype wire
