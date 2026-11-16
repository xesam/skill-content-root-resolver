# skill-content-root-resolver

`skill-content-root-resolver` 帮助把 **skill** 与它引用的 **主体内容** 分开维护，并让多种 Agent 和多个 skill 复用同一份源文件，避免复制后逐份更新。

## 它解决什么问题

这里有两个独立的重复问题：

| 要复用的内容 | 复制带来的问题 | 解决方式 |
| --- | --- | --- |
| 同一个 skill 被多个 Agent 使用 | 把 skill 复制到各 Agent 的安装目录后，更新要逐份同步 | skill 源文件保留一份，各 Agent 的约定目录用软链接指向它 |
| 同一套 SOP 被多个 skill 使用 | 把 SOP 放进每个 skill 后，更新要逐份同步 | SOP 在仓库中保留一份，各 skill 通过解析器定位并读取 |

软链接解决了 skill 源文件的复用，但 Agent 运行 skill 时，通常仍在用户当前打开的工程目录中工作，不会自动切换到 skill 源目录。因此，skill 不能依赖当前工作目录（CWD）拼出 SOP 路径。本项目提供一个小型 Bash 解析器，从 skill 内解析器脚本的实际位置找到主体内容仓库根目录；解析结果不依赖 Agent 当前工作的目录。

## 适用范围

适合希望维护一份共享主体内容，并由一个或多个 skill 引用的团队或个人：

- SOP、规范、模板、知识库等内容需要持续更新；
- 一个或多个 skill 需要引用这些内容，不希望将内容复制到每个 skill；
- skill 源文件保留在源仓库，通过软链接安装到 Agent 约定的目录。

本解析器要求 skill 和其引用的主体内容位于同一源仓库中：标准布局是 `<repo>/skills/<skill>/`，非标准布局可用根目录 `.skills` 文件声明。它不负责创建软链接，也不用于定位任意项目的 Git 根目录。如果内容是稳定快照、自包含于单个 skill 就足够，直接放入 skill 会更简单。

## 工作方式

主体内容与 skill 源文件保留在同一份仓库中，但各自分开管理：

```text
<source-repo>/
├── shared-content/
│   └── workflow.md
└── skills/
    ├── skill-a/
    │   ├── SKILL.md
    │   └── get-content-root.sh
    └── skill-b/
        ├── SKILL.md
        └── get-content-root.sh

<agent-a-skill-dir>/skill-a -> <source-repo>/skills/skill-a
<agent-b-skill-dir>/skill-a -> <source-repo>/skills/skill-a
```

`skill-a` 和 `skill-b` 可以读取同一份 `shared-content/workflow.md`；不同 Agent 的安装目录也都可以链接到同一个 `skill-a` 源目录。解析器从自身所在路径向上识别源仓库根目录。非标准布局可以在源仓库根目录放一个空的 `.skills` 文件作为显式标记。`--require` 可检查目标内容文件确实存在。

## 接入现有 skill

接入时不需要改已有的业务脚本。将解析器复制到目标 skill，并在 `SKILL.md` 执行流程中加入一个初始化步骤，让 Agent 在读取 SOP 前运行解析器。

1. 将本项目的 `get-content-root.sh` **复制**到目标 skill 目录。不要把它链接回本项目：解析器必须从目标仓库中的物理位置定位根目录。
2. 确保目标 skill 位于 `<repo>/skills/<skill>/`；如果采用其他布局，在 `<repo>/.skills` 创建标记文件。
3. 在目标 skill 的 `SKILL.md` 执行步骤中加入类似指令：

   ```markdown
   ### 获取伴生内容路径

   开始本次流程时，调用当前 skill 随附的 `get-content-root.sh` 一次，并传入本流程需要的全部内容路径：
   `--require "shared-content/prepare.md" "shared-content/workflow.md"`
   将脚本 stdout 作为本次流程的 `CONTENT_ROOT`。后续读取内容时，以 `CONTENT_ROOT` 为根拼接对应相对路径；不要根据当前工作目录推导内容根目录，也不要每读一个文件就重新运行解析器。
   ```

   由 Agent 从当前 skill 的附件中定位并执行该脚本；不要要求使用者把 skill 安装目录写入说明，也不要从工程当前工作目录推导脚本位置。`--require` 是可选的；需要校验时，填写该 skill 实际引用的全部主体内容相对路径。引用具体内容的 skill 建议启用校验，以确认解析出的根目录包含所需内容。若不需要校验，调用时省略 `--require` 及其路径即可。这样只需调整 skill 的说明文件，不必逐一改写已有的 shell、构建或业务脚本。
4. 将 skill 目录符号链接到你的 skill 安装目录，并通过目标 Agent 从不同于仓库根目录的位置调用一次，确认能找到内容。

## 在本仓库验证

将 skill 安装为符号链接：

```bash
mkdir -p "/absolute/path/to/agent/skills"
ln -s "$(pwd)/skills/skill-content-root-resolver" \
  "/absolute/path/to/agent/skills/skill-content-root-resolver"
```

将示例中的 `/absolute/path/to/agent/skills` 替换为所用 Agent 约定的 skill 安装目录。

直接运行解析器时，它应输出本仓库根目录的绝对路径：

```bash
bash skills/skill-content-root-resolver/scripts/get-content-root.sh
```

运行测试：

```bash
bash skills/skill-content-root-resolver/scripts/test-get-content-root.sh
```

## 进一步阅读

- [Skill 使用说明](skills/skill-content-root-resolver/SKILL.md)：接入步骤、适用判定和故障排查。
- [完整契约](skills/skill-content-root-resolver/references/content-root-contract.md)：根目录识别规则、边界情况和失败语义。
