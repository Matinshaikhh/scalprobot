# Changelog

Newest first. Entry zero is the forensic audit of 2026-09-03, and it is the
reference point for everything after it: no measurement taken before that
date is comparable with anything taken after, and the entry says why.

Every entry states whether it changes what a run *does*. That distinction
is the reason this file exists in this project — a harness change that
alters no trading decision can be compared against an earlier run, one that
alters a default cannot, and saying which is which is the difference
between a changelog and a list of commits.

Product versions are `SRP_PRODUCT_VERSION` in
[Constants.mqh](MQL5/Include/ScalpRobotPro/Core/Types/Constants.mqh). The
measurement harness carries its own version, `SRP_HARNESS_VERSION`, because
it changes at a different rate than the strategy; both are stamped into
every report header so a pasted number carries its own provenance.

---

## XSP 0.4 — the engine was right and its own check was wrong (2026-09-05)

**Changes what a run does: NO.** Not one trading line was touched, no
pre-registered XSP 0.2 parameter or gate moved, and the fix was proved
result-neutral by A/B before it was kept — bit-identical trade list, means
equal to 17 significant digits. This entry is about arithmetic and about a
measurement instrument that failed by accusing itself.

### The failure

The first run of `_build/xspresidual.py` on the real export stopped at the
section-7 engine gate:

```
worst accumulator drift=1.89e-15 over 45 sigma re-sums
independent window check: probes=67 values=268 worst_rel=3.46e-02 bad=1
XSP_RESIDUAL VERDICT=ENGINE_FAIL
```

The gate is `nbad or worst > 1e-9 or drift > 1e-9`, and it did its job: it
refused to let a study run on an engine it could not vouch for. Note the two
numbers disagree by thirteen orders of magnitude — the incremental sums drifted
1.89e-15, and the independent re-derivation of those same sums claimed 3.5%
error. Both cannot be true of the same accumulator.

### The root cause, by measurement

One probe of 67 failed. Not a class of probes, not a symbol, not a window
size — one minute:

```
i=49012  ts=2025-07-16 23:41:00  sst=47652  nl=15  nb=480  bounds_bad=[]
EL  got=2.08860706507607574167e-13  exp=1.74221748139302690106e-13
    absdiff=3.463896e-14  rel=3.463896e-02
```

`bounds_bad=[]` matters: every window bound was verified correct at all 67
probes, so nothing was misindexed. `absdiff=3.46e-14` is the entire error, in
basis points, on a quantity whose window contains fifteen EURUSD log returns
summing to **7.217982 bp in absolute value**. EURUSD ended that quarter hour
at the price it started; the exact signed sum is 1.742e-13 bp, which is not
"small" — it is zero to within the representation. The summation condition
number `sum|x| / |sum x|` at that minute is **4e13**.

The old tolerance was

```python
rel = abs(got - exp) / max(abs(exp), 1e-12)
```

and the 1e-12 floor is **seven orders of magnitude below the quantity's own
scale**. A 22-ulp accumulator drift divided by a denominator floored seven
decades too low reads as 3.5%. Measured against the window's own scale the
same error is 4.8e-15 — and the theoretical sliding-window bound,
`sqrt(1360)·ulp·|typ|`, is 4.09e-14, which the observed 3.46e-14 sits just
under. First divergence appeared 14 steps into the segment at exactly 1 ulp
and random-walked from there. Nothing was broken. **The engine was right and
the check was wrong**, and the wrongness was a floor constant.

### Fix A — scale the tolerance to `sum|terms|`, not to `|sum terms|`

`verify_windows()` now carries each expectation's own scale:

```python
sGL = math.fsum(abs(v) for v in gw)
...
rel = abs(got - exp) / max(scale, 1.0)
```

The 1.0 floor is the one the sigma-drift metric already used: `g` and `e` are
in basis points, so a window scale below 1.0 means there was nothing there to
get wrong. `Sxx` keeps its own value as its scale — a sum of squares cannot
cancel. This is not a loosened bar; it is a correct denominator. The forward
error of a float summation is bounded by `n·eps·sum|x_k|` **regardless of how
much the terms cancel**, so `sum|terms|` is the quantity the bound is written
against and `|sum terms|` never was.

Because the argument "we widened the tolerance and the failure went away" is
indistinguishable from the argument "we hid a bug", the new metric was
mutation-tested against deliberately broken engines before it was trusted:

| injected defect | worst_rel | probes flagged |
|---|---|---|
| none (control) | 5.89e-15 | 0 of 268 |
| L-window off-by-one on `GL` | 4.664e-01 | 67 |
| L-window off-by-one on `EL` | 1.111e+00 | 67 |
| one term double-counted | 1.983e-01 | 66 |
| beta-window off-by-one on `Sxy` | 4.273e-01 | 57 |
| beta-window off-by-one on `Sxx` | 8.521e-01 | 59 |
| `nl` bound violated | 3.145e-01 | 196 of 260 |
| `nb` bound violated | 1.045e+00 | 183 |
| 3e-9 relative perturbation | caught | 12 |
| 3e-11 relative perturbation | correctly ignored | 0 |

Real defects land at ~1e-1, achievable drift at ~1e-15, and the bar sits at
1e-9 between them — eleven orders of separation, seven above drift and seven
below the smallest structural defect. Cancellation immunity cost a factor of
about 7 in raw sensitivity and bought the difference between a test and a coin
flip.

### Fix B — pin the accumulators, so a minute's numbers do not depend on when it happened

The diagnosis exonerates the engine but leaves a real reproducibility defect
the old check was too broken to see. `GL`, `EL`, `Sxy` and `Sxx` were pure
add-new/drop-old accumulators: nothing in them ever re-derived the truth, so
their error is a random walk in the ulp of their intermediates that never
comes back. DEV's longest segment is ~90,000 minutes. The same minute,
evaluated 100 minutes into a segment and 90,000 minutes into it, returned
*slightly different numbers* — and that is a property of the data's history,
not of the minute.

All four are now pinned to exact `math.fsum` values every `RECOMPUTE_EVERY`
(4096) minutes, the same treatment the sigma window already had, with
scale-correct drift tracking under a new `resums` counter. The error can then
never represent more than 4096 updates. Cadence is on the bar index `i`, not
on a per-segment counter, so the identical indices are re-summed on every arm,
every permutation and every grid cell — no two runs can differ in where the
pinning happened. The probe stride (4001) is deliberately not a divisor of
4096, so the independent check lands at varying distances from the last pin
instead of always reading a freshly exact accumulator. The beta pin sits
*after* the window update, where the window is exactly `[i-nb+1, i]`, while
the probe for that minute was taken *before* it: what the check verifies is
the state as the minute was **judged**, not the state after it was tidied.

`s1`, the signed sigma accumulator, was the last one whose drift was measured
against nothing; it now reports on the `sum|terms|` scale too. `s2` keeps its
own value, being a sum of squares.

### Proof the fix changed no result

A/B with `RECOMPUTE_EVERY` monkey-patched to 4096 and then to 1e18 — the
latter strictly *worse* than the pre-fix code, since it disables the sigma
re-summation that already existed:

```
n=997  triggers=7778  suppressed=6727  eps_computed=185639
mean and t identical to 17 significant digits; trade lists identical
```

The closest `|z|` to the 2.0 trigger bar among taken trades is **2.348e-04**,
ten orders of magnitude above the 1e-14 arithmetic noise. No trigger can flip
on this data, and the pinning is therefore a reproducibility guarantee rather
than a change of measurement.

### After the fix

```
--selftest : checks=25 failed=0  VERDICT=PASS
             rolling sums and window bounds  worst_rel=2.73e-15  values=104
             sigma drift bounded  drift=3.31e-15  sigma_resums=7  window_pins=24

real DEV   : engine 0.3s  worst accumulator drift=3.29e-15
             over 45 sigma re-sums and 132 window pins
             independent window check: probes=67 values=268
                                      worst_rel=5.89e-15 bad=0
```

Six orders of margin under the unchanged 1e-9 gate.

### Audited for the same defect elsewhere

The broken pattern is `abs(a-b) / max(abs(signed_total), tiny_floor)`. Two
other comparisons in the file were checked by hand: the sigma `s2` metric
divides by a sum of squares with a 1.0 floor, which cannot cancel and is
correct as written; and the grid's `abs(row[2] - Z) < 1e-9` is a display
marker on an O(1) z-threshold, not an error metric. No other instance exists.

### What this entry does NOT contain

No interpretation of H1 or H2. The full run completed and printed its
pre-registered verdicts, and reading them is a separate act from repairing the
instrument that produced them. The engine gate is now the only thing this
entry claims: the arithmetic reproduces, and the check that says so can still
catch a one-term error.

---

## XSP 0.3 — the study's instrument is built and falsified; NO RESULT YET (2026-09-05)

**Status: there is not one measurement on real data in this entry.** The
exporter, the deploy harness and the analysis are finished, and the analysis
has been tested against data whose answer was known in advance. The real
export has not been run. Any number below came from synthetic input built for
the purpose of breaking the code, and every one of them is labelled as such.

**Changes what a run does: NO.** No trading code was written or modified. The
three files added are a Script with no order function, a PowerShell deploy
harness, and an offline Python analysis.

### What exists now

| file | role |
|---|---|
| [XSPExportMinutes.mq5](MQL5/Scripts/XauStructurePro/XSPExportMinutes.mq5) | Script (not an Expert): 1-minute bid OHLC + tick count + spread quantiles from the terminal's own tick archive |
| [CXspCsv.mqh](MQL5/Include/XauStructurePro/Research/CXspCsv.mqh) | the CSV sink, `FILE_COMMON`, overwrite-not-append |
| [exportminutes.ps1](_build/exportminutes.ps1) | asserts the compiled-in constants against this changelog, compile-gates in a scratch tree, deploys, archives stale output, and `-Verify` structurally checks what the terminal wrote |
| [xspresidual.py](_build/xspresidual.py) | the whole pre-registered analysis: H1, H2, the censored barrier null, variance ratio, cost-viability surface, the 48-cell exploratory grid |

**A Script, and not an Expert, on purpose.** Inside the Strategy Tester
`CopyTicksRange` returns the *tester's* stream, which under any model but 4 is
synthesised from M1 bars, and nothing in the returned array says so. Audit 6.2
measured that stream's spread at 4.0–4.4 pts against 9.5–33.5 real, so an
export contaminated that way would understate cost roughly threefold and read
as a real-tick file. The cost is one manual step: the script must be attached
to a chart by hand. The harness makes that step safe rather than removing it.

### The parameter cross-check XSP 0.2 demanded of itself

