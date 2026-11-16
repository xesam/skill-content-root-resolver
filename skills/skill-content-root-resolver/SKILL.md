---
name: skill-content-root-resolver
description: 为引用同仓库伴生内容（持续更新的规范、模板、知识库）的 skill 解析内容根目录——按 .skills 契约接入：放置位置（skills/ 子目录或 .skills 声明文件）、vendor 根解析脚本 get-content-root.sh、--require 内容校验、符号链接安装与失败排查。Use when creating or wiring a skill whose scripts must locate the root of their companion content repository. Triggers on "skill 脚本找不到规范目录", "skill 引用相对路径失效", "规范更新后 skill 读不到最新内容", "如何安装 skill 到技能目录", "vendor get-content-root.sh", ".skills 文件是什么", "skill 怎么定位内容根目录". Do NOT use for self-contained skills without companion repo content, for locating arbitrary project roots (use git rev-parse), or when the referenced content is a stable snapshot (copy it into the skill instead).
---

# skill-content-root-resolver

## 何时用

判定条件（三条全部满足才接入）：

1. skill 运行时引用伴生内容，且内容**随仓库持续更新**（规范、模板、知识库）；
2. 内容留在内容仓库内演进，skill 与内容**同仓**，skill 只持引用不持内容；
3. skill 以**符号链接**方式安装到技能目录。

不适用（误用即过度设计）：

- 自包含 skill：不引用伴生内容，无需定位；
- 内容是稳定快照：直接把内容复制进 skill 更简单；
- 跨机器定位任意目录：本契约明确排除（无环境变量、无注册表），这是另一个问题。

机制细节、边界语义与设计取舍见 [references/content-root-contract.md](references/content-root-contract.md)（draft-2）。接入前不必通读，按下面四步执行即可。

## 接入协议（四步）

1. **放置**：skill 目录建在 `<root>/skills/<skill>/`（标准布局，无需任何声明）；偏离标准布局时在目标根创建 `.skills` 文件（`touch <root>/.skills`）。

2. **vendor 脚本**：把本 skill 的 `scripts/get-content-root.sh` **复制**进目标 skill 目录。必须复制、不得链接——解析锚点是脚本的物理位置，链接回本仓库会解析到本仓库的根。升级 = 重新复制。

3. **接入说明**：在目标 skill 的 `SKILL.md` 执行流程中加入初始化步骤：

   ```markdown
   ### 获取伴生内容路径

   开始本次流程时，调用当前 skill 随附的 `get-content-root.sh` 一次，并传入本流程需要的全部内容路径：
   `--require "shared-content/prepare.md" "shared-content/workflow.md"`
   将脚本 stdout 作为本次流程的 `CONTENT_ROOT`。后续读取内容时，以 `CONTENT_ROOT` 为根拼接对应相对路径；不要根据当前工作目录推导内容根目录，也不要每读一个文件就重新运行解析器。
   ```

   由 Agent 从当前 skill 的附件中定位并执行脚本；不要要求使用者把 skill 安装目录写入说明。`--require` 是可选的；需要校验时，填写该 skill 实际引用的全部内容相对路径。引用具体内容的 skill 建议启用校验，以确认解析出的根目录包含所需内容；不需要校验时省略该参数即可。此方式无需修改 skill 已有的业务脚本。

4. **安装与验证**：将 `<root>/skills/<skill>` 符号链接到所用 Agent 约定的 skill 安装目录，然后通过该 Agent 从任意 CWD 调用一次，确认输出 `<root>`。

## 失败排查

退出码：`0` 成功（stdout 为根绝对路径）；`1` 解析失败（诊断信息在 stderr）；`2` 用法错误。

| 诊断信息 | 原因 | 修复 |
| --- | --- | --- |
| 两规则均未命中 + 复制安装提示 | skill 物理文件不在内容仓库内 | 删除复制件，改用符号链接安装 |
| 标准布局未命中 | skill 不在 `<root>/skills/` 下 | 移入 `skills/`，或在根创建 `.skills` |
| 非标准布局未命中 | 缺 `.skills` 声明 | `touch <root>/.skills` |
| `缺失: <路径>` | `--require` 校验不通过 | 仓库内容与 skill 引用不一致；若解析出的根非预期仓库，按契约 6.3 检查是否为 `skills` 名目录下的复制安装 |
| 启动前即报 no such file or directory | 符号链接断裂 | 由调用方 shell 报错定位，重建指向仓库内物理位置的链接 |

## 包内容

- `scripts/get-content-root.sh` — 待 vendor 的根解析器（约 100 行 bash，零外部依赖，bash 3.2 兼容）；
- `scripts/test-get-content-root.sh` — 22 个边界用例（契约 6.1 全布局 + 失败语义 + 参数校验 + 确定性），vendor 后建议在目标仓库跑一遍；
- `references/content-root-contract.md` — 契约全文（draft-2）。
