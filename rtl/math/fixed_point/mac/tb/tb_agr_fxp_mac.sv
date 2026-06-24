`default_nettype none
`timescale 1ns/1ps

module tb_agr_fxp_mac;

    int errors = 0;
    int checks = 0;

    function automatic longint to_signed(longint raw, int width);
        longint mask = (64'(1) <<< width) - 64'(1);
        longint val = raw & mask;
        to_signed = val[width-1] ? val | ~mask : val;
    endfunction

    function automatic void golden_model(
        input int in_a_w, in_b_w, acc_w,
        input bit use_rounding, use_saturate, align,
        input longint a_val, b_val, acc_val,
        output longint exp_acc_next,
        output bit exp_overflow
    );
        int full_w = in_a_w + in_b_w;
        longint full_mask = (64'(1) <<< full_w) - 64'(1);
        longint mult_full = a_val * b_val;
        int drop_w; longint drop_mask, half, drop_bits, candidate;
        bit is_tie, above_half, round_carry;
        longint scaled; longint out_mask, low_bits, high_bits;
        bit kept_sign_val, resize_overflow;
        longint acc_sum, acc_max, acc_min;
        bit acc_overflow;

        resize_overflow = 1'b0;
        if (acc_w >= full_w) scaled = mult_full;
        else if (align) begin
            drop_w = full_w - acc_w;
            drop_mask = (64'(1) <<< drop_w) - 64'(1);
            half = (64'(1) <<< (drop_w - 1));
            drop_bits = (mult_full & full_mask) & drop_mask;
            candidate = to_signed((mult_full & full_mask) >>> drop_w, acc_w);
            if (use_rounding) begin
                is_tie = (drop_bits == half);
                above_half = (drop_bits > half);
                round_carry = above_half | (is_tie & bit'(candidate[0]));
            end else round_carry = 1'b0;
            scaled = candidate + (round_carry ? 64'(1) : 64'(0));
        end else begin
            drop_w = full_w - acc_w;
            out_mask = (64'(1) <<< acc_w) - 64'(1);
            drop_mask = (64'(1) <<< drop_w) - 64'(1);
            low_bits = (mult_full & full_mask) & out_mask;
            high_bits = (mult_full & full_mask) >>> acc_w;
            kept_sign_val = bit'((low_bits >>> (acc_w - 1)) & 1);
            resize_overflow = (high_bits != (kept_sign_val ? drop_mask : 64'(0)));
            scaled = to_signed(low_bits, acc_w);
        end

        acc_sum = acc_val + scaled;
        acc_max = (64'(1) <<< (acc_w - 1)) - 64'(1);
        acc_min = -(64'(1) <<< (acc_w - 1));
        acc_overflow = (acc_sum > acc_max) || (acc_sum < acc_min);
        exp_overflow = acc_overflow || resize_overflow;

        if (use_saturate && exp_overflow)
            exp_acc_next = (acc_sum < 0) ? acc_min : acc_max;
        else
            exp_acc_next = to_signed(acc_sum, acc_w);
    endfunction

    // Old-style task ports for Verilator 5.x compatibility
    task automatic check;
        input string label;
        input int in_a_w;
        input int in_b_w;
        input int acc_w;
        input bit use_rounding;
        input bit use_saturate;
        input bit align;
        input longint a_val;
        input longint b_val;
        input longint acc_val;
        input longint dut_acc_next;
        input bit dut_overflow;

        longint exp_acc_next;
        bit exp_overflow;
        begin
            golden_model(in_a_w, in_b_w, acc_w, use_rounding, use_saturate, align,
                         a_val, b_val, acc_val, exp_acc_next, exp_overflow);
            checks = checks + 1;
            if (dut_acc_next !== exp_acc_next || dut_overflow !== exp_overflow) begin
                errors = errors + 1;
                $error("[%s] a=%0d b=%0d acc=%0d | exp=%0d/%0b got=%0d/%0b",
                       label, a_val, b_val, acc_val, exp_acc_next, exp_overflow, dut_acc_next, dut_overflow);
            end
        end
    endtask

    localparam int D_AW=8, D_BW=8, D_ACCW=8;

    // DUT1: MSB trunc wrap
    logic signed [D_AW-1:0] d1_a,d1_b; logic signed [D_ACCW-1:0] d1_acc,d1_accn; logic d1_ovf;
    agr_fxp_mac #(.IN_A_W(D_AW),.IN_B_W(D_BW),.ACC_W(D_ACCW),.USE_ROUNDING(0),.USE_SATURATE(0),.ALIGN(1))
        dut1(.a(d1_a),.b(d1_b),.acc(d1_acc),.acc_next(d1_accn),.overflow(d1_ovf));
    task automatic drive_1;
        input longint av; input longint bv; input longint accv;
        begin d1_a=av[D_AW-1:0];d1_b=bv[D_BW-1:0];d1_acc=accv[D_ACCW-1:0];#1;
        check("dut1",D_AW,D_BW,D_ACCW,0,0,1,$signed(d1_a),$signed(d1_b),$signed(d1_acc),$signed(d1_accn),d1_ovf); end
    endtask

    // DUT2: MSB trunc saturate
    logic signed [D_AW-1:0] d2_a,d2_b; logic signed [D_ACCW-1:0] d2_acc,d2_accn; logic d2_ovf;
    agr_fxp_mac #(.IN_A_W(D_AW),.IN_B_W(D_BW),.ACC_W(D_ACCW),.USE_ROUNDING(0),.USE_SATURATE(1),.ALIGN(1))
        dut2(.a(d2_a),.b(d2_b),.acc(d2_acc),.acc_next(d2_accn),.overflow(d2_ovf));
    task automatic drive_2;
        input longint av; input longint bv; input longint accv;
        begin d2_a=av[D_AW-1:0];d2_b=bv[D_BW-1:0];d2_acc=accv[D_ACCW-1:0];#1;
        check("dut2",D_AW,D_BW,D_ACCW,0,1,1,$signed(d2_a),$signed(d2_b),$signed(d2_acc),$signed(d2_accn),d2_ovf); end
    endtask

    // DUT4: MSB round saturate
    logic signed [D_AW-1:0] d4_a,d4_b; logic signed [D_ACCW-1:0] d4_acc,d4_accn; logic d4_ovf;
    agr_fxp_mac #(.IN_A_W(D_AW),.IN_B_W(D_BW),.ACC_W(D_ACCW),.USE_ROUNDING(1),.USE_SATURATE(1),.ALIGN(1))
        dut4(.a(d4_a),.b(d4_b),.acc(d4_acc),.acc_next(d4_accn),.overflow(d4_ovf));
    task automatic drive_4;
        input longint av; input longint bv; input longint accv;
        begin d4_a=av[D_AW-1:0];d4_b=bv[D_BW-1:0];d4_acc=accv[D_ACCW-1:0];#1;
        check("dut4",D_AW,D_BW,D_ACCW,1,1,1,$signed(d4_a),$signed(d4_b),$signed(d4_acc),$signed(d4_accn),d4_ovf); end
    endtask

    // DUT5: LSB trunc wrap
    logic signed [D_AW-1:0] d5_a,d5_b; logic signed [D_ACCW-1:0] d5_acc,d5_accn; logic d5_ovf;
    agr_fxp_mac #(.IN_A_W(D_AW),.IN_B_W(D_BW),.ACC_W(D_ACCW),.USE_ROUNDING(0),.USE_SATURATE(0),.ALIGN(0))
        dut5(.a(d5_a),.b(d5_b),.acc(d5_acc),.acc_next(d5_accn),.overflow(d5_ovf));
    task automatic drive_5;
        input longint av; input longint bv; input longint accv;
        begin d5_a=av[D_AW-1:0];d5_b=bv[D_BW-1:0];d5_acc=accv[D_ACCW-1:0];#1;
        check("dut5",D_AW,D_BW,D_ACCW,0,0,0,$signed(d5_a),$signed(d5_b),$signed(d5_acc),$signed(d5_accn),d5_ovf); end
    endtask

    task automatic random_regression;
        input int n;
        longint av, bv, accv;
        integer i;
        begin
            for(i=0;i<n;i=i+1) begin
                av={$urandom(),$urandom()}; bv={$urandom(),$urandom()}; accv={$urandom(),$urandom()};
                drive_1(av,bv,accv); drive_2(av,bv,accv); drive_4(av,bv,accv); drive_5(av,bv,accv);
            end
        end
    endtask

    initial begin
        $display("=== agr_fxp_mac self-checking testbench ===");
        drive_1(0,0,0); drive_2(0,0,0); drive_4(0,0,0); drive_5(0,0,0);
        drive_1(5,3,0); drive_2(5,3,0); drive_4(5,3,0);
        drive_1(127,127,0); drive_2(127,127,0); drive_4(127,127,0);
        drive_1(-128,-128,0); drive_2(-128,-128,0); drive_4(-128,-128,0);
        random_regression(3000);
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if(errors==0) begin $display("*** TEST PASSED ***"); $finish; end
        else $fatal(1,"*** TEST FAILED: %0d/%0d checks mismatched ***", errors, checks);
    end

endmodule
`default_nettype wire
