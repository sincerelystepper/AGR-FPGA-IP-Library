`default_nettype none

module tb_agr_fxp_addsub;

    localparam int IN_W = 16;
    localparam int OUT_W = 16;

    logic                     add_sub;
    logic signed [IN_W-1:0]  a;
    logic signed [IN_W-1:0]  b;
    logic signed [OUT_W-1:0] result;
    logic                     overflow;

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    logic signed [IN_W:0] b_eff_ref;
    logic signed [IN_W:0] ref_sum;
    logic ref_ov;
    logic signed [OUT_W-1:0] ref_res;

    agr_fxp_addsub #(.IN_W(IN_W), .OUT_W(OUT_W), .SATURATE(1)) dut (
        .add_sub, .a, .b, .result, .overflow
    );

    task automatic run_test(
        input string test_name,
        input logic add_sub_val,
        input logic signed [IN_W-1:0] a_val,
        input logic signed [IN_W-1:0] b_val
    );
        test_count++;
        add_sub = add_sub_val;
        a = a_val;
        b = b_val;
        #1;

        // Reference computation with correct saturation
        b_eff_ref = add_sub ? -b : b;
        ref_sum = a + b_eff_ref;

        // Overflow: same sign operands, different sign result
        ref_ov = (a[IN_W-1] == b_eff_ref[IN_W-1]) && (ref_sum[IN_W] != a[IN_W-1]);

        // Saturation
        if (ref_ov && ref_sum[IN_W])
            ref_res = {1'b1, {(OUT_W-1){1'b0}}};  // MIN (negative overflow)
        else if (ref_ov && !ref_sum[IN_W])
            ref_res = {1'b0, {(OUT_W-1){1'b1}}};  // MAX (positive overflow)
        else
            ref_res = ref_sum[OUT_W-1:0];

        if (result === ref_res && overflow === ref_ov) begin
            $display("[PASS] Test %0d: %s", test_count, test_name);
            $display("       a=%0d, b=%0d, add_sub=%0d", a_val, b_val, add_sub);
            $display("       result=%0d overflow=%0d", result, overflow);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s", test_count, test_name);
            $display("       a=%0d, b=%0d, add_sub=%0d", a_val, b_val, add_sub);
            $display("       Expected: result=%0d overflow=%0d", ref_res, ref_ov);
            $display("       Got:      result=%0d overflow=%0d", result, overflow);
            fail_count++;
        end
    endtask

    initial begin
        $display("================================================");
        $display("agr_fxp_addsub Verification Suite");
        $display("Parameters: IN_W=%0d, OUT_W=%0d", IN_W, OUT_W);
        $display("================================================");

        // Basic arithmetic
        run_test("Simple Add 5+3",        1'b0, 5, 3);
        run_test("Simple Sub 5-3",        1'b1, 5, 3);
        run_test("Neg Add -5+3",          1'b0, -5, 3);
        run_test("Neg Sub -5-(-3)",       1'b1, -5, -3);
        run_test("Zero Add 5+0",          1'b0, 5, 0);
        run_test("Zero Sub 5-0",          1'b1, 5, 0);

        // Overflow: 32767+32767 = 65534 -> saturate to 32767
        run_test("MAX+MAX saturate",      1'b0, 16'h7FFF, 16'h7FFF);
        // Overflow: -32768+(-32768) = -65536 -> saturate to -32768
        run_test("MIN+MIN saturate",      1'b0, 16'h8000, 16'h8000);
        // Overflow: 32767-(-32768) = 65535 -> saturate to 32767
        run_test("MAX-MIN saturate",      1'b1, 16'h7FFF, 16'h8000);
        // Overflow: -32768-32767 = -65535 -> saturate to -32768
        run_test("MIN-MAX saturate",      1'b1, 16'h8000, 16'h7FFF);

        // Edge cases
        run_test("Near MAX+1",            1'b0, 16'h7FFE, 1);
        run_test("Near MAX+2 saturate",   1'b0, 16'h7FFE, 2);
        run_test("Identity a+(-a)=0",     1'b0, 16'd1234, -16'd1234);
        run_test("Identity a-0=a",        1'b1, 16'd1234, 0);

        // Random tests
        $display("\n=== Running Random Tests ===");
        for (int i = 0; i < 100; i++) begin
            automatic logic signed [IN_W-1:0] rand_a = $random() & 16'hFFFF;
            automatic logic signed [IN_W-1:0] rand_b = $random() & 16'hFFFF;
            automatic logic rand_op = $random() & 1'b1;
            run_test($sformatf("Random test %0d", i), rand_op, rand_a, rand_b);
        end

        $display("\n================================================");
        $display("Verification Summary:");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("================================================");

        if (fail_count > 0) begin
            $display("VERIFICATION FAILED");
            $stop;
        end else begin
            $display("ALL TESTS PASSED");
        end
        $finish;
    end

    initial begin
        $dumpfile("tb_agr_fxp_addsub.vcd");
        $dumpvars(0, tb_agr_fxp_addsub);
    end

endmodule

`default_nettype wire