XSP 0.2 lists "any constant in this entry differing from the constant in the
code that ran" as disqualifying. Checked mechanically, not by eye: every one of
`W_BETA 480`, `MIN_BETA 400`, `W_SIG 480`, `MIN_SIG 400`, `L 15`, `H 30`,
`Z_CRIT 2.0`, `STRESS 1.5`, `COMMISSION_PTS 7.0`, `GAP_BREAK_MIN 5`,
`MIN_N 200`, `T_CRIT 2.0`, `DECOMP_FRAC 1.0`, `MECH_FRAC 0.5`, `PERMS 200`,
`H2_T_CRIT 2.58`, `H2_MIN_N 150`, `H2_PRE_MIN 15`, `H2_POST_MIN 30`, the 48-cell
grid, the R grid, the caps, the VR horizons, the DEV span and the five named
anchors matches. The report prints the same block at the top of every run so
the comparison can be repeated by anyone.

Two notes where the code is more specific than the prose was:

- "15 valid minutes span at most 20 clock minutes" is enforced as
  `ts[i] - ts[i-L+1] <= L*60 + SPAN_SLACK_MIN*60`, i.e. a five-minute slack that
  scales with `L` — necessary because the exploratory grid runs `L = 60`, where
  a fixed 20-minute cap would be meaningless.
- XSP 0.2 numbers five gates and then says "**All four must pass**". That is a
  wording slip in the pre-registration, noticed before the study ran and
  recorded here rather than quietly edited: **the code enforces all five**, in
  the order written. Leaving the slip visible and fixing nothing is the point —
  a pre-registration that gets tidied up after the fact is not one.

### The bug the selftest caught, which would have moved every H2 anchor

`last_sunday()` walked *forward* from the 28th to the next Sunday. October
2025's 28th is a Tuesday, so it returned **November 2** where the last Sunday
of October is the **26th** — a one-week error in the EU DST changeover, which
would have placed every H2 anchor an hour wrong for that week and produced a
plausible-looking answer with no visible symptom. Fixed to walk to the last day
of the month and then back to Sunday; the report now prints its own DST dates
(`EU 03.30 01:00Z -> 10.26 01:00Z`) so the same class of error is visible on the
face of the output.

The report also *refuses* to judge H2 if the broker's own clock, fitted from the
exported minute stamps, disagrees with the EU rule. H2 comes back
`INCONCLUSIVE` in that case rather than being evaluated against an anchor
placed by an assumption.

### The lesson that cost the most, and the number that settled it

The selftest's null case is a random-walk residual: the gates must kill it.
Seed 11 produced `gross_mean = +93.7 pts, t = 2.16, n = 187` — a false positive
on a random walk. **The threshold was not loosened.** The code was re-read for
look-ahead first (there is none: the `eps` window ends exactly at the entry
price `cl[i]`, the exit is `cl[i+H]`, and the direction depends only on
information through `i`), then the question was measured:

| universes | statistic | value |
|---|---|---|
| 1 (seed 11) | conditional gross mean | +93.7 pts, t = 2.16, n = 187 |
| 12 | pooled conditional gross | +24.05 pts, t = 2.01 |
| 60 | pooled conditional gross | **+4.22 ± 5.39 pts, t = 0.78** |
| 60 | unconditional forward-30 | +1.96 ± 2.10 pts |

The engine is unbiased; one 45-day universe yields under 200 observations and,
at a per-trade sd near 560 points, a standard error near 40 — so a
single-universe null test passes or fails on a 2σ coin flip, which is not a
test. The null case now pools twelve independent universes and asserts pooled
`|t| < 3.0`, pooled net `< 0`, pooled signal `t > 4.0`, and that the gate
function returns `DEAD` on the pooled null. **The answer to an underpowered
test is more data, not a looser threshold** — and the same arithmetic is why
gate 3 exists in the real study.

Current state: `XSP_RESIDUAL_SELFTEST checks=25 failed=0 VERDICT=PASS`, over six
sections — parser against the exporter's real schema, rolling-sum drift
(`worst_rel = 5.5e-14`), beta recovery (`1.1907` against an injected `1.2000`),
non-overlap enforcement, the injected-signal case, the pooled null case, the
mechanism control, and all six branches of the gate function.

### One row of the barrier null that is not a measurement

At `R = 1.00` the pooled target-first share is exactly `0.5000` at every cap and
`E[R]` exactly `0.0000`. That is arithmetic, not data: longs and shorts run on
the same minutes with symmetric barriers, so a long's target-first path *is* the
short's stop-first path and pooling forces `target == stop` identically. The
report now says so on the line above the table, because a reader scanning for
"matches the textbook formula" would otherwise land on the single row that
cannot disagree with it. The per-direction split is printed beside it, with the
matching caveat that the two rows are exact complements — one number per cap,
not two.

### Synthetic-only figures, from the end-to-end rehearsal

The full report path was run on generated files before asking for the real
export, so a one-hour manual step cannot be followed by a crash in section 12.
`RC 0`; the run printed `H1=SURVIVES H2=INCONCLUSIVE n=264 mean=+110.37 t=3.46`.
**Both of those verdicts are correct answers to a rigged question**: the
generator injects reversion, so `SURVIVES` proves the pipeline can see an effect
that is there, and the synthetic clock disagrees with the EU rule, which
exercises the refuse-to-judge branch. Neither says anything about gold. The
generator's own docstring states it is not a simulation of any market, and the
synthetic artifacts are deleted rather than left in `_build/_xsp/` where a
future reader could quote them.

### What has to happen next, in this order

1. `powershell -File _build\exportminutes.ps1` — asserts, compiles, deploys.
2. Attach `XSPExportMinutes` to any chart; wait for
   `XSP_EXPORT symbols=2 of 2 VERDICT=PASS`. Minutes, not seconds: XAUUSD alone
   is ~60.5M ticks over 279 days.
3. `powershell -File _build\exportminutes.ps1 -Verify` — structure, span,
   monotonicity, schema, and the tick-count cross-check against Phase A's
   60,541,601.
4. `python _build\xspresidual.py` — the pre-registered analysis, one pass, no
   parameter touched.

Then the verdict is read off the gates and reported as it comes. XSP 0.2 already
committed to the outcome that is permitted to be "no"; this entry adds only that
the instrument for reaching it has now been tested hard enough that a "no" can
be believed.

---

## XSP 0.2 — pre-registration of the dollar-residual reversion study (2026-09-05)

**Status: written BEFORE the study runs. There is not one measurement in this
entry.** Every constant, threshold, deciding cell and kill condition below is
fixed at the moment of writing. Nothing here may be changed after the run; if
a constant turns out to be badly chosen, the study is rerun on VAL-free data
under a NEW pre-registration that says so, it is not edited.

**Changes what a run does: NO.** No trading code is written or modified for
this study. There is no EA, no order function, no position. The instrument is
a data export plus an offline statistical test.

**Barrier-free by design.** Phase A's one unusable number came from a sample
filtered by stop-retirement. This study takes fixed-horizon forward returns
with no barriers and no early termination, so no observation can be removed
by its own path.

### H1 — the dollar-residual reversion hypothesis

> Over 5-60 minutes, the part of an XAUUSD move that the contemporaneous
> dollar move does **not** explain is disproportionately inventory-driven
> rather than information-driven, and it reverts. The part the dollar does
> explain is information, and it does not revert.

**Why it could be true.** XAU/USD, XAU/EUR and EUR/USD are bound by a
triangular arbitrage identity, so decomposing a gold move into a
dollar-explained part and a residual is a mechanical operation, not a
statistical coincidence. When gold moves and the dollar moves with it, a
common factor is repricing. When gold moves and the dollar does not, it is
either gold-specific news or someone transacting for inventory reasons; over
a 5-60 minute window containing no scheduled release, the second dominates.
What the trade earns is the liquidity-provision premium — compensation for
bearing risk at a moment when a counterparty needs immediacy. It is a
payment for a service, not a free lunch, which is why it can persist: the
speed-based version of this was arbitraged away years ago, but the part that
requires capital and risk-bearing to correct cannot be competed away by
latency alone.

**The honest counter-case, stated now so it cannot be presented later as a
surprise:** minute-scale cross-market lead-lag has been largely eliminated by
HFT, so if H1 fails it will most likely fail because the residual is already
corrected inside the first few seconds. The gates below are built to say that
plainly rather than to search for a horizon at which it did not.

**Why EURUSD and not a basket.** EURUSD is ~57% of DXY by weight and the
single most liquid dollar cross. It is also the only other symbol whose real
tick archive on this machine covers the whole DEV *and* VAL span
(`202501.tkc` … `202609.tkc`); the remaining FX majors hold one month each.
Using it is a data fact, not a modelling preference, and it is called a
dollar **proxy** throughout — never "DXY".

### The construction, fully specified

All series are 1-minute bars built from real ticks, **bid** closes for both
symbols (Phase A's convention, and it keeps the measurement spread-free so
cost can be charged once, analytically, in post-processing).

| symbol | role |
|---|---|
| XAUUSD | the traded series |
| EURUSD | the dollar proxy |

**Validity.** Minute `t` is VALID iff both symbols recorded at least one tick
in `t` and at least one in `t-1`, and the gap from the previous valid minute
is at most 5 clock minutes. A gap larger than that (weekend, outage, holiday)
**breaks the series**: no return is computed across it. Sunday-open jumps are
therefore never treated as one-minute returns. Every exclusion is counted and
printed.

**Returns.** `g(t) = ln(XAU_c(t)) - ln(XAU_c(t-1))`,
`e(t) = ln(EUR_c(t)) - ln(EUR_c(t-1))`.

**Rolling dollar beta.** Over the trailing `W_BETA = 480` valid minutes
ending at `t-1` — strictly past, so no observation sees its own bar:

```
beta(t) = sum(g*e) / sum(e*e)
```

No intercept: minute returns are zero-mean to well inside the noise, and an
intercept is one more fitted number for nothing. Requires >= 400 usable
pairs and `sum(e*e) > 0`, else the observation is SKIPPED and counted.

**The dislocation.** Over the last `L = 15` valid, contiguous minutes
(contiguous meaning the 15 valid minutes span at most 20 clock minutes):

```
eps(t) = G_L(t) - beta(t) * E_L(t)      G_L = sum g,  E_L = sum e
```

**Scale.** `sigma(t)` is the sample standard deviation of `eps` over the
trailing `W_SIG = 480` observations ending at `t-1`, again strictly past.
Requires >= 400, else SKIPPED and counted. `z(t) = eps(t)/sigma(t)`.

The z-score is what makes this study survive the DEV sample's own
non-stationarity: gold ran $3346 → $5274 and M15 ATR went from ~234 to
~1600 pts across the window, so any threshold in absolute points would be a
fitted constant in disguise. There is not one absolute price constant in the
specification.

**Trigger.** `|z(t)| >= Z_CRIT = 2.0`. Direction is `-sign(z(t))`: fade the
unexplained move.

