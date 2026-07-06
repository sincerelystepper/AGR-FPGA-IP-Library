`default_nettype none
`timescale 1ns/1ps

module tb_agr_fft_radix2;
    localparam int N=8, DATA_W=16, TW_W=16, OUT_W=32, FRAC_W=14;

    logic signed [DATA_W-1:0] in_r [N], in_i [N];
    logic signed [OUT_W-1:0] out_r [N], out_i [N];
    logic ovf;
    int errors=0, checks=0;

    agr_fft_radix2 #(.N(N),.DATA_W(DATA_W),.TW_W(TW_W),.OUT_W(OUT_W),.FRAC_W(FRAC_W))
        dut(.in_real(in_r),.in_imag(in_i),.out_real(out_r),.out_imag(out_i),.overflow(ovf));

    function automatic longint s64(longint v, int w);
        longint m=(64'(1)<<w)-64'(1); v=v&m;
        if(v>=(64'(1)<<(w-1))) v=v-(64'(1)<<w);
        return v;
    endfunction

    // Correct DIT FFT golden model for N=8
    task golden_fft;
        input longint xr[8], xi[8];
        output longint Xr[8], Xi[8];
        longint wr[4], wi[4];
        longint ar, ai, br, bi, tr, ti;
        int b, s, n_bfly, base, tw;
        begin
            wr[0]=1; wi[0]=0;    wr[1]=1; wi[1]=-1;
            wr[2]=0; wi[2]=-1;   wr[3]=-1; wi[3]=-1;
            for(b=0;b<8;b++) begin Xr[b]=xr[b]; Xi[b]=xi[b]; end

            // Stage 0: stride=4, 4 butterflies
            for(b=0;b<4;b++) begin
                tw = b % 4;
                ar=Xr[b]; ai=Xi[b]; br=Xr[b+4]; bi=Xi[b+4];
                Xr[b]   = (ar+br) >> 1;  Xi[b]   = (ai+bi) >> 1;
                tr = (ar-br)*wr[tw] - (ai-bi)*wi[tw];
                ti = (ar-br)*wi[tw] + (ai-bi)*wr[tw];
                Xr[b+4] = tr >> 1;  Xi[b+4] = ti >> 1;
            end

            // Stage 1: stride=2, 4 butterflies (groups of 2)
            for(b=0;b<2;b++) begin
                tw = (b*2) % 4;
                ar=Xr[b]; ai=Xi[b]; br=Xr[b+2]; bi=Xi[b+2];
                Xr[b]   = (ar+br) >> 1;  Xi[b]   = (ai+bi) >> 1;
                tr = (ar-br)*wr[tw] - (ai-bi)*wi[tw];
                ti = (ar-br)*wi[tw] + (ai-bi)*wr[tw];
                Xr[b+2] = tr >> 1;  Xi[b+2] = ti >> 1;
            end
            for(b=4;b<6;b++) begin
                tw = ((b-4)*2) % 4;
                ar=Xr[b]; ai=Xi[b]; br=Xr[b+2]; bi=Xi[b+2];
                Xr[b]   = (ar+br) >> 1;  Xi[b]   = (ai+bi) >> 1;
                tr = (ar-br)*wr[tw] - (ai-bi)*wi[tw];
                ti = (ar-br)*wi[tw] + (ai-bi)*wr[tw];
                Xr[b+2] = tr >> 1;  Xi[b+2] = ti >> 1;
            end

            // Stage 2: stride=1, 4 butterflies (groups of 1)
            for(b=0;b<8;b+=2) begin
                tw = 0;
                ar=Xr[b]; ai=Xi[b]; br=Xr[b+1]; bi=Xi[b+1];
                Xr[b]   = (ar+br) >> 1;  Xi[b]   = (ai+bi) >> 1;
                tr = (ar-br)*wr[tw] - (ai-bi)*wi[tw];
                ti = (ar-br)*wi[tw] + (ai-bi)*wr[tw];
                Xr[b+1] = tr >> 1;  Xi[b+1] = ti >> 1;
            end
        end
    endtask

    longint xr[8], xi[8], Xr[8], Xi[8];
    integer i;

    initial begin
        $display("=== Radix-2 FFT N=%0d ===", N);

        $display("--- Impulse: x[0]=256 ---");
        for(i=0;i<8;i++) begin in_r[i]=(i==0)?256:0; in_i[i]=0; end
        #1;
        golden_fft('{256,0,0,0,0,0,0,0}, '{0,0,0,0,0,0,0,0}, Xr, Xi);
        for(i=0;i<8;i++) begin
            checks+=2;
            if(s64(out_r[i],OUT_W)!==Xr[i]) begin errors++; $display("FAIL r[%0d]: DUT=%d EXP=%d",i,out_r[i],Xr[i]); end
            if(s64(out_i[i],OUT_W)!==Xi[i]) begin errors++; $display("FAIL i[%0d]: DUT=%d EXP=%d",i,out_i[i],Xi[i]); end
        end

        $display("--- DC: all x[i]=100 ---");
        for(i=0;i<8;i++) begin in_r[i]=100; in_i[i]=0; end
        #1;
        golden_fft('{100,100,100,100,100,100,100,100}, '{0,0,0,0,0,0,0,0}, Xr, Xi);
        for(i=0;i<8;i++) begin
            checks+=2;
            if(s64(out_r[i],OUT_W)!==Xr[i]) begin errors++; $display("FAIL r[%0d]: DUT=%d EXP=%d",i,out_r[i],Xr[i]); end
            if(s64(out_i[i],OUT_W)!==Xi[i]) begin errors++; $display("FAIL i[%0d]: DUT=%d EXP=%d",i,out_i[i],Xi[i]); end
        end

        $display("\n=== %0d checks, %0d errors ===", checks, errors);
        if(errors==0) $display("*** ALL TESTS PASSED ***");
        else $display("*** TEST FAILED ***");
        $finish;
    end
endmodule
`default_nettype wire
