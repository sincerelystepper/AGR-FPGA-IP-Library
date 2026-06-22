`default_nettype none

module agr_fxp_addsub #(
    parameter int IN_W      = 16,
    parameter int OUT_W     = 16,
    parameter bit SATURATE  = 1
)(
    input  wire                     add_sub,
    input  wire signed [IN_W-1:0]   a,
    input  wire signed [IN_W-1:0]   b,

    output logic signed [OUT_W-1:0] result,
    output logic                    overflow
);
    localparam int EXT_W = IN_W + 1;

    logic signed [EXT_W-1:0] a_ext;
    logic signed [EXT_W-1:0] b_ext;
    logic signed [EXT_W-1:0] b_eff;
    logic signed [EXT_W-1:0] sum_ext;

    // Sign-extend inputs to EXT_W bits
    assign a_ext = { {1{a[IN_W-1]}}, a };
    assign b_ext = { {1{b[IN_W-1]}}, b };

    // Add/Sub selection
    assign b_eff = add_sub ? -b_ext : b_ext;
    assign sum_ext = a_ext + b_eff;

    // Overflow detection: compare signs of original operands vs result
    // For addition: overflow if a and b have same sign but result has different sign
    // For subtraction: overflow if a and b have different signs but result has same sign as b
    assign sign_sum    = sum_ext[EXT_W-1];

    logic sign_sum;
    // Correct overflow: operands have same sign, result has different sign
    // This works for both add and sub because b_eff already incorporates the operation
    assign overflow = (a_ext[EXT_W-1] == b_eff[EXT_W-1]) && (sign_sum != a_ext[EXT_W-1]);

    // Saturation limits
    localparam signed [OUT_W-1:0] MAX_VAL = {1'b0, {(OUT_W-1){1'b1}}};
    localparam signed [OUT_W-1:0] MIN_VAL = {1'b1, {(OUT_W-1){1'b0}}};

    // Output: saturate on overflow, otherwise truncate
    assign result = (SATURATE && overflow) ? (sign_sum ? MIN_VAL : MAX_VAL)
                                           : sum_ext[OUT_W-1:0];

endmodule

`default_nettype wire
