# PineScript v6 Workspace

This directory is your local PineScript development workspace, integrated with the TradingView MCP service.

## Workflow

```
1. Describe → 2. Generate → 3. Validate → 4. Deploy
```

### Step 1: Describe

Tell TARS (via Telegram) what you want:

> "Create a PineScript strategy that enters long when RSI crosses above 30 and exits when RSI crosses above 70, with a 2% stop loss"

### Step 2: TARS Generates

TARS will generate PineScript v6 code. Key v6 features used:
- `strategy()` declaration with commission/slippage settings
- `ta.rsi()`, `ta.sma()`, `ta.ema()` for indicators
- `strategy.entry()` / `strategy.exit()` for trades
- `strategy.risk.max_drawdown()` for risk controls
- `input.*` for configurable parameters

### Step 3: Validate Locally

Save the script here and review:
- `indicators/` — standalone indicator scripts (no buy/sell)
- `strategies/` — full trading strategies with entry/exit
- `backtests/` — backtest result notes and screenshots

Use the MCP server to validate logic:
```bash
./tools/tradingview.sh backtest BTCUSDT <strategy_name>
```

### Step 4: Deploy to TradingView

1. Open TradingView → Pine Editor
2. Paste the script
3. Click "Add to chart" to see it live
4. Run "Strategy Tester" for historical backtesting

## PineScript v6 Quick Reference

```pine
//@version=6
strategy("My Strategy", overlay=true, default_qty_type=strategy.percent_of_equity, default_qty_value=10)

// Inputs
rsiLength = input.int(14, "RSI Length")
rsiOversold = input.int(30, "Oversold Level")

// Indicators
rsi = ta.rsi(close, rsiLength)

// Signals
longEntry = ta.crossover(rsi, rsiOversold)
longExit = rsi > 70

// Orders
if longEntry
    strategy.entry("Long", strategy.long)
if longExit
    strategy.close("Long")
```

## File Naming Convention

```
indicators/  → <indicator-name>_v<N>.pine
strategies/  → <strategy-name>_v<N>.pine
backtests/   → <strategy-name>_<symbol>_<date>.md
```

## Tips

- Always add `//@version=6` as the first line
- Use `input.*` for all magic numbers
- Test on multiple timeframes before deploying
- Keep position sizing at 1-10% of equity for safety
- Document your strategy logic in comments
