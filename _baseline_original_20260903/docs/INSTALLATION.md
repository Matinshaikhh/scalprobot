# Installation Guide

Scalping Robot Pro is source-distributed. There is no installer: you copy two folders
into MetaTrader's data directory and compile one file.

## Requirements

| | |
|---|---|
| Terminal | MetaTrader 5, build 3000 or later |
| Language | MQL5 with `interface` support |
| Account | Hedging or netting; both are detected and handled |
| Instrument | Any. Tuned for NASDAQ (US100/NAS100) on M1–M5 |
| Disk | ~2 MB of source, plus logs |

Build 3000+ matters because the architecture uses `interface` types and `override`,
neither of which older compilers accept.

## 1. Find your data folder

In MetaEditor or the terminal: **File → Open Data Folder**. This is *not* the install
directory. A typical path looks like:

```
C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<32-hex-id>\
```

If the terminal runs in portable mode (`/portable`), the data folder is the install
directory itself.

## 2. Copy the source

```
MQL5\Include\ScalpRobotPro\   ->  <Data Folder>\MQL5\Include\ScalpRobotPro\
MQL5\Experts\ScalpRobotPro\   ->  <Data Folder>\MQL5\Experts\ScalpRobotPro\
MQL5\Scripts\ScalpRobotPro\   ->  <Data Folder>\MQL5\Scripts\ScalpRobotPro\   (optional)
```

The `Scripts` folder holds verification harnesses. They are not needed to trade, but
they are the fastest way to prove the installation is sound.

Include paths inside the project are relative, so no project configuration is required.

## 3. Compile

Open `MQL5\Experts\ScalpRobotPro\ScalpRobotPro.mq5` in MetaEditor and press **F7**.

Expected result:

```
0 errors, 0 warnings
```

Anything else means the copy was incomplete — most often `Include\ScalpRobotPro\`
landed one level too deep. The compiler names the first missing header.

## 4. Verify before trading

Compiling proves the code is well formed. It does not prove the engine can build its
object graph, tick, and tear down cleanly. Run the integration harness for that:

Attach `Scripts\ScalpRobotPro\P6ProductionCheck` to any chart and read the Experts tab.

```
SRP_RESULT CHECKS=74 FAILED=0 VERDICT=PASS
```

`FAILED=0` is the only acceptable outcome. The harness builds the full engine,
pumps 250 ticks through the real pipeline, exercises the optimisation engine, and
tears everything down. It never sends an order: it halts the engine before ticking,
so `OrderSend` is unreachable by construction rather than by luck.

Among other things it asserts that the money-per-lot risk conversion agrees with the
terminal's own `OrderCalcProfit`. That check exists because a mismatch there does not
throw — it silently trades the wrong position size.

## 5. Attach to a chart

1. Open an M1 chart of your instrument.
2. Drag `ScalpRobotPro` from the Navigator onto it.
3. On the **Common** tab, enable **Allow Algo Trading**.
4. Review the inputs. At minimum set `InpMagicNumber` to a value no other EA uses.
5. Confirm.

A dashboard appears top-left. `AutoTrading` must be enabled in the toolbar for orders
to be sent.

### First-run checklist

- The Experts tab shows the version banner and the resolved environment.
- No `configuration is invalid` message. If validation fails the EA refuses to start
  and prints exactly which setting is contradictory — that is deliberate.
- The dashboard health field reads `OK`.

## Uninstalling

Remove the EA from the chart, then delete the three `ScalpRobotPro` folders. Logs and
state files under `MQL5\Files\ScalpRobotPro\` are left behind on purpose; delete them
separately if you want a clean slate.

## Troubleshooting

**"cannot open source file"** — `Include\ScalpRobotPro\` is misplaced. The folder must
sit directly inside `MQL5\Include\`.

**EA loads but never trades** — this is normal on a first run and is *always*
explained. On shutdown the engine prints a decline tally:

```
declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424 CONFIRMATION_FAILED=5579
```

The largest reason tells you which gate is closed. See the User Manual for what each
one means.

**Trading is disabled** — check `AutoTrading` in the toolbar, **Allow Algo Trading**
in the EA properties, and that the broker permits algorithmic trading on the account.

---

Trading involves substantial risk of loss. Validate any configuration on a demo
account before committing real capital.
