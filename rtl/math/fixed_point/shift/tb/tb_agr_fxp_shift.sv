// =============================================================================
// tb_agr_fxp_shift : comprehensive self-checking testbench
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_agr_fxp_shift;

    localparam int DATA_W = 8;
    localparam int SHIFT_W = 4;

    logic signed [DATA_W-1:0] in_val;
    logic [SHIFT_W-1:0] shift_amt;
    logic shift_dir;
    logic signed [DATA_W-1:0] out_wrap, out_sat;
    logic ovf_wrap, pl_wrap, ovf_sat, pl_sat;

    int errors = 0;
    int checks = 0;

    // Wrap instance
    agr_fxp_shift #(.DATA_W(DATA_W), .SHIFT_W(SHIFT_W), .USE_SATURATE(0))
        dut_wrap (.in_val, .shift_amt, .shift_dir, .out_val(out_wrap), .overflow(ovf_wrap), .precision_loss(pl_wrap));

    // Saturate instance
    agr_fxp_shift #(.DATA_W(DATA_W), .SHIFT_W(SHIFT_W), .USE_SATURATE(1))
        dut_sat  (.in_val, .shift_amt, .shift_dir, .out_val(out_sat), .overflow(ovf_sat), .precision_loss(pl_sat));

    // -------------------------------------------------------------------
    // Golden model (64-bit)
    // -------------------------------------------------------------------
    task automatic golden_shift(
        input longint in64,
        input int amt,
        input bit dir,
        input bit sat,
        output longint exp_out,
        output bit exp_ovf,
        output bit exp_pl
    );
        longint shifted, max_val, min_val;
        longint loss_mask;

        max_val = (1 << (DATA_W - 1)) - 1;
        min_val = -(1 << (DATA_W - 1));

        if (dir) begin
            // Left shift
            shifted = in64 << amt;
            exp_pl = 0;
            // Overflow: check if shifted value exceeds DATA_W signed range
            exp_ovf = (shifted > max_val) || (shifted < min_val);
            if (sat && exp_ovf)
                exp_out = (in64 < 0) ? min_val : max_val;
            else
                exp_out = shifted & ((1 << DATA_W) - 1);
            // Sign-extend if needed
            if (exp_out >= (1 << (DATA_W - 1)))
                exp_out = exp_out - (1 << DATA_W);
        end else begin
            // Right shift: arithmetic
            shifted = in64 >>> amt;
            exp_ovf = 0;
            loss_mask = (1 << amt) - 1;
            exp_pl = ((in64 & loss_mask) != 0);
            exp_out = shifted & ((1 << DATA_W) - 1);
            if (exp_out >= (1 << (DATA_W - 1)))
                exp_out = exp_out - (1 << DATA_W);
        end
    endtask

    // -------------------------------------------------------------------
    // Check
    // -------------------------------------------------------------------
    task automatic check;
        input string label;
        input longint in64;
        input int amt;
        input bit dir;
        longint exp_wrap, exp_sat;
        bit exp_ovf, exp_pl;
        begin
            golden_shift(in64, amt, dir, 0, exp_wrap, exp_ovf, exp_pl);
            checks = checks + 1;
            if (out_wrap !== exp_wrap || ovf_wrap !== exp_ovf || pl_wrap !== exp_pl) begin
                errors = errors + 1;
                $error("[%s] WRAP in=%0d amt=%0d dir=%0d | exp out=%0d ovf=%0b pl=%0b | got out=%0d ovf=%0b pl=%0b",
                       label, in64, amt, dir, exp_wrap, exp_ovf, exp_pl, out_wrap, ovf_wrap, pl_wrap);
            end
            golden_shift(in64, amt, dir, 1, exp_sat, exp_ovf, exp_pl);
            checks = checks + 1;
            if (out_sat !== exp_sat || ovf_sat !== exp_ovf || pl_sat !== exp_pl) begin
                errors = errors + 1;
                $error("[%s] SAT  in=%0d amt=%0d dir=%0d | exp out=%0d ovf=%0b pl=%0b | got out=%0d ovf=%0b pl=%0b",
                       label, in64, amt, dir, exp_sat, exp_ovf, exp_pl, out_sat, ovf_sat, pl_sat);
            end
        end
    endtask

    task automatic drive;
        input longint in64;
        input int amt;
        input bit dir;
        begin
            in_val = in64[DATA_W-1:0];
            shift_amt = amt[SHIFT_W-1:0];
            shift_dir = dir;
            #1;
            check("", in64, amt, dir);
        end
    endtask

    // ===================================================================
    // TEST 1: Shift by zero (passthrough)
    // ===================================================================
    task automatic test_shift_zero();
        $display("--- Test 1: Shift by zero ---");
        drive(0, 0, 0); drive(0, 0, 1);
        drive(1, 0, 0); drive(1, 0, 1);
        drive(-1, 0, 0); drive(-1, 0, 1);
        drive(127, 0, 0); drive(127, 0, 1);
        drive(-128, 0, 0); drive(-128, 0, 1);
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 2: Left shift - no overflow
    // ===================================================================
    task automatic test_left_no_overflow();
        $display("--- Test 2: Left shift, no overflow ---");
        drive(1, 1, 1);    // 1<<1=2
        drive(1, 4, 1);    // 1<<4=16
        drive(3, 2, 1);    // 3<<2=12
        drive(-1, 3, 1);   // -1<<3=-8 (sign-extended correctly)
        drive(-4, 2, 1);   // -4<<2=-16
        drive(15, 3, 1);   // 15<<3=120 (just fits)
        drive(-16, 3, 1);  // -16<<3=-128 (just fits - MIN)
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 3: Left shift - overflow
    // ===================================================================
    task automatic test_left_overflow();
        $display("--- Test 3: Left shift, overflow ---");
        drive(16, 3, 1);    // 16<<3=128 > 127 -> overflow
        drive(-17, 3, 1);   // -17<<3=-136 < -128 -> overflow
        drive(64, 2, 1);    // 64<<2=256 > 127 -> overflow, wrap to 0
        drive(-64, 2, 1);   // -64<<2=-256 < -128 -> overflow, wrap to 0
        drive(127, 1, 1);   // 127<<1=254 > 127 -> overflow
        drive(-128, 1, 1);  // -128<<1=-256 < -128 -> overflow
        drive(1, 7, 1);     // 1<<7=128 -> overflow (just past MAX)
        drive(-1, 7, 1);    // -1<<7=-128 -> no overflow (exact MIN)
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 4: Right shift - arithmetic
    // ===================================================================
    task automatic test_right_arithmetic();
        $display("--- Test 4: Right shift, arithmetic ---");
        drive(16, 1, 0);    // 16>>1=8, pl=0
        drive(17, 1, 0);    // 17>>1=8, pl=1 (LSB 1 lost)
        drive(-16, 1, 0);   // -16>>1=-8, pl=0
        drive(-17, 1, 0);   // -17>>1=-9, pl=1
        drive(127, 4, 0);   // 127>>4=7, pl=1
        drive(-128, 4, 0);  // -128>>4=-8, pl=0
        drive(-1, 4, 0);    // -1>>4=-1 (sign-extended), pl=1
        drive(0, 5, 0);     // 0>>5=0, pl=0
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 5: Shift >= DATA_W (extreme)
    // ===================================================================
    task automatic test_extreme_shifts();
        $display("--- Test 5: Extreme shifts (>= DATA_W) ---");
        // Left shift by DATA_W: everything shifted out
        drive(1, 8, 1);      // all bits shifted out -> overflow
        drive(-1, 8, 1);     // -1, all 1s -> overflow
        drive(0, 8, 1);      // 0 -> ok
        // Left shift beyond DATA_W (clamped)
        drive(1, 15, 1);     // shift_amt=15, clamped to 8 -> overflow
        // Right shift by DATA_W: all bits shifted out, result is sign
        drive(127, 8, 0);    // 127>>8=0, pl=1 (all bits lost)
        drive(-128, 8, 0);   // -128>>8=-1 (sign-extended to all 1s), pl=0
        drive(-1, 8, 0);     // -1>>8=-1, pl=1
        drive(85, 15, 0);    // clamped to 8, 85>>8=0, pl=1
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 6: Saturation behavior
    // ===================================================================
    task automatic test_saturation();
        $display("--- Test 6: Saturation ---");
        drive(64, 2, 1);     // 256 > 127 -> sat to 127
        drive(-64, 2, 1);    // -256 < -128 -> sat to -128
        drive(1, 7, 1);      // 128 -> sat to 127
        drive(-2, 7, 1);     // -256 -> sat to -128
        drive(127, 1, 1);    // 254 -> sat to 127
        drive(-128, 1, 1);   // -256 -> sat to -128
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 7: Precision loss (right shift)
    // ===================================================================
    task automatic test_precision_loss();
        $display("--- Test 7: Precision loss ---");
        drive(3, 1, 0);      // 3>>1=1, pl=1 (bit 0 lost)
        drive(2, 1, 0);      // 2>>1=1, pl=0
        drive(5, 2, 0);      // 5>>2=1, pl=1 (bits 0,1 lost)
        drive(4, 2, 0);      // 4>>2=1, pl=0
        drive(-3, 1, 0);     // -3>>1=-2, pl=1
        drive(-4, 1, 0);     // -4>>1=-2, pl=0
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // TEST 8: Random regression
    // ===================================================================
    task automatic test_random();
        longint v;
        int amt;
        bit dir;
        integer i;
        $display("--- Test 8: Random (3000 cases) ---");
        for (i = 0; i < 3000; i = i + 1) begin
            v   = (($urandom() & 32'h7FFFFFFF) % 256) - 128;
            amt = ($urandom() & 32'h7FFFFFFF) % 16;
            dir = ($urandom() & 1);
            drive(v, amt, dir);
        end
        $display("  done (%0d checks)", checks);
    endtask

    // ===================================================================
    // Main
    // ===================================================================
    initial begin
        $display("=== agr_fxp_shift comprehensive testbench ===");
        $display("DATA_W=%0d, SHIFT_W=%0d", DATA_W, SHIFT_W);

        test_shift_zero();
        test_left_no_overflow();
        test_left_overflow();
        test_right_arithmetic();
        test_extreme_shifts();
        test_saturation();
        test_precision_loss();
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
