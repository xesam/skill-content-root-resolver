#!/bin/bash
# get-content-root.sh 验证用例：契约 6.1 边界布局 + 失败语义 + 验证层
set -u

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd)
SUBJECT="$SCRIPT_DIR/get-content-root.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gsr-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

# canonical <dir>: 规整 mktemp 在 macOS 下的 /var 符号链接
canonical() { cd -P "$1" && pwd; }

assert_resolve() {
  desc=$1; expected=$2; script=$3; shift 3
  out=$(bash "$script" "$@" 2>/dev/null); code=$?
  if [ "$code" -eq 0 ] && [ "$out" = "$expected" ]; then
    ok "$desc"
  else
    bad "$desc (code=$code out=$out)"
  fi
}

assert_fail() {
  desc=$1; xcode=$2; pattern=$3; script=$4; shift 4
  out=$(bash "$script" "$@" 2>"$TMP/err.txt"); code=$?
  err=$(cat "$TMP/err.txt")
  if [ "$code" -eq "$xcode" ] && printf '%s' "$err" | grep -q "$pattern"; then
    ok "$desc"
  else
    bad "$desc (code=$code err=$err)"
  fi
}

touch "$TMP/outside.md"

# A. 标准布局（规则一）
RA=$TMP/std; mkdir -p "$RA/skills/foo"; cp "$SUBJECT" "$RA/skills/foo/get-content-root.sh"; RA=$(canonical "$RA")
assert_resolve "A 标准布局 → root" "$RA" "$RA/skills/foo/get-content-root.sh"

# B. skills 下任意深度嵌套（规则一）
RB=$TMP/deep; mkdir -p "$RB/skills/cat/foo"; cp "$SUBJECT" "$RB/skills/cat/foo/get-content-root.sh"; RB=$(canonical "$RB")
assert_resolve "B 任意深度嵌套 → root" "$RB" "$RB/skills/cat/foo/get-content-root.sh"

# C. 脚本直接位于 skills/（规则一，anchor 自身）
RC=$TMP/flat; mkdir -p "$RC/skills"; cp "$SUBJECT" "$RC/skills/get-content-root.sh"; RC=$(canonical "$RC")
assert_resolve "C 脚本在 skills/ 层 → root" "$RC" "$RC/skills/get-content-root.sh"

# D. 非标准布局、无声明 → 诊断式失败
RD=$TMP/nostd; mkdir -p "$RD/x/y/foo"; cp "$SUBJECT" "$RD/x/y/foo/get-content-root.sh"
assert_fail "D 非标准无 .skills → exit 1 + 诊断" 1 "未找到内容仓库根" "$RD/x/y/foo/get-content-root.sh"

# E. 非标准布局 + .skills（规则二）
RE=$TMP/marker; mkdir -p "$RE/x/y/foo"; cp "$SUBJECT" "$RE/x/y/foo/get-content-root.sh"; touch "$RE/.skills"; RE=$(canonical "$RE")
assert_resolve "E .skills 声明 → root" "$RE" "$RE/x/y/foo/get-content-root.sh"

# F. 规则二优先于放错位置的 skills 目录
RF=$TMP/prio; mkdir -p "$RF/sub/skills/foo"; cp "$SUBJECT" "$RF/sub/skills/foo/get-content-root.sh"; touch "$RF/.skills"; RF=$(canonical "$RF")
assert_resolve "F 声明覆盖 sub/skills → root 而非 sub" "$RF" "$RF/sub/skills/foo/get-content-root.sh"

# G. 嵌套宿主：外层声明、内层标准布局 → 外层
RG=$TMP/outer; mkdir -p "$RG/inner/skills/foo"; cp "$SUBJECT" "$RG/inner/skills/foo/get-content-root.sh"; touch "$RG/.skills"; RG=$(canonical "$RG")
assert_resolve "G 嵌套宿主外层声明 → outer" "$RG" "$RG/inner/skills/foo/get-content-root.sh"

# H. 嵌套宿主：内层也声明 → 最近声明胜出
RH=$TMP/both; mkdir -p "$RH/outer/inner/skills/foo"; cp "$SUBJECT" "$RH/outer/inner/skills/foo/get-content-root.sh"; touch "$RH/outer/.skills" "$RH/outer/inner/.skills"
OUTER=$(canonical "$RH/outer"); INNER=$(canonical "$RH/outer/inner")
assert_resolve "H 最近 .skills 胜出 → inner" "$INNER" "$RH/outer/inner/skills/foo/get-content-root.sh"

