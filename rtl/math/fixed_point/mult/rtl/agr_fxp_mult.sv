`default_nettype none

module agr_fxp_mult #(
    parameter int IN_A_W       = 16,
    parameter int IN_B_W       = 16,
    parameter int OUT_W        = 16,
    parameter bit SIGNED       = 1'b1,
    parameter bit TRUNCATE_MSB = 1'b1
) (
    input  logic signed [IN_A_W-1:0] a,
    input  logic signed [IN_B_W-1:0] b,
    output logic signed [IN_A_W+IN_B_W-1:0] result_full,
    output logic signed [OUT_W-1:0] result,
    output logic overflow
);

    initial begin
        if (IN_A_W < 1) $fatal(1, "IN_A_W must be >= 1");
        if (IN_B_W < 1) $fatal(1, "IN_B_W must be >= 1");
        if (OUT_W < 1)  $fatal(1, "OUT_W must be >= 1");
        if (SIGNED !== 1'b1) $fatal(1, "v1 implements SIGNED=1 only");
    end

    localparam int OUT_FULL_W = IN_A_W + IN_B_W;

    assign result_full = $signed(a) * $signed(b);

    generate
        if (OUT_W == OUT_FULL_W) begin : gen_passthrough
            assign result   = result_full;
            assign overflow = 1'b0;
        end else if (OUT_W > OUT_FULL_W) begin : gen_extend
            localparam int EXT_W = OUT_W - OUT_FULL_W;
            assign result   = {{EXT_W{result_full[OUT_FULL_W-1]}}, result_full};
            assign overflow = 1'b0;
        end else if (TRUNCATE_MSB) begin : gen_trunc_msb
            localparam int DROP_W = OUT_FULL_W - OUT_W;
            logic [DROP_W-1:0] dropped_lsbs;
            assign dropped_lsbs = result_full[DROP_W-1:0];
            assign result        = result_full[OUT_FULL_W-1 -: OUT_W];
            assign overflow      = |dropped_lsbs;
        end else begin : gen_trunc_lsb
            localparam int DROP_W = OUT_FULL_W - OUT_W;
            logic [DROP_W-1:0] dropped_msbs;
            logic kept_sign;
            assign result        = result_full[OUT_W-1:0];
            assign kept_sign     = result_full[OUT_W-1];
            assign dropped_msbs  = result_full[OUT_FULL_W-1:OUT_W];
            assign overflow      = (dropped_msbs != {DROP_W{kept_sign}});
        end
    endgenerate

endmodule

`default_nettype wire
