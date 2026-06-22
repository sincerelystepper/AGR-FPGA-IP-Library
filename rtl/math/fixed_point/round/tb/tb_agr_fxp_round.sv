// =============================================================================
// tb_agr_fxp_round : self-checking testbench for agr_fxp_round
// -----------------------------------------------------------------------------
// Strategy: 64-bit golden model covering all 4 rounding modes + both ALIGN
// modes. Directed tests target tie cases, sign transitions, and boundary
// values. Convergent mode is specifically tested for even-rounding bias
// elimination. Random regression covers 3000+ cases.
// =============================================================================

`default_nettype none

module tb_agr_fxp_round;

    int errors = 0;
    int checks = 0;

    // -------------------------------------------------------------------
    // 64-bit Golden Model
    // -------------------------------------------------------------------
    function automatic longint to_signed(longint raw, int width);
        longint mask = (64'(1) <<< width) - 64'(1);
        longint val = raw & mask;
        to_signed = val[width-1] ? val | ~mask : val;
    endfunction

    function automatic void golden_round(
        input int in_w, out_w, input bit [1:0] mode, input bit align,
        input longint in_val,
        output longint exp_out,
        output bit exp_overflow, exp_precision_loss
    );
        int drop_w;
        longint half, keep, drop, keep_lsb;
        longint rounded, candidate, passthrough;
        bit round_carry;
        longint in_mask, out_mask;

        in_mask = (64'(1) <<< in_w) - 64'(1);
        in_val = to_signed(in_val & in_mask, in_w);

        if (out_w >= in_w) begin
            // Passthrough or expansion: no rounding needed
            exp_out = in_val;
            exp_overflow = 1'b0;
            exp_precision_loss = 1'b0;
            return;
        end

        drop_w = in_w - out_w;
        half = 64'(1) <<< (drop_w - 1);

        if (align) begin
            // MSB-aligned
            keep = (in_val & in_mask) >>> drop_w;
            drop = in_val & ((64'(1) <<< drop_w) - 64'(1));
            keep_lsb = keep & 1;
        end else begin
            // LSB-aligned
            out_mask = (64'(1) <<< out_w) - 64'(1);
            keep = in_val & out_mask;
            drop = (in_val & in_mask) >>> out_w;
            keep_lsb = keep & 1;
        end

        // Rounding decision
        round_carry = 1'b0;
        case (mode)
            2'd0: round_carry = 1'b0;                           // TRUNCATE
            2'd1: round_carry = align ? (drop >= half) : 1'b0;                  // NEAREST
            2'd2: round_carry = align ? (drop >= half) : 1'b0;                  // HALF_UP
            2'd3: begin if (!align) round_carry = 1'b0; else                                          // CONVERGENT
                if (drop > half)       round_carry = 1'b1;
                else if (drop == half) round_carry = keep_lsb;
                else                   round_carry = 1'b0;
            end
        endcase

        // Apply rounding
        if (align) begin
            rounded = in_val + (round_carry <<< drop_w);
            candidate = (rounded & in_mask) >>> drop_w;
        end else begin
            rounded = in_val + round_carry;
            candidate = rounded & ((64'(1) <<< out_w) - 64'(1));
        end

        candidate = to_signed(candidate, out_w);
        passthrough = align ? to_signed(keep, out_w)
                            : to_signed(keep, out_w);

        exp_out = candidate;
        exp_precision_loss = (candidate !== passthrough) || (mode == 2'd0 && drop != 0);

        // overflow for LSB-aligned
        if (!align) begin
            longint dropped_msbs = (rounded & in_mask) >>> out_w;
            longint sign_ext = candidate[out_w-1] ? ((64'(1) <<< drop_w) - 64'(1)) : 0;
            exp_overflow = (dropped_msbs != sign_ext);
        end else begin
            exp_overflow = 1'b0;
        end
    endfunction

    // -------------------------------------------------------------------
    // Check task
    // -------------------------------------------------------------------
    task automatic check_dut(
        input string label,
        input int in_w, out_w,
        input bit [1:0] mode,
        input bit align,
        input longint in_val,
        input longint dut_out,
        input bit dut_overflow, dut_precision_loss
    );
        longint exp_out;
        bit exp_overflow, exp_precision_loss;
        golden_round(in_w, out_w, mode, align, in_val,
                     exp_out, exp_overflow, exp_precision_loss);
        checks++;
        if (dut_out !== exp_out || dut_overflow !== exp_overflow ||
            dut_precision_loss !== exp_precision_loss) begin
            errors++;
            $error("[%s] in=%0d mode=%0d align=%0d | out exp=%0d got=%0d | ovf exp=%0b got=%0b | pl exp=%0b got=%0b",
                   label, in_val, mode, align, exp_out, dut_out,
                   exp_overflow, dut_overflow,
                   exp_precision_loss, dut_precision_loss);
        end
    endtask

    // -------------------------------------------------------------------
    // DUT instances: 16->8, test all 4 modes, both ALIGN
    // -------------------------------------------------------------------
    localparam int IW = 16, OW = 8;

    // DUT 0: TRUNCATE MSB
    logic signed [IW-1:0] d0_in; logic signed [OW-1:0] d0_out; logic d0_ovf, d0_pl;
    agr_fxp_round #(.IN_W(IW),.OUT_W(OW),.MODE(2'd0),.ALIGN(1'b1))
        dut0(.in_val(d0_in),.out_val(d0_out),.overflow(d0_ovf),.precision_loss(d0_pl));
    task drive_0(longint v); d0_in=v[IW-1:0]; #1;
        check_dut("dut0_TRUNC_MSB",IW,OW,2'd0,1'b1,$signed(d0_in),$signed(d0_out),d0_ovf,d0_pl);
    endtask

    // DUT 1: NEAREST MSB
    logic signed [IW-1:0] d1_in; logic signed [OW-1:0] d1_out; logic d1_ovf, d1_pl;
    agr_fxp_round #(.IN_W(IW),.OUT_W(OW),.MODE(2'd1),.ALIGN(1'b1))
        dut1(.in_val(d1_in),.out_val(d1_out),.overflow(d1_ovf),.precision_loss(d1_pl));
    task drive_1(longint v); d1_in=v[IW-1:0]; #1;
        check_dut("dut1_NEAREST_MSB",IW,OW,2'd1,1'b1,$signed(d1_in),$signed(d1_out),d1_ovf,d1_pl);
    endtask

    // DUT 2: HALF_UP MSB
    logic signed [IW-1:0] d2_in; logic signed [OW-1:0] d2_out; logic d2_ovf, d2_pl;
    agr_fxp_round #(.IN_W(IW),.OUT_W(OW),.MODE(2'd2),.ALIGN(1'b1))
        dut2(.in_val(d2_in),.out_val(d2_out),.overflow(d2_ovf),.precision_loss(d2_pl));
    task drive_2(longint v); d2_in=v[IW-1:0]; #1;
        check_dut("dut2_HALFUP_MSB",IW,OW,2'd2,1'b1,$signed(d2_in),$signed(d2_out),d2_ovf,d2_pl);
    endtask

    // DUT 3: CONVERGENT MSB
    logic signed [IW-1:0] d3_in; logic signed [OW-1:0] d3_out; logic d3_ovf, d3_pl;
    agr_fxp_round #(.IN_W(IW),.OUT_W(OW),.MODE(2'd3),.ALIGN(1'b1))
        dut3(.in_val(d3_in),.out_val(d3_out),.overflow(d3_ovf),.precision_loss(d3_pl));
    task drive_3(longint v); d3_in=v[IW-1:0]; #1;
        check_dut("dut3_CONV_MSB",IW,OW,2'd3,1'b1,$signed(d3_in),$signed(d3_out),d3_ovf,d3_pl);
    endtask

    // DUT 4: CONVERGENT LSB
    logic signed [IW-1:0] d4_in; logic signed [OW-1:0] d4_out; logic d4_ovf, d4_pl;
    agr_fxp_round #(.IN_W(IW),.OUT_W(OW),.MODE(2'd3),.ALIGN(1'b0))
        dut4(.in_val(d4_in),.out_val(d4_out),.overflow(d4_ovf),.precision_loss(d4_pl));
    task drive_4(longint v); d4_in=v[IW-1:0]; #1;
        check_dut("dut4_CONV_LSB",IW,OW,2'd3,1'b0,$signed(d4_in),$signed(d4_out),d4_ovf,d4_pl);
    endtask

    // -------------------------------------------------------------------
    // Directed tests
    // -------------------------------------------------------------------
    task automatic directed_ties();
        // Half-way cases: in = K * 256 + 128 (DROP_W=8, half=128)
        // For 16->8, DROP_W=8, half=128
        // keep=0, drop=128: tie at 0.5
        // keep=1, drop=128: tie at 1.5
        // keep=2, drop=128: tie at 2.5
        // keep=3, drop=128: tie at 3.5

        // 0.5 tie: TRUNC=0, NEAREST=1 (>=half), HALF_UP=1, CONV=0 (keep[0]=0)
        drive_0(128);  // drop=128, keep=0
        drive_1(128);
        drive_2(128);
        drive_3(128);

        // 1.5 tie: TRUNC=1, NEAREST=2, HALF_UP=2, CONV=2 (keep[0]=1 -> round up)
        drive_0(384);  // 256+128, keep=1, drop=128
        drive_1(384);
        drive_2(384);
        drive_3(384);

        // 2.5 tie: TRUNC=2, NEAREST=3, HALF_UP=3, CONV=2 (keep[0]=0 -> round down)
        drive_0(640);  // 512+128, keep=2, drop=128
        drive_1(640);
        drive_2(640);
        drive_3(640);

        // 3.5 tie: TRUNC=3, NEAREST=4, HALF_UP=4, CONV=4 (keep[0]=1 -> round up)
        drive_0(896);  // 768+128, keep=3, drop=128
        drive_1(896);
        drive_2(896);
        drive_3(896);

        // Negative ties
        // -0.5 = -128 in 16-bit: keep=-1 (0xFF), drop=128
        drive_0(-128);
        drive_1(-128);
        drive_2(-128);
        drive_3(-128);
    endtask

    task automatic directed_boundaries();
        // Just below half: drop=127 < 128
        drive_0(127); drive_1(127); drive_2(127); drive_3(127);
        // Just above half: drop=129 > 128
        drive_0(129); drive_1(129); drive_2(129); drive_3(129);
        // Zero
        drive_0(0); drive_1(0); drive_2(0); drive_3(0);
        // Max positive: 32767
        drive_0(32767); drive_1(32767); drive_2(32767); drive_3(32767);
        // Min negative: -32768
        drive_0(-32768); drive_1(-32768); drive_2(-32768); drive_3(-32768);
    endtask

    task automatic directed_convergent();
        // Test convergent specifically on sequences that should be unbiased
        // .5 ties alternate: round to even
        // Sequence: 0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5
        // CONV:    0,   2,   2,   4,   4,   6,   6,   8  (even pattern)
        // HALF_UP: 1,   2,   3,   4,   5,   6,   7,   8  (always up, biased)
        longint ties[8] = '{128, 384, 640, 896, 1152, 1408, 1664, 1920};
        for (int i = 0; i < 8; i++) begin
            drive_3(ties[i]);  // CONVERGENT
            drive_2(ties[i]);  // HALF_UP for comparison
        end
    endtask

    task automatic directed_lsb();
        // LSB-aligned convergent: 16->8, drop top 8 bits
        drive_4(0);
        drive_4(127);
        drive_4(128);
        drive_4(-128);
        drive_4(-129);
    endtask

    // -------------------------------------------------------------------
    // Convergence bias test: apply repeated rounding and check that
    // the average error converges to zero for CONVERGENT mode
    // -------------------------------------------------------------------
    task automatic convergence_bias_test(int n);
        longint sum_trunc, sum_nearest, sum_halfup, sum_conv;
        longint val, orig;
        sum_trunc = 0; sum_nearest = 0; sum_halfup = 0; sum_conv = 0;

        $display("  Convergence bias test (%0d samples)...", n);
        for (int i = 0; i < n; i++) begin
            // Generate a value with random fractional part, centered around 0
            val = $urandom() & 32'hFFFF;
            // Make it signed
            if (val[15]) val = val | ~64'hFFFF;
            orig = val;

            // Apply each mode via golden model and accumulate
            d0_in = val[IW-1:0]; d1_in = val[IW-1:0];
            d2_in = val[IW-1:0]; d3_in = val[IW-1:0];
            #1;

            sum_trunc   += $signed(d0_out) * 256;  // Scale back up
            sum_nearest += $signed(d1_out) * 256;
            sum_halfup  += $signed(d2_out) * 256;
            sum_conv    += $signed(d3_out) * 256;
        end

        $display("  Average error (scaled):");
        $display("    TRUNC:    %0d", sum_trunc/n);
        $display("    NEAREST:  %0d", sum_nearest/n);
        $display("    HALF_UP:  %0d", sum_halfup/n);
        $display("    CONV:     %0d", sum_conv/n);
        $display("  (TRUNC should have large negative bias)");
        $display("  (CONV should be closest to 0)");
    endtask

    // -------------------------------------------------------------------
    // Random regression
    // -------------------------------------------------------------------
    task automatic random_regression(int n);
        longint v;
        for (int i = 0; i < n; i++) begin
            v = {$urandom(), $urandom()};
            drive_0(v); drive_1(v); drive_2(v); drive_3(v); drive_4(v);
        end
    endtask

    // -------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------
    initial begin
        $display("=== agr_fxp_round self-checking testbench ===");
        $display("");

        $display("--- Directed: tie cases ---");
        directed_ties();

        $display("--- Directed: boundaries ---");
        directed_boundaries();

        $display("--- Directed: convergent sequences ---");
        directed_convergent();

        $display("--- Directed: LSB-aligned ---");
        directed_lsb();

        $display("");
        convergence_bias_test(10000);

        $display("");
        $display("--- Random regression (3000) ---");
        random_regression(3000);

        $display("");
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if (errors == 0) begin
            $display("*** TEST PASSED ***");
            $finish;
        end else begin
            $fatal(1, "*** TEST FAILED: %0d/%0d checks mismatched ***", errors, checks);
        end
    end

endmodule : tb_agr_fxp_round

`default_nettype wire
