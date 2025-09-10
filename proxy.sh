#!/usr/bin/env bash
# proxy.sh - 测试 HTTP 代理连通性，并保存可用代理到带时间戳的文件

set -eo pipefail

PROXY_FILE=""
TARGET_URL="https://cp.cloudflare.com/"
TIMEOUT=8
PARALLEL=1

# 默认保存文件名 + 时间戳
SAVE_FILE="p_$(date +%Y%m%d_%H%M%S).txt"

usage() {
  cat <<EOF
Usage: $0 -f proxies.txt [-u target_url] [-t timeout_seconds] [-p parallel] [-o output_file]
  -f FILE    : 代理列表文件（必需）
  -u URL     : 测试目标 URL，默认: $TARGET_URL
  -t TIMEOUT : 单次请求超时（秒），默认: $TIMEOUT
  -p PARALLEL: 并行测试数量，默认: $PARALLEL
  -o FILE    : 输出文件前缀（程序会自动加时间戳），默认: p
EOF
  exit 1
}

while getopts ":f:u:t:p:o:h" opt; do
  case "$opt" in
    f) PROXY_FILE="$OPTARG" ;;
    u) TARGET_URL="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    p) PARALLEL="$OPTARG" ;;
    o) SAVE_FILE="$OPTARG_$(date +%Y%m%d_%H%M%S).txt" ;;
    h|*) usage ;;
  esac
done

if [[ -z "$PROXY_FILE" || ! -f "$PROXY_FILE" ]]; then
  echo "错误: 需要存在的代理文件 (-f)。"
  usage
fi

echo "结果将保存到: $SAVE_FILE"

sanitize_line() {
  local line="$1"
  line="${line%%#*}"
  line="$(echo -n "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  echo "$line"
}

normalize_proxy() {
  local raw="$1"
  if [[ "$raw" =~ ^https?:// ]]; then
    echo "$raw"
    return 0
  fi
  IFS=':' read -r a b c d <<< "$raw"
  if [[ -n "$d" ]]; then
    echo "http://${c}:${d}@${a}:${b}"
    return 0
  fi
  if [[ "$raw" =~ : ]]; then
    echo "http://${raw}"
    return 0
  fi
  echo "$raw"
}

test_proxy() {
  local raw="$1"
  local proxy_url
  proxy_url="$(normalize_proxy "$raw")"

  local out
  out=$(curl -sS -I --proxy "$proxy_url" --max-time "$TIMEOUT" -o /dev/null -w "%{http_code} %{time_total}" "$TARGET_URL" 2>&1) || {
    echo -e "$(date '+%F %T')\t$raw\tFAILED\t$out"
    return 1
  }
  local code time
  code=$(awk '{print $1}' <<<"$out")
  time=$(awk '{print $2}' <<<"$out")

  if [[ "$code" =~ ^2|^3 ]]; then
    echo -e "$(date '+%F %T')\t$raw\tOK\tHTTP $code\t${time}s"
    echo "$raw" >> "$SAVE_FILE"
    return 0
  else
    echo -e "$(date '+%F %T')\t$raw\tBAD\tHTTP $code\t${time}s"
    return 2
  fi
}

export -f sanitize_line normalize_proxy test_proxy
export TARGET_URL TIMEOUT SAVE_FILE

if [[ "$PARALLEL" -gt 1 ]]; then
  cat "$PROXY_FILE" \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -v '^\s*#' \
    | while IFS= read -r line; do sanitize_line "$line"; done \
    | awk 'NF' \
    | xargs -I{} -n1 -P "$PARALLEL" bash -c 'test_proxy "$1"' _ {}
else
  while IFS= read -r raw; do
    line="$(sanitize_line "$raw")"
    [[ -z "$line" ]] && continue
    test_proxy "$line"
  done < "$PROXY_FILE"
fi
