#!/usr/bin/env bash
# tradingview.sh — TARS bridge script for TradingView MCP server
# Usage: ./tools/tradingview.sh <command> [args...]
#
# Commands:
#   start            — Build & start Docker container
#   stop             — Stop Docker container
#   status           — Check if server is running and healthy
#   update           — Pull upstream changes and rebuild
#   indicators       — Get technical indicators for a symbol
#   full-analysis    — Fetch live data + run through 4 Ollama models in parallel
#   backtest         — Run a backtest for a symbol/strategy
#   screen           — Screen markets for opportunities
#   call             — Raw MCP tool call (advanced)

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

# Initialise an MCP session and return the session ID
_mcp_session_init() {
  curl -si -X POST "${SERVER_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"tars","version":"1.0"}}}' \
    2>&1 | grep -i "mcp-session-id" | awk '{print $2}' | tr -d '\r'
}

# Call coin_analysis via a session and extract the text content
_mcp_coin_analysis() {
  local symbol="$1" exchange="$2" timeframe="$3"
  local session_id
  session_id=$(_mcp_session_init)
  if [[ -z "$session_id" ]]; then
    echo '{"error":"failed to initialise MCP session"}'
    return 1
  fi
  curl -s -X POST "${SERVER_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "mcp-session-id: ${session_id}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"coin_analysis\",\"arguments\":{\"symbol\":\"${symbol}\",\"exchange\":\"${exchange}\",\"timeframe\":\"${timeframe}\"}}}" \
    | python3 -c "
import sys, json
raw = sys.stdin.read()
for line in raw.split('\n'):
    if line.startswith('data:'):
        try:
            obj = json.loads(line[5:])
            content = obj.get('result',{}).get('content',[])
            for c in content:
                print(c.get('text',''))
        except Exception:
            pass
"
}

# Run one ollama model and write output to a temp file
_ollama_analyze() {
  local model="$1" prompt="$2" outfile="$3"
  ollama run "$model" "$prompt" > "$outfile" 2>&1
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
    # Usage: indicators <SYMBOL> [EXCHANGE] [TIMEFRAME]
    # Example: indicators BTCUSDT BINANCE 4h
    symbol="${1:-BTCUSDT}"
    exchange="${2:-BINANCE}"
    timeframe="${3:-4h}"
    _require_server
    echo "Fetching indicators for ${symbol} on ${exchange} (${timeframe})..."
    _mcp_coin_analysis "$symbol" "$exchange" "$timeframe"
    ;;

  full-analysis)
    # Usage: full-analysis <SYMBOL> [EXCHANGE] [TIMEFRAME]
    # Example: full-analysis BTCUSDT BINANCE 4h
    symbol="${1:-BTCUSDT}"
    exchange="${2:-BINANCE}"
    timeframe="${3:-4h}"
    _require_server

    echo "[full-analysis] Fetching live market data for ${symbol} on ${exchange} (${timeframe})..."
    MARKET_DATA=$(_mcp_coin_analysis "$symbol" "$exchange" "$timeframe")

    if [[ -z "$MARKET_DATA" || "$MARKET_DATA" == *'"error"'* ]]; then
      echo "ERROR: Failed to fetch market data from MCP server" >&2
      echo "$MARKET_DATA" >&2
      exit 1
    fi

    PROMPT="You are a professional crypto technical analyst. Analyze the following market data and provide:
1. Overall bias (Bullish/Bearish/Neutral)
2. Top 3 strongest signals
3. Key risk level to watch
4. Short-term outlook (1-3 candles)
Be concise. No preamble. Just the analysis.

MARKET DATA:
${MARKET_DATA}"

    # Temp files for parallel output
    TMPDIR_FA=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_FA"' EXIT

    echo "[full-analysis] Running 4 models in parallel..."

    _ollama_analyze "deepseek-r1:32b"          "$PROMPT" "${TMPDIR_FA}/deepseek.txt" &
    PID_DS=$!
    _ollama_analyze "nemotron-cascade-2:latest" "$PROMPT" "${TMPDIR_FA}/nemotron.txt" &
    PID_NM=$!
    _ollama_analyze "qwen3-coder:30b"           "$PROMPT" "${TMPDIR_FA}/qwen3.txt" &
    PID_QW=$!
    _ollama_analyze "devstral-small-2:latest"   "$PROMPT" "${TMPDIR_FA}/devstral.txt" &
    PID_DV=$!

    # Wait for all background jobs; capture exit codes
    wait $PID_DS; EC_DS=$?
    wait $PID_NM; EC_NM=$?
    wait $PID_QW; EC_QW=$?
    wait $PID_DV; EC_DV=$?

    # Helper: strip ANSI escape codes + <think>...</think> blocks (qwen3 thinking output)
    _strip_think() {
      python3 -c "
import sys, re
text = sys.stdin.read()
# Strip ANSI/VT escape sequences (spinner, cursor movement, colour codes)
text = re.sub(r'(\x1B\[[0-9;]*[a-zA-Z]|\x1B[()][A-Z]|\x1B[^\[\(\)]|[\x00-\x08\x0B-\x0C\x0E-\x1A\x1C-\x1F\x7F])', '', text)
text = re.sub(r'\?[0-9]+[hl]', '', text)  # leftover DEC private modes
# Strip thinking blocks
text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
# Strip spinner chars and bare ESC sequences
text = re.sub(r'[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏].*?\n', '', text)
print(text.strip())
"
    }

    echo ""
    echo "=== DEEPSEEK-R1 ==="
    if [[ $EC_DS -eq 0 ]]; then
      cat "${TMPDIR_FA}/deepseek.txt" | _strip_think
    else
      echo "[ERROR: deepseek-r1:32b failed — exit $EC_DS]"
      cat "${TMPDIR_FA}/deepseek.txt"
    fi

    echo ""
    echo "=== NEMOTRON ==="
    if [[ $EC_NM -eq 0 ]]; then
      cat "${TMPDIR_FA}/nemotron.txt" | _strip_think
    else
      echo "[ERROR: nemotron-cascade-2:latest failed — exit $EC_NM]"
      cat "${TMPDIR_FA}/nemotron.txt"
    fi

    echo ""
    echo "=== QWEN3-CODER ==="
    if [[ $EC_QW -eq 0 ]]; then
      cat "${TMPDIR_FA}/qwen3.txt" | _strip_think
    else
      echo "[ERROR: qwen3-coder:30b failed — exit $EC_QW]"
      cat "${TMPDIR_FA}/qwen3.txt"
    fi

    echo ""
    echo "=== DEVSTRAL ==="
    if [[ $EC_DV -eq 0 ]]; then
      cat "${TMPDIR_FA}/devstral.txt" | _strip_think
    else
      echo "[ERROR: devstral-small-2:latest failed — exit $EC_DV]"
      cat "${TMPDIR_FA}/devstral.txt"
    fi
    echo ""
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

  indicators <SYM> [EX] [TF]   Get technical indicators via coin_analysis
                                  SYM: BTCUSDT, ETHUSDT, etc.
                                  EX:  BINANCE, NASDAQ, etc. (default: BINANCE)
                                  TF:  1m,5m,15m,1h,4h,1d  (default: 4h)

  full-analysis <SYM> [EX] [TF] Fetch live data + run through 4 Ollama models
                                  in parallel (deepseek-r1, nemotron, qwen3-coder,
                                  devstral). Outputs structured analysis for TARS.
                                  EX:  BINANCE (default)
                                  TF:  4h (default)

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
  ./tools/tradingview.sh full-analysis BTCUSDT BINANCE 4h
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
