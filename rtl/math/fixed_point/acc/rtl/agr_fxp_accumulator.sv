`timescale 1ns/1ps
// =============================================================================
// AGR-FPGA-IP-Library : agr_fxp_accumulator
// -----------------------------------------------------------------------------
// Project   : AGR-FXP-ACCUMULATOR (stateful fixed-point accumulator)
// Author    : Agrionics Co.
// Standard  : IEEE 1800-2017 SystemVerilog
// -----------------------------------------------------------------------------
// PURPOSE
//   Stateful accumulator: acc[n+1] = acc[n] + in_val (when enabled).
//   This is the registered companion to agr_fxp_mac - the MAC produces
//   acc_next, and this module registers it while adding control signals
//   (clear, load, enable) for real DSP pipeline integration.
//
//   First stateful block in the AGR DSP library. All previous cores
//   (addsub, mult, resize, round, MAC) are purely combinational.
//
// -----------------------------------------------------------------------------
// CONTROL PRIORITY (strict, documented)
// -----------------------------------------------------------------------------
//   rst > clear > load > enable > hold
//
//   This ordering is deliberate:
//   - rst:   safety override, returns to known state
//   - clear: software/control-plane zeroing without full reset
//   - load:  preload a seed value (e.g. bias term, initial condition)
//   - enable: normal accumulation step
//   - hold:   pipeline stall / clock-gating emulation
//
// -----------------------------------------------------------------------------
// NUMERICAL BEHAVIOR
// -----------------------------------------------------------------------------
//   Addition is performed at ACC_W+1 bits internally (sign-extended
//   operands). Overflow is detected on the exact extended sum BEFORE
//   truncation. This is the same "carry full precision, check once"
//   strategy used in agr_fxp_mac.
//
//   When USE_SATURATE=1 and overflow occurs:
//     - Positive overflow -> clamp to MAX =  2^(ACC_W-1) - 1
//     - Negative overflow -> clamp to MIN = -2^(ACC_W-1)
//   When USE_SATURATE=0:
//     - Standard two's complement wrap (low ACC_W bits of exact sum)
//
//   The overflow flag is sticky for one cycle only (purely combinational
//   from the current operation). It does NOT latch - the caller is
//   responsible for capturing it if needed.
//
// -----------------------------------------------------------------------------
// INTEGRATION WITH agr_fxp_mac
// -----------------------------------------------------------------------------
//   Typical DSP pipeline:
//     agr_fxp_mac (.a, .b, .acc(accumulator.acc), .acc_next, .overflow)
//     agr_fxp_accumulator (.in_val(mac.acc_next), .acc(accumulator.acc))
//
//   Or with rounding between MAC and accumulator:
//     agr_fxp_mac -> agr_fxp_round -> agr_fxp_accumulator
//
// -----------------------------------------------------------------------------
// PARAMETERS
//   ACC_W        : accumulator width, signed, >= 1
//   USE_SATURATE : 0 = wrap on overflow, 1 = saturate to MIN/MAX
//
// PORTS
//   clk      : system clock
//   rst      : synchronous reset (highest priority)
//   enable   : accumulate enable (acc = acc + in_val)
//   clear    : synchronous clear to zero
//   load     : load external value into accumulator
//   load_val : value to load when load=1
//   in_val   : value to add when enable=1
//   acc      : current accumulator value
//   overflow : overflow flag for the CURRENT operation
// =============================================================================

`default_nettype none

module agr_fxp_accumulator #(
    parameter int ACC_W        = 32,
    parameter bit USE_SATURATE = 1'b0
) (
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     enable,
    input  logic                     clear,
    input  logic                     load,
    input  logic signed [ACC_W-1:0]  load_val,

    input  logic signed [ACC_W-1:0]  in_val,

    output logic signed [ACC_W-1:0]  acc,
    output logic                     overflow
);

    // -------------------------------------------------------------------
    // Parameter validation
    // -------------------------------------------------------------------
    initial begin
        if (ACC_W < 1)
            $fatal(1, "agr_fxp_accumulator: ACC_W must be >= 1 (got %0d)", ACC_W);
    end

    // -------------------------------------------------------------------
    // Saturation constants
    // -------------------------------------------------------------------
    localparam logic signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};
    localparam logic signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};
    localparam logic signed [ACC_W:0]   ACC_MAX_EXT = {ACC_MAX[ACC_W-1], ACC_MAX};
    localparam logic signed [ACC_W:0]   ACC_MIN_EXT = {ACC_MIN[ACC_W-1], ACC_MIN};

    // -------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------
    logic signed [ACC_W-1:0] acc_reg;

    // -------------------------------------------------------------------
    // Next-state computation (combinational)
    // -------------------------------------------------------------------
    // Extended-width addition for exact overflow detection
    logic signed [ACC_W:0] acc_ext;
    logic signed [ACC_W:0] in_ext;
    logic signed [ACC_W:0] sum_ext;

    assign acc_ext = {acc_reg[ACC_W-1], acc_reg};
    assign in_ext  = {in_val[ACC_W-1], in_val};
    assign sum_ext = acc_ext + in_ext;

    // Overflow: sum exceeds ACC_W-bit signed range
    logic acc_overflow;
    assign acc_overflow = (sum_ext > ACC_MAX_EXT) || (sum_ext < ACC_MIN_EXT);

    // Next value based on control priority
    logic signed [ACC_W-1:0] next_acc;
    logic                    next_overflow;

    always_comb begin
        // Default: hold
        next_acc     = acc_reg;
        next_overflow = 1'b0;

        // Priority: rst > clear > load > enable > hold
        if (rst) begin
            next_acc     = '0;
            next_overflow = 1'b0;
        end else if (clear) begin
            next_acc     = '0;
            next_overflow = 1'b0;
        end else if (load) begin
            next_acc     = load_val;
            next_overflow = 1'b0;
        end else if (enable) begin
            if (USE_SATURATE && acc_overflow) begin
                next_acc = sum_ext[ACC_W] ? ACC_MIN : ACC_MAX;
            end else begin
                next_acc = sum_ext[ACC_W-1:0];
            end
            next_overflow = acc_overflow;
        end
        // else: hold (default)
    end

    // -------------------------------------------------------------------
    // Registered state
    // -------------------------------------------------------------------
    always_ff @(posedge clk) begin
        acc_reg  <= next_acc;
        overflow <= next_overflow;
    end

    // -------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------
    assign acc = acc_reg;

endmodule : agr_fxp_accumulator

`default_nettype wire
