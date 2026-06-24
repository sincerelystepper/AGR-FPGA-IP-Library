`default_nettype none
`timescale 1ns/1ps

module tb_agr_fxp_accumulator;

    localparam int ACC_W = 8;

    logic clk, rst, enable, clear, load;
    logic signed [ACC_W-1:0] load_val, in_val;
    logic signed [ACC_W-1:0] acc;
    logic overflow;

    int errors = 0;
    int checks = 0;

    // Reference model
    logic signed [ACC_W-1:0] ref_acc;
    bit ref_overflow;

    agr_fxp_accumulator #(.ACC_W(ACC_W), .USE_SATURATE(0))
        dut_wrap (.clk, .rst, .enable, .clear, .load, .load_val, .in_val, .acc(acc), .overflow);

    // Saturating instance
    logic signed [ACC_W-1:0] acc_sat;
    logic overflow_sat;
    logic signed [ACC_W-1:0] ref_acc_sat;

    agr_fxp_accumulator #(.ACC_W(ACC_W), .USE_SATURATE(1))
        dut_sat (.clk, .rst, .enable, .clear, .load, .load_val, .in_val, .acc(acc_sat), .overflow(overflow_sat));

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------
    task automatic tick();
        @(negedge clk);
    endtask

    task automatic reset_all();
        rst = 1; enable = 0; clear = 0; load = 0; in_val = 0; load_val = 0;
        tick();
        rst = 0;
        ref_acc = 0; ref_overflow = 0;
        ref_acc_sat = 0;
        tick();
    endtask

    task automatic do_clear();
        clear = 1; enable = 0; load = 0;
        tick();
        clear = 0;
        ref_acc = 0; ref_overflow = 0;
        ref_acc_sat = 0;
    endtask

    task automatic do_load(input logic signed [ACC_W-1:0] val);
        load = 1; load_val = val; enable = 0; clear = 0;
        tick();
        load = 0;
        ref_acc = val; ref_overflow = 0;
        ref_acc_sat = val;
    endtask

    task automatic do_accumulate(input logic signed [ACC_W-1:0] val);
        longint sum, sum_sat;
        enable = 1; in_val = val; clear = 0; load = 0;
        tick();
        enable = 0;

        // Wrap reference
        sum = longint'(ref_acc) + longint'(val);
        if (sum > 127)       begin ref_acc = sum - 256; ref_overflow = 1; end
        else if (sum < -128) begin ref_acc = sum + 256; ref_overflow = 1; end
        else                 begin ref_acc = sum[ACC_W-1:0]; ref_overflow = 0; end

        // Saturate reference
        sum_sat = longint'(ref_acc_sat) + longint'(val);
        if (sum_sat > 127)       ref_acc_sat = 127;
        else if (sum_sat < -128) ref_acc_sat = -128;
        else                     ref_acc_sat = sum_sat[ACC_W-1:0];
    endtask

    task automatic do_hold();
        enable = 0; clear = 0; load = 0;
        tick();
        ref_overflow = 0;
    endtask

    // -------------------------------------------------------------------
    // Check tasks
    // -------------------------------------------------------------------
    task automatic check_acc(string label);
        checks = checks + 1;
        if (acc !== ref_acc) begin
            errors = errors + 1;
            $error("[%s] wrap acc mismatch: exp=%0d got=%0d", label, ref_acc, acc);
        end
    endtask

    task automatic check_acc_sat(string label);
        checks = checks + 1;
        if (acc_sat !== ref_acc_sat) begin
            errors = errors + 1;
            $error("[%s] sat acc mismatch: exp=%0d got=%0d", label, ref_acc_sat, acc_sat);
        end
    endtask

    task automatic check_overflow(string label);
        checks = checks + 1;
        if (overflow !== ref_overflow) begin
            errors = errors + 1;
            $error("[%s] wrap overflow mismatch: exp=%0b got=%0b", label, ref_overflow, overflow);
        end
    endtask

    task automatic check_both(string label);
        check_acc(label);
        check_acc_sat(label);
        check_overflow(label);
    endtask

    // ===================================================================
    // TEST 1: Reset behavior
    // ===================================================================
    task automatic test_reset_behavior();
        $display("--- Test 1: Reset behavior ---");
        // Reset clears state
        do_accumulate(50);
        do_accumulate(30);
        check_both("after accumulate before reset");
        reset_all();
        check_both("after reset - should be 0");
        // Reset during accumulation
        do_accumulate(10);
        rst = 1; enable = 1; in_val = 99;
        tick();
        rst = 0; enable = 0;
        ref_acc = 0; ref_acc_sat = 0; ref_overflow = 0;
        check_both("reset beats enable");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 2: Clear behavior
    // ===================================================================
    task automatic test_clear_behavior();
        $display("--- Test 2: Clear behavior ---");
        do_accumulate(50);
        do_clear();
        check_both("after clear - should be 0");
        // Clear from negative
        do_accumulate(-100);
        do_clear();
        check_both("clear from negative");
        // Clear beats enable
        do_accumulate(10);
        clear = 1; enable = 1; in_val = 50;
        tick();
        clear = 0; enable = 0;
        ref_acc = 0; ref_acc_sat = 0; ref_overflow = 0;
        check_both("clear beats enable");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 3: Load behavior
    // ===================================================================
    task automatic test_load_behavior();
        $display("--- Test 3: Load behavior ---");
        do_load(42);
        check_both("load positive");
        do_load(-100);
        check_both("load negative");
        do_load(0);
        check_both("load zero");
        do_load(127);
        check_both("load MAX");
        do_load(-128);
        check_both("load MIN");
        // Load beats enable
        do_accumulate(10);
        load = 1; load_val = 77; enable = 1; in_val = 99;
        tick();
        load = 0; enable = 0;
        ref_acc = 77; ref_acc_sat = 77; ref_overflow = 0;
        check_both("load beats enable");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 4: Hold behavior
    // ===================================================================
    task automatic test_hold_behavior();
        $display("--- Test 4: Hold behavior ---");
        do_load(55);
        do_hold();
        check_both("hold after load");
        do_hold();
        check_both("hold twice");
        do_accumulate(10);
        do_hold();
        check_both("hold after accumulate");
        do_hold();
        check_both("hold twice more");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 5: Control priority (exhaustive pairs)
    // ===================================================================
    task automatic test_priority_exhaustive();
        $display("--- Test 5: Priority exhaustive ---");
        // reset > clear
        rst=1; clear=1; tick(); rst=0; clear=0;
        ref_acc=0; ref_acc_sat=0; ref_overflow=0;
        check_both("reset > clear");
        // reset > load
        rst=1; load=1; load_val=55; tick(); rst=0; load=0;
        check_both("reset > load");
        // reset > enable
        rst=1; enable=1; in_val=99; tick(); rst=0; enable=0;
        check_both("reset > enable");
        // clear > load
        do_accumulate(30);
        clear=1; load=1; load_val=88; tick(); clear=0; load=0;
        ref_acc=0; ref_acc_sat=0; ref_overflow=0;
        check_both("clear > load");
        // clear > enable
        clear=1; enable=1; in_val=77; tick(); clear=0; enable=0;
        check_both("clear > enable");
        // load > enable
        load=1; load_val=33; enable=1; in_val=99; tick(); load=0; enable=0;
        ref_acc=33; ref_acc_sat=33; ref_overflow=0;
        check_both("load > enable");
        // enable > hold (implicit - tested in hold test)
        // Simultaneous all except reset
        clear=1; load=1; load_val=11; enable=1; in_val=22;
        tick(); clear=0; load=0; enable=0;
        ref_acc=0; ref_acc_sat=0; ref_overflow=0;
        check_both("clear beats load+enable");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 6: Transition cases
    // ===================================================================
    task automatic test_transitions();
        $display("--- Test 6: Transition cases ---");
        // accumulate -> clear -> accumulate
        do_accumulate(40); do_clear(); do_accumulate(15);
        check_both("acc->clear->acc");
        // load -> accumulate -> load -> accumulate
        do_load(10); do_accumulate(5); do_load(-30); do_accumulate(7);
        check_both("load->acc->load->acc");
        // accumulate -> overflow -> clear -> accumulate
        do_accumulate(100); do_accumulate(50);
        check_overflow("overflow detected");
        do_clear(); do_accumulate(20);
        check_both("after overflow+clear");
        // rapid mode switching
        for (int i = 0; i < 20; i++) begin
            tick();
            if (i % 4 == 0)      do_accumulate(1);
            else if (i % 4 == 1) do_hold();
            else if (i % 4 == 2) do_clear();
            else                 do_load(i);
        end
        check_both("rapid switching");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 7: Overflow wrap mode (exhaustive boundaries)
    // ===================================================================
    task automatic test_overflow_wrap();
        longint sum;
        $display("--- Test 7: Overflow wrap mode ---");
        reset_all();
        // Just below positive overflow: 126+1=127 (no overflow)
        do_load(126); do_accumulate(1);
        sum = 127;
        ref_acc = sum[ACC_W-1:0]; ref_overflow = 0; ref_acc_sat = 127;
        check_both("126+1=127 no overflow");
        // At positive overflow: 127+1=128 -> -128 (overflow)
        do_accumulate(1);
        sum = 128;
        ref_acc = -128; ref_overflow = 1; ref_acc_sat = 127;
        check_both("127+1=128 overflow->-128 wrap, 127 sat");
        // Far positive overflow: 127+100=227 -> -29
        do_load(127); do_accumulate(100);
        sum = 227;
        ref_acc = sum - 256; ref_overflow = 1; ref_acc_sat = 127;
        check_both("127+100 overflow");
        // Just above negative overflow: -128+1=-127 (no overflow)
        do_load(-128); do_accumulate(1);
        sum = -127;
        ref_acc = -127; ref_overflow = 0; ref_acc_sat = -127;
        check_both("-128+1=-127 no overflow");
        // At negative overflow: -128-1=-129 -> 127 (overflow)
        do_load(-128); do_accumulate(-1);
        sum = -129;
        ref_acc = 127; ref_overflow = 1; ref_acc_sat = -128;
        check_both("-128-1=-129 overflow->127 wrap, -128 sat");
        // Far negative overflow: -128-100=-228 -> 28
        do_load(-128); do_accumulate(-100);
        sum = -228;
        ref_acc = sum + 256; ref_overflow = 1; ref_acc_sat = -128;
        check_both("-128-100 overflow");
        // Min+Max: -128+127=-1 (no overflow)
        do_load(-128); do_accumulate(127);
        sum = -1;
        ref_acc = -1; ref_overflow = 0; ref_acc_sat = -1;
        check_both("-128+127=-1 no overflow");
        // Max+Min: 127-128=-1 (no overflow)
        do_load(127); do_accumulate(-128);
        sum = -1;
        ref_acc = -1; ref_overflow = 0; ref_acc_sat = -1;
        check_both("127-128=-1 no overflow");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 8: Long sequences (FIR-like)
    // ===================================================================
    task automatic test_long_sequences();
        $display("--- Test 8: Long sequences ---");
        reset_all();
        // Sequence of 100 small positive adds
        for (int i = 0; i < 100; i++) do_accumulate(1);
        check_both("100x1=100");
        // Sequence of 100 small negative adds
        for (int i = 0; i < 200; i++) do_accumulate(-1);
        check_both("100-200=-100");
        // Alternating signs (sawtooth)
        for (int i = 0; i < 50; i++) begin
            do_accumulate(10);
            do_accumulate(-7);
        end;
        check_both("50x(10-7)=150");
        // Sweep from MIN to MAX
        do_load(-128);
        for (int i = 0; i < 256; i++) do_accumulate(1);
        check_both("-128+256=128 wraps to -128? No: -128+256=128 overflow->-128 wrap");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 9: Overflow flag timing
    // ===================================================================
    task automatic test_overflow_flag();
        integer i;
        $display("--- Test 9: Overflow flag timing ---");
        reset_all();
        do_load(127);
        do_accumulate(1);
        check_overflow("127+1 overflow");
        do_accumulate(1);
        check_overflow("-128+1=-127 no overflow");
        do_load(100);
        do_accumulate(50);
        check_overflow("100+50=150 overflow");
        do_accumulate(50);
        check_overflow("-106+50=-56 no overflow");
        do_accumulate(50);
        check_overflow("-56+50=-6 no overflow");
        do_accumulate(50);
        check_overflow("-6+50=44 no overflow");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 10: Dense random
    // ===================================================================
    task automatic test_random();
        int r, val;
        integer i;
        $display("--- Test 10: Dense random (5000 cycles) ---");
        reset_all();
        for (i = 0; i < 5000; i = i + 1) begin
            tick();
            r = ($urandom() & 32'h7FFFFFFF) % 100;
            val = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            if (r < 2)        reset_all();
            else if (r < 7)   do_clear();
            else if (r < 15)  do_load(val);
            else if (r < 80)  do_accumulate(val);
            else              do_hold();
            if ((i % 250) == 0) check_both($sformatf("random %0d", i));
        end
        check_both("final random check");
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // Main
    // ===================================================================
    initial begin
        $display("=== agr_fxp_accumulator comprehensive testbench ===");
        $display("ACC_W=%0d, testing wrap AND saturate instances", ACC_W);
        reset_all();

        test_reset_behavior();
        test_clear_behavior();
        test_load_behavior();
        test_hold_behavior();
        test_priority_exhaustive();
        test_transitions();
        test_overflow_wrap();
        test_long_sequences();
        test_overflow_flag();
        test_random();

        $display("");
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if (errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $finish;
        end else begin
            $display("*** TEST FAILED: %0d errors ***", errors);
            $stop;
        end
    end

endmodule
`default_nettype wire
