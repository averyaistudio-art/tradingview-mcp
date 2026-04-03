# TARS Integration Guide

This document explains how TARS (the OpenClaw AI assistant) uses the TradingView MCP service.

## Architecture

```
Telegram → TARS (OpenClaw) → tradingview.sh → MCP Server (Docker:8765) → TradingView APIs
```

The MCP server runs as a Docker container exposing a streamable-HTTP API on port 8765. TARS calls the bridge script `tools/tradingview.sh` to interact with it.

## Quick Start

```bash
# Start the service
~/projects/tradingview-mcp/tools/tradingview.sh start

# Check status
~/projects/tradingview-mcp/tools/tradingview.sh status
```

## Command Reference

### Service Management

| Command | What it does |
|---------|-------------|
| `tradingview.sh start` | Build Docker image and start container |
| `tradingview.sh stop` | Stop the container |
| `tradingview.sh status` | Check if server is running |
| `tradingview.sh update` | Pull upstream changes + rebuild |

### Data Commands

| Command | Example | What it does |
|---------|---------|-------------|
| `indicators <SYM> [EX] [INT]` | `indicators BTCUSDT BINANCE 4h` | Get TA indicators (RSI, MACD, BB, etc.) |
| `backtest <SYM> [STRAT] [EX]` | `backtest ETHUSDT sma_cross` | Run strategy backtest |
| `screen [MARKET] [CRITERIA]` | `screen crypto rsi_oversold` | Scan markets for setups |

### Advanced

```bash
# Raw MCP tool call
./tools/tradingview.sh call get_analysis '{"symbol":"BTCUSDT","exchange":"BINANCE","screener":"crypto","interval":"1h"}'
```

## Calling from Telegram

TARS can execute any tradingview.sh command when asked:

> "Check BTC indicators on the 4h"
> → TARS runs: `./tools/tradingview.sh indicators BTCUSDT BINANCE 4h`

> "Screen crypto for RSI oversold setups"
> → TARS runs: `./tools/tradingview.sh screen crypto rsi_oversold`

> "Backtest a simple SMA cross on ETH"
> → TARS runs: `./tools/tradingview.sh backtest ETHUSDT sma_cross`

## PineScript v6 Workflow

1. **Describe** — Tell TARS what the script should do
2. **TARS generates** — PineScript v6 code is created
3. **Save locally** — Put in `pinescripts/strategies/` or `pinescripts/indicators/`
4. **Validate** — TARS can backtest the logic via MCP
5. **Deploy** — Paste into TradingView Pine Editor

See `pinescripts/README.md` for full workflow docs.

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `TRADINGVIEW_MCP_URL` | `http://localhost:8765` | MCP server endpoint |
| `DOCKER_BIN` | `/Applications/Docker.app/Contents/Resources/bin/docker` | Docker binary path |

## Upstream Sync

The fork tracks `atilaahmettaner/tradingview-mcp`. To pull upstream updates:

```bash
~/projects/tradingview-mcp/scripts/update-fork.sh
```

This fetches, merges, and pushes automatically.

## Troubleshooting

**Server not starting:**
```bash
docker compose logs tradingview-mcp
docker compose build --no-cache
```

**Port conflict:**
Edit `docker-compose.yml` and change `8765:8765` to another port, then update `TRADINGVIEW_MCP_URL`.

**Bridge script fails:**
Check Docker is running: `/Applications/Docker.app/Contents/Resources/bin/docker ps`
