#!/bin/bash
# 定位内容仓库根目录，stdout 输出规整后的绝对路径
# 契约依据: content-root-contract.md
# 用法: get-content-root.sh [--require <相对路径>...]
# 退出码: 0 成功  1 解析失败  2 用法错误

set -u

usage() {
  echo "用法: $0 [--require <相对路径>...]" >&2
  echo "  --require  可选；根解析成功后校验这些相对路径，须全部存在" >&2
}

usage_error() {
  echo "错误: $1" >&2
  usage
  exit 2
}

is_root_path() {
  local remaining=$1 component has_more
  while :; do
    case $remaining in
      */*) component=${remaining%%/*}; remaining=${remaining#*/}; has_more=1 ;;
      *) component=$remaining; has_more=0 ;;
    esac
    case $component in
      ""|.) ;;
      *) return 1 ;;
    esac
    [ "$has_more" -eq 1 ] || return 0
  done
}

require_paths=()
if [ $# -gt 0 ]; then
  [ "$1" = "--require" ] || usage_error "未知参数: $1"
  shift
  [ $# -gt 0 ] || usage_error "--require 至少需要一个路径"
  for a in "$@"; do
    case $a in
      --*) usage_error "未知参数: $a" ;;
      "") usage_error "--require 路径不能为空" ;;
      /*) usage_error "--require 路径必须是仓库根内的相对路径: $a" ;;
      *)
        case "/$a/" in
          */../*) usage_error "--require 路径不得包含 .. 路径段: $a" ;;
        esac
        is_root_path "$a" && usage_error "--require 路径不能指向仓库根目录本身"
        require_paths+=("$a")
        ;;
    esac
  done
fi

# 解析 $0 自身的符号链接（文件级链接安装；目录级链接由下方 cd -P 处理）
self=$0
hops=0
while [ -L "$self" ] && [ "$hops" -lt 40 ]; do
  target=$(readlink "$self") || { echo "错误: 读取符号链接失败: $self" >&2; exit 1; }
  case $target in
    /*) self=$target ;;
    *) self=$(dirname "$self")/$target ;;
  esac
  hops=$((hops + 1))
done

# anchor = 脚本物理目录
if ! anchor=$(cd -P "$(dirname "$self")" 2>/dev/null && pwd); then
  echo "错误: 无法解析脚本物理位置: $0" >&2
  echo "  脚本入口目录: $(dirname "$0")" >&2
  echo "  若以失效符号链接调用，请检查链接目标是否存在" >&2
  exit 1
fi

# 第一遍（规则二）: 祖先链上最近的存在 .skills 文件的目录
root=""
d=$anchor
while :; do
  if [ -f "$d/.skills" ]; then
    root=$d
    break
  fi
  [ "$d" = "/" ] && break
  d=$(dirname "$d")
done

# 第二遍（规则一）: 祖先链上最近的 skills 名目录，其父目录为根
if [ -z "$root" ]; then
  d=$anchor
  while :; do
    if [ "$(basename "$d")" = "skills" ]; then
      root=$(dirname "$d")
      break
    fi
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
fi

# 两遍均未命中: 诊断式退出
if [ -z "$root" ]; then
  echo "错误: 未找到内容仓库根 (anchor: $anchor)" >&2
  echo "  脚本入口: $0" >&2
  echo "  规则二未命中: $anchor 至 / 的祖先链上无 .skills 文件" >&2
  echo "  规则一未命中: 该链上无名为 skills 的目录" >&2
  echo "修复建议:" >&2
  echo "  - 标准布局: 将 skill 收纳于仓库根的 skills/ 子目录下" >&2
  echo "  - 非标准布局: 在目标根目录创建 .skills 文件，如: touch <root>/.skills" >&2
  echo "  - 复制安装(物理文件不在内容仓库内): 删除复制件，改用符号链接安装" >&2
  exit 1
fi

# 可选验证层: --require
if [ "${#require_paths[@]}" -gt 0 ]; then
  missing=()
  for p in "${require_paths[@]}"; do
    [ -e "$root/$p" ] || missing+=("$p")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "错误: 根已定位($root)，但特征路径校验未通过:" >&2
    for p in "${missing[@]}"; do
      echo "  缺失: $root/$p" >&2
    done
    echo "  请检查仓库内容与 skill 引用的一致性" >&2
    exit 1
  fi
fi

cd -P "$root" && pwd