**Non-overlap, and why it is a gate rather than a detail.** After a trigger at
`t`, every further trigger is suppressed until `t + H` valid minutes have
passed. Overlapping forward windows share price path and are the same
pseudo-replication that inflated n in the old tree — defect 2 wearing
different clothes. Suppressions are counted and printed alongside n so the
ratio is visible.

**Outcome.** For direction `d`:

```
raw_pts  = d * (XAU_c(t+H) - XAU_c(t)) / point
c        = STRESS * spread_med_pts(t) + 7.0        STRESS = 1.5 primary
net_pts  = raw_pts - c
```

`spread_med_pts(t)` is the median tick spread inside minute `t`, exported per
minute. Cost is charged **once** per round trip: a long gives up the spread
entering and a short gives it up exiting, relative to a bid-measured path.
Charging it twice would overstate the toll two-fold.

### The primary cell — declared, and the only one that decides anything

**`L = 15 min, H = 30 min, Z_CRIT = 2.0, STRESS = 1.5, DEV only. Statistic:
mean net_pts per non-overlapping observation, with `t = mean/(sd/sqrt(n))`.**

`L = 15` and `H = 30` are read off Phase A's timing data, which is the only
non-arbitrary anchor available: `sec_to_mfe` had p25 = 238 s, median 1230 s,
p75 = 2685 s, so the favourable excursion typically arrives 4-45 minutes in
and a 30-minute horizon brackets the median. `Z_CRIT = 2.0` is the
conventional two-sigma bar, chosen because it is conventional and therefore
not chosen by me.

### Gates, evaluated in this order

1. **DEAD** if `mean(net_pts) <= 0`.
2. **DEAD** if `0 < t <= 2.0` and `n >= 200`.
3. **UNDERPOWERED** if `n < 200`. This counts as a failure for the purpose of
   building anything. It is *not* rescued by lowering `Z_CRIT` to harvest more
   observations — that is tuning, and a dislocation too rare to sample is also
   too rare to trade.
4. **DECOMPOSITION FAIL** if the identical test with `beta` forced to zero —
   i.e. fading the *raw* 15-minute gold move — produces a mean `net_pts` at or
   above the residual version's. The dollar decomposition is the hypothesis;
   if the raw move does the same work, H1 as stated is false even if some
   reversion exists. A generic reversion finding would be a **different**
   hypothesis and would need its own pre-registration and its own data.
5. **MECHANISM FAIL** if the day-shuffled control — EURUSD's whole days
   randomly permuted, destroying the contemporaneous relationship while
   preserving both marginal distributions, 200 permutations — produces a mean
   `net_pts` at or above 50% of the residual version's. Then `beta` is not
   carrying contemporaneous information and any result is an artefact of the
   filtering, not of the dollar.

**All four must pass.** Any one failure kills H1 and it is not re-cut.

### H2 — the scheduled-liquidity hypothesis, pre-registered in the same pass

> At moments when flow must transact regardless of price, inventory pressure
> produces a transient dislocation that reverts.

**Five anchors, named now, never scanned.** London AM fix 10:30 London,
London PM fix 15:00 London, COMEX floor open 08:20 New York, COMEX settlement
13:30 New York, 17:00 New York roll. Converted to broker server time from the
exported minute stamps, with the DST rule stated in the report.

**Statistic.** Mean signed reversion over the 30 minutes after the anchor,
conditioned on the sign of the 15 minutes before it, net of the same cost
model. **Gate:** at least one anchor must clear `t > 2.0` after a Bonferroni
correction over the five (i.e. `t > 2.58`, the 0.01 two-sided bar), with
`n >= 150` for that anchor. Otherwise H2 is DEAD.

Time-of-day is the most over-mined class of retail "edge" in existence: a
scan of 288 five-minute slots on 9 months of data will always return
something. The protection is that five slots were named in advance for
mechanical reasons and the other 283 are not looked at. If H2 fails, the
answer is not to widen the list.

### Multiplicity, stated numerically

Two pre-registered hypotheses in one pass. At a 5% bar each, the chance that
at least one clears by luck is `1 - 0.95^2 = 9.75%`. That is disclosed, not
corrected away, because each hypothesis has its own independent mechanism and
its own gate; a surviving H1 will be re-tested on VAL before anything is
built, which is the real protection.

### Exploratory grid — decides nothing, and is reported so that it cannot

`L ∈ {5,15,30,60}` × `H ∈ {5,15,30,60}` × `Z_CRIT ∈ {1.5,2.0,2.5}` = **48
cells**. At a 5% bar, `1 - 0.95^48 = 91.5%` chance that at least one clears
2 SE by chance alone. The grid exists to show the *shape* of the result — a
real effect degrades smoothly as you move away from the centre, an artefact
appears in one cell and vanishes beside it — and for no other purpose. **No
cell in this grid may be quoted as a finding, including the primary one if the
primary gate has already failed.**

### Also delivered, descriptive, gating nothing

- **The empirical censored barrier null** — the Phase A correction made
  concrete. `R ∈ {0.5,0.75,1.0,1.5,2.0,3.0}` × caps `{300,900,1800,3600} s`,
  simulated on the real minute paths from stratified random entry times, so
  every future study has a measured null instead of `1/(1+R)`. The R grid
  extends **below** 1.0 because a reversion hypothesis lives there and Phase
  A's grid started at 1.0 — a structural blind spot for the hypothesis class
  now under test.
- **Variance ratio** `VR(H) = Var(r_H)/(H*Var(r_1))` for
  `H ∈ {1,2,5,15,30,60,120,240,480}` minutes, whole sample and by session.
  One number per horizon saying whether the process trends, reverts, or is a
  martingale there. If VR ≈ 1 everywhere, price-only strategies are dead at
  every horizon and that is a finding in its own right.
- **Spread by hour of day**, so the cheap-regime gate is chosen from a cost
  fact rather than from outcomes.
- **Forward-return distribution by horizon**, ATR-normalised — the
  cost-viability surface, computed with no strategy in it at all.

### What would make this study unquotable

- Either symbol's exported minute coverage falling short of the declared DEV
  span, or XAUUSD's exported tick count diverging materially from the
  60,541,601 Phase A recorded over the same window. Both are printed and
  checked, not assumed.
- Any observation drawn from `2026.03.01` or later. VAL is sealed. One look,
  at one frozen candidate, at the end.
- Zero-filling a missing minute instead of breaking the series — it would
  drag `beta` toward zero and manufacture residual where none exists.
- Overlapping forward windows counted as independent observations.
- Any constant in this entry differing from the constant in the code that ran.
  The report prints its own parameter block for exactly this comparison.

### The outcome that is permitted to be "no"

H1 and H2 may both fail. If they do, the honest conclusion is that no price-,
clock- or dollar-based reversion edge exists at this horizon on this
instrument as measured, and the recommendation will be to stop or to change
instrument — not to open a third cut on the same nine months. Phase A already
demonstrated that this project will report a DEAD verdict on its own
pre-registered hypothesis; that only stays true if it happens the second time
as well.

One caveat inherited by everything above: the feed is `MetaQuotes-Demo`. The
17-pt median spread is a demo spread. Every net number in this study must be
re-checked against a live retail spread before it informs a capital decision.


---

## XSP 0.1-phaseA — RESULT: both setups dead, and a correction to this study's own null (2026-09-05)

**Status: this is a RESULT entry.** The pre-registration it answers is the
next entry down, written before the run. Nothing here re-cuts anything: the
deciding cell was named in advance and the verdict is read off that cell.

**Changes what a run does: NO.** No compiled code changed. This entry records
an outcome and corrects one piece of the *reporting* arithmetic.

### What ran

`XauStructurePro 0.1-phaseA`, XAUUSD, setup TF M15, exec TF M5, DEV segment
`2025.05.27 → 2026.02.28`, Model 4 real ticks, 60,541,601 ticks over 268,353
minutes, `tick_model_inferred=SRP_TICK_MODEL_REAL_TICKS`, `quotable=yes`,
`RECONCILED=yes`, 2172 instances, 0 orphans. Build 0 errors / 0 warnings.
Self-test `XSP_CHECK CHECKS=348 FAILED=0 VERDICT=PASS`.

### The verdict on the pre-registered cell

Primary cell as declared — R = 1.5, cap 3600 s, pessimistic cost, expectancy
in R per instance:

| cut | n resolved | win rate | E_net | verdict |
|---|---|---|---|---|
| ALL | 815 | 34.48% | −0.0190 R | DEAD |
| S1 continuation | 409 | 33.01% | −0.0163 R | DEAD |
| S2 reversal | 406 | 35.96% | −0.0503 R | DEAD |

Both setups are rejected. **The rejection rests on expectancy**, which is
cap-inclusive and therefore immune to the censoring problem described below.
S1 and S2 are closed; their exploratory cuts are not to be mined.

The claim-once machinery did real work and the census proves it:
`s2 detected=5711 emitted=917 suppressed=4794`. Defect 2 was caught 4794
times in one pass. Without `CXspStructureEvents` the reversal arm would have
reported an n roughly six times too large.

### Correction: the win-rate null in the entry below is wrong for R >= 1.5

The pre-registration declares `p_rw = 1/(1+R)` and calls it exact. It is
exact only for a walk run to completion. Under a finite holding cap it is
not, and the run's own numbers show the error growing with R:

| R | resolved within 3600 s | p_hat | `1/(1+R)` | gap |
|---|---|---|---|---|
| 1.0 | 49.6% | 0.5288 | 0.5000 | **+2.9 pp** |
| 1.5 | 37.5% | 0.3448 | 0.4000 | −5.5 pp |
| 2.0 | 32.6% | 0.2345 | 0.3333 | −9.9 pp |
| 3.0 | 28.1% | 0.1033 | 0.2500 | −14.7 pp |

Monotone in R, and positive at R = 1.0. That is the signature of
**differential time-censoring**, not of an anti-predictive signal: the far
barrier takes longer to reach than the near one, so a cap that leaves 50-72%
of instances unresolved deletes target-first paths preferentially, and the
size of the deletion scales with the target distance.

**Retracted:** the reading that these setups are "worse than random". Test 1
of the pre-registration — `p_hat - p_rw > 2*SE` against a theoretical null —
is invalid at R >= 1.5 and must not be quoted from this run. Test 2 and the
expectancy metric stand.

**Replacement, binding on every study after this one:** the null is the
*empirical* conditional win rate obtained by simulating the same barrier
geometry and the same cap on the same real price paths from random entry
times. It is measured, not derived. `1/(1+R)` may appear in a report only as
the uncensored limit, labelled as such.

Nothing in this correction rescues S1 or S2, and the R = 1.0 column is not
an invitation: that cell was not the declared one, and reading a verdict off
it after the fact is the exact move the pre-registration exists to prevent.

### What the instance file says about why it failed

Measured from `_build/_xsp/dev_20260905_170205/xsp_instances.csv`, all 2172
rows, bid path, spread-free:

| quantity | p10 | median | p90 |
|---|---|---|---|
| stop distance (pts) | 391.7 | **1000.6** | 2753.3 |
| ATR14 M15 at event (pts) | 295.1 | 590.5 | 1303.5 |
| stop / ATR14 | 0.85 | **1.75** | 2.71 |
| spread at trigger (pts) | 13.0 | 17.0 | 20.0 |
| MFE over tracked window (pts) | 64 | **515** | 1984 |
| abs(MAE) over tracked window (pts) | 79 | 474 | 1599 |
| `k = c/S` pessimistic | 0.0101 | **0.0327** | 0.0857 |

Three findings, and they are the design inputs for the next study.

**1. Cost is not the binding constraint at this horizon.** Median round-trip
cost is 24 pts against a median favourable excursion of 515 pts — a ratio of
**21.6×**, with 81.4% of instances above 6×. The pre-registration guessed
`k ≈ 0.088` from a 300-pt stop; the realised median is 0.0327, so the
required edge over the null to break even was `k/(1+R) ≈ 1.3 pp`, not the
3.5 pp declared. The bar was lower than advertised and the setups still
missed it. AUDIT §8.1's cost arithmetic is sound at 22 seconds and does not
transfer to 60 minutes.

**2. The geometry, not the horizon, was unreachable.** A 1.75-ATR stop makes
1.5R a 2.6-ATR demand inside four M15 bars, against a median 515-pt
excursion and a 1500-pt target. **The invalidation-derived stop is retired as
a sizing rule.** It survives as a statement about where a hypothesis is void;
the inference "therefore the stop is that distance" is what produced 62.5%
non-resolution and an uninterpretable measurement.

**3. These entries carried no direction.** Fraction of instances with
MFE > \|MAE\| = **0.5023**. With SRP's break-of-structure result at M1 and both
XSP setups at M15, that is three independent measurements agreeing that price
shape does not predict direction on this instrument at this horizon. The next
hypothesis does not come from the price series.

One suggestive number, recorded and explicitly **not claimed**:
Spearman(5-min mark, subsequent 55-min increment) = −0.118, z = −4.65,
which reads as reversion. It is computed on the 1561 `timeout` instances —
every one of which failed to hit its stop by construction — so the filter
biases it toward reversion. It cannot be used. It is the reason the next
study is barrier-free.


---

## XSP 0.1-phaseA — pre-registration of the falsification study (2026-09-05)

**Status: written BEFORE the study runs. There is not one measurement in this
entry.** It exists so that the deciding cell, the thresholds and the two
predicted failure modes are on the record while the outcome is still unknown.
A number chosen after seeing the data is not evidence about the data, and the
only defence against that is a timestamp — this one.

This entry changes what a run *does* only in the sense that it introduces a
second EA that cannot trade. `MQL5/Include/ScalpRobotPro/` is untouched and
stays the [AUDIT §9.5](audit/AUDIT.md) comparison baseline;
`MQL5/Experts/XauStructurePro/XSPSetupStudy.mq5` compiles no order function at
all, so it cannot place a trade even by defect. Authorised by
[AUDIT §11 step 5](audit/AUDIT.md): "proceed to the layered architecture in
section 8 as new code, keeping the old EA intact and runnable for comparison."

### The primary cell, declared here and nowhere else

**R = 1.5, holding cap 3600 s, pessimistic cost, expectancy in R per instance.**

`_build/xspstudy.py` defaults to exactly this (`--primary-tier 1.5
--primary-cap 3600`) and prints it back at the head of every report, so a
report cannot be read without seeing which cell was pre-declared as deciding.

Why this cell and not one of the other fifteen. Write `k = c/S` for cost as a
fraction of the stop. The edge over the driftless-walk null that a setup needs
merely to break even is then

```
BE_net - p_rw = (1+k)/(1+R) - 1/(1+R) = k/(1+R)
```

which *falls* as R rises — so on the break-even test alone, the highest tier
is the easiest. It is not free: a higher target is reached inside a fixed cap
less often, so barrier-resolved n falls, SE rises, and the significance test
divides by that SE. R = 1.5 is where the required edge is still small and the
resolution still high. Order of magnitude, from AUDIT's own figures and *not*
from this data: a leg-origin stop plus 0.20 ATR on XAUUSD M15 at ATR ≈ 250
lands near 300 pts, so at the [§8.1](audit/AUDIT.md) working spread of 13 pts
(§6.2 measured 9.5–33.5 real) `k ≈ (1.5×13 + 7)/300 ≈ 0.088`, and the required
edge is 4.4 pp at R=1.0, **3.5 pp at R=1.5**, 2.9 pp at R=2.0, 2.2 pp at R=3.0.
The 1.3 pp that R=3.0 saves is not worth the resolution it costs.

Cap 3600 s is the top of the settled 5–60 minute horizon, chosen because the
largest cap resolves the most instances at the barriers and so leaves the win
rate best defined. The other three caps are recorded and reported.

**Multiplicity, stated as a number rather than acknowledged.** The 4×4 surface
is 16 cells. At a 2 SE bar per cell, the chance that at least one clears by
luck alone is `1 - 0.95^16 = 56%`. That is why exactly one cell decides and
the other fifteen are labelled EXPLORATORY in the report itself.

### The two inequalities, and why they are two

The plan this work follows cost-adjusted both the null and the break-even. That
was wrong and is corrected here: it charged cost twice and left the two tests
algebraically near-identical, so passing one all but guaranteed passing the
other and the pair carried barely more information than either alone.

**Test 1 — does a signal exist at all?** Cost-free, because a driftless walk
does not pay commission either:

```
p_rw = 1/(1+R)          EXACTLY, not an average
claim: p_hat - p_rw > 2*SE      SE = sqrt(p_hat(1-p_hat)/n)
```

`p_rw` is exact rather than estimated because every instance in a tier has
`T = R*S` **by construction** — the target is defined as R times that
instance's own stop, so there is no distribution of geometries to average over.

**Test 2 — is the signal big enough to trade?** Cost enters here and only here:

```
k = c/S               c = stress*spread_at_trigger + commission
BE_net = (1+k)/(1+R)
claim: p_hat > BE_net
```

`BE_net` is linear in `k`, so the sample-wide value is exactly
`(1 + mean(k))/(1+R)`: the entire effect of cost on the decision is the one
number `mean(c/S)`, which the report prints. This is [§8.1](audit/AUDIT.md)'s
arithmetic applied per instance instead of once for the whole strategy.

**Kill gate, pre-declared:** `p_hat <= p_rw` at n >= 200 barrier-resolved kills
that setup. It is not rescued by re-cutting the labels, and it is not rescued
by collecting more data — `xspstudy.py` deliberately tests DEAD *before*
UNDERPOWERED for that reason.

**Cost is ONE spread per round trip, not two.** Barriers are measured on the
BID for both directions, so the measured path is spread-free and a long gives
up the spread on entry while a short gives it up on exit. Charging two spreads
would overstate the toll twofold and could fail a setup that pays.

**Deciding metric is expectancy in R, not win rate.** Expectancy includes the
time exits at the cap; win rate is defined only over barrier-resolved
instances and therefore silently excludes them. Win rate is reported second.

### S1 — continuation. The ten fields ([AUDIT §9.2](audit/AUDIT.md))

| Field | Declared value |
|---|---|
| **Setup** | An M15 displacement leg continues rather than reverts over 5–60 minutes. [CXspContinuation.mqh](MQL5/Include/XauStructurePro/Setups/CXspContinuation.mqh) |
| **Trigger** | Last **closed** M15 bar (shift 1; shift 0 is never read) satisfying all three: range ≥ `XSP_DISP_ATR_MULT`(1.50) × ATR *as it stood on that bar*; `MathAbs(close−open)/range ≥ XSP_DISP_BODY_RATIO`(0.60); close within the top/bottom `1 − XSP_DISP_CLOSE_POS`(0.70) of the range in the trade direction. |
| **Invalidation** | The **leg origin** — the displacement bar's low for a buy, its high for a sell. If price returns there the leg did not hold and nothing of the premise remains. |
| **Stop** | `MathAbs(ref_entry − invalidation) + XSP_STOP_BUFFER_ATR`(0.20) × ATR, in points, from `CXspSetupBase::StopPoints`. **Derived, never chosen.** Returns 0 — and the instance is refused and counted, not clamped — when the level is already on the wrong side of the first available price (a gap between the bar close and the next tick). A clamped stop is a different hypothesis from this one. |
| **Target** | `R × stop` for R ∈ {1.0, 1.5, 2.0, 3.0}, all four recorded from one pass. **R = 1.5 decides**, per the arithmetic above. |
| **Confirmation** | Broker **tick-volume** expansion: trigger-bar quote-update count ÷ median count for the same *server* minute-of-day over the previous `XSP_CONFIRM_SLOT_SESSIONS`(20) sessions, passing at ≥ `XSP_CONFIRM_MIN_RATIO`(1.50). Uncorrelated with the trigger as L5 requires — the trigger reads only price, this reads no price. **Not order flow, not traded volume, not DOM**: XAUUSD spot is not centrally cleared, no venue-wide volume exists to read, and no `MarketBook*` call exists in this codebase. A participation proxy, labelled as one. Fewer than 3 prior slots ⇒ `ratio = 0`, `slot_samples < 3`, excluded from that cut rather than read as a failure. |
| **Should work in** | Mid-to-high realised-volatility deciles, where a bar clearing 1.5× ATR represents a real repricing; and where the H1 swing structure agrees with the leg. |
| **Should NOT work in** | The low realised-vol deciles, and against H1 structure. |
| **Minimum sample** | n ≥ 200 barrier-resolved at the primary cell. Exploratory cuts reportable only at n ≥ 100, and then only as a hypothesis for a fresh slice. |
| **Deciding metric** | Expectancy in R per instance, net of pessimistic cost, at R=1.5 / 3600 s, with both inequalities above required. |
| **Predicted failure mode** | *"Dies in the low realised-volatility deciles, where a bar can clear 1.5× a small ATR without anything having happened, so the 'displacement' is noise wearing the right shape."* |

### S2 — reversal. The ten fields

| Field | Declared value |
|---|---|
| **Setup** | Price that penetrates a liquidity pool and closes back inside within a bounded window has failed at that level and reverts over 5–60 minutes. [CXspReversal.mqh](MQL5/Include/XauStructurePro/Setups/CXspReversal.mqh) |
| **Trigger** | Over the last `XSP_SWEEP_WINDOW_BARS`(3) **closed** M15 bars: the window extreme strictly exceeds a pool price and the window's last close is strictly back inside it. Strict on both sides — a high that merely *touched* the level did not penetrate it, and a close sitting exactly on it has not come back inside. The pool must predate the window (`origin_time < rates[window].time`), or the window's own bars would be sweeping a level they created. The **deepest** pool taken out is the one reported: exceeding a pool at 3450 necessarily exceeded every pool beneath it, so the weaker forms are not separate occurrences. A window that swept a pool above *and* one below and closed between them emits **nothing** and is counted as `Ambiguous()` — picking a side there is a coin flip wearing the clothes of a signal. |
| **Invalidation** | The **sweep extreme** — the highest high (sell) or lowest low (buy) the window printed. If price exceeds it, the level did not hold. |
| **Stop** | Identical derivation to S1: distance to the sweep extreme + 0.20 ATR, refused rather than clamped. |
| **Target** | `R × stop`, same four tiers, same R = 1.5 deciding. |
| **Confirmation** | The same single tick-volume test, with the same caveats. |
| **Should work in** | Ranging/chop H1 context, where a swept extreme is a liquidity event rather than a breakout; pools with a longer origin history. |
| **Should NOT work in** | Trend days — precisely where the sweep is the *beginning* of the move. |
| **Minimum sample** | n ≥ 200 barrier-resolved at the primary cell; n ≥ 100 for any exploratory cut. |
| **Deciding metric** | As S1. |
| **Predicted failure mode** | *"Dies when the sweep is the START of a trend day rather than a rejection. That is what the H1 context label is for; it is recorded, not gated, so the failure mode is measurable instead of assumed away."* |

Pool kinds recorded: `prior_day_high`, `prior_day_low`, `equal_highs`,
`equal_lows`, `session_high`, `session_low`. Equal-high/low clusters use
`XSP_POOL_TOLERANCE_ATR`(0.15) as the cluster width.

### Every threshold this study will use, frozen here

From [XspConstants.mqh](MQL5/Include/XauStructurePro/Core/XspConstants.mqh).
None was fitted; each is either an AUDIT figure or a round number chosen before
any XSP measurement existed. **No sweep over any of them is authorised** —
[§4.4](audit/AUDIT.md) already measured `corr(win_rate, payoff_ratio) = −0.982`
across 1,078 passes, i.e. geometry search only slides along a fixed tradeoff.

```
XSP_STOP_BUFFER_ATR        0.20     XSP_ATR_PERIOD             14
XSP_POOL_TOLERANCE_ATR     0.15     XSP_DISP_ATR_MULT          1.50
XSP_SWEEP_WINDOW_BARS      3        XSP_DISP_BODY_RATIO        0.60
XSP_CONFIRM_MIN_RATIO      1.50     XSP_DISP_CLOSE_POS         0.70
XSP_CONFIRM_SLOT_SESSIONS  20       XSP_VOL_RANK_BARS          480
XSP_R_TIERS      1.0/1.5/2.0/3.0    XSP_SPREAD_RANK_SAMPLES    4096
XSP_CAP_TIERS    300/900/1800/3600  XSP_MAX_LIVE_INSTANCES     256
XSP_TF_SETUP  M15   XSP_TF_CONTEXT  H1   XSP_TF_HIGHER  H4
```

### Recorded, not gated

L1 HTF alignment, L2 regime deciles and L5 confirmation are CSV **columns**,
never filters. One run therefore measures every filter's discriminatory power
on one population, instead of needing one backtest per filter — which is also
what stops the filter search from becoming the parameter sweep §4.4 already
showed to be worthless. Gating on H1 alignment would delete the
H1-disagreeing population and with it any way to measure what H1 alignment is
worth against its own standard error, which is what §9.3 requires before a
component may be kept.

Sentinels are distinct on purpose and none of them is a value: `-1`
(`XSP_NEVER`) is "barrier not reached inside the window", not "reached at
second 0"; `-999.0` (`XSP_NO_MARK`) is "no mark at this cap", distinct from
`-1` because the stop sits at exactly `-1.0` R; decile `-1` is "the ranking
window held too few samples", **not** decile zero. The spread decile ranks
observed ticks, so the first instances of a run legitimately carry `-1`; the
report counts them and excludes them from that cut.

### What would make this study unquotable, decided in advance

`xspstudy.py` **hard-refuses** (exit 2) a file with no `# xsp:` preamble, a
schema mismatch, a header that is not the 45 expected columns in order, or no
parseable rows. It **soft-fails** (exit 1, `QUOTABLE=no` in the verdict line)
on: no trailing provenance/census block — meaning the pass never reached
`OnDeinit`, so the rows are a *prefix* of the window they name and nothing in
the rows themselves would reveal it; `RECONCILED != yes`; segment UNDECLARED;
tick model not `REAL_TICKS`; `forward != no`; `optimisation != no`; or any
violated tracker invariant. All four refusal paths and the integrity detector
were exercised against a synthetic file whose statistics were known in closed
form, and every figure the script reports matched hand computation.

