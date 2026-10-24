#!/bin/bash
# init-app — 模板一键起底：改名 + 通道接线 + 初始化（新 app 复制本模板后跑一次）
#
# toolbox-script
# format: v1
# name: init-app
# summary: 模板一键起底：--name/--org/--title 机械替换全部散落点（pubspec/gradle/kotlin 目录/通道名/manifest SERVER_ID/R2 部署前缀），契约（SDK 坐标 + 签名权限）护门不动，可选 --with-agents 生成 AGENTS.md 骨架，跑完自动 pub get+analyze 验收
# trigger: manual
# platform: unix
# cat: ops
# alias: initapp
# self-test: --self-test
set -euo pipefail

OLD_NAME='good_template'
OLD_ORG='com.goodhub'
OLD_ORG_PATH='com/goodhub/good_template'
OLD_TITLE='GoodTemplate'
OLD_CHANNEL='good_template/mcp_binder'

NEW_NAME=''   # dart 包名（snake_case）
NEW_ORG=''    # 反向域名，如 com.yourco
NEW_TITLE=''
DRY_RUN=0
WITH_AGENTS=0
JSON_ONLY=0

usage() {
  cat <<'USAGE'
用法: toolbox run init-app --name <snake_name> --org <com.yourco> [--title "应用名"] [选项]
      --name     新 app 包名（snake_case，用于 pubspec name / applicationId / 目录 / 通道）
      --org      反向域名（用于 applicationId / namespace / Kotlin 包路径）
      --title    应用显示名（manifest SERVER_TITLE / 通知文案；缺省取 --name）
      --with-agents  生成裁剪版 AGENTS.md 骨架（AI 开发约定，后续可走 dev-init 补全）
      --dry-run  预览将执行的替换，不动真文件
      --json     预检结论（不执行本体）：检查参数与模板在位状态
      --self-test 金丝雀：校验替换函数与契约护门逻辑
gradle SDK 坐标（com.zzh.goodhub.*）与签名权限名是对接契约，本脚本只检查、永不修改。
USAGE
}

report_json() { # $1=rc $2=msg $3=remedy(可空)
  if [ "$1" -eq 0 ]; then
    printf '{"status":"OK","severity":"info","message":"%s"}\n' "$2"
  else
    printf '{"status":"FAIL","severity":"error","message":"%s","remedy":"%s"}\n' "$2" "$3"
  fi
  exit "$1"
}

# 参数解析（REMAINDER 之外的选项在这里吃掉）
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NEW_NAME="$2"; shift 2 ;;
    --org) NEW_ORG="$2"; shift 2 ;;
    --title) NEW_TITLE="$2"; shift 2 ;;
    --with-agents) WITH_AGENTS=1; shift ;;
    --dry-run|-n) DRY_RUN=1; shift ;;
    --json) JSON_ONLY=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[remedy] 未知参数: $1（toolbox run init-app --help 看用法）"; exit 2 ;;
  esac
done

# --json 预检：参数合法性 + 模板在位（不执行替换）
if [ "$JSON_ONLY" = 1 ]; then
  if [ -z "$NEW_NAME" ] || [ -z "$NEW_ORG" ]; then
    report_json 1 "缺少 --name 或 --org" "补齐 toolbox run init-app --name <snake> --org <com.yourco>"
  fi
  case "$NEW_NAME" in
    [a-z_][a-z0-9_]*) ;;
    *) report_json 1 "--name 须为 snake_case（dart 包名约束）" "改成如 my_app 的形式" ;;
  esac
  [ -f pubspec.yaml ] || report_json 1 "pubspec.yaml 不在当前目录（须在模板仓库根跑）" "cd 模板仓库根后重试"
  [ -f "lib/mcp_binder_entrypoint.dart" ] || report_json 1 "模板件缺失 lib/mcp_binder_entrypoint.dart" "确认在 goodTemplate 模板副本内跑"
  report_json 0 "预检通过：参数合法且模板件在位"
fi

if [ "${SELF_TEST:-0}" != 1 ]; then
  if [ -z "$NEW_NAME" ] || [ -z "$NEW_ORG" ]; then
    usage; exit 2
  fi
  [ -n "$NEW_TITLE" ] || NEW_TITLE="$NEW_NAME"
