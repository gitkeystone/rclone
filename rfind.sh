#!/usr/bin/env bash
# rfind.sh - 按关键字/通配模式检索远程对象存储中的文件或目录
#
# 用法: rfind.sh [选项] <pattern> [-- <rclone 额外参数>...]
#
# 匹配: 纯关键字按子串匹配；含 * ? [ 时按通配模式匹配
#
# 退出码:
#   0  成功（含无匹配）
#   2  用法错误
#   1  运行时失败

set -euo pipefail

DEFAULT_BUCKET="${RFIND_BUCKET:-jiaofu-resource}"

usage() {
  cat <<'EOF'
用法: rfind.sh [选项] <pattern> [-- <rclone 额外参数>...]

按关键字/通配模式检索远程对象存储中名称匹配的文件或目录。
纯关键字按子串匹配；含 * ? [ 时按通配模式匹配。

选项:
  -h, --help               显示本帮助并退出
  --remote <remote:bucket> 指定检索目标存储（缺省用默认目标）
  --files-only             仅检索文件
  --dirs-only              仅检索目录
  --ignore-case            不区分大小写匹配
  --                       其后参数透传给 rclone

环境变量:
  RFIND_REMOTE  指定检索目标 remote:bucket（被 --remote 覆盖）
  RFIND_BUCKET  默认 bucket（缺省 jiaofu-resource）

退出码:
  0  成功（含无匹配）  2  用法错误  1  运行时失败
EOF
}

die() {
  local code="$1"
  shift
  printf '错误: %s\n' "$*" >&2
  exit "$code"
}

usage_error() {
  local msg="$1"
  printf '错误: %s\n' "$msg" >&2
  usage >&2
  exit 2
}

# 从 rclone lsf 输出中过滤出名称匹配且符合作用域的条目
filter_lines() {
  local match_p="$1"
  local files_only="$2"
  local dirs_only="$3"
  local ignore_case="$4"
  local line entry_name leaf
  local is_dir

  if (( ignore_case )); then
    shopt -s nocasematch
  fi

  while IFS= read -r line; do
    if [[ "$line" == */ ]]; then
      is_dir=1
      entry_name="${line%/}"
    else
      is_dir=0
      entry_name="$line"
    fi
    if (( files_only )) && (( is_dir )); then
      continue
    fi
    if (( dirs_only )) && (( ! is_dir )); then
      continue
    fi
    leaf="${entry_name##*/}"
    # shellcheck disable=SC2254
    case "$leaf" in
      $match_p)
        printf '%s\n' "$line"
        ;;
    esac
  done

  if (( ignore_case )); then
    shopt -u nocasematch
  fi
}

main() {
  local remote_arg=""
  local files_only=0
  local dirs_only=0
  local ignore_case=0
  local pattern=""
  local -a rclone_args=()

  # 参数解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --remote)
        if [[ $# -lt 2 || "$2" == -* ]]; then
          usage_error "选项 --remote 需要一个参数（<remote:bucket>）"
        fi
        remote_arg="$2"
        shift 2
        ;;
      --remote=*)
        remote_arg="${1#--remote=}"
        shift
        ;;
      --files-only)
        files_only=1
        shift
        ;;
      --dirs-only)
        dirs_only=1
        shift
        ;;
      --ignore-case)
        ignore_case=1
        shift
        ;;
      --)
        shift
        rclone_args+=("$@")
        break
        ;;
      -*)
        usage_error "未知选项: $1"
        ;;
      *)
        if [[ -z "$pattern" ]]; then
          pattern="$1"
        else
          usage_error "多余的参数: $1（额外 rclone 参数请置于 -- 之后）"
        fi
        shift
        ;;
    esac
  done

  # 校验必需参数与互斥选项
  if [[ -z "$pattern" ]]; then
    usage_error "缺少 <pattern> 参数"
  fi
  if (( files_only && dirs_only )); then
    usage_error "--files-only 与 --dirs-only 不能同时使用"
  fi

  # 探测依赖
  if ! command -v rclone >/dev/null 2>&1; then
    die 1 "未找到 rclone，请先安装并确保其在 PATH 中"
  fi

  # 获取已配置的 remote 列表（供默认路径与配置型 remote 校验使用）
  local -a remotes=()
  local line
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      remotes+=("$line")
    fi
  done < <(rclone listremotes 2>/dev/null)

  # 确定目标远程路径（--remote 优先于 RFIND_REMOTE）
  if [[ -z "$remote_arg" && -n "${RFIND_REMOTE:-}" ]]; then
    remote_arg="$RFIND_REMOTE"
  fi

  local remote
  if [[ -n "$remote_arg" ]]; then
    if [[ "$remote_arg" != *:* ]]; then
      usage_error "--remote 格式应为 <remote-name>:<bucket>，当前为: $remote_arg"
    fi
    if [[ "$remote_arg" != :* ]]; then
      # 配置型 remote（name:bucket），校验 name 是否已配置
      local remote_name="${remote_arg%%:*}"
      local found=0
      local r
      for r in "${remotes[@]}"; do
        if [[ "$r" == "${remote_name}:" ]]; then
          found=1
          break
        fi
      done
      if (( ! found )); then
        die 1 "rclone 配置中未找到 remote \"${remote_name}\"；当前已配置: ${remotes[*]}"
      fi
    fi
    remote="$remote_arg"
  else
    if [[ ${#remotes[@]} -eq 0 ]]; then
      die 1 "rclone 本地配置中没有任何 remote；请先运行 'rclone config' 配置远程存储，或用 --remote 指定目标"
    fi
    remote="${remotes[0]}${DEFAULT_BUCKET}"
  fi

  # 构造匹配模式（纯关键字按子串匹配）
  local match_p
  if [[ "$pattern" != *'*'* && "$pattern" != *'?'* && "$pattern" != *'['* ]]; then
    match_p="*${pattern}*"
  else
    match_p="$pattern"
  fi

  # 检索并过滤
  local -a rclone_cmd=(rclone lsf "$remote" --recursive)
  if [[ ${#rclone_args[@]} -gt 0 ]]; then
    rclone_cmd+=("${rclone_args[@]}")
  fi

  if ! "${rclone_cmd[@]}" | filter_lines "$match_p" "$files_only" "$dirs_only" "$ignore_case"; then
    die 1 "rclone 检索失败（远程不可达或无权限？）"
  fi
}

main "$@"
