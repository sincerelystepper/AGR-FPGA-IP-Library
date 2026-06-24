`default_nettype none
`timescale 1ns/1ps

module agr_fxp_mac #(
    parameter int IN_A_W       = 16,
    parameter int IN_B_W       = 16,
    parameter int ACC_W        = 32,
    parameter bit USE_ROUNDING = 1'b0,
    parameter bit USE_SATURATE = 1'b0,
    parameter bit ALIGN        = 1'b1
) (
    input  logic signed [IN_A_W-1:0] a,
    input  logic signed [IN_B_W-1:0] b,
    input  logic signed [ACC_W-1:0]  acc,
    output logic signed [ACC_W-1:0]  acc_next,
    output logic                     overflow
);

    initial begin
        if (IN_A_W < 1) $fatal(1, "IN_A_W must be >= 1");
        if (IN_B_W < 1) $fatal(1, "IN_B_W must be >= 1");
        if (ACC_W < 1)  $fatal(1, "ACC_W must be >= 1");
    end

    localparam int INTERNAL_FULL_W = IN_A_W + IN_B_W;

    logic signed [INTERNAL_FULL_W-1:0] mult_full;
    assign mult_full = $signed(a) * $signed(b);

    logic signed [ACC_W:0] scaled_ext;
    logic                  resize_overflow;

    generate
        if (ACC_W >= INTERNAL_FULL_W) begin : gen_passthrough_or_expand
            localparam int EXT_W = (ACC_W + 1) - INTERNAL_FULL_W;
            assign scaled_ext      = {{EXT_W{mult_full[INTERNAL_FULL_W-1]}}, mult_full};
            assign resize_overflow = 1'b0;
        end else if (ALIGN) begin : gen_reduce_msb
            localparam int DROP_W = INTERNAL_FULL_W - ACC_W;
            logic signed [ACC_W-1:0] candidate;
            logic round_carry;
            assign candidate = mult_full[INTERNAL_FULL_W-1 -: ACC_W];
            if (USE_ROUNDING) begin : gen_round_on
                localparam logic [DROP_W-1:0] HALF = {1'b1, {(DROP_W-1){1'b0}}};
                logic [DROP_W-1:0] drop_bits;
                assign drop_bits   = mult_full[DROP_W-1:0];
                assign round_carry = (drop_bits > HALF) | ((drop_bits == HALF) & candidate[0]);
            end else begin : gen_round_off
                assign round_carry = 1'b0;
            end
            logic signed [ACC_W:0] candidate_ext, round_inc;
            assign candidate_ext = {candidate[ACC_W-1], candidate};
            assign round_inc     = {{ACC_W{1'b0}}, round_carry};
            assign scaled_ext    = candidate_ext + round_inc;
            assign resize_overflow = 1'b0;
        end else begin : gen_reduce_lsb
            localparam int DROP_W = INTERNAL_FULL_W - ACC_W;
            logic [DROP_W-1:0] dropped_msbs;
            logic kept_sign;
            assign kept_sign      = mult_full[ACC_W-1];
            assign dropped_msbs  = mult_full[INTERNAL_FULL_W-1:ACC_W];
            assign resize_overflow = (dropped_msbs != {DROP_W{kept_sign}});
            assign scaled_ext      = {mult_full[ACC_W-1], mult_full[ACC_W-1:0]};
        end
    endgenerate

    logic signed [ACC_W:0] acc_ext, acc_sum_ext;
    assign acc_ext     = {acc[ACC_W-1], acc};
    assign acc_sum_ext = acc_ext + scaled_ext;

    localparam logic signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};
    localparam logic signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};
    localparam logic signed [ACC_W:0]   ACC_MAX_EXT = {ACC_MAX[ACC_W-1], ACC_MAX};
    localparam logic signed [ACC_W:0]   ACC_MIN_EXT = {ACC_MIN[ACC_W-1], ACC_MIN};

    logic acc_overflow;
    assign acc_overflow = (acc_sum_ext > ACC_MAX_EXT) || (acc_sum_ext < ACC_MIN_EXT);
    assign overflow     = acc_overflow | resize_overflow;
    assign acc_next = (USE_SATURATE && overflow) ? (acc_sum_ext < 0 ? ACC_MIN : ACC_MAX)
                                                   : acc_sum_ext[ACC_W-1:0];
endmodule
`default_nettype wire