`_build/xspstudy.ps1` refuses before spending the compute: `-From/-To`
alongside `-Segment DEV|VAL` (a run declaring one segment while covering other
dates is unquotable and nothing downstream could detect it); `VAL` without
`-ConfirmOneLookAtVal`; `Model < 4` without `-AllowGeneratedTicks`, which then
forces the segment to UNDECLARED. It verifies `.tkc` coverage month by month on
every pass, because MT5 falls back to bar generation **per uncovered month**
in silence while the provenance line infers one tick model for the whole run —
so the header cannot show the seam.

`.tkc` coverage is confirmed present: `bases/MetaQuotes-Demo/ticks/XAUUSD/`
holds `202505.tkc` through `202609.tkc`, so DEV and VAL are both covered on
disk. `202505.tkc` is 1.7 MB against 8.9 MB for June, consistent with the
archive starting 2025-05-27 — DEV's start sits exactly at that boundary. The
feed is a **demo** feed, not a production broker's spread.

### Data split, fixed ([§9.1](audit/AUDIT.md))

| Segment | Span | Use |
|---|---|---|
| DEV | 2025-05-27 → 2026-02-28 (9.1 mo) | Phases A and B, unlimited looks |
| VAL | 2026-03-01 → 2026-09-01 (6.0 mo) | **one** look per frozen candidate |
| bars pre-2025-05-27 | 2020-01-17 → | sanity checks only, labelled bar-generated, never for selection |

