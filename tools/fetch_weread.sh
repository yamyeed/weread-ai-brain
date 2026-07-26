#!/bin/bash
# tools/fetch_weread.sh
# 微信读书 API 快速查询辅助脚本 (适配官方网关网关版本)
# 用法: ./fetch_weread.sh --confirm-private-data <命令> [参数]

set -euo pipefail

# ========== 配置 ==========
readonly API_KEY="${WEREAD_API_KEY:-}"
readonly GATEWAY_URL="https://i.weread.qq.com/api/agent/gateway"
readonly EXPECTED_GATEWAY_URL="https://i.weread.qq.com/api/agent/gateway"
readonly SKILL_VERSION="2.0.0"
readonly CONFIRMATION_FLAG="--confirm-private-data"

DATA_ACCESS_CONFIRMED=false
if [ "${1:-}" = "$CONFIRMATION_FLAG" ]; then
  DATA_ACCESS_CONFIRMED=true
  shift
fi

CMD="${1:-help}"

data_scope_for_command() {
  case "$1" in
    shelf|books|user)
      echo "书架列表与用户昵称"
      ;;
    stats|summary)
      echo "阅读统计"
      ;;
    bookmarks|notes)
      echo "指定书籍的划线笔记"
      ;;
    reviews|thoughts)
      echo "指定书籍的个人想法与评论"
      ;;
    bookinfo|detail)
      echo "指定书籍的书目信息"
      ;;
    progress)
      echo "指定书籍的阅读进度"
      ;;
    dashboard|all)
      echo "书架列表、用户昵称与阅读统计"
      ;;
    *)
      echo "未知数据范围"
      ;;
  esac
}

is_network_command() {
  case "$1" in
    shelf|books|user|stats|summary|bookmarks|notes|reviews|thoughts|bookinfo|detail|progress|dashboard|all)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

show_privacy_notice() {
  local data_scope
  data_scope="$(data_scope_for_command "$CMD")"

  echo "🔒 隐私提示：即将访问微信读书官方统一网关" >&2
  echo "   目标：${GATEWAY_URL}" >&2
  echo "   本次范围：${data_scope}" >&2
  echo "   凭据：WEREAD_API_KEY 仅作为 Bearer Token 发往上述官方网关" >&2
}

# ========== 前置检查 ==========
if is_network_command "$CMD" && [ -z "$API_KEY" ]; then
  echo "❌ 错误: 未设置 WEREAD_API_KEY 环境变量"
  echo ""
  echo "请先获取你的微信读书 API Key："
  echo "  1. 打开手机「微信读书 App」"
  echo "  2. 点击「我」→「设置 ⚙️」→「微信读书 Skill」"
  echo "  3. 复制以 wrk- 开头的 Key"
  echo ""
  echo "然后运行: export WEREAD_API_KEY=wrk-你的密钥"
  exit 1
fi

if is_network_command "$CMD" && [ "$GATEWAY_URL" != "$EXPECTED_GATEWAY_URL" ]; then
  echo "❌ 安全停止: 微信读书网关地址不在允许列表中" >&2
  exit 1
fi

if is_network_command "$CMD" && [[ "$API_KEY" != wrk-* ]]; then
  echo "❌ 安全停止: WEREAD_API_KEY 必须以 wrk- 开头" >&2
  exit 1
fi

if is_network_command "$CMD"; then
  show_privacy_notice

  if [ "$DATA_ACCESS_CONFIRMED" != true ]; then
    echo "" >&2
    echo "请求已停止。请先向用户说明上述数据范围并取得明确同意。" >&2
    echo "确认后重新运行：$0 ${CONFIRMATION_FLAG} ${CMD} [参数]" >&2
    exit 2
  fi
fi

# 通用网关 POST 请求函数
fetch_gateway() {
  local api_name="$1"
  shift
  
  # 构造平铺的 JSON Body
  local payload="{\"api_name\": \"$api_name\", \"skill_version\": \"$SKILL_VERSION\""
  for arg in "$@"; do
    local key="${arg%%=*}"
    local val="${arg#*=}"
    payload="$payload, \"$key\": \"$val\""
  done
  payload="$payload}"
  
  curl --silent \
    --show-error \
    --fail \
    --proto '=https' \
    --tlsv1.2 \
    --connect-timeout 10 \
    --max-time 30 \
    --request POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$GATEWAY_URL"
}

