# Deployment Guide

Taking Scalping Robot Pro from a compiled EA to a live account. Installation is covered
in `INSTALLATION.md`; this document is about running it safely in production.

## The staged path

Skipping stages is how accounts get damaged. Each stage answers a question the previous
one cannot.

| Stage | Duration | Question it answers |
|---|---|---|
| 1. Integration check | seconds | Does the object graph build and tear down cleanly? |
| 2. Backtest | minutes | Does the strategy have an edge on history? |
| 3. Walk-forward | hours | Is that edge real or curve-fitted? |
| 4. Demo forward test | 2–4 weeks | Does it survive live spreads, slippage and latency? |
| 5. Live, minimum size | 4+ weeks | Does it behave identically with real money? |
| 6. Live, target size | ongoing | — |

Stage 4 is the one most often skipped and the one that catches the most. A backtest
cannot model your broker's spread behaviour at the cash open, requotes, or a weekend
gap against an open position.

## Stage 1 — integration check

Attach `Scripts\ScalpRobotPro\P6ProductionCheck` to any chart.

```
SRP_RESULT CHECKS=74 FAILED=0 VERDICT=PASS
```

Anything other than `FAILED=0` means stop and investigate. This takes seconds and is
worth running after every configuration change you do not fully trust.

## Stage 2 — backtest

See `BACKTESTING.md`. Two things to note before you believe a number:

**Model choice.** "Every tick based on real ticks" is the only model that reflects
intrabar behaviour honestly. "1 minute OHLC" is roughly 40x faster and adequate for
parameter exploration, but it fills at prices that may never have existed inside the bar.

**News filtering is inactive in the tester unless you supply a CSV.** The terminal's
economic calendar returns *today's* events regardless of the simulated bar, so consulting
it during a backtest is look-ahead bias. The engine refuses to do that and says so:

```
Scalping Robot Pro: news filtering is INACTIVE for this test. ... Results do not
account for news. Set the news CSV input to model it.
```

Your backtest therefore trades through releases that the live robot would sit out.
Treat backtested results as an upper bound until you supply a news CSV.

## Stage 3 — walk-forward

Optimising and then reporting the best in-sample pass is self-deception. Walk-forward
splits history into in-sample and out-of-sample windows and asks whether the parameters
chosen on the first half survive the second. See `OPTIMIZATION.md`.

Reject the parameter set if walk-forward efficiency is below 0.5. In-sample brilliance
with no out-of-sample edge is the signature of curve-fitting, and the analyzer names it:

```
curve-fitted: in-sample brilliance, no out-of-sample edge
```

## Stage 4 — demo forward test

Run on a demo account from the *same broker and account type* you intend to trade live.
A demo on a different server tells you very little.

Watch for:

- **Slippage** — the dashboard reports average slippage. If it materially exceeds
  `InpMaxSlippagePoints`, your stops and targets are optimistic.
- **Spread at the open** — index spreads can multiply for the first minutes.
  `InpMaxSpreadPoints` should reject the spike without blocking normal trading.
- **Execution latency** — logged per order when the execution channel is enabled.
- **Trade count** — should be within a factor of two of the backtest over comparable
  conditions. A large divergence means a filter is behaving differently live.

Compare the demo trade count and win rate against the backtest for the same period. They
will not match exactly. They should be recognisably the same system.

## Stage 5 — live at minimum size

Set `InpFixedLot` to the broker minimum, or `InpRiskPercent` to 0.1, whichever sizing
model you use. The goal is not profit; it is confirming behaviour with real fills.

Run for at least four weeks or thirty trades, whichever is longer. Thirty is the
`InpOptMinTrades` default for a reason: below that, results are noise.

### Pre-flight checklist

- [ ] Integration check passes on the live terminal
- [ ] `InpMagicNumber` is unique across every EA on the account
- [ ] Risk per trade is below the daily loss limit — the validator enforces this, but
      confirm the numbers are what you intended
- [ ] `InpKillSwitchEnabled = true`
- [ ] `InpFlattenOnTrip` set deliberately (see below)
- [ ] News filter enabled with a live calendar
- [ ] Terminal set not to sleep or hibernate
- [ ] VPS or always-on machine if trading sessions you will not be awake for

### `InpFlattenOnTrip`

When a guard trips, this decides whether open positions are closed or left to their
stops.

`true` — flatten. Correct when you cannot supervise the account: a tripped drawdown
guard means something is behaving unexpectedly, and holding risk through that is a
choice you would not make deliberately.

`false` — leave positions to their stops. Correct when you are watching and would
rather not realise a loss that may recover within the existing stop.

There is no universally right answer, which is why it is configurable and why the
default is documented rather than hidden.

## Stage 6 — target size

Increase size gradually. Doubling risk does not double return; it more than doubles the
depth of a normal losing streak.

Recheck walk-forward validity quarterly. Market regimes change, and a parameter set that
was robust for a year can decay.

## Running multiple instances

Supported, with one rule: **every instance needs a distinct `InpMagicNumber`.**

Positions are filtered by magic *and* symbol, so instances never touch each other's
trades. State files are namespaced per symbol and magic
(`risk_state_<symbol>_<magic>.csv`), so latched guards do not collide either.

What is *not* isolated is the account. Two instances each risking 1% risk 2% together,
and each enforces its own daily loss limit independently. Set per-instance limits with
the total in mind.

## Persistence and restarts

Latched guards survive a restart. Drawdown is measured from a persisted all-time equity
peak, so restarting the terminal does not reset a drawdown limit and hand the robot a
fresh budget to lose.

State lives in `MQL5\Files\ScalpRobotPro\State\`. Deleting it resets latched guards and
the peak — occasionally what you want after a deliberate account change, never something
to do casually.

The kill switch clears only by human action. That is the point of it.

## Monitoring

The dashboard covers a glance. For anything more, the log channels are:

| Channel | Default | Use |
|---|---|---|
| Errors | on | always keep on |
| Trades | on | the audit trail |
| Risk events | on | why a trade was refused or resized |
| Performance | on | periodic analytics |
| Execution time | on | slippage and latency |
| Indicators | **off** | highest volume; a diagnostic, not a production need |

Logs go to `MQL5\Files\ScalpRobotPro\Logs\` with daily rotation.

## What to do when it stops trading

It is explained, not mysterious. On shutdown, and whenever a run took no entries, the
engine prints a decline tally naming the gate that refused:

```
declines by reason: NEWS_BLOCKED=117742 SESSION_BLOCKED=6893
```

Read that before changing settings. Most "it stopped working" reports are a session
filter, a news blackout, or a tripped guard doing exactly what it was configured to do.

---

Trading involves substantial risk of loss. No amount of testing removes it.
