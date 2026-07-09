# MoonForge 架构与运行手册

MoonForge 是一个用 MoonBit（native target）自举的工具：给定一个带 `moon prove`
契约、循环不变式留空并用标签包裹的 `.mbt` 文件，自动调用 LLM 生成不变式、注入
源码、跑 `moon prove` 验证，验证失败则把失败原因喂回给 LLM 重试，直到通过或
耗尽轮次预算。

这份文档描述**当前实现的实际状态**（哪些模块存在、怎么运行、已知边界在哪），
不是路线图。决策过程和历次演进记录在 `MoonForge_PLAN.md`；踩过的坑和可复用的
经验教训在 `docs/LESSONS.md`。三份文档的关系：这份是"现在长什么样"，
`LESSONS.md` 是"为什么长这样、下次别踩同一个坑"，`MoonForge_PLAN.md` 是完整的
历史决策日志，按时间顺序追加，一般不需要通读，只在需要还原某个决策的完整上下文
时查阅。

## 一句话数据流

```
target.mbt (带 @MOONFORGE_INVARIANT_START/_END 标签，标签间留空)
  → bouncer.check_purity + classify_domain   (安全闸门 + 领域分类)
  → bouncer.build_prompt                     (baseline + 领域先验规则)
  → llm.LlmBackend.complete                  (生成候选不变式文本)
  → sanitizer.strip_markdown                 (剥代码围栏，拒绝可疑内容)
  → injector.inject                          (按标签精确替换，绝不动其余内容)
  → prover_loop.ProveRunner.run_prove        (真跑 moon prove)
  → 成功 → VerificationSuccess
  → 失败 → prover_loop.classify + build_repair_instructions → 追加系统提示 → 回到 llm 那一步，直到轮次耗尽
```

整个循环在 `orchestrator.run` / `orchestrator.loop_rounds` 里实现
（`moon-forge/orchestrator/orchestrator.mbt`）。

## 模块地图

| 包 | 路径 | 职责 | 关键类型 |
|---|---|---|---|
| `shell` | `moon-forge/shell/` | 薄封装 `moonbitlang/async/process`，跑任意命令拿 stdout/stderr/exit code | `run_capture` / `run_capture_merged` |
| `llm` | `moon-forge/llm/` | LLM 调度抽象，多后端可插拔 | `trait LlmBackend`，`ShellBackend`、`HttpBackend` |
| `sanitizer` | `moon-forge/sanitizer/` | 把 LLM 原始回复归约成"可信任的一段代码"，归约不了就拒绝而不是猜 | `strip_markdown` → `SanitizeResult`（`Clean` / `NeedsReview`） |
| `injector` | `moon-forge/injector/` | 基于文本标签精确定位/替换，不解析 AST | `locate_region` / `replace_region` / `inject` |
| `bouncer` | `moon-forge/bouncer/` | 前置安全闸门 + 领域分类 + 先验规则库 + prompt 组装 | `check_purity`、`classify_domain`、`build_prompt` |
| `prover_loop` | `moon-forge/prover_loop/` | 跑 `moon prove`（本地或跨 WSL2 桥接）、失败分类、修复提示生成 | `trait ProveRunner`（`LocalProveRunner`/`WslProveRunner`）、`classify`、`build_repair_instructions` |
| `orchestrator` | `moon-forge/orchestrator/` | 串联以上所有模块的主循环，管理轮次预算 | `run`、`RunConfig`、`RunResult` |
| `fixtures` | `moon-forge/fixtures/` | 回归测试用的真实录制样本和端到端 demo 模块 | 见下节 |
| `cmd/main` | `moon-forge/cmd/main/` | 脚手架占位的可执行入口，**尚未实现** CLI 封装 | — |

设计上 `orchestrator` 只依赖 `LlmBackend`/`ProveRunner` 两个 trait，不关心具体
实现，所以换 LLM 后端或换验证执行方式都不需要改 `orchestrator` 代码。

## 三个可插拔的 LLM 后端

`llm/backend.mbt` 定义唯一的接口：

```moonbit
pub(open) trait LlmBackend {
  async fn complete(Self, system_prompt : String, user_prompt : String) -> String
}
```

