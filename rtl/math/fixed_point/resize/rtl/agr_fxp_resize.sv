`default_nettype none

module agr_fxp_resize #(
    parameter int IN_W  = 16,
    parameter int OUT_W = 16,
    parameter bit MODE  = 1'b0,
    parameter bit ALIGN = 1'b1
) (
    input  logic signed [IN_W-1:0]  in_val,
    output logic signed [OUT_W-1:0] out_val,
    output logic                    overflow,
    output logic                    precision_loss
);

    initial begin
        if (IN_W < 1)  $fatal(1, "IN_W must be >= 1");
        if (OUT_W < 1) $fatal(1, "OUT_W must be >= 1");
    end

    logic in_sign;
    assign in_sign = in_val[IN_W-1];

    logic signed [OUT_W-1:0] candidate;

    generate
        if (OUT_W > IN_W) begin : gen_expand
            localparam int EXT_W = OUT_W - IN_W;
            assign candidate      = {{EXT_W{in_val[IN_W-1]}}, in_val};
            assign overflow       = 1'b0;
            assign precision_loss = 1'b0;
        end else if (OUT_W == IN_W) begin : gen_passthrough
            assign candidate      = in_val;
            assign overflow       = 1'b0;
            assign precision_loss = 1'b0;
        end else if (ALIGN) begin : gen_reduce_msb
            localparam int DROP_W = IN_W - OUT_W;
            logic [DROP_W-1:0] dropped_lsbs;
            assign dropped_lsbs   = in_val[DROP_W-1:0];
            assign candidate      = in_val[IN_W-1 -: OUT_W];
            assign overflow       = 1'b0;
            assign precision_loss = |dropped_lsbs;
        end else begin : gen_reduce_lsb
            localparam int DROP_W = IN_W - OUT_W;
            logic [DROP_W-1:0] dropped_msbs;
            logic kept_sign;
            assign candidate       = in_val[OUT_W-1:0];
            assign kept_sign       = in_val[OUT_W-1];
            assign dropped_msbs    = in_val[IN_W-1:OUT_W];
            assign overflow        = (dropped_msbs != {DROP_W{kept_sign}});
            assign precision_loss  = (dropped_msbs != {DROP_W{kept_sign}});
        end
    endgenerate

    localparam logic signed [OUT_W-1:0] SAT_MAX = {1'b0, {(OUT_W-1){1'b1}}};
    localparam logic signed [OUT_W-1:0] SAT_MIN = {1'b1, {(OUT_W-1){1'b0}}};

    assign out_val = (MODE && overflow) ? (in_sign ? SAT_MIN : SAT_MAX) : candidate;

endmodule

`default_nettype wire