### The outcome that is permitted to be "no"

If no combination of (setup × regime × confirmation) clears both inequalities
on DEV, **the redesign stops at Phase B and reports that.** That is a real
possible outcome, it is pre-authorised here, and it is cheaper than an order
path built on nothing. VAL is not touched until a candidate is frozen and its
row above is already in this file.

### Harness corrections shipped alongside (build scripts only)

**No file under `MQL5/Include/ScalpRobotPro/` was touched and
`SRP_HARNESS_VERSION` is unchanged**, so the version stamped into every run
header still means exactly what it meant yesterday. These are `_build/*.ps1`
defaults. They change no compiled code and no trading decision — but two of
them change **which dates a default invocation covers**, so a default
`walkforward.ps1` run after this entry is not comparable with one before it.

1. **[walkforward.ps1](_build/walkforward.ps1) default windows were outside the
   real-tick archive.** They ran `2023.01.02 → 2025.08.01` in five windows;
   the archive begins 2025-05-27, so four of the five contained **no real ticks
   at all** and the fifth was ~35% covered. MT5 does not refuse an uncovered
   window — it generates ticks from M1 bars silently. Replaced with four
   consecutive non-overlapping windows tiling the §9.1 DEV span exactly
   (69/70/70/69 days, 278 total, zero gaps, zero overlap, verified
   arithmetically). VAL is deliberately **not** among them: it is one look per
   frozen candidate and a rolling script must not spend it by default.
2. **A window starting before the archive is now refused, not run** — before
   anything is compiled or deployed, since the cost of being wrong is a whole
   run of numbers that read as real. `-AllowPreTickHistory` overrides, and
   `-Model < 4` warns instead of refusing because generated ticks were then
   asked for explicitly. `Segment` now defaults to `DEV` (accurate for the new
   windows, and the *weak* claim) and accepts `VAL` as a spelling of ordinal 2,
   so the script and §9.1 stop disagreeing about the name.
3. **The malformed-window mechanism is now caught pre-flight.** The run loop
   split `from:to` and used `$parts[0]`/`$parts[1]` unvalidated, so a
   `-Windows` list collapsed across a shell boundary into one string yielded a
   nonsense `to` date and a pass with no provenance block — one of the two
   hypotheses for the audit's unquotable OOS window. It is refused now. The
   other hypothesis, "no real ticks past 2025-08", is **refuted**:
   `202505.tkc` … `202609.tkc` are all present.
4. **[runharness.ps1](_build/runharness.ps1) could not see five of eight
   verdict tokens.** The default `-Pattern` listed three, so `SRP_SCALP`,
   `SRP_VOLUME`, `SRP_NEWSGATE`, `SRP_SESSIONGATE` and `XSP_CHECK` could all
   **pass** and still be reported as "NO VERDICT LINE FOUND" — a false negative
   indistinguishable from a real failure. All eight are now listed, enumerated
   from the sources rather than guessed. Diagnostic prefixes (`XSP_STUDY`,
   `XSP_TRACK`, …) are deliberately excluded: the pattern feeds
   `Select-Object -Last 1`, so including one would let a stray note be selected
   *as* the verdict. A `-Tree` parameter was added so `XSP_CHECK` is actually
   reachable — a token no code path can emit reads as coverage that is not there.

---

## 1.11 / strategy-redesign — the XAUUSD M1 edge redesign (2026-09-05)

**Status: NOT yet compiled, NOT yet backtested.** Every claim in this entry
is a design expectation drawn from the July 2026 evidence and from cost
algebra — not a measurement. No performance figure may be quoted for 1.11
until the walk-forward plan at the foot of this entry has actually run. This
entry changes what a run *does*, materially and on every trade, so a 1.11
result is not comparable with any 1.10 result over the same dates.

### The diagnosis (why 1.10 lost ~$1,500 on $5,000)

Two arithmetic facts, not a run of bad luck, accounted for the loss.

1. **Cost was ~30% of the gross target.** A round trip is ~46.5 pts (spread
   ~34 + 6.0 commission + ~6.5 execution) and the tiers aimed at 0.55–0.70
   ATR — at ATR~238 that is only ~131–167 pts. There is no win rate that
   pays for a target that small against that cost.
2. **The gate priced a target the exit rule never reached.** The
   early-profit exit closes at 0.85 of the target; in July it fired on 42 of
   51 wins, and only 5 of 144 trades ever touched the full target. The
   break-even gate, however, priced the *full* target, so it admitted trades
   whose stated 55.7% break-even was really 61.2% once the 0.85 share was
   applied. The gate was not wrong about its arithmetic; it was arithmetic
   about the wrong number.

