`default_nettype none
`timescale 1ns/1ps

module tb_agr_fft_butterfly;
    localparam int IN_W = 8, TW_W = 8, OUT_W = 32;
    logic signed [IN_W-1:0] ar, ai, br, bi;
    logic signed [TW_W-1:0] wr, wi;
    logic signed [OUT_W-1:0] x0r, x0i, x1r, x1i;
    logic ovf;
    int errors=0, checks=0;

    agr_fft_butterfly #(.IN_W(IN_W),.TW_W(TW_W),.OUT_W(OUT_W))
        dut(.a_real(ar),.a_imag(ai),.b_real(br),.b_imag(bi),.w_real(wr),.w_imag(wi),
            .x0_real(x0r),.x0_imag(x0i),.x1_real(x1r),.x1_imag(x1i),.overflow(ovf));

    task test; input longint a,b,c,d,e,f,xr,xi,yr,yi; begin
        ar=a[7:0];ai=b[7:0];br=c[7:0];bi=d[7:0];wr=e[7:0];wi=f[7:0];#1;checks+=4;
        if(x0r!==xr||x0i!==xi||x1r!==yr||x1i!==yi) begin errors++;
            $display("FAIL: X0e(%d+j%d) X0g(%d+j%d) X1e(%d+j%d) X1g(%d+j%d)",xr,xi,x0r,x0i,yr,yi,x1r,x1i);
        end
    end endtask

    integer i; longint sr,si,dr,di;
    initial begin
        $display("=== FFT Butterfly OUT_W=%0d ===", OUT_W);
        test(1,0,1,0,1,0, 2,0, 0,0);
        test(2,3,4,5,1,0, 6,8, -2,-2);
        test(1,0,0,0,0,1, 1,0, 0,1);
        test(5,3,5,3,1,0, 10,6, 0,0);
        for(i=0;i<2000;i++) begin
            ar=($urandom%256)-128; ai=($urandom%256)-128;
            br=($urandom%256)-128; bi=($urandom%256)-128;
            wr=($urandom%256)-128; wi=($urandom%256)-128;
            sr=ar+br; si=ai+bi;
            dr=ar-br; di=ai-bi;
            test(ar,ai,br,bi,wr,wi, sr,si, dr*wr-di*wi, dr*wi+di*wr);
        end
        $display("=== %0d checks, %0d errors ===",checks,errors);
        if(errors==0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
`default_nettype wire