- **`ShellBackend`**（`llm/shell_backend.mbt`，默认）：调用 `codex exec -s
  read-only`，走已登录的 codex 会话（当前用 `gpt-5.5`）。`-s read-only` +
  独立 scratch 目录确保 codex 只能读取推理，不能写任何文件——真正的文件修改
  永远只经过 `injector`。
- **`HttpBackend`**（`llm/http_backend.mbt`）：直连任意 OpenAI 兼容的
  `/chat/completions` endpoint，`base_url`/`api_key`/`model` 都是构造参数，
  同一个结构体已验证可用于：
  - DeepSeek（`https://api.deepseek.com/v1`，不需要代理）
  - Mistral 的 Leanstral 1.5（`https://api.mistral.ai/v1`，模型 id
    `labs-leanstral-1-5`，本机需要通过 `proxy_url` 走代理才能连通）
  - 可选的 `extra_system_prompt` 字段：在 `bouncer` 组装好的领域先验规则之后
    追加一段"backend 自己的行为提示"，与目标域无关，只跟这个具体模型的已知
    习惯有关。目前唯一在用的值是 `leanstral_prompt_addendum`（给 Leanstral
    的一个 few-shot 示例，见 `docs/LESSONS.md` "prompt 工程"一节）。

切后端就是换构造参数，运行时可切换，不是编译时二选一。

## bouncer：安全闸门 + 领域先验规则

`bouncer` 在每次 `orchestrator.run` 一开始就跑，分两步：

1. `check_purity(source)`：扫描目标文件文本，命中已知副作用包名
   （`moonbitlang/async` 系列）或副作用调用（`println`、`@fs.`、`@process.`
   等）就拒绝，返回 `NeedsHumanReview`，**在调用 LLM 之前**就短路——不是完整
   语义分析，是廉价但零成本的防呆闸门。
2. `classify_domain(source)`：关键词计数分类到 `Defi` / `Graph` /
   `Unclassified`（平局或零命中归 `Unclassified`，不猜测）。
3. `build_prompt(domain, user_task)`：组装 `baseline_system_prompt`（约束
   模型只能用这个工具链已知支持的语法：`proof_require`/`proof_ensure`/
   `proof_invariant`/`proof_assert`/`proof_reasoning`，并列出旧语法
   `invariant:`/`#requires`/`#ensures` 的真实报错文案，明确禁止）+ 领域对应
   的先验规则库（`defi_prior_rules` / `graph_prior_rules` / 中性回退）。

先验规则库目前的内容（`bouncer/prompt_templates.mbt`）：

- **DeFi**：非负性前置条件必须显式声明为具名谓词、除法必须先证明分母非零、
  swap/mint/burn/liquidate 必须有具名的 `proof_ensure`（不能只说"函数正常
  返回"）、舍入方向必须用 `proof_assert` 显式断言。取材于本项目自带的
  `cpmm_swap`/`ltv_lending` 等案例。
- **Graph**：open/closed 集合互斥不变量、代价数组单调性、循环条件必须写成
  `loopvar < expr` 的形状（这个工具链只在这种形状下自动生成终止 variant）、
  优先证明单步松弛的局部正确性而不是一步到位证明全局最优性。取材于
  `moonbit-proof` 里的搜索类 demo 和 `doc/Moonbit 形式化验证通用算法.md`
  第 5 章的 A*/IDA* 路线图。**目前只有单元测试覆盖，还没有真实的端到端 Graph
  验证案例检验过它对 LLM 生成质量的实际影响**（对应 `MoonForge_PLAN.md`
  第 12 节延后事项 #6）。

## prover_loop：真跑 moon prove + 失败分类

### 为什么需要 `WslProveRunner`

`moon prove` 依赖 Why3 + SMT 求解器（Alt-Ergo/Z3/CVC5），这条依赖链在 Windows
原生环境装不起来（`opam` 不支持 Windows 原生）。MoonForge 主进程本身跑在
Windows 原生（因为 `moonbitlang/async` 的 `process` 模块原生支持 Windows），
但验证这一步单独桥接到 WSL2：

```moonbit
pub(open) trait ProveRunner {
  async fn run_prove(Self, module_root : String, package_path : String, pkg_name : String) -> ProveOutcome
}
```

