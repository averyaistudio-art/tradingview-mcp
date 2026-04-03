#!/usr/bin/env bash
# tradingview.sh — TARS bridge script for TradingView MCP server
# Usage: ./tools/tradingview.sh <command> [args...]
#
# Commands:
#   start       — Build & start Docker container
#   stop        — Stop Docker container
#   status      — Check if server is running and healthy
#   update      — Pull upstream changes and rebuild
#   indicators  — Get technical indicators for a symbol
#   backtest    — Run a backtest for a symbol/strategy
#   screen      — Screen markets for opportunities
#   call        — Raw MCP tool call (advanced)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_URL="${TRADINGVIEW_MCP_URL:-http://localhost:8765}"
DOCKER_BIN="${DOCKER_BIN:-/Applications/Docker.app/Contents/Resources/bin/docker}"

# Fallback: find docker in common locations
if ! command -v docker &>/dev/null && [[ -x "$DOCKER_BIN" ]]; then
  export PATH="$(dirname "$DOCKER_BIN"):$PATH"
fi

_is_running() {
  # First try: check Docker container status
  if command -v docker &>/dev/null; then
    docker ps --filter name=tradingview-mcp --filter status=running --format '{{.Names}}' 2>/dev/null | grep -q tradingview-mcp && return 0
  fi
  # Fallback: try HTTP probe (MCP server returns 404/406 but is reachable)
  local code
  code=$(curl -so /dev/null -w "%{http_code}" --max-time 3 "${SERVER_URL}/" 2>/dev/null)
  [[ "$code" =~ ^[234] ]]
}

_require_server() {
  if ! _is_running; then
    echo "ERROR: TradingView MCP server is not running at ${SERVER_URL}" >&2
    echo "  Run: $(basename "$0") start" >&2
    exit 1
  fi
}

_mcp_call() {
  local tool="$1"
  local args="${2:-{}}"
  # MCP streamable-http: POST to /mcp with JSON-RPC
  curl -sf -X POST "${SERVER_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":${args}}}" \
    2>/dev/null || echo '{"error":"request failed"}'
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    echo "Starting TradingView MCP server..."
    cd "$REPO_DIR"
    docker compose up -d --build
    echo "Waiting for server to be ready..."
    for i in {1..20}; do
      if _is_running; then
        echo "✓ Server ready at ${SERVER_URL}"
        exit 0
      fi
      sleep 2
    done
    echo "⚠ Server may still be starting. Check: docker compose logs tradingview-mcp"
    ;;

  stop)
    echo "Stopping TradingView MCP server..."
    cd "$REPO_DIR"
    docker compose down
    echo "✓ Stopped"
    ;;

  status)
    echo "=== TradingView MCP Status ==="
    echo "Server URL: ${SERVER_URL}"
    if _is_running; then
      echo "Status: ✓ RUNNING"
    else
      echo "Status: ✗ NOT RUNNING"
      # Check if container exists
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q tradingview-mcp; then
        echo "Container: exists (may be starting up)"
        docker ps --filter name=tradingview-mcp --format "  {{.Status}}" 2>/dev/null || true
      else
        echo "Container: not found — run: tradingview.sh start"
      fi
    fi
    ;;

  update)
    echo "Updating TradingView MCP from upstream..."
    cd "$REPO_DIR"
    bash scripts/update-fork.sh
    echo "Rebuilding Docker image..."
    docker compose build --no-cache
    docker compose up -d
    echo "✓ Updated and restarted"
    ;;

  indicators)
    # Usage: indicators <SYMBOL> [EXCHANGE] [INTERVAL]
    # Example: indicators BTCUSDT BINANCE 1h
    symbol="${1:-BTCUSDT}"
    exchange="${2:-BINANCE}"
    interval="${3:-1h}"
    _require_server
    echo "Fetching indicators for ${symbol} on ${exchange} (${interval})..."
    _mcp_call "get_analysis" "{\"symbol\":\"${symbol}\",\"exchange\":\"${exchange}\",\"screener\":\"crypto\",\"interval\":\"${interval}\"}"
    ;;

  backtest)
    # Usage: backtest <SYMBOL> [STRATEGY] [EXCHANGE]
    # Example: backtest BTCUSDT sma_cross BINANCE
    symbol="${1:-BTCUSDT}"
    strategy="${2:-sma_cross}"
    exchange="${3:-BINANCE}"
    _require_server
    echo "Running backtest for ${symbol} with strategy ${strategy}..."
    _mcp_call "run_backtest" "{\"symbol\":\"${symbol}\",\"exchange\":\"${exchange}\",\"strategy\":\"${strategy}\"}"
    ;;

  screen)
    # Usage: screen [MARKET_TYPE] [CRITERIA]
    # Example: screen crypto rsi_oversold
    market="${1:-crypto}"
    criteria="${2:-rsi_oversold}"
    _require_server
    echo "Screening ${market} markets for ${criteria}..."
    _mcp_call "screen_markets" "{\"market_type\":\"${market}\",\"criteria\":\"${criteria}\"}"
    ;;

  call)
    # Raw MCP tool call: call <tool_name> <json_args>
    tool="${1:?Usage: call <tool_name> <json_args>}"
    args="${2:-{}}"
    _require_server
    _mcp_call "$tool" "$args"
    ;;

  help|--help|-h)
    cat <<'EOF'
tradingview.sh — TARS bridge for TradingView MCP

USAGE:
  tradingview.sh <command> [args...]

COMMANDS:
  start                         Build & start Docker container
  stop                          Stop Docker container
  status                        Check server health
  update                        Pull upstream + rebuild

  indicators <SYM> [EX] [INT]  Get technical indicators
                                  SYM: BTCUSDT, AAPL, etc.
                                  EX:  BINANCE, NASDAQ, etc. (default: BINANCE)
                                  INT: 1m,5m,15m,1h,4h,1d (default: 1h)

  backtest <SYM> [STRAT] [EX]  Run strategy backtest
                                  STRAT: sma_cross, rsi, macd, etc.

  screen [MARKET] [CRITERIA]   Screen markets
                                  MARKET: crypto, stocks, forex
                                  CRITERIA: rsi_oversold, squeeze, breakout

  call <tool> <json>            Raw MCP tool call (advanced)

ENVIRONMENT:
  TRADINGVIEW_MCP_URL           Server URL (default: http://localhost:8765)

EXAMPLES:
  ./tools/tradingview.sh start
  ./tools/tradingview.sh indicators BTCUSDT BINANCE 4h
  ./tools/tradingview.sh backtest ETHUSDT sma_cross
  ./tools/tradingview.sh screen crypto rsi_oversold
  ./tools/tradingview.sh status
EOF
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Run: $(basename "$0") help" >&2
    exit 1
    ;;
esac
