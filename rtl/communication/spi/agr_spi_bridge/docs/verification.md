
# Verification — AGR SPI Bridge

| | |
|---|---|
| Simulator | Verilator |
| Host language | C++17 |
| Self-checking | Yes — pass/fail printed to stdout, no manual waveform reading required |
| Waveform | VCD (`waveforms/wave.vcd`, regenerated via `make wave`) |
| Lint | Verilator `-Wall` |
| Synthesis check | Yosys 0.33, `synth_ice40` |
| Regression | **PASS** (WRITE + READ) |

## What the testbench verifies

`tb/tb.cpp` drives two transactions against the DUT and checks the result
in C++, not in waveform:

- **WRITE**: sends `CMD=0x80, ADDR_H=0x12, ADDR_L=0x34, WDATA=0xAB` over
  MOSI, then scans 200 cycles after `CSN` releases for
  `bus_req && bus_we && bus_addr==0x1234 && bus_wdata==0xAB`.
- **READ**: sends `CMD=0x00, ADDR_H=0x12, ADDR_L=0x34` in transaction A (the
  host model answers any observed read request with `bus_rdata=0xA5` plus a
  one-cycle `bus_ready`), waits 200 cycles, then opens transaction B and
  shifts a dummy byte while sampling `spi_miso`, checking the result equals
  `0xA5`.

This validates: CDC pass-through, byte framing, address/data latch
correctness, the write-commit pipeline, the read bus-request path, and the
two-transaction read-back path end to end.

## How failures are detected

Plain boolean flags compared against expected constants
(`wp`/`rp` in `tb.cpp`), printed as `PASS`/`FAIL`. No assertion library, no
UVM, no formal properties — this is a directed test, not a constrained-random
or formally verified core.

## Corner cases covered

- Write commit timing relative to the 4-byte frame boundary.
- Read address latch timing relative to the 3-byte frame boundary.
- CDC synchronizer settling across a realistic (40×) oversampling ratio.
- CDC margin boundary, swept down to find the actual minimum (see
  [`timing.md`](timing.md)) — 6× oversampling is the simulated floor for
  reads.

## Corner cases NOT covered

- Parameter values other than the default `ADDR_W=16`, `DATA_W=8` (see
  README limitations — overriding either currently produces width-mismatch
  warnings, not a working alternate configuration).
- `CPOL=1` (idle-high SCK), or strict SPI Mode 0/3 half-period setup/hold
  timing.
- Back-to-back multi-frame transactions within one continuous `CSN`
  assertion.
