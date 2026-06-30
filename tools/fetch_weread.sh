#!/bin/bash
# tools/fetch_weread.sh
# 微信读书 API 快速查询辅助脚本 (适配官方网关网关版本)
# 用法: ./fetch_weread.sh <命令> [参数]

set -e

# ========== 配置 ==========
API_KEY="${WEREAD_API_KEY:-}"
GATEWAY_URL="https://i.weread.qq.com/api/agent/gateway"
SKILL_VERSION="2.0.0"

# ========== 前置检查 ==========
if [ -z "$API_KEY" ]; then
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
  
  curl -s -f -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$GATEWAY_URL" 2>/dev/null || {
      # 降级尝试，有些环境 curl 对 ssl 握手或其它有报错，输出错误日志
      curl -s -X POST \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$GATEWAY_URL"
    }
}

# ========== 命令路由 ==========
CMD="${1:-help}"

case "$CMD" in

  # 书架列表（含用户昵称 name 字段）
  shelf|books|user)
    echo "📚 获取书架列表..."
    fetch_gateway "/shelf/sync" | python3 -m json.tool 2>/dev/null || fetch_gateway "/shelf/sync"
    ;;

  # 阅读统计概要
  stats|summary)
    echo "📊 获取阅读统计..."
    # 尝试 /readdata/summary，如果返回为空或错误，降级尝试 /readdata/detail
    res=$(fetch_gateway "/readdata/summary")
    if [ -z "$res" ] || echo "$res" | grep -q "errcode"; then
      res=$(fetch_gateway "/readdata/detail" "mode=1")
    fi
    echo "$res" | python3 -m json.tool 2>/dev/null || echo "$res"
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
    fetch_gateway "/book/bookmarklist" "bookId=${BOOK_ID}" | python3 -m json.tool 2>/dev/null || fetch_gateway "/book/bookmarklist" "bookId=${BOOK_ID}"
    ;;

  # 指定书籍的想法/评论
  reviews|thoughts)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 reviews <bookId>"
      exit 1
    fi
    echo "💬 获取书籍 [${BOOK_ID}] 的想法..."
    fetch_gateway "/review/list/mine" "bookId=${BOOK_ID}" | python3 -m json.tool 2>/dev/null || fetch_gateway "/review/list/mine" "bookId=${BOOK_ID}"
    ;;

  # 指定书籍的详细信息
  bookinfo|detail)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 bookinfo <bookId>"
      exit 1
    fi
    echo "📖 获取书籍 [${BOOK_ID}] 详情..."
    fetch_gateway "/book/info" "bookId=${BOOK_ID}" | python3 -m json.tool 2>/dev/null || fetch_gateway "/book/info" "bookId=${BOOK_ID}"
    ;;

  # 指定书籍的阅读进度
  progress)
    BOOK_ID="${2:-}"
    if [ -z "$BOOK_ID" ]; then
      echo "❌ 用法: $0 progress <bookId>"
      exit 1
    fi
    echo "📈 获取书籍 [${BOOK_ID}] 阅读进度..."
    fetch_gateway "/book/getprogress" "bookId=${BOOK_ID}" | python3 -m json.tool 2>/dev/null || fetch_gateway "/book/getprogress" "bookId=${BOOK_ID}"
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
  help|*)
    echo "╔══════════════════════════════════════════════╗"
    echo "║  📊 WeRead Insight - 统一网关查询脚本        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "用法: $0 <命令> [参数]"
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
    ;;

esac
