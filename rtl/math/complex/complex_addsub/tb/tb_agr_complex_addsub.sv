`default_nettype none
`timescale 1ns/1ps

module tb_agr_complex_addsub;

    localparam int IN_W = 8;
    localparam int OUT_W = 16;

    logic signed [IN_W-1:0] a_real, a_imag, b_real, b_imag;
    logic sub;
    logic signed [OUT_W-1:0] out_real, out_imag;
    logic overflow;

    int errors = 0;
    int checks = 0;

    agr_complex_addsub #(.IN_W(IN_W), .OUT_W(OUT_W), .USE_SATURATE(0))
        dut (.a_real, .a_imag, .b_real, .b_imag, .sub, .out_real, .out_imag, .overflow);

    task automatic test;
        input longint ar, ai, br, bi;
        input bit op_sub;
        input longint exp_r, exp_i;
        input bit exp_ovf;
        longint full_r, full_i;
        begin
            a_real = ar[IN_W-1:0]; a_imag = ai[IN_W-1:0];
            b_real = br[IN_W-1:0]; b_imag = bi[IN_W-1:0];
            sub = op_sub;
            #1;

            // Golden model: 64-bit math
            if (op_sub) begin
                full_r = ar - br;
                full_i = ai - bi;
            end else begin
                full_r = ar + br;
                full_i = ai + bi;
            end

            checks = checks + 3;
            if (out_real !== full_r || out_imag !== full_i || overflow !== exp_ovf) begin
                errors = errors + 1;
                $display("FAIL: (%0d+j%0d) %s (%0d+j%0d) exp=(%0d+j%0d,ovf=%0b) got=(%0d+j%0d,ovf=%0b)",
                       ar, ai, op_sub ? "-" : "+", br, bi, full_r, full_i, exp_ovf, out_real, out_imag, overflow);
            end
        end
    endtask

    integer i;
    longint ar, ai, br, bi;

    initial begin
        $display("=== agr_complex_addsub testbench ===");
        $display("IN_W=%0d, OUT_W=%0d", IN_W, OUT_W);

        $display("--- Simple ADD ---");
        test(1,0,1,0, 0, 2,0,0);
        test(1,1,1,1, 0, 2,2,0);
        test(5,3,2,7, 0, 7,10,0);

        $display("--- Simple SUB ---");
        test(5,3,2,7, 1, 3,-4,0);
        test(1,1,1,1, 1, 0,0,0);

        $display("--- Zero ---");
        test(0,0,5,5, 0, 5,5,0);
        test(5,5,0,0, 0, 5,5,0);
        test(0,0,0,0, 0, 0,0,0);
        test(0,0,0,0, 1, 0,0,0);

        $display("--- Identity (A-A=0) ---");
        test(5,3,5,3, 1, 0,0,0);
        test(-2,7,-2,7, 1, 0,0,0);

        $display("--- Sign combinations ---");
        test(2,3,4,5, 0, 6,8,0);
        test(-2,3,4,5, 0, 2,8,0);
        test(2,-3,4,5, 0, 6,2,0);
        test(-2,-3,-4,-5, 0, -6,-8,0);
        test(-2,-3,4,5, 1, -6,-8,0);

        $display("--- MAX/MIN ---");
        test(127,0,127,0, 0, 254,0,0);
        test(-128,0,-128,0, 0, -256,0,0);
        test(127,0,-128,0, 1, 255,0,0);
        test(127,127,127,127, 0, 254,254,0);
        test(127,127,-128,-128, 1, 255,255,0);

        $display("--- Symmetry ---");
        test(2,3,4,5, 0, 6,8,0);
        test(4,5,2,3, 0, 6,8,0);

        $display("--- Random (3000 cases) ---");
        for (i = 0; i < 3000; i = i + 1) begin
            ar = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            ai = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            br = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            bi = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            test(ar, ai, br, bi, 0, ar+br, ai+bi, 0);
            test(ar, ai, br, bi, 1, ar-br, ai-bi, 0);
        end

        $display("");
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** TEST FAILED ***");
        $finish;
    end

endmodule
`default_nettype wire