- `LocalProveRunner`：直接在当前机器跑 `moon prove`（适合 MoonForge 本身就
  运行在装好 Why3 的机器上，比如直接在 WSL2 内部跑）。**目前没有任何测试真实
  调用过这个实现**——本机 Windows 没有直接可用的 Why3，所有真实测试都走的是
  `WslProveRunner`（对应延后事项 #3）。
- `WslProveRunner`：从 Windows 原生进程通过 `wsl.exe` 桥接执行 `moon prove`，
  再用第二次 `wsl.exe` 调用读回 `<pkg>.proof.json`（报告路径是 WSL2 内部路径，
  Windows 侧进程不能直接打开）。

### 失败分类（`FailureKind`）

```moonbit
pub(all) enum FailureKind {
  SyntaxError
  Unproved(has_invalid~ : Bool, timeout_goals~ : Int, unknown_goals~ : Int)
  ProverCrashed
  Unknown
}
```

`classify` 优先读结构化的 `.proof.json`（`summary.{valid,invalid,timeout,
unknown,step_limit,oom,failure}` 字段），缺失时（说明连 Why3 都没跑起来，比如
语法解析就失败了）才回退到匹配终端文本。

**关键的真实发现**：这个工具链把 MoonBit 的 `Int` 建模成一个不透明的抽象类型
（不是纯 Z3 整数域），所以"循环不变式假"和"命题本身为假"在当前版本下统一
表现为 `Timeout`/`Unknown`，几乎不会返回带具体反例的清晰 `Invalid`。
`Unproved` 因此不区分"真正证伪"和"solver 放弃"，两者需要的下一步操作一样
（强化不变式/修正谓词）。`has_invalid` 字段仍保留，供未来工具链版本如果真的
能返回干净反例时使用。

### 已知覆盖的真实失败样本（`fixtures/recorded_prove_outputs/`）

| 文件 | 类型 | 说明 |
|---|---|---|
| `success_isqrt.*` | 成功 | 真实录制的 isqrt 通过输出 |
| `success_checksorted.*` | 成功 | 真实录制的 checksorted 通过输出 |
| `syntax_error.txt` | `SyntaxError` | `where` 子句缺逗号触发的连锁报错 |
| `assertion_failed_or_timeout.*` | `Unproved` | 真实的假后置条件案例（如上所述，表现为 timeout 不是 invalid） |
| `legacy_invariant_syntax_error.txt` | `SyntaxError` | LLM 生成旧语法 `invariant:` 触发的真实报错（见 `docs/LESSONS.md`） |

`ProverCrashed` 分类目前只有手写的单元测试覆盖，尚未在真实运行中复现过（对应
延后事项 #5）。

## sanitizer + injector：注入安全的最后一道闸

这两个模块是"防止把 LLM 幻觉直接写进用户源文件"的最后防线，测得比其他模块更
严格。

`sanitizer.strip_markdown` 的策略：
1. 恰好一对代码围栏 → 提取内部内容，`Clean`。
2. 零个围栏 → 用 `looks_like_prose` 启发式判断（是否包含 `fn `/`let `/
   `proof_` 等常见标记），像代码就接受，像散文就 `NeedsReview`。
3. **两个以上围栏** → 直接 `NeedsReview`，不猜哪个是权威版本。

`injector.locate_region`/`replace_region` 基于标签的字面文本定位，起止标签
必须恰好各出现一次、结束标签必须在起始标签之后，否则 raise 而不是静默匹配
错误位置。`replace_region` 会把新内容规范化成"以且只以一个换行符结尾"——
这不是随手加的，是修过一个真实 bug 后加的强制约束（见
`docs/LESSONS.md`）。

`orchestrator.loop_rounds` 对 `sanitizer` 返回 `NeedsReview` 的处理：**如果
轮次预算未耗尽，会走修复循环重试**（`sanitizer.build_repair_instructions`
生成"只返回恰好一个代码块"的追加提示），而不是立刻终止——这个行为是后来
针对 Leanstral 的真实失败模式补上的，对 `ShellBackend`（codex/gpt-5.5）路径
从未触发过。

## 目前已验证的端到端案例

`fixtures/target_examples/` 下有两个独立的 MoonBit 模块，`.mbt` 里的循环体
`proof_invariant` 全部留空并用 `// @MOONFORGE_INVARIANT_START`/`_END`
标签包裹：

