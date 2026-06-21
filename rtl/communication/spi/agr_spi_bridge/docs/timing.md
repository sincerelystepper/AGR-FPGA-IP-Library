
# Timing — AGR SPI Bridge

## Clock domains

One synchronous domain (`clk`). `spi_csn`, `spi_sck`, `spi_mosi` are all
treated as fully asynchronous to it and pass through independent 3-stage
synchronizers before any logic touches them (see
[`architecture.md`](architecture.md#cdc-strategy)).

## Reset

`rst_n` is asynchronous, active-low, and used directly in every
`always_ff` sensitivity list (`posedge clk or negedge rst_n`). No minimum
pulse-width has been tested — the testbench holds it low for 10 `clk`
cycles, which is comfortably long, but no lower bound has been
characterized. Treat this as untested rather than assuming a specific
minimum.

## CDC margin — empirically measured, not assumed

The synchronizers need the asynchronous `SCK`/`CSN` edges to be slow
relative to `clk` for the edge-detect logic to settle correctly. Rather
than asserting a number, this was swept directly: the testbench's
half-bit-period constant (`wait_cycles(N)` between each `SCK` edge,
shipped at `N=20`) was varied down to find where the regression actually
breaks.

| `clk` cycles per `SCK` half-period | Oversampling ratio | WRITE | READ |
|---|---|---|---|
| 20 (shipped baseline) | 40× | PASS | PASS |
| 6 | 12× | PASS | PASS |
| 5 | 10× | PASS | PASS |
| 4 | 8× | PASS | PASS |
| **3** | **6×** | **PASS** | **PASS** |
| 2 | 4× | PASS | **FAIL** |
| 1 | 2× | PASS | **FAIL** |

**READ requires at least 3 `clk` cycles per `SCK` half-period (≥6×
oversampling).** Below that, the TX shift-register update (gated on the
synchronized `SCK` edge) doesn't settle before the master's sampling
point, and the wrong bit gets shifted out.

**WRITE did not fail down to the lowest ratio tested (2×).** Take this
with real caution, not as a green light to run that fast: this is a
zero-jitter, perfectly-aligned RTL simulation with no metastability model
and no setup/hold variance — a synchronizer operating anywhere near the
Nyquist limit will not behave this cleanly on real silicon. The 2×/4× pass
results for WRITE are a simulation artifact of idealized cycle alignment,
not a verified operating point.

**Recommended minimum for a real design: 8–10× oversampling**
(`clk` ≥ 8–10 × `SCK` frequency), which sits comfortably above the 6×
point where this simulation actually starts failing, with margin for
real-world jitter and setup/hold that this testbench cannot model. The
shipped testbench's 40× baseline is far more conservative than necessary
and was simply never tightened.

To reproduce or re-sweep after an RTL change, parameterize the half-bit
wait count in a copy of `tb.cpp` by a CLI argument, loop over candidate
values, and check both the WRITE and READ pass flags at each value — this
is exactly how the table above was generated.

## Read-response gap

Because reads are split across two SPI transactions (see README), the
minimum gap between transaction A (address phase) ending and transaction B
(data phase) starting is:

```
gap_min ≈ t_cs_rise_sync + t_bus_turnaround + margin
```

- `t_cs_rise_sync`: ~2 `clk` cycles, the synchronizer settling time measured
  in the waveform for any `CSN` edge.
- `t_bus_turnaround`: however long the connected peripheral takes to
  respond to `bus_req` with `bus_rdata`/`bus_ready`. This is **entirely
  peripheral-dependent** — the bridge itself imposes no bound and has no
  timeout.
- `margin`: integrator's choice. The shipped testbench uses a 200-cycle gap,
  which is generous relative to its own near-instant test peripheral.

There is no handshake that tells the SPI master "not ready yet" — starting
transaction B too early simply returns whatever `spi_miso` last held
(typically `0`), silently, rather than an error code. Sizing this gap
correctly is the integrator's responsibility.

## What hasn't been characterized

- No place-and-route has been run, so there is no Fmax / max-`clk`-frequency
  number for any target device — only the simulation-side CDC ratios above.
- `CPOL=1` (idle-high `SCK`) has never been exercised.
- Strict SPI Mode 0/3 half-period setup/hold timing (as opposed to this
  testbench's full-period-stable convention) has never been exercised.
