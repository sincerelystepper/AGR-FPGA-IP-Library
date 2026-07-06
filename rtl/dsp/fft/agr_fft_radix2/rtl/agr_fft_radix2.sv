`default_nettype none
`timescale 1ns/1ps

module agr_fft_radix2 #(
    parameter int N      = 8,
    parameter int DATA_W = 16,
    parameter int TW_W   = 16,
    parameter int OUT_W  = 32,
    parameter int FRAC_W = 14
) (
    input  logic signed [DATA_W-1:0] in_real  [N],
    input  logic signed [DATA_W-1:0] in_imag  [N],
    output logic signed [OUT_W-1:0]  out_real [N],
    output logic signed [OUT_W-1:0]  out_imag [N],
    output logic                     overflow
);

    initial begin
        if (N < 4)            $fatal(1, "N must be >= 4");
        if ((N & (N-1)) != 0) $fatal(1, "N must be power of 2");
        if (DATA_W < 1)       $fatal(1, "DATA_W must be >= 1");
        if (TW_W < 2)         $fatal(1, "TW_W must be >= 2");
        if (OUT_W < 1)        $fatal(1, "OUT_W must be >= 1");
    end

    localparam int STAGES = $clog2(N);

    // ===================================================================
    // Twiddle ROM (unscaled integer for N=8, parameterized for general N)
    // ===================================================================
    function automatic int tw_real(int k);
        // For N=8: round(cos(2πk/8)) = [1,1,0,-1]
        // For general N, add cases or use ROM module
        case (N)
            8:  case(k) 0: return 1;  1: return 1;  2: return 0;  3: return -1; default: return 0; endcase
            16: case(k) 0: return 1;  1: return 1;  2: return 1;  3: return 0;
                         4: return 0;  5: return 0;  6: return -1; 7: return -1; default: return 0; endcase
            default: return 0;
        endcase
    endfunction

    function automatic int tw_imag(int k);
        case (N)
            8:  case(k) 0: return 0;  1: return -1; 2: return -1; 3: return -1; default: return 0; endcase
            16: case(k) 0: return 0;  1: return 0;  2: return -1; 3: return -1;
                         4: return -1; 5: return -1; 6: return -1; 7: return -1; default: return 0; endcase
            default: return 0;
        endcase
    endfunction

    // ===================================================================
    // Inter-stage pipelines: STAGES+1 separate wire arrays
    // Stage 0 input = padded input
    // Stage s output = pipes[s+1]
    // Final output = pipes[STAGES]
    // ===================================================================
    wire signed [OUT_W-1:0] pipes_r [STAGES+1][N];
    wire signed [OUT_W-1:0] pipes_i [STAGES+1][N];

    // Pad inputs into pipes[0]
    genvar p;
    for (p = 0; p < N; p = p + 1) begin : gen_pad
        assign pipes_r[0][p] = {{OUT_W-DATA_W{in_real[p][DATA_W-1]}}, in_real[p]};
        assign pipes_i[0][p] = {{OUT_W-DATA_W{in_imag[p][DATA_W-1]}}, in_imag[p]};
    end

    // ===================================================================
    // Generate STAGES - each writes to its OWN pipes[s+1]
    // ===================================================================
    genvar s;
    for (s = 0; s < STAGES; s = s + 1) begin : gen_stage
        localparam int STRIDE = N >> (s + 1);
        localparam int N_BFLY = N / 2;  // Always N/2 butterflies per stage

        // Generate N/2 butterflies within this stage
        genvar b;
        for (b = 0; b < N_BFLY; b = b + 1) begin : gen_bfly
            // Which group does this butterfly belong to?
            // Groups of size 2*STRIDE. Butterfly b is in group (b / STRIDE).
            // Within group, offset = b % STRIDE.
            localparam int group     = b / STRIDE;
            localparam int offset    = b % STRIDE;
            localparam int idx_a     = group * 2 * STRIDE + offset;
            localparam int idx_b     = idx_a + STRIDE;
            localparam int tw_idx    = (b << s) % (N/2);
            localparam int TW_R      = tw_real(tw_idx);
            localparam int TW_I      = tw_imag(tw_idx);

            // Butterfly computation
            wire signed [OUT_W-1:0] sum_r = (pipes_r[s][idx_a] + pipes_r[s][idx_b]) >>> 1;
            wire signed [OUT_W-1:0] sum_i = (pipes_i[s][idx_a] + pipes_i[s][idx_b]) >>> 1;
            wire signed [OUT_W-1:0] diff_r = pipes_r[s][idx_a] - pipes_r[s][idx_b];
            wire signed [OUT_W-1:0] diff_i = pipes_i[s][idx_a] - pipes_i[s][idx_b];
            wire signed [OUT_W-1:0] prod_r = (diff_r*TW_R - diff_i*TW_I) >>> 1;
            wire signed [OUT_W-1:0] prod_i = (diff_r*TW_I + diff_i*TW_R) >>> 1;

            // Drive outputs ONLY for this butterfly's two indices
            // X0 goes to idx_a, X1 goes to idx_b
            assign pipes_r[s+1][idx_a] = sum_r;
            assign pipes_i[s+1][idx_a] = sum_i;
            assign pipes_r[s+1][idx_b] = prod_r;
            assign pipes_i[s+1][idx_b] = prod_i;
        end
    end

    // ===================================================================
    // Final output = pipes[STAGES]
    // ===================================================================
    genvar o;
    for (o = 0; o < N; o = o + 1) begin : gen_out
        assign out_real[o] = pipes_r[STAGES][o];
        assign out_imag[o] = pipes_i[STAGES][o];
    end

    assign overflow = 1'b0;

endmodule
`default_nettype wire
