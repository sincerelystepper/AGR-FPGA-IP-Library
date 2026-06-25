`default_nettype none
`timescale 1ns/1ps

module tb_agr_complex_mult;

    localparam int IN_W = 8;
    localparam int OUT_W = 16;

    logic signed [IN_W-1:0] a_real, a_imag, b_real, b_imag;
    logic signed [OUT_W-1:0] out_real, out_imag;
    logic overflow;

    int errors = 0;
    int checks = 0;

    agr_complex_mult #(.IN_W(IN_W), .OUT_W(OUT_W), .USE_ROUNDING(1), .USE_SATURATE(0))
        dut (.a_real, .a_imag, .b_real, .b_imag, .out_real, .out_imag, .overflow);

    task automatic test;
        input longint ar, ai, br, bi, exp_r, exp_i;
        input bit exp_ovf;
        begin
            a_real = ar[IN_W-1:0]; a_imag = ai[IN_W-1:0];
            b_real = br[IN_W-1:0]; b_imag = bi[IN_W-1:0];
            #1;
            checks = checks + 3;
            if (out_real !== exp_r || out_imag !== exp_i || overflow !== exp_ovf) begin
                errors = errors + 1;
                $display("FAIL: (%0d+j%0d)*(%0d+j%0d) exp=(%0d+j%0d,ovf=%0b) got=(%0d+j%0d,ovf=%0b)",
                       ar, ai, br, bi, exp_r, exp_i, exp_ovf, out_real, out_imag, overflow);
            end
        end
    endtask

    integer i;
    longint ar, ai, br, bi, ac, bd, ad, bc, full_r, full_i;

    initial begin
        $display("=== agr_complex_mult testbench ===");
        $display("IN_W=%0d, OUT_W=%0d", IN_W, OUT_W);

        // Directed tests
        test(1,0,1,0, 1,0,0);
        test(1,1,1,1, 0,2,0);
        test(2,3,4,5, -7,22,0);
        test(-2,3,4,5, -23,2,0);
        test(127,0,127,0, 16129,0,0);
        test(0,0,5,5, 0,0,0);
        test(5,5,0,0, 0,0,0);
        test(0,0,0,0, 0,0,0);
        test(-2,-3,-4,-5, -7,22,0);
        test(127,127,127,127, 0,32258,0);
        test(-128,0,-128,0, 16384,0,0);

        // Random regression (3000 cases)
        $display("--- Random (3000 cases) ---");
        for (i = 0; i < 3000; i = i + 1) begin
            ar = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            ai = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            br = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            bi = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            ac = ar * br; bd = ai * bi; ad = ar * bi; bc = ai * br;
            full_r = ac - bd; full_i = ad + bc;
            test(ar, ai, br, bi, full_r, full_i, 0);
        end

        $display("");
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** TEST FAILED ***");
        $finish;
    end

endmodule
`default_nettype wire