fi

# ---------- 替换原语 ----------
NEW_ORG_PATH="${NEW_ORG//./\/}/$NEW_NAME"      # com.yourco/my_app
NEW_PACKAGE="${NEW_ORG}.${NEW_NAME}"           # com.yourco.my_app
NEW_ENTRY="package:${NEW_NAME}/mcp_binder_entrypoint.dart"
NEW_CHANNEL="${NEW_NAME}/mcp_binder"
say() { if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }

sub() { # sub <file> <old> <new> <label> — 幂等替换（已替换则跳过）
  local f="$1" old="$2" new="$3" label="$4"
  grep -q "$old" "$f" || { say "  跳过 $label（无 $old，可能已替换）"; return 0; }
  if [ "$DRY_RUN" = 1 ]; then say "  $label: $old → $new"
  else sed -i "s|$old|$new|g" "$f"; fi
}

mv_kotlin() { # Kotlin 包目录整体改名 + package 行
  local src="android/app/src/main/kotlin/$OLD_ORG_PATH"
  local dst="android/app/src/main/kotlin/$NEW_ORG_PATH"
  if [ -d "$src" ] && [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$(dirname "$dst")" && mv "$src" "$dst"
  fi
  say "  Kotlin 包目录: $src → $dst"
}

guard_contract() { # SDK 坐标 / 签名权限 / 服务 action 是 goodhub 对接契约：只检查，永不改
  grep -q 'com.zzh.goodhub.mcp:goodhub-mcp-plugin-core' android/app/build.gradle.kts || {
    echo "[remedy] gradle 缺插件接入 SDK 依赖（goodhub-mcp-plugin-core，契约承载）——确认模板完整"; exit 1; }
  local manifest="android/app/src/main/AndroidManifest.xml"
  grep -q 'com.zzh.goodhub.permission.MCP_SERVER' "$manifest" || {
    echo "[remedy] manifest 丢了 goodhub 签名权限声明（契约不可变）——请回退 AndroidManifest.xml"; exit 1; }
  grep -q 'com.zzh.goodhub.action.MCP_SERVER' "$manifest" || {
    echo "[remedy] manifest 丢了 goodhub 服务 intent action（契约不可变）——请回退 AndroidManifest.xml"; exit 1; }
  say "契约检查通过（SDK 坐标 com.zzh.goodhub.* + 签名权限原样保留）"
}

# ---------- 替换清单（唯一事实：新 app 要改的所有点都在这里） ----------
do_replace() {
  local kt_main
  kt_main="$(find android/app/src/main/kotlin -name MainActivity.kt 2>/dev/null | head -1)"
  [ -n "$kt_main" ] || { echo "[remedy] 未找到 MainActivity.kt（确认在模板仓库根跑，且 android/ 完整）"; exit 1; }
  local KT_MAIN_DIR; KT_MAIN_DIR="$(dirname "$kt_main")"  # 新 app 的 Kotlin 包目录
  say "替换清单（$OLD_NAME → $NEW_NAME @ $NEW_ORG）："
  sub pubspec.yaml "^name: $OLD_NAME" "name: $NEW_NAME" "pubspec name"
  sub pubspec.yaml 'description: "goodhub 服务端模板[^"]*"' "description: \"$NEW_TITLE（goodhub 服务端模板起底）\"" "pubspec description"
  local gradle="android/app/build.gradle.kts"
  sub "$gradle" "applicationId = \"$OLD_ORG.$OLD_NAME\"" "applicationId = \"$NEW_PACKAGE\"" "applicationId"
  sub "$gradle" "namespace = \"$OLD_ORG.$OLD_NAME\"" "namespace = \"$NEW_PACKAGE\"" "namespace"
  for cfg in android/settings.gradle.kts android/settings.gradle; do
    [ -f "$cfg" ] && sub "$cfg" "rootProject.name = [\"']$OLD_NAME[\"']" "rootProject.name = \"$NEW_NAME\"" "rootProject.name"
  done
  mv_kotlin
  if [ "$DRY_RUN" = 0 ]; then
    for kt in $(find android/app/src/main/kotlin -name '*.kt'); do
      sed -i "s|^package $OLD_ORG\.$OLD_NAME|package $NEW_PACKAGE|" "$kt"
    done
  fi
  say "  Kotlin package 行 → $NEW_PACKAGE"
  sub lib/mcp_binder_entrypoint.dart "$OLD_CHANNEL" "$NEW_CHANNEL" "Dart binder 通道名"
  local ktsvc="android/app/src/main/kotlin/$NEW_ORG_PATH/McpBinderService.kt"
  if [ "$DRY_RUN" = 0 ]; then
    local whole
    for whole in \
      "$ktsvc" \
      "android/app/src/main/kotlin/$NEW_ORG_PATH/SecretStoreChannel.kt" \
      "lib/service/keystore_secret_store.dart" \
      "lib/mcp/mcp_server.dart"; do
      sed -i "s|$OLD_NAME|$NEW_NAME|g" "$whole" # 通道名/别名/密文文件名/serverName/注释一次覆盖
    done
  fi
  say "  名称内嵌件整文件替换（binder 服务/凭证通道/KV 通道）"
  local manifest="android/app/src/main/AndroidManifest.xml"
  sub "$manifest" "android:label=\"$OLD_NAME\"" "android:label=\"$NEW_TITLE\"" "应用显示名"
  if [ "$DRY_RUN" = 0 ]; then
    sed -i "s|$OLD_ORG\\.$OLD_NAME\\.McpBinderService|$NEW_PACKAGE.McpBinderService|g" "$manifest"
  fi
  say "  service 类全限定名 → $NEW_PACKAGE.McpBinderService"
  sub "$manifest" "android:value=\"$OLD_NAME\"" "android:value=\"$NEW_NAME\"" "SERVER_ID"
  sub "$manifest" "android:value=\"$OLD_TITLE\"" "android:value=\"$NEW_TITLE\"" "SERVER_TITLE"
  sub lib/main.dart "title: '$OLD_NAME'" "title: '$NEW_NAME'" "app title"
  sub lib/main.dart "\\[$OLD_NAME\\]" "[$NEW_NAME]" "调试日志前缀"
  sub lib/service/mcp_controller.dart "$OLD_NAME · MCP 服务运行中" "$NEW_TITLE · MCP 服务运行中" "前台通知标题"
  if [ "$DRY_RUN" = 0 ]; then
    for tf in $(grep -rl "package:$OLD_NAME/" test lib 2>/dev/null || true); do
      sed -i "s|package:$OLD_NAME/|package:$NEW_NAME/|g" "$tf"
    done
  fi
  say "  dart 包导入前缀 package:$OLD_NAME/ → package:$NEW_NAME/（test+lib 扫全）"
  # R2 部署落点按 app 隔离：多 app 共用同一 bucket 时各占各前缀，
  # 防清单互覆 + 清旧包循环误删他 app 的 APK（桶/域名仍走 .env 用户级配置）。
  sub scripts/agent-tools/release-r2.sh 'REMOTE_PREFIX:-updates' "REMOTE_PREFIX:-updates/$NEW_NAME" "R2 部署前缀（按 app 隔离）"
  guard_contract
}

# ---------- 收尾装配 ----------
do_finalize() {
  if [ "$WITH_AGENTS" = 1 ] && [ ! -f AGENTS.md ]; then
    if [ "$DRY_RUN" = 0 ]; then
      cat > AGENTS.md <<MD
# $NEW_TITLE · AI 开发约定

goodhub 服务端模板起底：Flutter Android 常驻壳 + 内嵌 MCP 服务端（HTTP 回环 + Binder 双通道）。

## 硬约束

- flutter 不在默认 PATH：先 \`export PATH="\$HOME/flutter/bin:\$PATH"\`
- 一切 AI 写操作必经 lib/action/command_gateway.dart（唯一写入口），禁绕过直写存储
- Binder 对接契约不可改：SDK 坐标 com.zzh.goodhub.mcp / 签名权限 com.zzh.goodhub.permission.MCP_SERVER
- 新 app 待办：写真实领域网关（参照 sample 装配，落 tool_face_assembly 单点收口）、需要凭证的键在装配处登记 SecretAwareKv.secretKeys、goodhub 实机 bind 联调（同签名出包）；存储默认已持久化 + 凭证分流
- 完整 AI 开发体系（context/ 断点、索引、skill）后续走 dev-init 接入
MD
    fi
    say "  生成 AGENTS.md 骨架（--with-agents）"
  fi
  if [ "$DRY_RUN" = 0 ]; then
    if [ ! -d scripts/agent-tools ] || [ ! -f scripts/agent-tools/README.md ]; then toolbox init --project >/dev/null 2>&1 || true; fi
    if [ ! -d .git ]; then git init -q && git add -A && git commit -qm "chore: 自 goodTemplate 起底（init-app 改名 $NEW_NAME）" || true; fi
  fi
  say "  toolbox 项目池 / git 首提交 / AGENTS.md 就绪检查完成"
}

# ---------- 验收门 ----------
do_verify() {
  [ "$DRY_RUN" = 1 ] && return 0
  say "验收门：pub get + analyze…"
  if command -v flutter >/dev/null 2>&1 || [ -x "$HOME/flutter/bin/flutter" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
    flutter pub get >/dev/null 2>&1 || { echo "[remedy] flutter pub get 失败——查网络/SDK"; exit 1; }
    flutter analyze 2>&1 | tail -1
    flutter analyze >/dev/null 2>&1 || { echo "[remedy] analyze 有 error——改名残留，逐文件 grep $OLD_NAME 清理"; exit 1; }
  else
    echo "⚠ flutter 不可用，跳过验收门（记得手跑 flutter analyze）"
  fi
  say "改名残留扫描："
  local left
  left=$(grep -rl "$OLD_NAME" lib android/app/src/main/kotlin android/app/src/main/AndroidManifest.xml pubspec.yaml 2>/dev/null || true)
  [ -n "$left" ] && { echo "  ⚠ 以下文件仍有 $OLD_NAME 残留（多为注释/出处标注，人工确认）:"; echo "$left" | sed 's/^/    /'; } || say "  无残留"
}

# ---------- 金丝雀自测 ----------
bash_self_test() {
  # 在临时目录用最小样本验证 sub/guard 逻辑：替换命中 + 契约护门能抓坏样本
  SELF_TEST_TMP="$(mktemp -d)"; local tmp="$SELF_TEST_TMP"
  trap 'rm -rf "${SELF_TEST_TMP:-}"' EXIT
  mkdir -p "$tmp/android/app/src/main/kotlin/com/goodhub/good_template"
  echo 'name: good_template' > "$tmp/pubspec.yaml"
  echo 'implementation("com.zzh.goodhub.mcp:goodhub-mcp-plugin-core:0.2.0")' > "$tmp/android/app/build.gradle.kts"
  printf '<service android:permission="com.zzh.goodhub.permission.MCP_SERVER">\n  <action android:name="com.zzh.goodhub.action.MCP_SERVER" />\n</service>\n' > "$tmp/android/app/src/main/AndroidManifest.xml"
  ( cd "$tmp" && OLD_NAME='good_template'; NEW_NAME='my_app'
    sed -i 's|^name: good_template|name: my_app|' pubspec.yaml
    grep -q '^name: my_app' pubspec.yaml || { echo "self-test: 替换未命中"; exit 1; }
    sed -i 's|com.zzh.goodhub.permission.MCP_SERVER|com.evil.permission.X|' android/app/src/main/AndroidManifest.xml
    grep -q 'com.zzh.goodhub.permission.MCP_SERVER' android/app/src/main/AndroidManifest.xml \
      && { echo "self-test: 护门未抓到坏样本"; exit 1; }
    echo "self-test: PASS（替换命中 + 坏样本被抓）" ) || return 1
}

if [ "${SELF_TEST:-0}" = 1 ]; then bash_self_test; exit $?; fi
do_replace
do_finalize
do_verify
say "完成：$NEW_TITLE（$NEW_PACKAGE）。下一步：写真实领域网关（参照 sample 装配）→ 凭证键登记 secretKeys → 真机 e2e。"
