
# Architecture — AGR SPI Bridge

## Overview

The module is eight sequential blocks, in the order they appear in
`rtl/agr_spi_bridge.sv`:

```
spi_csn ─┐
spi_sck ─┼─▶ [1] CDC sync ─▶ [2] bit engine ─▶ [3] byte latch ─▶ [4] FSM
spi_mosi─┘                                                         │
                                                                     ▼
                                                            [5] commit pipeline
                                                                     │
                                                                     ▼
                                              [6] transaction engine ──▶ bus_req/we/addr/wdata
                                                     ▲
                                          bus_rdata/bus_ready
                                                     │
                                                     ▼
spi_miso ◀── [8] TX shift engine ◀── [7] TX data staging
```

Blocks 1–6 form the **receive path** (SPI → bus). Blocks 7–8 form the
**transmit path** (bus → SPI), fed by `bus_rdata`/`bus_ready` from block 6.

## SPI transaction

See the README for the byte-level frame tables. At the FSM level, each
fully-received byte advances `state` by one step:

| State | Byte just received | Latched into | Next state |
|---|---|---|---|
| `S_IDLE` | `CMD` | `cmd_commit` (full byte; only bit 7 is later decoded) | `S_CMD` |
| `S_CMD` | `ADDR_H` | `addr_reg[15:8]` | `S_ADDR_H` |
| `S_ADDR_H` | `ADDR_L` | `addr_reg[7:0]` | `S_ADDR_L` |
| `S_ADDR_L` | `WDATA` (write only) | `wdata_reg` | `S_DATA` |
| `S_DATA` | (any further byte, same `CSN` window) | — | `S_IDLE` |

Note the latch table is keyed on the state *while the byte arrives*, not
the state it transitions to — e.g. `ADDR_H` is latched while `state ==
S_CMD`, one cycle before the FSM advances to `S_ADDR_H`.

`state` returning to `S_IDLE` from `S_DATA` on the next received byte is
what makes back-to-back frames within one continuous `CSN` low period
structurally possible (see README limitations) — it is not specifically
tested, but it falls out of the FSM naturally.

## Register interface

This is a minimal strobe handshake, not a formal bus protocol
(Wishbone/AXI-lite, etc.):

- **Write**: `bus_req=1, bus_we=1, bus_addr, bus_wdata` all valid for
  exactly one `clk` cycle. The peripheral is expected to capture them
  combinationally or on that same edge. `bus_ready` is not required for
  writes in the current implementation — the bridge does not wait for it
  on the write path.
- **Read**: `bus_req=1, bus_we=0, bus_addr` valid for one cycle. The
  bridge then holds `read_pending` until the peripheral returns
  `bus_rdata` together with a one-cycle `bus_ready` pulse — any number of
  cycles later, no timeout. `read_pending` is also cleared unconditionally
  on `cs_rise` (a new chip-select assertion), which silently drops an
  outstanding read if the master starts a new transaction before the
  peripheral answered.

## FSM

State encoding is a 3-bit enum (`typedef enum logic [2:0]`) with 5 named
values out of 8 possible encodings — see
[Known limitations](../README.md#known-limitations) regarding the 3
unreachable encodings and the existing `cs_rise` self-recovery path.

## CDC strategy

Each of `spi_csn`, `spi_sck`, `spi_mosi` has its own independent 3-bit
shift-register synchronizer (`cs_ff`, `sck_ff`, `mosi_ff`), clocked by
`clk`, with no shared logic between them:

```systemverilog
cs_ff <= {cs_ff[1:0], spi_csn};   // [0]=newest sample, [2]=oldest
```

Edge pulses compare the two *oldest* stages:

```systemverilog
wire cs_fall  = ~cs_ff[2] &  cs_ff[1];
wire cs_rise  =  cs_ff[2] & ~cs_ff[1];
```

**Naming note, important for anyone editing this file:** despite the
names, `cs_fall` is the wire that pulses when `spi_csn` has gone **high**
(transaction *ending*), and `cs_rise` pulses when `spi_csn` has gone
**low** (transaction *starting*). The same swap exists for `sck_rise`
(pulses on the physical SCK *falling* edge) and `sck_fall` (pulses on the
physical SCK *rising* edge). This was the root cause of a same-day bug:
the TX-path load logic was written assuming `cs_fall` meant "transaction
starting" (the intuitive reading of the name) and so never fired at the
right time — `spi_miso` stayed at `0` for the entire read-response phase.
The fix changed the two TX-path use sites to `cs_rise`; the bit-engine and
FSM, which already used `cs_rise`/`sck_rise` correctly (by accident of
consistent internal convention, not correct naming), were left alone.
Full writeup: [`verification.md`](verification.md#bug-history).

Renaming the four wires to match physical behavior is listed as future
work rather than done now, specifically to avoid touching logic that is
currently verified and working.

Empirically, the edge pulse for a given physical transition appears
within 2 synchronizer-settling `clk` cycles of that transition (measured
from the simulation waveform, not derived from a datasheet figure — see
[`timing.md`](timing.md) for the CDC margin this implies for `SCK`).

## Pipeline

Blocks 5 (`commit_raw` → `commit_strobe`) add two registered cycles
between "last frame byte received" and "`bus_req` asserted." This exists
purely to give the address/data latches (block 4, a separate `always_ff`
clocked the same edge) a settled cycle before the transaction engine reads
them — `addr_reg`/`wdata_reg` are valid by the time `commit_strobe` fires
two cycles later.

## Parameters

`ADDR_W` (default 16) and `DATA_W` (default 8) are declared on the module
but **not threaded through the internal frame logic** — see
[Known limitations](../README.md#known-limitations) in the README; this is
a real gap, verified with a Verilator parameter-override test, not a
caveat added out of caution.

## Resource expectations

Generated with `yosys -p "read_verilog -sv agr_spi_bridge.sv; synth_ice40 -top agr_spi_bridge; stat"`
(Yosys 0.33), default parameters, no I/O constraints, pre place-and-route:

| Cell type | Count | Notes |
|---|---|---|
| `SB_LUT4` | 39 | Combinational logic |
| `SB_DFFE` | 48 | Enabled flip-flops |
| `SB_DFFER` | 40 | Enabled, async-reset flip-flops |
| `SB_DFFR` | 14 | Async-reset flip-flops |
| `SB_DFFS` | 4 | Async-set flip-flops |
| `SB_CARRY` | 1 | Carry chain (the `bit_cnt + 1` increment) |
| **Total** | **146** | |

Flip-flop count (106 total across the four `SB_DFF*` variants) dominates
over LUT count (39), so the practical floor on an iCE40 device is roughly
**106 logic cells** (each iCE40 LC = 1 LUT4 + 1 DFF; only ~39 of those 106
LCs will also use their LUT). On an iCE40HX1K (1280 LCs) that's ~8% of the
device; on an iCE40HX8K (7680 LCs) it's under 2%. This is a synthesis-only
estimate — no place-and-route or Fmax figure has been generated, so no
timing-closure claim is made here (see [`timing.md`](timing.md) for what
*has* been measured: simulation-side CDC margin, not silicon Fmax).
