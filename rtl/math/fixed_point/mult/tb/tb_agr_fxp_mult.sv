`default_nettype none

module tb_agr_fxp_mult;

    int errors = 0;
    int checks = 0;

    function automatic longint to_signed(longint raw, int width);
        longint mask = (64'(1) <<< width) - 64'(1);
        longint val = raw & mask;
        to_signed = val[width-1] ? val | ~mask : val;
    endfunction

    function automatic void golden_model(
        input int a_w, b_w, out_w,
        input bit truncate_msb,
        input longint a_val, b_val,
        output longint exp_full, exp_result,
        output bit exp_overflow
    );
        int full_w = a_w + b_w;
        longint full_mask = (64'(1) <<< full_w) - 64'(1);
        longint raw_full = a_val * b_val;
        exp_full = to_signed(raw_full, full_w);

        if (out_w == full_w) begin
            exp_result = exp_full;
            exp_overflow = 1'b0;
        end else if (out_w > full_w) begin
            exp_result = to_signed(exp_full, out_w);
            exp_overflow = 1'b0;
        end else if (truncate_msb) begin
            int drop_w = full_w - out_w;
            longint drop_mask = (64'(1) <<< drop_w) - 64'(1);
            longint dropped_bits = exp_full & drop_mask;
            longint top_bits = (exp_full & full_mask) >>> drop_w;
            exp_result = to_signed(top_bits, out_w);
            exp_overflow = (dropped_bits != 0);
        end else begin
            int drop_w = full_w - out_w;
            longint out_mask = (64'(1) <<< out_w) - 64'(1);
            longint low_bits = exp_full & out_mask;
            longint dropped_bits = (exp_full & full_mask) >>> out_w;
            longint sign_rep = low_bits[out_w-1] ? ((64'(1) <<< drop_w) - 64'(1)) : 64'(0);
            exp_result = to_signed(low_bits, out_w);
            exp_overflow = (dropped_bits != sign_rep);
        end
    endfunction

    task automatic check(
        string label, int a_w, b_w, out_w, bit truncate_msb,
        longint a_val, b_val, dut_full, dut_result, bit dut_overflow
    );
        longint exp_full, exp_result;
        bit exp_overflow;
        golden_model(a_w, b_w, out_w, truncate_msb, a_val, b_val,
                     exp_full, exp_result, exp_overflow);
        checks++;
        if (dut_full !== exp_full || dut_result !== exp_result || dut_overflow !== exp_overflow) begin
            errors++;
            $error("[%s] a=%0d b=%0d | full exp=%0d got=%0d | result exp=%0d got=%0d | overflow exp=%0b got=%0b",
                   label, a_val, b_val, exp_full, dut_full, exp_result, dut_result, exp_overflow, dut_overflow);
        end
    endtask

    // DUT A: 8x8->8 MSB-trunc
    localparam int A_AW=8, A_BW=8, A_OW=8; localparam bit A_TM=1;
    logic signed [A_AW-1:0] a_a, a_b;
    logic signed [A_AW+A_BW-1:0] a_full;
    logic signed [A_OW-1:0] a_res; logic a_ovf;
    agr_fxp_mult #(.IN_A_W(A_AW),.IN_B_W(A_BW),.OUT_W(A_OW),.SIGNED(1),.TRUNCATE_MSB(A_TM))
        dut_a(.a(a_a),.b(a_b),.result_full(a_full),.result(a_res),.overflow(a_ovf));
    task automatic drive_a(longint av, longint bv);
        a_a=av[A_AW-1:0]; a_b=bv[A_BW-1:0]; #1;
        check("dut_a",A_AW,A_BW,A_OW,A_TM,longint'($signed(a_a)),longint'($signed(a_b)),
              longint'($signed(a_full)),longint'($signed(a_res)),a_ovf);
    endtask

    // DUT B: 12x20->16 LSB-trunc
    localparam int B_AW=12,B_BW=20,B_OW=16; localparam bit B_TM=0;
    logic signed [B_AW-1:0] b_a; logic signed [B_BW-1:0] b_b;
    logic signed [B_AW+B_BW-1:0] b_full;
    logic signed [B_OW-1:0] b_res; logic b_ovf;
    agr_fxp_mult #(.IN_A_W(B_AW),.IN_B_W(B_BW),.OUT_W(B_OW),.SIGNED(1),.TRUNCATE_MSB(B_TM))
        dut_b(.a(b_a),.b(b_b),.result_full(b_full),.result(b_res),.overflow(b_ovf));
    task automatic drive_b(longint av, longint bv);
        b_a=av[B_AW-1:0]; b_b=bv[B_BW-1:0]; #1;
        check("dut_b",B_AW,B_BW,B_OW,B_TM,longint'($signed(b_a)),longint'($signed(b_b)),
              longint'($signed(b_full)),longint'($signed(b_res)),b_ovf);
    endtask

    // DUT C: 6x6->16 extend
    localparam int C_AW=6,C_BW=6,C_OW=16; localparam bit C_TM=1;
    logic signed [C_AW-1:0] c_a,c_b; logic signed [C_AW+C_BW-1:0] c_full;
    logic signed [C_OW-1:0] c_res; logic c_ovf;
    agr_fxp_mult #(.IN_A_W(C_AW),.IN_B_W(C_BW),.OUT_W(C_OW),.SIGNED(1),.TRUNCATE_MSB(C_TM))
        dut_c(.a(c_a),.b(c_b),.result_full(c_full),.result(c_res),.overflow(c_ovf));
    task automatic drive_c(longint av, longint bv);
        c_a=av[C_AW-1:0]; c_b=bv[C_BW-1:0]; #1;
        check("dut_c",C_AW,C_BW,C_OW,C_TM,longint'($signed(c_a)),longint'($signed(c_b)),
              longint'($signed(c_full)),longint'($signed(c_res)),c_ovf);
    endtask

    // DUT D: 4x4->8 passthrough
    localparam int D_AW=4,D_BW=4,D_OW=8; localparam bit D_TM=1;
    logic signed [D_AW-1:0] d_a,d_b; logic signed [D_AW+D_BW-1:0] d_full;
    logic signed [D_OW-1:0] d_res; logic d_ovf;
    agr_fxp_mult #(.IN_A_W(D_AW),.IN_B_W(D_BW),.OUT_W(D_OW),.SIGNED(1),.TRUNCATE_MSB(D_TM))
        dut_d(.a(d_a),.b(d_b),.result_full(d_full),.result(d_res),.overflow(d_ovf));
    task automatic drive_d(longint av, longint bv);
        d_a=av[D_AW-1:0]; d_b=bv[D_BW-1:0]; #1;
        check("dut_d",D_AW,D_BW,D_OW,D_TM,longint'($signed(d_a)),longint'($signed(d_b)),
              longint'($signed(d_full)),longint'($signed(d_res)),d_ovf);
    endtask

    task automatic directed_corners_a();
        longint amax=(64'(1)<<<(A_AW-1))-1, amin=-(64'(1)<<<(A_AW-1));
        longint bmax=(64'(1)<<<(A_BW-1))-1, bmin=-(64'(1)<<<(A_BW-1));
        drive_a(0,0); drive_a(1,1); drive_a(-1,-1); drive_a(-1,1); drive_a(1,-1);
        drive_a(amax,bmax); drive_a(amin,bmin); drive_a(amin,bmax);
        drive_a(amin,-1); drive_a(amax,-1);
    endtask

    task automatic directed_corners_b();
        longint amax=(64'(1)<<<(B_AW-1))-1, amin=-(64'(1)<<<(B_AW-1));
        longint bmax=(64'(1)<<<(B_BW-1))-1, bmin=-(64'(1)<<<(B_BW-1));
        drive_b(0,0); drive_b(1,1); drive_b(-1,-1); drive_b(-1,1);
        drive_b(amax,bmax); drive_b(amin,bmin); drive_b(amin,bmax);
        drive_b(amin,-1); drive_b(amax,-1); drive_b(2,3);
    endtask

    task automatic directed_corners_c();
        longint amax=(64'(1)<<<(C_AW-1))-1, amin=-(64'(1)<<<(C_AW-1));
        longint bmax=(64'(1)<<<(C_BW-1))-1, bmin=-(64'(1)<<<(C_BW-1));
        drive_c(0,0); drive_c(amax,bmax); drive_c(amin,bmin);
        drive_c(amin,bmax); drive_c(-1,1);
    endtask

    task automatic directed_corners_d();
        longint amax=(64'(1)<<<(D_AW-1))-1, amin=-(64'(1)<<<(D_AW-1));
        longint bmax=(64'(1)<<<(D_BW-1))-1, bmin=-(64'(1)<<<(D_BW-1));
        drive_d(0,0); drive_d(amax,bmax); drive_d(amin,bmin);
        drive_d(amin,bmax); drive_d(-1,1);
    endtask

    task automatic overflow_focus_a();
        drive_a(1,1); drive_a(-128,-128); drive_a(64,2); drive_a(65,2);
    endtask

    task automatic overflow_focus_b();
        longint amax=(64'(1)<<<(B_AW-1))-1, bmax=(64'(1)<<<(B_BW-1))-1;
        drive_b(1,1); drive_b(amax,bmax);
        drive_b(-1,32767); drive_b(-1,-32768);
    endtask

    task automatic random_regression(int n);
        for(int i=0;i<n;i++) begin
            drive_a({$urandom(),$urandom()},{$urandom(),$urandom()});
            drive_b({$urandom(),$urandom()},{$urandom(),$urandom()});
            drive_c({$urandom(),$urandom()},{$urandom(),$urandom()});
            drive_d({$urandom(),$urandom()},{$urandom(),$urandom()});
        end
    endtask

    initial begin
        $display("=== agr_fxp_mult self-checking testbench ===");
        directed_corners_a(); directed_corners_b();
        directed_corners_c(); directed_corners_d();
        overflow_focus_a(); overflow_focus_b();
        random_regression(5000);
        $display("=== %0d checks run, %0d errors ===", checks, errors);
        if(errors==0) begin
            $display("*** TEST PASSED ***");
            $finish;
        end else
            $fatal(1,"*** TEST FAILED: %0d/%0d checks mismatched ***", errors, checks);
    end

endmodule
`default_nettype wire