On top of both, the entry had no demonstrable edge: break-of-structure
supplied 135 of 144 trades and resolved its own target/stop barriers 35.4% of
the time where a driftless walk on the same barriers predicts 44.8% (SE
4.1pp, ~2.3σ *worse* than random).

### What changed (each of these changes what a run does)

1. **The gate now prices the collected target.** `CScalpController::Evaluate`
   step 6b computes `effective_target = target * early_exit_share`, and every
   test below it — spread-to-target ratio, reward:cost, net payoff, required
   win rate — is now measured against that, not the full target. This is the
   single correction that matters most.
2. **A measured win rate can only *lower* the bar.** `GateWinRate()` returns
   a tier's assumed rate until ≥30 of its trades have closed, then the
   measured rate only if it is *worse*. A tier can never trade on an accuracy
   it has not demonstrated, and a good assumption is never inflated by a lucky
   sample.
3. **Tier geometry widened from cost algebra, not a search.** SUPER
   0.55/0.45→1.35/0.60, STANDARD 0.70/0.70→1.20/0.60, SWING 1.40/0.90→1.60/0.75;
   holds 120/300/900→600/300/1800s; assumed rates 0.55/0.58/0.48→0.47/0.50/0.45.
   Changed in all four copies that had drifted apart — EA inputs,
   `CConfigurationBuilder`, the `CRuntimeConfig` fallback and the
   `CScalpController` constructor — so the startup coherence check validates
   the geometry that will actually trade.
4. **Break-of-structure is disabled as an entry.** Gold profile
   `bos_enabled=false`, `weight_bos=0.0`; the EA input default and the internal
   seed defaults follow. `CMarketStructure` still feeds structure *context* to
   the plugins that remain. The Nasdaq profile keeps BoS deliberately — the
   2.3σ evidence is XAUUSD-specific and does not travel.
5. **The signal's own structural stop is finally consumed.**
   `CLiquiditySweepStrategy` always wrote `suggested_stop = sweep.extreme_reached`
   and nothing read it. The gate now trusts that level when it falls in a band
   around the ATR stop, and the order is both placed *and sized* against that
   same distance — closing the size/placement mismatch that made 48 of 48
   trades run a stop their tier was never costed for.
6. **The weighted vote resolves its carrier by `confidence*weight`,** matching
   how the winning *direction* was already chosen, so plugin weight finally
   governs whose geometry is traded. Sweep confidence was rescaled from a
   four-way mean to the base+increment convention the other plugins use, so
   the contest is between comparable numbers.
7. **SWING is reachable.** `SelectScalpTier` routes HIGH/EXTREME volatility to
   SWING, the TRANSITION regime to STANDARD, and everything else to SUPER.

### What was kept

All of Fixes 1–5 and the entire risk/safety layer. Volume is still computed
from the stop the trade actually carries. The 0.25% per-trade risk ceiling,
the exposure ceiling, daily-loss protection, the session filter and the
cooldowns are untouched. No martingale, grid, recovery sizing or trade quota
was added, and no risk control was loosened to raise return.
### What was deliberately NOT done

No parameter optimization or sweep. The geometry is derived from the cost
model; a sweep tuned on the loss period would overfit it. The Nasdaq profile
and the neutral-baseline `Reset()` seed were left alone — there is no
non-XAUUSD evidence to act on. Trade frequency will *fall*: wider targets are
touched less often, which the July holding-time data independently supports
(the 0–10s bucket lost $4.30/trade and the 61–120s bucket was flat). Fewer,
better-priced trades is the intended trade, not a side effect to be corrected.

### The self-test harness (changes no trading decision)

`ScalpCheck.mqh`'s shared controller now lifts the STANDARD tier's assumed
win rate to the 0.90 ceiling. The break-even gate above prices the *collected*
target, and would otherwise refuse the very trades the cost, spread, duplicate
and cooldown cases need admitted in order to exercise their own gates — all of
which run *before* the break-even test. The refusal cases are untouched (they
block earlier), and no case in the file asserts a break-even block, so the lift
can only ever relax the one gate this unit harness was never built to assert.
Break-even economics are validated by steps 2–4 below, not here, because the
harness reads a live ATR whose magnitude is not fixed across data sets. This is
a test-only edit: it moves no order and alters no shipping default.

### Validation that must run before any 1.11 number is quoted

1. **Compile** clean — 0 errors, 0 warnings (Matin runs the Windows toolchain
   here; this environment cannot).
2. **Barrier falsification** on the redesigned entries: observed
   P(target-first) must not sit below the driftless-walk prediction
   `stop/(stop+target)`. If it does, the entry has no edge and no geometry
   rescues it — that result would condemn the redesign, and it is pre-declared
   here so it cannot be explained away afterward.
3. **Walk-forward twice** via `_build/walkforward.ps1`: once `-PinSpread 34`
   for comparability with the Fix 5 captures, once unpinned for realism;
   commission modelled; DEV segments only during design; the 2025.08-onward
   span held out as OOS and not looked at until the design is frozen.
4. **A/B** against the current build via `_build/abdiff.py`, so the change is
   measured as a difference, not an absolute.

Only step 1 is a code property; steps 2–4 decide whether the edge is real.
Until they run, 1.11 is a hypothesis with its arithmetic shown.

## 1.10 / harness-v2 — the measurement harness (2026-09-04)

**Status: fixes 1–5 compiled, deployed and behaviourally verified.** Fix 5's
evidence pass ran on 2026-09-04 against `ScalpRobotPro.ex5` 769,544 bytes,
sha256 `61e7c7b1…`; the four runs and their captures are in `_build/_fix5/`.
One thing that pass established is worth reading before any figure from a
pinned run is quoted: a pin of 13.00 pts on a tape averaging 34.17 pts is
reproducible but *unrepresentative*, and the EA says so and refuses to be
quoted. Reproducibility and representativeness are separate properties, and
`InpPinSpreadSample` only buys the first.

