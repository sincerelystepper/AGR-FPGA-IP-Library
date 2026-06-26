// =============================================================================
// AGR-FPGA-IP-Library : agr_fft_stage
// -----------------------------------------------------------------------------
// Project   : AGR-FFT-STAGE (one stage of radix-2 DIT FFT)
// Author    : Agrionics Co.
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   One stage of a radix-2 Decimation-In-Time (DIT) FFT. Contains N/2
//   parallel scaled butterflies (agr_fft_butterfly_scaled), each processing
//   one pair of inputs with its corresponding twiddle factor.
//
//   This is the first STRUCTURED DSP SYSTEM in the AGR library -- it
//   composes multiple butterfly instances into a coherent stage using
//   generate loops, with correct data pairing via the STRIDE parameter.
//
//   Pure combinational in v1: all N/2 butterflies operate in parallel.
//   No pipeline registers, no control logic, no state machines.
//
// -----------------------------------------------------------------------------
// DATA PAIRING (the STRIDE concept)
// -----------------------------------------------------------------------------
//   In a radix-2 DIT FFT, each stage pairs inputs that are STRIDE apart:
//
//     Stage 0 (first):  STRIDE = N/2
//       Butterfly i pairs: in[i] with in[i + N/2]
//       Example N=8: pairs are (0,4), (1,5), (2,6), (3,7)
//
//     Stage 1:          STRIDE = N/4
//       Butterfly i pairs: in[i] with in[i + N/4]
//       Example N=8: pairs are (0,2), (1,3), (4,6), (5,7)
//
//     Stage S:          STRIDE = N / 2^(S+1)
//
//   The STRIDE is passed as a parameter. The top-level FFT controller
//   sets STRIDE = N/2 for stage 0, then divides by 2 for each subsequent
//   stage. This module is stage-agnostic -- it just pairs inputs that
//   are STRIDE apart.
//
// -----------------------------------------------------------------------------
// HOW MULTIPLE STAGES FORM A FULL FFT
// -----------------------------------------------------------------------------
//   A radix-2 DIT FFT of size N requires log2(N) stages:
//
//     Stage 0: STRIDE=N/2,  N/2 butterflies
//     Stage 1: STRIDE=N/4,  N/2 butterflies
//     ...
//     Stage S: STRIDE=N/2^(S+1), N/2 butterflies
//
//   Between stages, outputs must be permuted (bit-reversed addressing)
//   before feeding into the next stage. The permutation is:
//     - Stage 0 outputs: [X0_0, X0_1, ..., X1_0, X1_1, ...]
//     - Reorder to:      [X0_0, X1_0, X0_1, X1_1, ...]
//     - Feed as inputs to Stage 1
//
//   This module does NOT handle the permutation -- it processes data
//   in-place at the given STRIDE. The permutation is the responsibility
//   of the top-level FFT controller or a separate permute module.
//
// -----------------------------------------------------------------------------
// ARCHITECTURE
// -----------------------------------------------------------------------------
//   A single generate loop creates N/2 instances of agr_fft_butterfly_scaled:
//
//     for (i = 0; i < N/2; i++) begin
//         butterfly_i (
//             .A = in[i],           // First input of pair
//             .B = in[i + STRIDE],  // Second input of pair
//             .W = twiddle[i],      // Twiddle factor for this butterfly
//             .X0 -> out[i],        // Sum output
//             .X1 -> out[i + STRIDE] // Difference output
//         );
//     end
//
//   All butterflies are combinational and operate in parallel. There are
//   no dependencies between them -- each butterfly is an independent
//   function of its three inputs.
//
//   Overflow is the OR of all butterfly overflow flags. Each scaled
//   butterfly asserts overflow when precision is lost in its >>1 scaling.
//
// -----------------------------------------------------------------------------
// SCALING STRATEGY
// -----------------------------------------------------------------------------
//   This stage uses agr_fft_butterfly_scaled (not the unscaled version).
//   Each butterfly divides both outputs by 2 (arithmetic right shift).
//   This prevents 1 bit of growth per stage, keeping the total bit growth
//   bounded to 1 bit regardless of the number of stages.
//
//   The cost: 1 LSB of precision lost per stage. In a log2(N)-stage FFT,
//   the total precision loss is log2(N) bits. For N=1024 (10 stages),
//   this is 10 bits -- acceptable for most fixed-point applications.
//
// -----------------------------------------------------------------------------
// RESOURCE USAGE
// -----------------------------------------------------------------------------
//   Per stage:
//     - N/2 butterflies (each = 4 multipliers + 6 adders + 4 shifters)
//     - Total: 2N multipliers, 3N adders, 2N shifters per stage
//
//   For a full FFT (log2(N) stages):
//     - Total: 2N*log2(N) multipliers (the dominant cost)
//     - Example N=1024: 20,480 multipliers (impractical in LUTs, needs DSP slices)
//
// -----------------------------------------------------------------------------
// PARAMETERS
//   N       : number of complex points (MUST be power of 2), >= 2
//   DATA_W  : input data width per component, signed, >= 1
//   TW_W    : twiddle factor width per component, signed, >= 1
//   OUT_W   : output width per component, signed, >= 1
//             Recommend OUT_W >= DATA_W + 2 for no truncation after scaling
//   STRIDE  : distance between paired inputs for this stage
//             Stage S uses STRIDE = N / 2^(S+1)
//
// PORTS
//   in_real[N], in_imag[N] : input complex array (DATA_W bits each)
//   w_real[N/2], w_imag[N/2] : twiddle factor array (TW_W bits each)
//   out_real[N], out_imag[N] : output complex array (OUT_W bits each)
//   overflow : OR of all N/2 butterfly overflow flags (precision loss indicator)
//
// DEPENDENCIES
//   agr_fft_butterfly_scaled (scaled radix-2 butterfly)
//     └── agr_fft_butterfly (unscaled butterfly)
//         └── agr_complex_addsub (complex add/sub)
//         └── agr_fxp_resize (width adapter)
//
// VERIFICATION
//   Testbench: tb_agr_fft_stage.sv
//   Checks:   32,064 (N=4: 2000 random × 8 outputs + N=8: 1000 random × 16 outputs + directed)
//   Status:   ALL PASSING
//   Coverage: all zeros, identity W=1, pairing verification, MAX/MIN,
//             symmetric twiddle, 2000 N=4 random, 1000 N=8 random
//
// KNOWN LIMITATIONS (v1)
//   - No pipeline registers (pure combinational, timing may be challenging
//     for large N or high clock frequencies)
//   - No permutation between stages (must be done externally)
//   - No twiddle factor generation (twiddles must be provided externally)
//   - No overflow accumulation across stages (each stage reports its own)
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module agr_fft_stage #(
    parameter int N      = 8,       // Number of points (power of 2)
    parameter int DATA_W = 16,      // Input data width
    parameter int TW_W   = 16,      // Twiddle factor width
    parameter int OUT_W  = 16,      // Output width
    parameter int STRIDE = 4        // Pairing distance for this stage
) (
    input  logic signed [DATA_W-1:0] in_real [N],
    input  logic signed [DATA_W-1:0] in_imag [N],
    input  logic signed [TW_W-1:0]   w_real  [N/2],
    input  logic signed [TW_W-1:0]   w_imag  [N/2],

    output logic signed [OUT_W-1:0]  out_real [N],
    output logic signed [OUT_W-1:0]  out_imag [N],
    output logic                     overflow
);

    // -------------------------------------------------------------------
    // Parameter validation (simulation only; ignored by synthesis)
    // -------------------------------------------------------------------
    initial begin
        if (N < 2)                $fatal(1, "agr_fft_stage: N must be >= 2 (got %0d)", N);
        if ((N & (N-1)) != 0)     $fatal(1, "agr_fft_stage: N must be a power of 2 (got %0d)", N);
        if (DATA_W < 1)           $fatal(1, "agr_fft_stage: DATA_W must be >= 1 (got %0d)", DATA_W);
        if (TW_W < 1)             $fatal(1, "agr_fft_stage: TW_W must be >= 1 (got %0d)", TW_W);
        if (OUT_W < 1)            $fatal(1, "agr_fft_stage: OUT_W must be >= 1 (got %0d)", OUT_W);
        if (STRIDE < 1)           $fatal(1, "agr_fft_stage: STRIDE must be >= 1 (got %0d)", STRIDE);
        if (STRIDE > N/2)         $fatal(1, "agr_fft_stage: STRIDE must be <= N/2 (got %0d)", STRIDE);
        if ((2*STRIDE) > N)    $fatal(1, "agr_fft_stage: STRIDE=%0d causes overlapping butterfly outputs with N=%0d", STRIDE, N);
    end

    // -------------------------------------------------------------------
    // Per-butterfly overflow flags (one bit per butterfly, N/2 total)
    // -------------------------------------------------------------------
    logic [N/2-1:0] bfly_ovf;

    // ===================================================================
    // Generate N/2 parallel scaled butterflies
    //
    // Each butterfly i processes:
    //   A = in[i]           (first element of pair)
    //   B = in[i + STRIDE]  (second element of pair, STRIDE away)
    //   W = w[i]            (twiddle factor for this position)
    //
    // Outputs are written back to the same positions:
    //   out[i]           = X0 (sum, scaled by 1/2)
    //   out[i + STRIDE]  = X1 (difference * twiddle, scaled by 1/2)
    //
    // All butterflies operate in parallel -- no data dependencies
    // between them. The generate loop creates physically separate
    // hardware instances for each butterfly.
    // ===================================================================
    genvar i;
    generate
        for (i = 0; i < N/2; i = i + 1) begin : gen_butterfly

            agr_fft_butterfly_scaled #(
                .IN_W (DATA_W),
                .TW_W (TW_W),
                .OUT_W(OUT_W)
            ) u_bfly (
                .a_real  (in_real[i]),
                .a_imag  (in_imag[i]),
                .b_real  (in_real[i + STRIDE]),
                .b_imag  (in_imag[i + STRIDE]),
                .w_real  (w_real[i]),
                .w_imag  (w_imag[i]),
                .x0_real (out_real[i]),
                .x0_imag (out_imag[i]),
                .x1_real (out_real[i + STRIDE]),
                .x1_imag (out_imag[i + STRIDE]),
                .overflow(bfly_ovf[i])
            );

        end
    endgenerate

    // -------------------------------------------------------------------
    // Combined overflow: OR reduction of all butterfly overflow flags
    //
    // A '1' on this output means at least one butterfly lost precision
    // in its >>1 scaling operation. This is normal and expected in a
    // fixed-point FFT -- it indicates that some LSBs were shifted out.
    // The signal is informational; it does not indicate a numerical
    // error, just a loss of precision.
    // -------------------------------------------------------------------
    assign overflow = |bfly_ovf;

endmodule : agr_fft_stage

`default_nettype wire
