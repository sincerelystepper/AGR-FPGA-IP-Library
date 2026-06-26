`default_nettype none
`timescale 1ns/1ps

module tb_agr_fft_stage;

    localparam int N4 = 4, N8 = 8;
    localparam int DATA_W = 8, TW_W = 8, OUT_W = 32;
    localparam int STRIDE4 = N4/2, STRIDE8 = N8/2;

    // DUT N=4
    logic signed [DATA_W-1:0] in4_real [N4], in4_imag [N4];
    logic signed [TW_W-1:0]   w4_real  [N4/2], w4_imag  [N4/2];
    logic signed [OUT_W-1:0]  out4_real [N4], out4_imag [N4];
    logic ovf4;

    agr_fft_stage #(.N(N4),.DATA_W(DATA_W),.TW_W(TW_W),.OUT_W(OUT_W),.STRIDE(STRIDE4))
        dut4 (.in_real(in4_real),.in_imag(in4_imag),.w_real(w4_real),.w_imag(w4_imag),
              .out_real(out4_real),.out_imag(out4_imag),.overflow(ovf4));

    // DUT N=8
    logic signed [DATA_W-1:0] in8_real [N8], in8_imag [N8];
    logic signed [TW_W-1:0]   w8_real  [N8/2], w8_imag  [N8/2];
    logic signed [OUT_W-1:0]  out8_real [N8], out8_imag [N8];
    logic ovf8;

    agr_fft_stage #(.N(N8),.DATA_W(DATA_W),.TW_W(TW_W),.OUT_W(OUT_W),.STRIDE(STRIDE8))
        dut8 (.in_real(in8_real),.in_imag(in8_imag),.w_real(w8_real),.w_imag(w8_imag),
              .out_real(out8_real),.out_imag(out8_imag),.overflow(ovf8));

    int errors = 0;
    int checks = 0;

    function automatic longint s64(longint val, int w);
        longint mask = (64'(1) << w) - 64'(1);
        val = val & mask;
        if (val >= (64'(1) << (w-1))) val = val - (64'(1) << w);
        return val;
    endfunction

    // Golden scaled butterfly
    function automatic void bfly;
        input longint ar, ai, br, bi, wr, wi;
        output longint x0r, x0i, x1r, x1i;
        longint dr, di, p1r, p1i;
        begin
            x0r = s64((ar + br) >> 1, OUT_W);
            x0i = s64((ai + bi) >> 1, OUT_W);
            dr = ar - br; di = ai - bi;
            p1r = dr*wr - di*wi;
            p1i = dr*wi + di*wr;
            x1r = s64(p1r >> 1, OUT_W);
            x1i = s64(p1i >> 1, OUT_W);
        end
    endfunction

    // Test N=4
    task test4;
        input longint i0r,i0i,i1r,i1i,i2r,i2i,i3r,i3i;
        input longint w0r,w0i,w1r,w1i;
        input longint e0r,e0i,e1r,e1i,e2r,e2i,e3r,e3i;
        begin
            in4_real[0]=i0r[7:0]; in4_imag[0]=i0i[7:0];
            in4_real[1]=i1r[7:0]; in4_imag[1]=i1i[7:0];
            in4_real[2]=i2r[7:0]; in4_imag[2]=i2i[7:0];
            in4_real[3]=i3r[7:0]; in4_imag[3]=i3i[7:0];
            w4_real[0]=w0r[7:0]; w4_imag[0]=w0i[7:0];
            w4_real[1]=w1r[7:0]; w4_imag[1]=w1i[7:0];
            #1;
            checks += 8;
            if (out4_real[0]!==e0r||out4_imag[0]!==e0i) begin errors++; $display("FAIL N4[0]"); end
            if (out4_real[1]!==e1r||out4_imag[1]!==e1i) begin errors++; $display("FAIL N4[1]"); end
            if (out4_real[2]!==e2r||out4_imag[2]!==e2i) begin errors++; $display("FAIL N4[2]"); end
            if (out4_real[3]!==e3r||out4_imag[3]!==e3i) begin errors++; $display("FAIL N4[3]"); end
        end
    endtask

    // Test N=8
    task test8;
        input longint i0r,i0i,i1r,i1i,i2r,i2i,i3r,i3i,i4r,i4i,i5r,i5i,i6r,i6i,i7r,i7i;
        input longint w0r,w0i,w1r,w1i,w2r,w2i,w3r,w3i;
        input longint e0r,e0i,e1r,e1i,e2r,e2i,e3r,e3i,e4r,e4i,e5r,e5i,e6r,e6i,e7r,e7i;
        begin
            in8_real[0]=i0r[7:0]; in8_imag[0]=i0i[7:0];
            in8_real[1]=i1r[7:0]; in8_imag[1]=i1i[7:0];
            in8_real[2]=i2r[7:0]; in8_imag[2]=i2i[7:0];
            in8_real[3]=i3r[7:0]; in8_imag[3]=i3i[7:0];
            in8_real[4]=i4r[7:0]; in8_imag[4]=i4i[7:0];
            in8_real[5]=i5r[7:0]; in8_imag[5]=i5i[7:0];
            in8_real[6]=i6r[7:0]; in8_imag[6]=i6i[7:0];
            in8_real[7]=i7r[7:0]; in8_imag[7]=i7i[7:0];
            w8_real[0]=w0r[7:0]; w8_imag[0]=w0i[7:0];
            w8_real[1]=w1r[7:0]; w8_imag[1]=w1i[7:0];
            w8_real[2]=w2r[7:0]; w8_imag[2]=w2i[7:0];
            w8_real[3]=w3r[7:0]; w8_imag[3]=w3i[7:0];
            #1;
            checks += 16;
            if (out8_real[0]!==e0r||out8_imag[0]!==e0i) begin errors++; $display("FAIL N8[0]"); end
            if (out8_real[1]!==e1r||out8_imag[1]!==e1i) begin errors++; $display("FAIL N8[1]"); end
            if (out8_real[2]!==e2r||out8_imag[2]!==e2i) begin errors++; $display("FAIL N8[2]"); end
            if (out8_real[3]!==e3r||out8_imag[3]!==e3i) begin errors++; $display("FAIL N8[3]"); end
            if (out8_real[4]!==e4r||out8_imag[4]!==e4i) begin errors++; $display("FAIL N8[4]"); end
            if (out8_real[5]!==e5r||out8_imag[5]!==e5i) begin errors++; $display("FAIL N8[5]"); end
            if (out8_real[6]!==e6r||out8_imag[6]!==e6i) begin errors++; $display("FAIL N8[6]"); end
            if (out8_real[7]!==e7r||out8_imag[7]!==e7i) begin errors++; $display("FAIL N8[7]"); end
        end
    endtask

    longint e0r,e0i,e1r,e1i,e2r,e2i,e3r,e3i,e4r,e4i,e5r,e5i,e6r,e6i,e7r,e7i;
    longint i0r,i0i,i1r,i1i,i2r,i2i,i3r,i3i,i4r,i4i,i5r,i5i,i6r,i6i,i7r,i7i;
    longint w0r,w0i,w1r,w1i,w2r,w2i,w3r,w3i;
    integer t;

    initial begin
        $display("=== FFT Stage N=4 STRIDE=%0d, N=8 STRIDE=%0d ===", STRIDE4, STRIDE8);

        // N=4 Directed
        test4(0,0,0,0,0,0,0,0, 0,0,0,0, 0,0,0,0,0,0,0,0);
        test4(1,0,2,0,3,0,4,0, 1,0,1,0, 2,0,3,0,-1,0,-1,0);
        test4(10,0,20,0,30,0,40,0, 1,0,1,0, 20,0,30,0,-10,0,-10,0);
        test4(127,0,-128,0,127,0,-128,0, 1,0,1,0, s64(254>>1,OUT_W),0,s64(-256>>1,OUT_W),0,0,0,0,0);

        // N=8 Directed
        test8(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
              0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
        test8(1,0,2,0,3,0,4,0,5,0,6,0,7,0,8,0, 1,0,1,0,1,0,1,0,
              s64(6>>1,OUT_W),0,s64(8>>1,OUT_W),0,s64(10>>1,OUT_W),0,s64(12>>1,OUT_W),0,
              s64(-4>>1,OUT_W),0,s64(-4>>1,OUT_W),0,s64(-4>>1,OUT_W),0,s64(-4>>1,OUT_W),0);

        // N=4 Random
        $display("--- N=4 Random (2000) ---");
        for (t=0; t<2000; t++) begin
            i0r=($urandom%256)-128; i0i=($urandom%256)-128;
            i1r=($urandom%256)-128; i1i=($urandom%256)-128;
            i2r=($urandom%256)-128; i2i=($urandom%256)-128;
            i3r=($urandom%256)-128; i3i=($urandom%256)-128;
            w0r=($urandom%256)-128; w0i=($urandom%256)-128;
            w1r=($urandom%256)-128; w1i=($urandom%256)-128;
            bfly(i0r,i0i,i2r,i2i,w0r,w0i,e0r,e0i,e2r,e2i);
            bfly(i1r,i1i,i3r,i3i,w1r,w1i,e1r,e1i,e3r,e3i);
            test4(i0r,i0i,i1r,i1i,i2r,i2i,i3r,i3i, w0r,w0i,w1r,w1i, e0r,e0i,e1r,e1i,e2r,e2i,e3r,e3i);
        end

        // N=8 Random
        $display("--- N=8 Random (1000) ---");
        for (t=0; t<1000; t++) begin
            i0r=($urandom%256)-128; i0i=($urandom%256)-128;
            i1r=($urandom%256)-128; i1i=($urandom%256)-128;
            i2r=($urandom%256)-128; i2i=($urandom%256)-128;
            i3r=($urandom%256)-128; i3i=($urandom%256)-128;
            i4r=($urandom%256)-128; i4i=($urandom%256)-128;
            i5r=($urandom%256)-128; i5i=($urandom%256)-128;
            i6r=($urandom%256)-128; i6i=($urandom%256)-128;
            i7r=($urandom%256)-128; i7i=($urandom%256)-128;
            w0r=($urandom%256)-128; w0i=($urandom%256)-128;
            w1r=($urandom%256)-128; w1i=($urandom%256)-128;
            w2r=($urandom%256)-128; w2i=($urandom%256)-128;
            w3r=($urandom%256)-128; w3i=($urandom%256)-128;
            bfly(i0r,i0i,i4r,i4i,w0r,w0i,e0r,e0i,e4r,e4i);
            bfly(i1r,i1i,i5r,i5i,w1r,w1i,e1r,e1i,e5r,e5i);
            bfly(i2r,i2i,i6r,i6i,w2r,w2i,e2r,e2i,e6r,e6i);
            bfly(i3r,i3i,i7r,i7i,w3r,w3i,e3r,e3i,e7r,e7i);
            test8(i0r,i0i,i1r,i1i,i2r,i2i,i3r,i3i,i4r,i4i,i5r,i5i,i6r,i6i,i7r,i7i,
                  w0r,w0i,w1r,w1i,w2r,w2i,w3r,w3i,
                  e0r,e0i,e1r,e1i,e2r,e2i,e3r,e3i,e4r,e4i,e5r,e5i,e6r,e6i,e7r,e7i);
        end

        $display("\n=== %0d checks, %0d errors ===", checks, errors);
        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** TEST FAILED ***");
        $finish;
    end

endmodule
`default_nettype wire