Fixes 1–4: `_build\build.ps1` (MetaEditor) compiled the tree with 0 errors
and 0 warnings; the binary was deployed to
`C:\Program Files\MetaTrader 5\MQL5\Experts\ScalpRobotPro\` (sha256
`fe1d4db6…`, 760,888 bytes) and has been run on real ticks. The fix-4
identity test below establishes that fixes 2 and 4 move no order.

Fix 5: the checker command at the end of this entry reports
`CHECKS=26 FAILED=0 VERDICT=PASS` with both configuration chains resolved,
and the `StringFormat` call sites in the ten files it touches are
arity-correct (79 checked, 0 mismatches). Behaviour was then established by
the four-run evidence pass recorded under "Fix 5 — verified" below.

**Results from 1.00 and 1.10 are not comparable, and this is deliberate.**
Section 11 step 2 of the audit asks for five harness changes and says none
of them changes a trading decision. That is true of the code paths, but two
of them change run behaviour through their *defaults*, which is the honest
caveat:

- Fix 1 means a −2% day no longer ends the run, so 1.10 runs cover periods
  that 1.00 runs truncated. Every historical result in this project stopped
  at its first bad day, which flattered the survivors.
- Fix 3 ships `InpScalpCommissionPoints = 6.0` where the modelled cost was
  previously zero. Same entries, worse arithmetic, and the worse one is the
  real one.

A 1.00 result and a 1.10 result over the same dates are therefore two
different experiments. Comparing them measures the harness, not the edge.

### Fix 1 — the daily stand-down is separated from the drawdown latch

`CProductionEngine` routed every verdict that demanded a flatten into
`EmergencyFlatten`, which arms two latches that never auto-clear. A routine
losing day therefore ended the run outright. Breaches are now routed by
type: `DAILY`/`WEEKLY`/`MONTHLY` stand down and rearm at the next window,
`DRAWDOWN`/`EMERGENCY` stay terminal.

- New input `InpDailyLimitTerminal = false` restores the old behaviour for
  anyone who wants it.
- Stand-downs are counted (`StandDownCount()`) and reported, so a run that
  spent a month flat cannot be read as a run that found no setups.

**Changes what a run does:** yes, through the default. This is the fix that
makes drawdown measurable at all.

### Fix 2 — slippage is measured on server-side fills

Stop and target fills executed by the broker were never measured, so the
one place where execution cost is unavoidable was invisible. Server-fired
exits are now detected and their signed deviation from the trigger price
accumulated: count, SL/TP split, average, worst, and money total.

The zero case is the one that matters. `ServerFillsAllExact()` is true when
every server fill landed exactly on its trigger, which is not execution
quality — it is 1-minute OHLC generation placing the fill on the barrier by
construction. When it is true the report says so, and Fix 4 makes the same
predicate deny the run's quotable verdict, so the header cannot carry the
warning and claim to be quotable at the same time.

**Changes what a run does:** no. Observation only.

### Fix 3 — commission is a parameter with a non-zero default

New input `InpScalpCommissionPoints = 6.0` (points per round trip,
1 pt = $1/lot), carried through `scalp.commission_points` to
`CScalpController`, where it enters the round-trip cost that gates entries
and sets the early-exit floor. Previously modelled as zero.

**Changes what a run does:** yes, through the default. A 6-point round trip
against a 95–200 point stop is 3–6% of the risk budget, and it correctly
refuses setups that only cleared the bar when the cost was pretended away.

### Fix 4 — every report states what produced it

The audit found real numbers being quoted with no record of the tape that
made them. A profit factor and a win rate in a summary row are useless
without the tick model beside them, and the tick model was nowhere near
them. `CRunProvenance` now formats one block that opens every report:

- **build** — product version and harness version.
- **instrument** — symbol and timeframe.
- **terminal** — `tester`, `optimisation`, `visual`, `forward`. These four
  are the only run facts the terminal actually confirms.
- **TICK MODEL** — real ticks / generated / live, followed on its own line
  by `INFERRED, the terminal does not report this`. MQL5 exposes no API for
  the tester's generation mode, so this is deduced from median ticks per
  minute and median distinct spreads per minute. The caveat is a separate
  line rather than part of the verdict text, and the machine-readable field
  is named `tick_model_inferred`, because a column name is the only place a
  caveat survives being sorted into a spreadsheet.
- **cost model** — the sampled startup spread, commission, execution cost,
  minimum reward/cost ratio, and the target and early-exit floors, each
  marked `derived` or `configured`.
- **data segment** — `UNDECLARED` / `DEV` / `OOS`, from the new input
  `InpRunDataSegment` (key `general.data_segment`). Defaults to
  `UNDECLARED`, which makes the run non-quotable as in-sample or
  out-of-sample evidence. Only the operator knows whether a span was held
  out, so only the operator can declare it.
- **QUOTABLE** — `yes` only when no warning is outstanding. The verdict is
  defined as "the warnings list is empty", so a warning can never be added
  without the verdict seeing it.

Two supporting changes:

- The provenance block is printed *above* the no-closed-trades early return
  in `CTraderInterface::PublishSessionReport()`. An empty result with no
  conditions stated is the one report that gets misremembered as "it just
  does not trade".
- `CScalpController` now samples the startup spread unconditionally and
  tracks which of the three derived distances were actually derived, so the
  header can state the sample even when everything was configured
  explicitly, and the "startup sample vs run average" warning is only
  raised where it costs the run something.

This also fixed a latent misreport: `SetCostModel` was fed
`m_config.scalp_target_min_points` and `scalp_early_exit_min_points`, which
are `0.0` in the ordinary "let the code derive it" case, so the header could
print a `0.00 pts` floor for a run that was enforcing a derived one. The
effective values are now read back from the enforcer after `Initialize()`.

**Changes what a run does:** no. Reporting only.

### Verification — the fix-4 identity test

The claim that fixes 2 and 4 are observation-only is the kind of claim that
is easy to make and easy to be wrong about, so it was measured rather than
asserted. `_build/abcompare.ps1` runs the preserved 1.00 binary and the
1.10 binary under identical conditions and `_build/abdiff.py` compares the
two decision streams order by order.

Fixes 1 and 3 provably *do* change decisions, so they were switched off by
input rather than by choosing a flattering period —
`InpScalpCommissionPoints=0.0` restores the 1.00 cost model and
`InpDailyLimitTerminal=true` restores the 1.00 latch. What remained between
the two binaries was fix 2 and fix 4.

XAUUSD M1, 2026.09.01 → 2026.09.02, every tick based on real ticks, 5,000
USD at 1:100, `InpCapitalBase=1`:

| | 1.00 baseline | 1.10, fixes 1+3 off |
|---|---|---|
| signals → entries | 25 → 15, 9 blocked on COST | 25 → 15, 9 blocked on COST |
| entry gates | accuracy=5 scalp=9 riskEngine=1 | accuracy=5 scalp=9 riskEngine=1 |
| risk engine | 15 approvals, 1 rejection, day 2.04%/2.00% | 15 approvals, 1 rejection, day 2.04%/2.00% |
| trade events | 46 | 46 |
| final balance | 4897.76 USD | 4897.76 USD |

**Identical: 46 trade events at the same modelled times, the same prices,
in the same order.** On this period, fixes 2 and 4 moved nothing.

Two things make this more than a pair of matching numbers:

- **The baseline reproduced a figure it did not know about.** Two 1.00
  passes run from the GUI on 2026-09-03 over this period both ended at
  4897.76 USD. The scripted baseline reproduces it exactly, which is what
  establishes that the staged binary and the generated input set are
  faithful — a baseline that cannot reproduce itself is not a baseline.
- **The breach path was exercised, not avoided.** The day limit was
  exceeded on both sides (2.04% against 2.00%) and both runs latched and
  stopped. The handoff asked for "a period with no daily breach"; using the
  input instead means the divergent code path actually ran and still agreed.

Limits of the test, stated because they are the reason it is not the whole
answer: it covers one trading day and 15 entries, it ends at the daily-limit
latch, and it does not exercise the weekly or monthly breach routing, which
fix 1 also changes and which no input can neutralise. Artefacts are in
`_build/_ab/`: both captured passes, the two 1.00 control passes the differ was
validated against, and the complete 252- and 254-input `.set` files the two
sides actually ran.

### Fix 5 — the trade geometry has one root, and the root can be pinned

Twelve trading distances descend arithmetically from a single
`SymbolInfoInteger(SYMBOL_SPREAD)` read once at init — with a `10.0` point
fallback when that read fails — and nothing re-derives them afterwards
(audit §5.5). Two runs of the same configuration over the same period
therefore trade different distances, because they sample different ticks: a
95-point stop and a 200-point stop are both reachable from one `.set` file,
and neither run recorded which one it used. That is why no result this
project has produced was reproducible, including the ones that looked good.

The fix pins the **root**, not the twelve leaves. All twelve are pure
functions of that one number plus `spread_float` and `broker_min`, so one
input is both sufficient and a truer statement of the defect than twelve
separate pins would be.

- **`InpPinSpreadSample`** — double, points, default `0.0`; key
  `general.pin_spread_sample`. At `0.0` the live tick is sampled exactly as
  before. Any positive value is used in its place.
- **Three sampling sites, all pinned from that one input.** The audit named
  one. There are three, and a fix that pinned only the first would have
  produced a report claiming a reproducibility the cost model did not have:
  `CSymbolClassifier::Resolve` called from `OnInit` step 1, which feeds the
  sealed configuration's geometry; the *second* `Resolve`, inside
  `CProductionEngine`, which feeds the regime and volatility bands; and
  `CScalpController::Initialize`, which feeds execution cost, the target
  floor and the early-exit floor.
- **`derived_mask`** — a new `ENUM_SRP_GEOM_DERIVED` bitfield on
  `SMarketProfile`, set at each of the thirteen assignment sites in
  `ScaleToSymbol` as the assignment is made. It records which distances the
  code actually derived rather than which ones it could have, so a profile
  that presets all twelve is reported as presetting all twelve instead of
  being described from a table of intentions.
- **`GEOMETRY DERIVATION`** — printed at init by both the entry point and the
  engine: the sample, whether it was pinned or read, all twelve values each
  marked `derived from the sample` or `preset/configured`, how many descend
  from the sample, and — when unpinned — an explicit `! NOT REPRODUCIBLE`
  line. `sl_min_points` is listed apart and excluded from the count: it is
  an intermediate feeding `sl_fixed`, `breakeven_offset` and `trail_step`,
  and never reaches the sealed config.
- **Provenance.** A `GEOMETRY   :` line joins the fix-4 header, and under
  `MQL_TESTER` an unpinned run raises `! GEOMETRY NOT PINNED`, which denies
  `QUOTABLE` — the verdict is defined as "no warnings outstanding", so this
  needed no separate wiring. The CSV export gains a seventh column,
  `geom_pinned` (`undeclared` / `yes` / `no`), because an optimisation
  export is exactly where one row in a thousand gets quoted, and an unpinned
  row cannot be re-run.

The warning fires only in the tester, on purpose. A live run's geometry
*should* fit the broker it is trading with, there is no rerun for it to be
faithful to, and a warning that can never be cleared would make `QUOTABLE`
meaningless on live results. The derived count is reported rather than used
as a gate for the same reason: the scalp controller samples independently
even when the profile preset all twelve distances.

`CConfigValidator` rejects a negative pin as an **error**, not a warning. A
negative value fails the `>0` test inside `PinSpreadSample`, so the run
would sample the live tick while the configuration claimed to be pinned —
the one outcome worse than not pinning at all. Above 500 points it warns
instead, since nothing on this feed has been observed there but a stress
test is a legitimate reason to ask.

Two structural defects found on the way were **documented and left alone**,
because fixing either would move a trading decision and this fix is not
permitted to:

- The double `Resolve`. Collapsing it into one shared struct would change
  which numbers the regime engine sees.
- `CProfileApplier` does not copy `sl_min_points`. It is an intermediate, so
  nothing downstream misses it today, but the omission is a trap for anyone
  who later assumes an applied profile is complete.

**This is a reproducibility fix, not a design fix.** That a static geometry
is used at all is audit §8.2, and making it responsive to conditions is a
strategy change belonging to step 6.

**Changes what a run does:** not at the default. `0.0` samples the same tick
and derives the same twelve distances as 1.10 did before this fix, so
nothing already measured is invalidated. At any other value it changes every
one of the twelve, and therefore entries, exits and sizing — which is what
the input is for, and why the default is `0.0` rather than a "sensible"
number.

Verified without a compiler: `python _build/srpcheck.py MQL5
--chain=pin_spread_sample=GENERAL_PIN_SPREAD_SAMPLE` reports `chain OK`
with both consumers found and `VERDICT=PASS`, and the `StringFormat` sites
in the ten touched files are arity-correct (79 checked, 0 mismatches).
**Verified 2026-09-04 by a four-run pass on XAUUSD M1 real ticks,
2026.09.01–02, every run declaring `InpRunDataSegment=2`.** Captures,
per-run byte offsets and the normalised geometry blocks are in
`_build/_fix5/`.

- **A and B, both `InpPinSpreadSample=13.0`.** Identical
  `GEOMETRY DERIVATION` blocks, 38 lines each — same sample, same twelve
  distances, `PINNED by InpPinSpreadSample`, `11 of the 12` derived (the
  twelfth, `deviation_points`, prints `preset/configured` because it does
  not descend from the sample). `abdiff.py` reports `IDENTICAL: 46 trade
  events, same modelled times, same prices, same order`, and both runs end
  at `final balance 9811.52 USD`. That is the reproducibility claim.
- **D, `InpPinSpreadSample=40.0`.** The proof that the pin is not inert,
  which A-against-B cannot give on its own: every derived distance scales
  by exactly 40/13 (`sl_fixed` 312→960, `tp_fixed` 468→1440, `trail_step`
  31.2→96, `max_spread` 52→160), `deviation_points` stays at 20.00, and
  the deal stream diverges — 46 events against 43, first divergence at
  event 6, `final balance 9899.31`. The pin reaches the geometry and the
  geometry reaches the orders.
- **C, the unpinned control at `0.0`.** Prints `spread sample: 13.00 pts
  (LIVE, read once at init - NOT reproducible)` and `read from the tick
  current at init`, raises both `! GEOMETRY NOT PINNED` and `! NOT
  REPRODUCIBLE: rerunning this configuration samples a different tick`,
  and carries `geom_pinned=no` with `QUOTABLE   : NO`.

**What the control does not show.** The live tick at init on this period
happened to be 13.00 pts — the same value the pinned runs were given — so C
derived A's distances and placed A's orders. C therefore demonstrates that
an unpinned run *labels itself* correctly; it does not demonstrate that an
unpinned run varies. Run D carries that half of the argument instead. A
control on a period whose init tick differs from the pin would show both at
once, and is worth running when one is to hand.

**A second finding from the same pass, which matters more than the fix.**
All four runs report `QUOTABLE   : NO`, and with the segment declared OOS
the sole remaining reason is `! STARTUP SPREAD SAMPLE 13.00 pts vs run
average 34.17 pts` (`spread_min_pts=8`, `spread_max_pts=8038`). The refusal
is correct: every run above sized its geometry from a sample around a third
of the spread it actually traded through, and `blocked by: COST=10` of 25
signals is what that looks like downstream. Pinning makes a run repeatable,
not representative. Audit step 3 is closed; the question of what sample a
quotable run should be pinned to is not, and it is a strategy question, so
it waits.


### Harness scripts

- [abcompare.ps1](_build/abcompare.ps1) and [abdiff.py](_build/abdiff.py) —
  new. The identity test above. `abcompare.ps1` stages both binaries in
  `Experts\SRP_AB\` with no `.mq5` beside them, so neither side of an
  experiment can be silently recompiled from whatever source is current;
  generates one *complete* `.set` per side from that side's own source,
  because the two binaries do not declare the same input list; and reconciles
  them, aborting if any shared input differs for a reason that is not part of
  the experiment. `-SetsOnly` stages and reconciles without launching.
  `abdiff.py` compares the deal streams with serial numbers normalised away,
  and refuses to answer when a capture holds more than one pass.
- [makeset.ps1](_build/makeset.ps1) — maps `SRP_SEGMENT_UNDECLARED/DEV/OOS`
  to ordinals. Without this the new enum input would have been written as a
  name, arrived as `0`, and every scripted OOS run would have silently
  reported itself as UNDECLARED — the exact omission Fix 4 exists to close.
- [walkforward.ps1](_build/walkforward.ps1) — new `-Segment` parameter
  (`UNDECLARED` default, `DEV`, `OOS`) forwarded to the tester as
  `InpRunDataSegment`; the summary table gained `tape` and `quotable`
  columns lifted from each window's provenance block, defaulting to
  `NOT REPORTED`, and a warning counting windows that produced no
  provenance block at all. Fix 5 added `-PinSpread <points>` (default `0.0`,
  formatted in invariant culture so a comma-decimal machine cannot write
  `13,00` and split the override list), plus `spreadPts` and `pinned`
  columns and two more warnings: one counting windows that each derived
  their own geometry, and one that fires when pinned windows disagree about
  the sample, which would mean the override never reached them. Without the
  pin the windows were never comparable with each other — window 1 could
  trade a 95-point stop and window 4 a 200-point stop, and the table read
  that as the edge changing over time.

Two defects in the existing harness surfaced while running the identity test,
both of the kind that produce a plausible wrong number rather than an error:

- **[backtest.ps1](_build/backtest.ps1) mixed passes into one report.** The
  per-run log cutoff was applied once to the concatenation of every log file,
  but the Tester log and the agent log each span the whole day, so the tail of
  the first file was kept *and the whole of the second*. The first A/B capture
  came back holding six earlier passes, and their counters read as a
  divergence between the two binaries. Now applied per file. Any earlier
  report from this script that looked like it contained more results than the
  run it named was this. **Changes what a run does:** no — reporting only,
  but it changes what past reports should be trusted to say.
- **The terminal's saved input set deviates from the source defaults.** Both
  1.00 and 1.10 declare `InpCapitalBase = SRP_CAPITAL_EQUITY` (0), yet every
  recorded pass in the logs — 1.00 and 1.10 alike — ran with `1` (BALANCE),
  from an input set saved in the GUI. Risk sizing reads it, so it moves lot
  sizes and therefore decisions: a GUI run and a scripted run over the same
  period are *not* the same experiment unless it is pinned. `abcompare.ps1`
  pins it on both sides, which is what let the baseline reproduce 4897.76.

The `-Segment` default is `UNDECLARED` rather than `OOS` on purpose. Every
window runs the shipping configuration unfitted, so nothing was tuned to any
individual window — but the shipping defaults were themselves chosen with
some of this history in view, and a script cannot know how much.

### Sites

Line numbers are as of 2026-09-04 and will drift; the named symbols will not.

Fix 1 — breach routing [CProductionEngine.mqh:2413](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:2413),
`StandDownForDay` [:2961](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:2961),
`StandDownCount` [:341](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:341),
input [ScalpRobotPro.mq5:183](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:183).

Fix 2 — exit capture [CProductionEngine.mqh:3034](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:3034),
`ServerExitSummary` [:3053](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:3053),
`ServerFillsAllExact` [:3077](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:3077).

Fix 3 — input [ScalpRobotPro.mq5:348](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:348),
default [CRuntimeConfig.mqh:399](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:399),
`ConfigureCosts` [CScalpController.mqh:776](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:776),
entry cost gate [:1137](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:1137),
early-exit floor [:860](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:860).

Fix 4 — `Warnings` [CRunProvenance.mqh:470](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:470),
`IsQuotable` [:557](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:557),
`Header` [:570](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:570),
`HeaderCsv` [:631](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:631),
`CsvColumns` [:678](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:678),
`TickModelText` [:416](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:416);
declaration into the observer [CProductionEngine.mqh:1499](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:1499)
and [:1517](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:1517);
preamble printed above the early return
[CTraderInterface.mqh:500](MQL5/Include/ScalpRobotPro/Interface/CTraderInterface.mqh:500),
`EffectivePreamble` [:516](MQL5/Include/ScalpRobotPro/Interface/CTraderInterface.mqh:516);
spread sample [CScalpController.mqh:834](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:834),
`DescribeCostModel` [:1490](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:1490).

Fix 4, data segment — input [ScalpRobotPro.mq5:492](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:492)
and snapshot [:787](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:787),
key [CConfigKeys.mqh:29](MQL5/Include/ScalpRobotPro/Configuration/CConfigKeys.mqh:29)/[:348](MQL5/Include/ScalpRobotPro/Configuration/CConfigKeys.mqh:348),
builder [CConfigurationBuilder.mqh:285](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:285)/[:665](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:665)/[:1016](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:1016),
runtime [CRuntimeConfig.mqh:183](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:183)/[:409](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:409)/[:653](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:653)/[:815](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:815),
validator warning [CConfigValidator.mqh:703](MQL5/Include/ScalpRobotPro/Configuration/CConfigValidator.mqh:703).

Fix 5 — input [ScalpRobotPro.mq5:519](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:519),
snapshot [:817](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:817),
pin applied at OnInit step 1b [:914](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:914),
derivation printed [:942](MQL5/Experts/ScalpRobotPro/ScalpRobotPro.mq5:942);
`PinSpreadSample` [CSymbolClassifier.mqh:198](MQL5/Include/ScalpRobotPro/Profiles/CSymbolClassifier.mqh:198),
`spread_pinned` [:100](MQL5/Include/ScalpRobotPro/Profiles/CSymbolClassifier.mqh:100),
`Describe` [:499](MQL5/Include/ScalpRobotPro/Profiles/CSymbolClassifier.mqh:499);
`ENUM_SRP_GEOM_DERIVED` [CMarketProfile.mqh:51](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:51),
profile fields [:256](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:256),
`DerivedCount` [:475](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:475),
`DerivationRow` [:500](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:500),
`DescribeDerivation` [:512](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:512),
mask sites in `ScaleToSymbol` [:1008-1117](MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh:1008);
`ConfigureSpreadPin` [CScalpController.mqh:813](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:813),
pin applied [:887](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:887),
`DescribeCostModel` [:1559](MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh:1559);
second sample pinned [CProductionEngine.mqh:478](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:478),
controller wired [:1168](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:1168),
`SetGeometry` call [:1555](MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:1555);
`SetGeometry` [CRunProvenance.mqh:384](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:384),
`GeometryText` [:518](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:518),
warning [:617](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:617),
`Header` [:722](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:722),
`HeaderCsv` [:773](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:773),
seventh CSV field [:823](MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh:823);
key [CConfigKeys.mqh:37](MQL5/Include/ScalpRobotPro/Configuration/CConfigKeys.mqh:37)/[:357](MQL5/Include/ScalpRobotPro/Configuration/CConfigKeys.mqh:357),
builder [CConfigurationBuilder.mqh:289](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:289)/[:674](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:674)/[:1030](MQL5/Include/ScalpRobotPro/Configuration/CConfigurationBuilder.mqh:1030),
runtime [CRuntimeConfig.mqh:196](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:196)/[:671](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:671)/[:837](MQL5/Include/ScalpRobotPro/Runtime/CRuntimeConfig.mqh:837),
validator [CConfigValidator.mqh:715](MQL5/Include/ScalpRobotPro/Configuration/CConfigValidator.mqh:715).

### Verification commands

```bash
python _build/srpcheck.py MQL5 --chain=data_segment=GENERAL_DATA_SEGMENT --chain=pin_spread_sample=GENERAL_PIN_SPREAD_SAMPLE
```

The root argument (`MQL5`) is required; omitting it makes the checker read
the `--chain=` string as the root and fail with a confusing
`FileNotFoundError`.

---

## 0 — Forensic audit (2026-09-03)

Entry zero is not a change. It is a read-only investigation of the 1.00
build, and it is in this file because it is the point at which the project's
recorded history stops being usable evidence.

**Files modified: none.** `_baseline_original_20260903/` holds a
byte-identical copy of the 265 files as they stood, and is never edited.

**Verdict: C — the system should be fundamentally redesigned.** Full
reasoning in [AUDIT.md](audit/AUDIT.md) §12. The findings that matter for
anything measured after this date:

- **Every profitable backtest in the project's history came from 1-minute
  OHLC tick generation.** With 209 byte-identical trading inputs over
  identical days, OHLC generation gives profit factor 1.126 and real ticks
  give 0.853. The share of trades reaching target falls from 39.2% to 6.5%.
- **On this feed OHLC generation models the spread at 4.0–4.4 points where
  reality is 9.5–33.5**, fills every stop exactly at its price (12,774 of
  12,774 losers at precisely −1.000 R), and cannot represent price movement
  shorter than 20 seconds — for a strategy whose median hold under real
  ticks is 22 seconds.
- **Profitability across eleven runs tracks modelled spread and nothing
  else**, with perfect separation at the 4.4/9.5-point boundary, p = 0.0022.
- **Every real-tick run lost:** five runs, 196 trades, −0.128 R per trade.
  Unanimous in direction, p ≈ 0.07 on its own, treated as corroborative
  rather than conclusive.
- **The calibration constants rest on a dataset that cannot exist here.**
  The GOLD profile and the accuracy filter are fitted to "31 months of real
  ticks"; this terminal holds 15.2 — and by the developer's own recorded
  figures that dataset was itself losing 0.145 R per trade, t = −5.23.
- **The trade geometry is inherited from one tick,** not designed: stop,
  target, break-even trigger and offset, trailing distance and step, maximum
  spread gate, slippage allowance and structure-break buffer all descend
  arithmetically from a single spread measurement taken once at
  initialisation, and nothing re-derives them.
- **No backtest in this project ever survived a bad day.** The best result in
  the history — profit factor 1.548 — earned it by stopping on 2026-06-16,
  just as it started to break.

Nineteen defects are catalogued in §5, three Critical. The audit's own
position is that fixing all of them yields a correctly-implemented version
of a strategy that has never shown an edge on data that can be trusted, so
the measurement apparatus is rebuilt first (1.10, above) and the strategy
question is asked afterwards.