print_json_or_raw() {
  local response="$1"

  if ! printf '%s\n' "$response" | python3 -m json.tool 2>/dev/null; then
    printf '%s\n' "$response"
  fi
}

case "$CMD" in

  # 书架列表（含用户昵称 name 字段）
  shelf|books|user)
    echo "📚 获取书架列表..."
    response=$(fetch_gateway "/shelf/sync")
    print_json_or_raw "$response"
    ;;

  # 阅读统计概要
  stats|summary)
    echo "📊 获取阅读统计..."
    # 尝试 /readdata/summary，如果返回为空或错误，降级尝试 /readdata/detail
    res=$(fetch_gateway "/readdata/summary")
    if [ -z "$res" ] || echo "$res" | grep -q "errcode"; then
      res=$(fetch_gateway "/readdata/detail" "mode=1")
    fi
    print_json_or_raw "$res"
    ;;

  # 指定书籍的划线笔记
  bookmarks|notes)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 bookmarks <bookId>"
      echo "   先运行 '$0 shelf' 获取 bookId"
      exit 1
    fi
    echo "✍️ 获取书籍 [${BOOK_ID}] 的划线笔记..."
    response=$(fetch_gateway "/book/bookmarklist" "bookId=${BOOK_ID}")
    print_json_or_raw "$response"
    ;;

  # 指定书籍的想法/评论
  reviews|thoughts)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 reviews <bookId>"
      exit 1
    fi
    echo "💬 获取书籍 [${BOOK_ID}] 的想法..."
    response=$(fetch_gateway "/review/list/mine" "bookId=${BOOK_ID}")
    print_json_or_raw "$response"
    ;;

  # 指定书籍的详细信息
  bookinfo|detail)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 bookinfo <bookId>"
      exit 1
    fi
    echo "📖 获取书籍 [${BOOK_ID}] 详情..."
    response=$(fetch_gateway "/book/info" "bookId=${BOOK_ID}")
    print_json_or_raw "$response"
    ;;

  # 指定书籍的阅读进度
  progress)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 progress <bookId>"
      exit 1
    fi
    echo "📈 获取书籍 [${BOOK_ID}] 阅读进度..."
    response=$(fetch_gateway "/book/getprogress" "bookId=${BOOK_ID}")
    print_json_or_raw "$response"
    ;;

  # 全量数据拉取（供看板使用）
  dashboard|all)
    echo "📊 正在拉取全量数据用于看板生成..."
    echo ""
    echo "=== 书架列表（含用户信息） ==="
    fetch_gateway "/shelf/sync"
    echo ""
    echo "=== 阅读统计 ==="
    res=$(fetch_gateway "/readdata/summary")
    if [ -z "$res" ] || echo "$res" | grep -q "errcode"; then
      res=$(fetch_gateway "/readdata/detail" "mode=overall")
    fi
    echo "$res"
    echo ""
    echo "=== 书架列表 ==="
    fetch_gateway "/shelf/sync"
    echo ""
    echo "✅ 全量数据拉取完毕。"
    ;;

  # 帮助
  help|-h|--help|*)
    echo "╔══════════════════════════════════════════════╗"
    echo "║  📊 WeRead Insight - 统一网关查询脚本        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "用法: $0 ${CONFIRMATION_FLAG} <命令> [参数]"
    echo ""
    echo "可用命令:"
    echo "  shelf       获取书架列表（含用户昵称 name 字段）"
    echo "  stats       获取阅读统计概要"
    echo "  bookmarks   <bookId>  获取指定书籍的划线笔记"
    echo "  reviews     <bookId>  获取指定书籍的想法"
    echo "  bookinfo    <bookId>  获取指定书籍详情"
    echo "  progress    <bookId>  获取指定书籍阅读进度"
    echo "  dashboard   拉取全量数据（书架+统计）"
    echo "  help        显示此帮助"
    echo ""
    echo "前置条件: export WEREAD_API_KEY=wrk-你的密钥"
    echo "隐私确认: 先向用户说明数据范围并取得明确同意，再传入 ${CONFIRMATION_FLAG}"
    ;;

esac
