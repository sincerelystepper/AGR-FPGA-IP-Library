`default_nettype none
`timescale 1ns/1ps

module agr_fxp_shift #(
    parameter int DATA_W   = 16,
    parameter int SHIFT_W  = 4,
    parameter bit USE_SATURATE = 1'b0
) (
    input  logic signed [DATA_W-1:0]  in_val,
    input  logic        [SHIFT_W-1:0] shift_amt,
    input  logic                      shift_dir,
    output logic signed [DATA_W-1:0]  out_val,
    output logic                      overflow,
    output logic                      precision_loss
);

    initial begin
        if (DATA_W < 1)  $fatal(1, "DATA_W must be >= 1");
        if (SHIFT_W < 1) $fatal(1, "SHIFT_W must be >= 1");
    end

    localparam int MAX_SHIFT = DATA_W;
    localparam int EFF_W = $clog2(MAX_SHIFT) + 1;

    localparam logic signed [DATA_W-1:0] SAT_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    localparam logic signed [DATA_W-1:0] SAT_MIN = {1'b1, {(DATA_W-1){1'b0}}};

    // Effective shift (clamped)
    logic [EFF_W-1:0] effective_shift;
    assign effective_shift = (shift_amt >= MAX_SHIFT) ? MAX_SHIFT : shift_amt;

    // Full-width shift
    logic signed [2*DATA_W-1:0] shifted_full;
    assign shifted_full = shift_dir ? (in_val << effective_shift) : (in_val >>> effective_shift);

    // Truncated result
    logic signed [DATA_W-1:0] shifted_trunc;
    assign shifted_trunc = shifted_full[DATA_W-1:0];

    // Overflow: true if the truncated value != the full shifted value
    // This catches both sign-bit corruption AND magnitude overflow
    logic left_overflow;
    assign left_overflow = shift_dir && (effective_shift > 0) &&
                           (shifted_full !== signed'(shifted_trunc));

    // Precision loss: LSBs discarded in right shift
    logic [DATA_W-1:0] loss_mask;
    assign loss_mask = (1 << effective_shift) - 1;

    logic right_precision_loss;
    assign right_precision_loss = (!shift_dir) && (effective_shift > 0) &&
                                   |(in_val & loss_mask);

    assign overflow       = shift_dir ? left_overflow : 1'b0;
    assign precision_loss = shift_dir ? 1'b0 : right_precision_loss;

    // Saturation
    assign out_val = (USE_SATURATE && overflow) ? (in_val[DATA_W-1] ? SAT_MIN : SAT_MAX)
                                                  : shifted_trunc;

endmodule
`default_nettype wire
