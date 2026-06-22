// =============================================================================
// AGR-FPGA-IP-Library : agr_fxp_round
// -----------------------------------------------------------------------------
// Project   : AGR-FXP-ROUND (fixed-point rounding core)
// Author    : Agrionics Co. | Kopano Maketekete
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   Converts a signed fixed-point value from IN_W bits to OUT_W bits using
//   configurable rounding modes, eliminating the quantization bias that
//   pure truncation introduces. Designed to integrate cleanly with
//   agr_fxp_resize in DSP pipelines (FIR, FFT, MAC accumulation).
//
//   Pure combinational in v1: no clock, no reset, no state.
//
// -----------------------------------------------------------------------------
// ROUNDING MODES (MODE parameter)
// -----------------------------------------------------------------------------
//   MODE = 0 : TRUNCATE
//     Baseline: simply drop the lower DROP_W bits. Identical behavior to
//     agr_fxp_resize in truncate mode. Zero-area overhead.
//     precision_loss = |dropped_bits (any discarded bit was non-zero).
//
//   MODE = 1 : ROUND_TO_NEAREST (round-half-up)
//     Add the half-way constant (2^(DROP_W-1)) before truncation.
//     Values >= half-way round up; values < half-way round down.
//     Symmetric for positive and negative values in two's complement.
//     Ties (drop == half) always round up.
//     precision_loss = (rounded output != pure truncation output).
//
//   MODE = 2 : ROUND_HALF_UP
//     Identical to ROUND_TO_NEAREST for two's complement unsigned drop
//     comparison. Ties round up. Small positive bias in symmetric data.
//
//   MODE = 3 : CONVERGENT (round-half-to-even, "banker's rounding")
//     Ties round to the nearest EVEN LSB. This eliminates the statistical
//     bias that ROUND_HALF_UP introduces. Critically important for:
//       - Repeated rounding in iterative algorithms
//       - FFT twiddle factor accumulation
//       - FIR filter coefficient quantization
//     Implementation: if drop > half, add 1; if drop == half, add keep[0].
//     Example (DROP_W=3, half=4):
//       drop=2 < 4        -> add 0
//       drop=6 > 4        -> add 1
//       drop=4 == half, keep[0]=1 (odd)  -> add 1 (round to even)
//       drop=4 == half, keep[0]=0 (even) -> add 0 (already even)
//
// -----------------------------------------------------------------------------
// ALIGNMENT MODES (ALIGN parameter)
// -----------------------------------------------------------------------------
//   ALIGN = 1 (MSB-aligned): Keep top OUT_W bits; drop bottom DROP_W bits.
//     This is the PRIMARY DSP case: reducing fractional precision while
//     preserving the integer range and sign. Rounding acts on the
//     discarded fractional bits (the DROP_W LSBs).
//
//   ALIGN = 0 (LSB-aligned): Keep bottom OUT_W bits; drop top DROP_W bits.
//     Used for integer narrowing. Rounding is NOT applied in this mode
//     (half-based rounding is meaningless for high-order magnitude bits).
//     Overflow detection follows agr_fxp_resize semantics.
//
// -----------------------------------------------------------------------------
// OVERFLOW / PRECISION_LOSS
// -----------------------------------------------------------------------------
//   overflow:
//     MSB-aligned: always 0 (sign and magnitude ordering preserved).
//     LSB-aligned: 1 if dropped MSBs are not pure sign-extension of the
//                  retained sign bit (same as agr_fxp_resize).
//
//   precision_loss:
//     TRUNCATE mode: 1 if any dropped bit was non-zero.
//     Rounding modes: 1 if rounded output differs from pure truncation
//                     (i.e., rounding changed the value).
//     No reduction: always 0.
//
// -----------------------------------------------------------------------------
// ARCHITECTURE (4 explicit stages, all combinational in v1)
// -----------------------------------------------------------------------------
//   Stage 0: Decomposition
//     - Split in_val into keep_bits (top OUT_W) and drop_bits (bottom DROP_W)
//     - Compute half-way constant = 2^(DROP_W-1)
//     - Extract keep_lsb for convergent mode
//
//   Stage 1: Rounding Decision
//     - Compute round_carry based on MODE and drop_bits vs half_const
//     - MSB-aligned only; LSB-aligned skips rounding
//
//   Stage 2: Apply Rounding
//     - Add round_carry at the DROP_W-th bit position to full-width value
//     - Handles carry propagation through keep bits
//
//   Stage 3: Truncation
//     - Extract OUT_W bits from rounded value (MSB or LSB per ALIGN)
//     - Passthrough/expansion when OUT_W >= IN_W
//
//   Stage 4: Flags + Output
//     - precision_loss: information-loss indicator
//     - overflow: magnitude/range error indicator
//     - out_val: final result
//
// -----------------------------------------------------------------------------
// DSP INTEGRATION
// -----------------------------------------------------------------------------
//   Designed to pair with agr_fxp_resize in pipeline chains:
//     agr_fxp_mult -> agr_fxp_round -> agr_fxp_resize -> downstream
//
//   Typical use: after a multiply produces a wide product, use agr_fxp_round
//   to round the fractional bits before agr_fxp_resize truncates to the
//   final datapath width. This eliminates the systematic negative bias
//   that pure truncation introduces in two's complement arithmetic.
//
// -----------------------------------------------------------------------------
// NUMERICAL PROPERTIES
// -----------------------------------------------------------------------------
//   - Correctly handles negative values in two's complement
//   - Rounding add is performed on full-width value before truncation
//   - Carry propagation into sign bit is handled (overflow flag)
//   - Tie cases (exact half-way) are resolved per MODE
//   - CONVERGENT mode eliminates bias: E[round(x)] = x for symmetric data
//
// -----------------------------------------------------------------------------
// PARAMETERS
//   IN_W   : input width, signed 2's complement, >= 1
//   OUT_W  : output width, signed 2's complement, >= 1
//   MODE   : 0=TRUNCATE, 1=ROUND_TO_NEAREST, 2=ROUND_HALF_UP, 3=CONVERGENT
//   ALIGN  : 0=LSB-aligned, 1=MSB-aligned (DSP default)
//
// PORTS
//   in_val         : signed input, IN_W bits
//   out_val        : signed output, OUT_W bits
//   overflow       : magnitude/range error flag
//   precision_loss : information-loss flag
// =============================================================================