- **`isqrt_demo`**：单标量不变式（`0 <= lo`、`lo <= hi`、`lo*lo<=n`、
  `n<(hi+1)*(hi+1)`），`bouncer` 分类结果是 `Unclassified`。
- **`batch_auction_demo`**：真实 DeFi 案例（统一价格批量拍卖的清算数量二分
  搜索），需要两个数组协同的量化不变式（`all_cross_before`/`all_fail_from`），
  手工验证过清空不变式后 5/9 目标超时，是真实会卡住求解器的场景，不是已被
  自动化能力覆盖的伪挑战。`bouncer` 分类结果是 `Defi`，会真实触发先验规则
  注入。

`orchestrator/orchestrator_test.mbt` 里对应的端到端测试都是**真实调用**（真实
起 `codex exec` 进程、真实通过 `wsl.exe` 桥接跑 `moon prove`），不是 mock。
`orchestrator/orchestrator_wbtest.mbt` 里另有两个用 `ScriptedBackend`/
`AlwaysSucceedsRunner` 测试替身驱动的白盒测试，专门覆盖 `NeedsReview` 重试
逻辑本身，不依赖外部服务。

Leanstral 1.5 作为 `HttpBackend` 的评估测试也在 `orchestrator_test.mbt`
里（`MoonForge evaluation: Leanstral 1.5 ...` 两条），行为是"打印结果，不
`fail`"，因为这些是观察性评估而不是验收标准的一部分；`MISTRAL_API_KEY` 未
配置时优雅跳过。评估结论见 `docs/LESSONS.md`。

## 怎么跑

### 环境前提

- Windows 侧：MoonBit 工具链（`moonup` 管理，当前锚定 nightly，与 WSL2 侧
  保持一致）、Visual Studio 2022（提供 MSVC，`native` target 编译需要）。
- WSL2（Ubuntu-24.04）侧：`opam` switch `moonforge`（OCaml 4.14.2）+ Why3
  1.7.2 + Alt-Ergo 2.6.2（`~/.opam/moonforge/bin`）+ Z3 4.15.3 + CVC5 1.3.1
  （`~/tools`，官方二进制直接下载，不经 opam）+ MoonBit nightly（`~/.moon`）。
- `codex` CLI 已登录（`ShellBackend` 依赖它）。
- 可选：`DEEPSEEK_API_KEY`、`MISTRAL_API_KEY` + `MOONFORGE_HTTP_PROXY`
  （测试 `HttpBackend` 用，未设置时相关测试优雅跳过）。

### 编译与检查（不需要 C 编译器）

```bash
cd moon-forge
moon check          # 类型检查，全平台都能跑
moon info && moon fmt  # 更新 .mbti 接口文件 + 格式化
```

### 跑测试（native target，需要先激活 MSVC 环境）

Windows 上 `moon test --target native` 需要系统 C 编译器（`cl`/`cc`/`gcc`/
`clang`），本机走 MSVC，必须先跑 `vcvarsall.bat` 且与 `moon.exe` 在**同一个**
`cmd` 进程里执行（环境变量不会跨进程传播）：

```bash
powershell.exe -NoProfile -Command "cmd.exe /c '\"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat\" x64 && cd \"<项目目录>\" && <moon.exe路径> test --target native'"
```

跑单个包 / 按名字过滤某个测试：加 `<package>` 和 `-f "<test name prefix>*"`。

真实端到端测试（isqrt/batch_auction）会真实调用 `codex exec` 和真实跑
`wsl.exe ... moon prove`，需要网络和 WSL2 环境都可用，跑起来比纯单元测试慢。

### 尚未实现的部分

- `cmd/main` 还没有包装成 `moon-forge run target.mbt` 这样的命令行入口，
  `orchestrator.run` 目前只是库函数。
- 没有终端彩色输出层，`RunResult` 只是一个数据值。
- `LocalProveRunner` 没有专门的端到端测试覆盖。
- Graph 领域没有真实的端到端验证案例（只有 DeFi 和 Unclassified 两个）。

这些延后事项的判断依据（"为什么不影响当前质量"）记录在 `MoonForge_PLAN.md`
第 12 节。
