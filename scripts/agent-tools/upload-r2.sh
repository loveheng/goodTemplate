#!/bin/bash
# upload-r2 — R2 上传/列出/删除（零依赖 SigV4，node 本体在池内 .mjs 原位件）
#
# toolbox-script
# format: v1
# name: upload-r2
# summary: Cloudflare R2 对象上传/列出/删除包装器（JS 本体 upload-r2.mjs 原位保留，本壳参数透传 + 契约出口）
# trigger: manual
# platform: unix
# cat: deploy
# self-test: --self-test
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
用法: toolbox run upload-r2 <localFile> <remoteKey> [contentType] [cacheControl]
      toolbox run upload-r2 --list <prefix>          列出对象 key（逐行输出）
      toolbox run upload-r2 --delete <remoteKey>     删除单个对象
      toolbox run upload-r2 --json                   预检结论（不执行本体）
凭证/桶从环境变量读取: R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET
USAGE
  exit 0
fi
if [ "${1:-}" = "--json" ]; then
  rc=0; msg="预检通过：node 与 R2_* 凭证就绪"; remedy=""
  command -v node >/dev/null 2>&1 || { rc=1; msg="node 未安装"; remedy="安装 node 后重试"; }
  if [ $rc -eq 0 ]; then for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET; do
      [ -n "${!v:-}" ] || { rc=1; msg="缺环境变量 $v"; remedy="在 .env 或 shell 配置 R2_* 凭证"; break; }; done; fi
  if [ $rc -eq 0 ]; then printf '{"status":"OK","severity":"info","message":"%s"}\n' "$msg"
  else printf '{"status":"FAIL","severity":"error","message":"%s","remedy":"%s"}\n' "$msg" "$remedy"; fi
  exit $rc
fi
if [ "${1:-}" = "--self-test" ]; then
  node -e "import('$( realpath "$HERE/upload-r2.mjs" )')" 2>/dev/null \
    && echo "self-test: mjs 可加载" || { node --check "$HERE/upload-r2.mjs" && echo "self-test: mjs 语法通过"; }
  exit $?
fi
exec node "$HERE/upload-r2.mjs" "$@"