`default_nettype none

module agr_fxp_round #(
    parameter int IN_W  = 16,
    parameter int OUT_W = 16,
    parameter bit [1:0] MODE  = 2'd0,
    parameter bit       ALIGN = 1'b1
) (
    input  logic signed [IN_W-1:0]  in_val,
    output logic signed [OUT_W-1:0] out_val,
    output logic                    overflow,
    output logic                    precision_loss
);

    // -------------------------------------------------------------------
    // Elaboration-time parameter sanity checks (simulation/lint only --
    // plain $fatal in an initial block with no clock/storage; ignored by
    // synthesis, generates no hardware).
    // -------------------------------------------------------------------
    initial begin
        if (IN_W < 1)
            $fatal(1, "agr_fxp_round: IN_W must be >= 1 (got %0d)", IN_W);
        if (OUT_W < 1)
            $fatal(1, "agr_fxp_round: OUT_W must be >= 1 (got %0d)", OUT_W);
    end

    // Derived constants
    localparam bit NEEDS_REDUCTION = (OUT_W < IN_W);
    localparam int DROP_W = NEEDS_REDUCTION ? (IN_W - OUT_W) : 0;

    // ===================================================================
    // STAGE 0: Decomposition
    // ===================================================================
    // Split input into keep_bits (bits that survive truncation) and
    // drop_bits (bits that are discarded). For MSB-aligned, drop_bits
    // are the low-order fractional bits. For LSB-aligned, drop_bits
    // are the high-order magnitude bits.
    //
    // half_const = 2^(DROP_W-1), the exact half-way threshold.
    // keep_lsb = LSB of keep_bits, used for convergent tie-breaking.
    // ===================================================================
    logic signed [OUT_W-1:0] keep_bits;
    logic [DROP_W-1:0]       drop_bits;
    logic [DROP_W-1:0]       half_const;
    logic                    keep_lsb;

    if (NEEDS_REDUCTION && DROP_W > 0 && ALIGN) begin : gen_decomp
        assign keep_bits  = in_val[IN_W-1 -: OUT_W];
        assign drop_bits  = in_val[DROP_W-1:0];
        assign half_const = 1'b1 << (DROP_W - 1);
        assign keep_lsb   = keep_bits[0];
    end else begin : gen_no_decomp
        assign keep_bits  = '0;
        assign drop_bits  = '0;
        assign half_const = '0;
        assign keep_lsb   = 1'b0;
    end

    // ===================================================================
    // STAGE 1: Rounding Decision
    // ===================================================================
    // Compute round_carry (1 = add 1 to the LSB of keep_bits).
    // Only applies for MSB-aligned reduction with DROP_W > 0.
    //
    // TRUNCATE:    never round
    // NEAREST:     round if drop >= half (ties round up)
    // HALF_UP:     round if drop >= half (ties round up)
    // CONVERGENT:  round if drop > half, OR drop == half AND keep[0]=1
    //              (ties round to even -- no statistical bias)
    // ===================================================================
    logic round_carry;

    always_comb begin
        round_carry = 1'b0;
        if (NEEDS_REDUCTION && DROP_W > 0 && ALIGN) begin
            case (MODE)
                2'd0: round_carry = 1'b0;
                2'd1: round_carry = (drop_bits >= half_const);
                2'd2: round_carry = (drop_bits >= half_const);
                2'd3: begin
                    if (drop_bits > half_const)
                        round_carry = 1'b1;
                    else if (drop_bits == half_const)
                        round_carry = keep_lsb;
                    else
                        round_carry = 1'b0;
                end
                default: round_carry = 1'b0;
            endcase
        end
    end

    // ===================================================================
    // STAGE 2: Apply Rounding
    // ===================================================================
    // Add round_carry at the DROP_W-th bit position to the full IN_W-bit
    // value, producing an (IN_W+1)-bit result to catch any carry out
    // of the sign bit. The addend is constructed as:
    //   round_addend = round_carry * 2^DROP_W
    //
    // This is done on the sign-extended input to guarantee correct
    // two's complement arithmetic for negative values.
    // ===================================================================
    logic signed [IN_W:0] rounded_full;
    logic signed [IN_W:0] round_addend;

    always_comb begin
        if (NEEDS_REDUCTION && DROP_W > 0 && round_carry) begin
            // Add 1 at the DROP_W-th bit position (LSB of keep bits)
            round_addend = signed'({1'b0, {IN_W{1'b0}}}) + (1 << DROP_W);
        end else begin
            round_addend = '0;
        end
    end

    assign rounded_full = signed'({in_val[IN_W-1], in_val}) + round_addend;

    // ===================================================================
    // STAGE 3: Truncation
    // ===================================================================
    // Extract OUT_W bits from the rounded full-width value.
    // MSB-aligned: take top OUT_W bits (drop low DROP_W bits).
    // LSB-aligned: take bottom OUT_W bits (drop high DROP_W bits).
    // No reduction: pass through in_val directly.
    // ===================================================================
    logic signed [OUT_W-1:0] candidate;

    always_comb begin
        if (NEEDS_REDUCTION) begin
            if (ALIGN)
                candidate = rounded_full[IN_W-1 -: OUT_W];
            else
                candidate = rounded_full[OUT_W-1:0];
        end else begin
            candidate = in_val[OUT_W-1:0];
        end
    end

    // ===================================================================
    // STAGE 4: Flags + Output
    // ===================================================================
    // precision_loss:
    //   TRUNCATE mode: any dropped bit was non-zero
    //   Rounding modes: rounded output differs from pure truncation
    //   No reduction: always 0
    //
    // overflow:
    //   MSB-aligned: always 0 (sign + magnitude ordering preserved)
    //   LSB-aligned: dropped MSBs not pure sign-extension of kept sign
    //   No reduction: always 0
    // ===================================================================
    logic signed [OUT_W-1:0] passthrough_val;

    always_comb begin
        if (OUT_W >= IN_W)
            passthrough_val = signed'(in_val);
        else if (ALIGN)
            passthrough_val = in_val[IN_W-1 -: OUT_W];
        else
            passthrough_val = in_val[OUT_W-1:0];
    end

    always_comb begin
        if (NEEDS_REDUCTION && MODE == 2'd0)
            precision_loss = (drop_bits != '0);
        else if (NEEDS_REDUCTION)
            precision_loss = (candidate !== passthrough_val);
        else
            precision_loss = 1'b0;
    end

    logic [DROP_W-1:0] dropped_msbs_ovf;
    logic kept_sign_bit_ovf;

    assign kept_sign_bit_ovf = rounded_full[OUT_W-1];
    assign dropped_msbs_ovf  = rounded_full[IN_W-1:OUT_W];

    if (NEEDS_REDUCTION && !ALIGN) begin : gen_overflow_lsb
        assign overflow = (dropped_msbs_ovf != {DROP_W{kept_sign_bit_ovf}});
    end else begin : gen_overflow_none
        assign overflow = 1'b0;
    end

    assign out_val = candidate;

endmodule : agr_fxp_round

`default_nettype wire
