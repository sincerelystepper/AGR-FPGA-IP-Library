`default_nettype none

module tb_agr_fxp_resize;

    int errors = 0;
    int checks = 0;

    function automatic longint to_signed(longint raw, int width);
        longint mask = (64'(1) <<< width) - 64'(1);
        longint val = raw & mask;
        to_signed = val[width-1] ? val | ~mask : val;
    endfunction

    function automatic void golden_model(
        input int in_w, out_w, input bit mode, align,
        input longint in_val, output longint exp_out,
        output bit exp_overflow, exp_precision_loss
    );
        longint in_mask, out_mask, drop_mask;
        int drop_w; longint dropped, candidate, sat_max, sat_min;
        bit kept_sign_val, in_sign;
        in_mask = (64'(1) <<< in_w) - 64'(1);
        in_sign = (in_val < 0);

        if (out_w > in_w) begin
            exp_out = in_val; exp_overflow = 0; exp_precision_loss = 0;
        end else if (out_w == in_w) begin
            exp_out = in_val; exp_overflow = 0; exp_precision_loss = 0;
        end else if (align) begin
            drop_w = in_w - out_w;
            drop_mask = (64'(1) <<< drop_w) - 64'(1);
            dropped = (in_val & in_mask) & drop_mask;
            candidate = (in_val & in_mask) >>> drop_w;
            exp_out = to_signed(candidate, out_w);
            exp_overflow = 0;
            exp_precision_loss = (dropped != 0);
        end else begin
            out_mask = (64'(1) <<< out_w) - 64'(1);
            drop_w = in_w - out_w;
            candidate = (in_val & in_mask) & out_mask;
            dropped = (in_val & in_mask) >>> out_w;
            kept_sign_val = bit'((candidate >>> (out_w-1)) & 1);
            exp_overflow = (dropped != (kept_sign_val ? ((64'(1) <<< drop_w) - 64'(1)) : 64'(0)));
            exp_precision_loss = exp_overflow;
            if (mode && exp_overflow) begin
                sat_max = (64'(1) <<< (out_w-1)) - 64'(1);
                sat_min = -(64'(1) <<< (out_w-1));
                exp_out = in_sign ? sat_min : sat_max;
            end else begin
                exp_out = to_signed(candidate, out_w);
            end
        end
    endfunction

    task automatic check(
        input string  label,
        input int     in_w, out_w,
        input bit     mode, align,
        input longint in_val, dut_out,
        input bit     dut_overflow, dut_precision_loss
    );
        longint exp_out;
        bit exp_overflow, exp_precision_loss;
        golden_model(in_w, out_w, mode, align, in_val, exp_out, exp_overflow, exp_precision_loss);
        checks++;
        if (dut_out !== exp_out || dut_overflow !== exp_overflow || dut_precision_loss !== exp_precision_loss) begin
            errors++;
            $error("[%s] in=%0d | out exp=%0d got=%0d | ovf exp=%0b got=%0b | pl exp=%0b got=%0b",
                   label, in_val, exp_out, dut_out, exp_overflow, dut_overflow, exp_precision_loss, dut_precision_loss);
        end
    endtask

    /* verilator lint_off UNUSEDSIGNAL */

    // DUT1: 16->8 MSB TRUNCATE
    localparam int D1_IW=16, D1_OW=8; localparam bit D1_MODE=0, D1_ALIGN=1;
    logic signed [D1_IW-1:0] d1_in; logic signed [D1_OW-1:0] d1_out; logic d1_ovf, d1_pl;
    agr_fxp_resize #(.IN_W(D1_IW),.OUT_W(D1_OW),.MODE(D1_MODE),.ALIGN(D1_ALIGN))
        dut1(.in_val(d1_in),.out_val(d1_out),.overflow(d1_ovf),.precision_loss(d1_pl));
    task automatic drive_1(longint v); d1_in=v[D1_IW-1:0]; #1;
        check("dut1",D1_IW,D1_OW,D1_MODE,D1_ALIGN,$signed(d1_in),$signed(d1_out),d1_ovf,d1_pl);
    endtask

    // DUT2: 16->8 MSB SATURATE
    localparam int D2_IW=16, D2_OW=8; localparam bit D2_MODE=1, D2_ALIGN=1;
    logic signed [D2_IW-1:0] d2_in; logic signed [D2_OW-1:0] d2_out; logic d2_ovf, d2_pl;
    agr_fxp_resize #(.IN_W(D2_IW),.OUT_W(D2_OW),.MODE(D2_MODE),.ALIGN(D2_ALIGN))
        dut2(.in_val(d2_in),.out_val(d2_out),.overflow(d2_ovf),.precision_loss(d2_pl));
    task automatic drive_2(longint v); d2_in=v[D2_IW-1:0]; #1;
        check("dut2",D2_IW,D2_OW,D2_MODE,D2_ALIGN,$signed(d2_in),$signed(d2_out),d2_ovf,d2_pl);
    endtask

    // DUT3: 16->8 LSB TRUNCATE
    localparam int D3_IW=16, D3_OW=8; localparam bit D3_MODE=0, D3_ALIGN=0;
    logic signed [D3_IW-1:0] d3_in; logic signed [D3_OW-1:0] d3_out; logic d3_ovf, d3_pl;
    agr_fxp_resize #(.IN_W(D3_IW),.OUT_W(D3_OW),.MODE(D3_MODE),.ALIGN(D3_ALIGN))
        dut3(.in_val(d3_in),.out_val(d3_out),.overflow(d3_ovf),.precision_loss(d3_pl));
    task automatic drive_3(longint v); d3_in=v[D3_IW-1:0]; #1;
        check("dut3",D3_IW,D3_OW,D3_MODE,D3_ALIGN,$signed(d3_in),$signed(d3_out),d3_ovf,d3_pl);
    endtask

    // DUT4: 16->8 LSB SATURATE
    localparam int D4_IW=16, D4_OW=8; localparam bit D4_MODE=1, D4_ALIGN=0;
    logic signed [D4_IW-1:0] d4_in; logic signed [D4_OW-1:0] d4_out; logic d4_ovf, d4_pl;
    agr_fxp_resize #(.IN_W(D4_IW),.OUT_W(D4_OW),.MODE(D4_MODE),.ALIGN(D4_ALIGN))
        dut4(.in_val(d4_in),.out_val(d4_out),.overflow(d4_ovf),.precision_loss(d4_pl));
    task automatic drive_4(longint v); d4_in=v[D4_IW-1:0]; #1;
        check("dut4",D4_IW,D4_OW,D4_MODE,D4_ALIGN,$signed(d4_in),$signed(d4_out),d4_ovf,d4_pl);
    endtask

    // DUT5: 8->16 expand
    localparam int D5_IW=8, D5_OW=16; localparam bit D5_MODE=0, D5_ALIGN=1;
    logic signed [D5_IW-1:0] d5_in; logic signed [D5_OW-1:0] d5_out; logic d5_ovf, d5_pl;
    agr_fxp_resize #(.IN_W(D5_IW),.OUT_W(D5_OW),.MODE(D5_MODE),.ALIGN(D5_ALIGN))
        dut5(.in_val(d5_in),.out_val(d5_out),.overflow(d5_ovf),.precision_loss(d5_pl));
    task automatic drive_5(longint v); d5_in=v[D5_IW-1:0]; #1;
        check("dut5",D5_IW,D5_OW,D5_MODE,D5_ALIGN,$signed(d5_in),$signed(d5_out),d5_ovf,d5_pl);
    endtask

    // DUT6: 10->10 passthrough
    localparam int D6_IW=10, D6_OW=10; localparam bit D6_MODE=1, D6_ALIGN=0;
    logic signed [D6_IW-1:0] d6_in; logic signed [D6_OW-1:0] d6_out; logic d6_ovf, d6_pl;
    agr_fxp_resize #(.IN_W(D6_IW),.OUT_W(D6_OW),.MODE(D6_MODE),.ALIGN(D6_ALIGN))
        dut6(.in_val(d6_in),.out_val(d6_out),.overflow(d6_ovf),.precision_loss(d6_pl));
    task automatic drive_6(longint v); d6_in=v[D6_IW-1:0]; #1;
        check("dut6",D6_IW,D6_OW,D6_MODE,D6_ALIGN,$signed(d6_in),$signed(d6_out),d6_ovf,d6_pl);
    endtask

    // DUT7: 4->1 LSB SATURATE
    localparam int D7_IW=4, D7_OW=1; localparam bit D7_MODE=1, D7_ALIGN=0;
    logic signed [D7_IW-1:0] d7_in; logic signed [D7_OW-1:0] d7_out; logic d7_ovf, d7_pl;
    agr_fxp_resize #(.IN_W(D7_IW),.OUT_W(D7_OW),.MODE(D7_MODE),.ALIGN(D7_ALIGN))
        dut7(.in_val(d7_in),.out_val(d7_out),.overflow(d7_ovf),.precision_loss(d7_pl));
    task automatic drive_7(longint v); d7_in=v[D7_IW-1:0]; #1;
        check("dut7",D7_IW,D7_OW,D7_MODE,D7_ALIGN,$signed(d7_in),$signed(d7_out),d7_ovf,d7_pl);
    endtask

    // DUT8: 13->7 MSB TRUNCATE
    localparam int D8_IW=13, D8_OW=7; localparam bit D8_MODE=0, D8_ALIGN=1;
    logic signed [D8_IW-1:0] d8_in; logic signed [D8_OW-1:0] d8_out; logic d8_ovf, d8_pl;
    agr_fxp_resize #(.IN_W(D8_IW),.OUT_W(D8_OW),.MODE(D8_MODE),.ALIGN(D8_ALIGN))
        dut8(.in_val(d8_in),.out_val(d8_out),.overflow(d8_ovf),.precision_loss(d8_pl));
    task automatic drive_8(longint v); d8_in=v[D8_IW-1:0]; #1;
        check("dut8",D8_IW,D8_OW,D8_MODE,D8_ALIGN,$signed(d8_in),$signed(d8_out),d8_ovf,d8_pl);
    endtask

    /* verilator lint_on UNUSEDSIGNAL */

    task automatic crosscheck_msb_mode_invariance(longint v);
        d1_in=v[D1_IW-1:0]; d2_in=v[D2_IW-1:0]; #1; checks++;
        if(d1_out!==d2_out||d1_ovf!==d2_ovf||d1_pl!==d2_pl) begin errors++;
            $error("[xcheck] in=%0d: dut1(%d,%b,%b) != dut2(%d,%b,%b)",v,$signed(d1_out),d1_ovf,d1_pl,$signed(d2_out),d2_ovf,d2_pl);
        end
    endtask

    task automatic directed_d1_d2();
        drive_1(0);drive_2(0); drive_1(128);drive_2(128);
        drive_1(129);drive_2(129); drive_1(32767);drive_2(32767);
        drive_1(-32768);drive_2(-32768); drive_1(-1);drive_2(-1);
        crosscheck_msb_mode_invariance(129);
        crosscheck_msb_mode_invariance(-32768);
        crosscheck_msb_mode_invariance(-1);
    endtask

    task automatic directed_d3_d4();
        drive_3(0);drive_4(0); drive_3(127);drive_4(127);
        drive_3(128);drive_4(128); drive_3(-128);drive_4(-128);
        drive_3(-129);drive_4(-129); drive_3(32767);drive_4(32767);
        drive_3(-32768);drive_4(-32768); drive_3(1);drive_4(1);
        drive_3(-1);drive_4(-1);
    endtask

    task automatic directed_d5(); drive_5(0);drive_5(127);drive_5(-128);drive_5(-1);drive_5(1); endtask
    task automatic directed_d6(); drive_6(0);drive_6(511);drive_6(-512);drive_6(-1);drive_6(1); endtask
    task automatic directed_d7();
        drive_7(0);drive_7(1);drive_7(-1);drive_7(-8);drive_7(7);
    endtask
    task automatic directed_d8(); drive_8(0);drive_8(4095);drive_8(-4096);drive_8(64);drive_8(63); endtask

    task automatic random_regression(int n);
        longint v;
        for(int i=0;i<n;i++) begin
            v={$urandom(),$urandom()};
            drive_1(v);drive_2(v);drive_3(v);drive_4(v);
            drive_5(v);drive_6(v);drive_7(v);drive_8(v);
        end
    endtask

    initial begin
        $display("=== agr_fxp_resize self-checking testbench ===");
        directed_d1_d2(); directed_d3_d4(); directed_d5();
        directed_d6(); directed_d7(); directed_d8();
        random_regression(3000);
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if(errors==0) begin $display("*** TEST PASSED ***"); $finish; end
        else $fatal(1,"*** TEST FAILED: %0d/%0d checks mismatched ***", errors, checks);
    end

endmodule
`default_nettype wire