- A peripheral that never returns `bus_ready` (no timeout exists; untested
  by construction — there's nothing to assert against).
- Reset pulse-width minimums.
- Read transaction B starting *before* `bus_ready` has landed (the "stale
  data" / "MISO at last value" path described in the README is inferred
  from reading the RTL, not exercised by a directed test).

## Lint results

`verilator --lint-only -Wall agr_spi_bridge.sv` (i.e. *without* the
`-Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE` suppressions `build.sh` normally
applies, to see everything once):

| Finding | Location | Disposition |
|---|---|---|
| `UNUSEDSIGNAL`: `rx_shift[7]` unused | bit engine | Benign — `rx_byte` is built directly from `rx_shift[6:0]` + the incoming bit; the MSB of the shift register is never read. Cosmetic. |
| `UNUSEDSIGNAL`: `cmd_commit[6:0]` unused | byte latch | Intentional — only bit 7 (R/W select) is decoded anywhere. Bits `[6:0]` are reserved for future opcodes; document, don't fix. |
| `UNUSEDSIGNAL`: `read_buffer` entirely unused | transaction engine | **Real dead code.** Written on reset and on every `bus_ready`, never read by anything (confirmed by `grep -n read_buffer`, 3 hits: declaration + 2 writes, 0 reads). The actual read-data path is `tx_data_reg`/`tx_data_valid`, latched independently in the TX-staging block. Recommend deleting `read_buffer`. |
| `CASEINCOMPLETE`: FSM transition `case(state)` | FSM | Intentional non-exhaustive case (3-bit encoding, 5 of 8 values named). `cs_rise` unconditionally forces `state <= S_IDLE` ahead of the case statement, so any unreachable encoding self-heals on the next chip-select assertion. An explicit `default:` is still recommended hardening, not a correctness requirement. |
| `CASEINCOMPLETE`: addr/data latch `case(state)` | latch | Intentional — `S_IDLE`/`S_DATA` correctly have nothing to latch. No action needed. |

Synthesis (`yosys synth_ice40`) completes with **0 errors, 0 warnings**,
146 cells (39 LUT4, 106 FF, 1 carry) — see
[`architecture.md`](architecture.md#resource-expectations) for the full
breakdown. Dead-code elimination during synthesis is why the cell count is
lower than the ~120 flip-flop bits declared in source.

## Parameterization check

Verilator was run with `ADDR_W=8, DATA_W=16` explicitly overridden (default
is `16`/`8`) against a small wrapper module, to check whether the declared
parameters actually propagate:

```
%Warning-WIDTHTRUNC:  bus_addr  <= addr_reg;     (16 bits -> 8-bit port)
%Warning-WIDTHEXPAND: bus_wdata <= wdata_reg;    (8 bits -> 16-bit port)
%Warning-WIDTHTRUNC:  read_buffer  <= bus_rdata; (16 bits -> 8-bit reg)
%Warning-WIDTHTRUNC:  tx_data_reg  <= bus_rdata; (16 bits -> 8-bit reg)
```

Confirms the README/architecture claim: `addr_reg` and `wdata_reg` are
hardcoded `[15:0]`/`[7:0]` and don't track the parameters. This is a real
gap, not a hedge — **only the default configuration is verified.**

## Bug history

### 2026-06-21 — `cs_fall`/`cs_rise` swap silenced the read-response path

**Symptom**: WRITE passed; READ always returned `0x00` instead of the
expected `0xA5`. Waveform showed `spi_miso` flat at `0` for the entire
read-response transaction, despite `bus_rdata`/`bus_ready` correctly
landing `0xA5` into `tx_data_reg`.

**Root cause**: `cs_fall` and `cs_rise` are defined with their names
swapped relative to what they actually detect (see
[`architecture.md`](architecture.md#cdc-strategy) for the full mechanism).
The TX-path load condition (`if (cs_fall && tx_data_valid) ...`) was
written assuming `cs_fall` meant "new transaction starting" — the natural
reading of the name — but it actually pulses at transaction *end*. The
shift register only ever loaded one full transaction late, after the
master had already clocked out and sampled eight zero bits.

**Found via**: direct VCD inspection — `spi_csn` falling at a given
timestamp, cross-referenced against which of `cs_fall`/`cs_rise` actually
pulsed at that timestamp. Confirmed independently against four other
correct usages of `cs_rise` already in the file (state reset, `cmd_commit`
clear, `read_pending` clear) — those four were consistent with each other
and with the wire's *actual* behavior, only the two TX-path usages of
`cs_fall` were the outlier.

**Fix**: both TX-path usages changed to `cs_rise`. The pre-existing
standalone `if (cs_rise) tx_loaded <= 0;` was folded into the same if/else
as the new load condition, since once both used `cs_rise` they would fire
on the same edge and the later statement in program order would have
silently clobbered the load (non-blocking-assignment ordering).

**Verified**: re-run against the fixed RTL, `WRITE: PASS`, `READ: 0xa5
(expected 0xA5) -> PASS`. New waveform regenerated and checked bit-by-bit:
MISO shifts `1,0,1,0,0,1,0,1` = `0xA5`, MSB-first, aligned with the
master's sampling windows — see `images/spi_bridge_read_response_zoom.png`.

**Process note**: the waveform evidence (`wave.vcd` and several PNGs) that
existed in this repo before this fix was captured *from the broken RTL* —
i.e. the evidence showed the bug, not a pass. Anyone publishing
verification evidence alongside a PASS claim should regenerate it after
every RTL change that touches the path being shown; `tb/tb_wave.cpp` +
`make wave` exists specifically so this is a one-command operation instead
of a manual GTKWave capture, to make that regeneration habit cheap enough
to actually happen.