# I. .skills 为目录时不构成声明（-f 判定），回退规则一
RI=$TMP/dirmark; mkdir -p "$RI/.skills" "$RI/skills/foo"; cp "$SUBJECT" "$RI/skills/foo/get-content-root.sh"; RI=$(canonical "$RI")
assert_resolve "I .skills 目录不误判 → 仍按规则一" "$RI" "$RI/skills/foo/get-content-root.sh"

# J. 目录级符号链接安装（契约主安装方式）
RJ=$TMP/dirsym; mkdir -p "$RJ/skills/foo" "$RJ/installA"; cp "$SUBJECT" "$RJ/skills/foo/get-content-root.sh"; ln -s "$RJ/skills/foo" "$RJ/installA/foo"; RJ=$(canonical "$RJ")
assert_resolve "J 目录级符号链接 → root" "$RJ" "$RJ/installA/foo/get-content-root.sh"

# K. 文件级符号链接安装
RK=$TMP/filesym; mkdir -p "$RK/skills/foo" "$RK/installB"; cp "$SUBJECT" "$RK/skills/foo/get-content-root.sh"; ln -s "$RK/skills/foo/get-content-root.sh" "$RK/installB/get-content-root.sh"; RK=$(canonical "$RK")
assert_resolve "K 文件级符号链接 → root" "$RK" "$RK/installB/get-content-root.sh"

# L. --require 通过
RL=$TMP/reqok; mkdir -p "$RL/skills/foo" "$RL/docs"; cp "$SUBJECT" "$RL/skills/foo/get-content-root.sh"; touch "$RL/docs/x.md"; RL=$(canonical "$RL")
assert_resolve "L --require 全部存在 → root" "$RL" "$RL/skills/foo/get-content-root.sh" --require docs/x.md

# M. --require 失败 → 列出缺失路径
assert_fail "M --require 缺失 → exit 1 + 列出缺失" 1 "缺失:" "$RL/skills/foo/get-content-root.sh" --require docs/missing.md

# N. --require 无参数 → 用法错误
assert_fail "N --require 无参数 → exit 2" 2 "用法:" "$RL/skills/foo/get-content-root.sh" --require

# O. 未知旗标 → 用法错误
assert_fail "O 未知旗标 → exit 2" 2 "用法:" "$RL/skills/foo/get-content-root.sh" --bogus

# P. --require 列表中混入旗标 → 用法错误
assert_fail "P require 列表混入旗标 → exit 2" 2 "用法:" "$RL/skills/foo/get-content-root.sh" --require docs --x

# Q. 任意 CWD 调用结果一致（确定性）
o1=$(cd / && bash "$RA/skills/foo/get-content-root.sh"); c1=$?
o2=$(cd "$TMP" && bash "$RA/skills/foo/get-content-root.sh"); c2=$?
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && [ "$o1" = "$o2" ] && [ "$o1" = "$RA" ]; then
  ok "Q 任意 CWD 调用结果一致"
else
  bad "Q 任意 CWD 调用结果一致 (o1=$o1 o2=$o2)"
fi

# R-U. --require 参数必须是有效的仓库内相对路径
assert_fail "R --require 父目录路径 → exit 2" 2 "不得包含 .." "$RL/skills/foo/get-content-root.sh" --require ../outside.md
assert_fail "S --require 绝对路径 → exit 2" 2 "必须是仓库根内的相对路径" "$RL/skills/foo/get-content-root.sh" --require "$TMP/outside.md"
assert_fail "T --require 空路径 → exit 2" 2 "路径不能为空" "$RL/skills/foo/get-content-root.sh" --require ""
assert_fail "U --require 根目录本身 → exit 2" 2 "不能指向仓库根目录本身" "$RL/skills/foo/get-content-root.sh" --require .
assert_fail "V --require 点路径归一化到根目录 → exit 2" 2 "不能指向仓库根目录本身" "$RL/skills/foo/get-content-root.sh" --require ./.

echo "-----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
