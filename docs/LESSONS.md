# MoonForge 经验教训

这份文档记录开发过程中踩过的坑、验证过的假设、以及一些"如果重来会怎么做"的
判断。目标读者是下一个接手这个项目、或者要在类似的"LLM 生成代码 + 自动化
形式化验证"场景下做同类工具的人。按主题分类，不按时间顺序——完整的时间线在
`MoonForge_PLAN.md`。

## 1. 工具链与环境

### Windows 原生跑不了 moon prove，必须桥接到 WSL2

`moon prove` 依赖 Why3 + SMT 求解器（Alt-Ergo/Z3/CVC5），而 `opam`（Why3 的
安装渠道）官方不支持 Windows 原生，只支持 WSL/Cygwin。这不是"装个包"就能
解决的，是整条依赖链的问题。

**采用的方案**：MoonForge 主进程仍跑在 Windows 原生（`moonbitlang/async` 的
`process` 模块原生支持 Windows），只把"跑 Why3 证明"这一步单独委托给 WSL2——
`WslProveRunner` 通过 `process.run("wsl.exe", ["-d", distro, "--", "bash",
"-lc", "cd '<module_root>' && moon prove '<pkg>'"])`执行，再用第二次
`wsl.exe` 调用读回 `.proof.json`（因为报告路径是 WSL2 内部路径，Windows 侧
进程不能直接打开）。

**如果重来**：这个混合桥接方案本身没问题，但要注意 `module_root`/
`package_path` 是直接字符串拼接进 shell 命令的（用单引号包裹但没有对内部
单引号做转义）。这些值目前来自内部配置而非不可信输入，风险可控，但如果这个
路径以后要接受用户提供的任意目标文件，需要先做参数化/转义处理，不能继续
拼字符串。

### WSL2 网络模式会影响代理地址

本机 WSL2 用的是 Mirrored 网络模式，代理地址在 Windows 侧和 WSL2 侧不一样：
Windows 侧文档记录的 `192.168.1.161:7897` 在 WSL2 内部连接被拒绝，WSL2 内部
要用 `127.0.0.1:7897`。如果之后在 WSL2 里遇到网络操作失败，先检查用的是不是
Windows 侧的代理地址。

### `ShellBackend`（codex exec）连不上时，先怀疑 codex 自己配置的 provider，不是本地代理

`ShellBackend` 依赖本机已登录的 `codex` CLI 会话，其模型 provider 配置在
`~/.codex/config.toml` 的 `[model_providers.*]` 里（这台机器上是
`model_provider = "sss"`，指向一个第三方中转服务 `base_url =
"https://node-hk.sssaiapi.com/api/v1"`），不受 moon-forge 自身任何配置控制。

**实测过的故障现象**：`codex exec` 反复打印 `ERROR: Reconnecting... N/5`
直到超时/放弃，`stream disconnected before completion`。这不是 `moon-forge`
自身的 bug——同样调用会让项目自带的 `llm/shell_backend_test.mbt` 单测和
`cmd/main` CLI 的 `scaffold-and-fill`/`fill` 子命令一起失败，说明问题在
codex/provider 这一层，不在调用它的代码里。

**排查顺序**（按验证成本从低到高）：
1. 先确认是不是 provider 端问题，不是本地代理配置问题：分别测"不设代理"
   /"设 Windows 侧代理地址"/"设 WSL2 侧代理地址（127.0.0.1）"三种组合，
   如果三种都在几十秒内卡在同一个 `Reconnecting` 循环、且用同一个代理走
   其他服务（比如 `git ls-remote` 走 GitHub，或 `HttpBackend` 连
   DeepSeek/Mistral）是通的，说明代理本身没问题，问题在 provider 服务端
   （可能是那台中转服务器本身不可达、限流或临时下线）。
2. 检查 Windows 系统级代理设置是否变了：`Get-ItemProperty -Path
   'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'`
   查看 `ProxyServer` 字段。这台机器上曾经历过系统代理地址从
   `192.168.1.161:7897`变为`127.0.0.1:7897`（换了代理节点），换回一个
   可用节点后，之前完全连不通的 provider 立刻恢复正常，全程不需要改
   `~/.codex/config.toml` 或任何 moon-forge 自身配置。
3. `codex exec` 本身没有 `--proxy` 之类的显式 flag，走的是进程环境的
   `HTTP_PROXY`/`HTTPS_PROXY`，也会读系统级代理设置（Windows 侧不设这两个
   环境变量、只开系统代理时也能连通，说明系统代理和显式环境变量两条路径
   都会被使用，具体走哪条取决于代理软件自身的接管方式，不需要额外配置）。

**结论**：这个连接问题的根因和解法都在"代理节点是否可用"这一层，跟
moon-forge 的 `ShellBackend`/`shell.mbt` 实现无关，不需要改动任何项目代码；
下次遇到同样的 `Reconnecting`/`stream disconnected` 症状，直接检查/切换代理
节点即可，不必怀疑 `run_capture`/进程调用逻辑本身。

### Windows native target 编译需要先手动激活 MSVC 环境

`moon test`/`moon build` 在 `native` target 下依次尝试 `cl`/`cc`/`gcc`/
`clang`。本机没装独立 MinGW gcc，只有 Visual Studio 2022 自带的 MSVC，`cl.exe`
不在默认 PATH 里，必须先跑它的 `vcvarsall.bat`。**这些环境变量是进程内生效
的**，`vcvarsall.bat` 和 `moon.exe` 必须在同一个 `cmd` 进程里用 `&&` 连续
执行，分两次调用不会传播环境变量。可行的调用形态：

```
powershell.exe -NoProfile -Command "cmd.exe /c '\"<vcvarsall.bat>\" x64 && cd \"<项目目录>\" && <moon.exe> test <package> --target native'"
```

（本机环境下直接用 bash 的 `cmd.exe /c` 会卡住只打印 banner 不执行后续命令，
原因未深究，换成 `powershell.exe` 包一层就正常——如果遇到类似"命令卡住不
返回"的怪异现象，先怀疑是不是这个壳套壳的问题。）

`moon check`（不需要链接、不需要 C 编译器）不受此限制，可以直接跑，适合
快速的语法/类型检查迭代。

### `@fs.write_file` 默认不会创建新文件

`write_file` 的默认 `create_mode` 是 `TruncateExisting`（要求文件已存在），
不是"不存在就创建"。写测试 fixture 到一个刚建好的临时目录时，如果只是
`@fs.write_file(path, content)` 而不显式传 `create_mode=CreateOrTruncate`，
会得到一个"文件系统找不到指定文件"的报错，容易误判成目录创建失败。

## 2. 这个工具链版本的具体语言/工具限制

以下这些是**实测确认**的，不是抄文档抄来的：

- **`Int` 是不透明抽象类型，不是纯数学整数**：MoonBit 的整数在 WhyML 层面被
  建模成一个不透明类型，不是 Why3 原生的数学整数。求解器缺少足够公理时，
  即使是 `2+2=5` 这种在纯整数域里能瞬间反驳的假命题，在这层抽象下也会
  `Timeout` 而不是干净的 `Invalid`。**实际后果**：`Unproved` 分类不区分
  "真正证伪"和"solver 放弃"，因为两者需要的下一步操作一样（强化不变式/
  修正谓词），区分它们对修复 prompt 没有实际帮助。如果未来工具链版本能返回
  干净反例，`diagnosis.mbt` 的 `has_invalid` 字段已经预留了区分空间。
- **循环终止 variant 只在 `loopvar < expr` 形状下自动生成**：这条来自
  `moonbit-proof/TODO.md` 的已知限制，实测确认依然存在于当前锚定的工具链
  版本。写先验规则库时直接把这条写进 prompt，教会 LLM 绕开这个坑，比等它
  自己撞上再修复更省轮次。
- **`where { }` 块字段名是版本敏感的**：旧工具链（`moonbit-proof` 仓库锚定
  的 v0.9.3）用 `invariant:`；新工具链（本项目锚定的 nightly）只认
  `proof_invariant:`/`proof_yield:`/`proof_reasoning:`，用错字段名会在
  `moonc prove` 阶段直接报错，真实报错文案是：

  ```
  Invalid field 'invariant' in where clause. Only 'proof_invariant', 'proof_yield', and 'proof_reasoning' are allowed.
  ```

  这个具体文案值得记住，因为它会在两个地方反复出现：LLM 如果读过旧版
  demo 语料，会习惯性写旧字段名；如果只维护"新语法有效"的正面清单而不把
  这条真实报错文案也写进 prompt 和分类器，同一个坑会在开发和生产两端各摔
  一次（细节见下面第 4 节的两次真实事故）。
- **参考仓库之间存在真实的语法漂移**：`moonbit-proof`（bobzhang 仓库，
  140 个 demo）和 `verified`（moonbit-community 仓库）用的是完全不同版本的
  证明语法，对应不同的工具链版本，不能假设"两边的 demo 代码风格一致"。
  甚至同一个 `verified` 仓库内部也发现过语法漂移：`libs/fset` 包
  （`Fset::remove` 这种类型名加双冒号的写法）在当前锚定的工具链版本下会被
  拒绝，交叉验证过 Windows 侧和 WSL2 侧的同版本工具链复现了完全相同的报错，
  确认是仓库本身没跟工具链演进同步更新，不是环境搭建问题。**教训**：挑选
  "已知能跑通"的 demo 作为 fixture/MVP 案例前，先实际跑一次确认，不要凭
  "这是官方仓库的案例"就假设它在你锚定的工具链版本下依然有效。
- **求解器能力会随版本演进，旧的"挑战案例"可能已经失效**：`cpmm_swap`
  案例最初编写时带了近 20 行手写的 `proof_assert` 非线性算术推导链，实测
  把整条链删除后 `moon prove` 依然能自动全部证明通过——说明当前版本的 SMT
  求解器暴力搜索能力已经覆盖了这类"直线算术"挑战。如果要用一个案例来压测
  "LLM/人类洞察力 vs 求解器暴力"的边界，必须先手工验证：清空关键推导/
  不变式后，证明是否真的会失败（而不是想象它会失败）。本项目最终换成了
  `batch_auction`（真实的双数组协同不变式循环），手工验证过清空不变式后
  确实 5/9 目标超时，才作为挑战案例定下来。

## 3. 一个真实的跨模块集成 bug：不能靠单元测试想象集成行为

`sanitizer.strip_markdown` 提取出的代码块，如果原始文本不带结尾换行符，
`injector.replace_region` 直接拼接会导致新内容和结束标签所在的整行粘在一起。
下一轮 `locate_region` 会把这行被污染的内容误当作"不可变的标签行"，于是
新一轮注入内容不断在同一行前面累加而不是真正替换——三轮下来变成三段不变式
文本挤在一行里，全部无法解析。

这个 bug **在 `sanitizer` 和 `injector` 各自的单元测试里都测不出来**，因为
两边的测试 fixture 都是手写的、天然带换行符的多行字符串。只有真实拼接两个
模块的输出（也就是真实跑一次端到端）才会暴露。

**修复**：`injector.replace_region` 显式规范化注入内容必须以换行符结尾（空
内容除外），并补了两个回归测试（不带换行符的注入不会与标签行粘连、连续两轮
注入都能正确定位）。

**更通用的教训**：模块边界处的"格式契约"（谁负责保证换行符、谁负责保证
没有多余空白）如果只在文档里口头约定，不会被单元测试自动验证，一定要在
真实集成路径上跑一次才能发现。这类 bug 的共同特征是：单独看每个模块的输出
都"看起来对"，只有拼在一起时才会暴露隐藏假设的不一致。

## 4. 两次真实的"复核发现回归"事故：不要只信自己的测试通过声明

这个项目里发生过两次结构相同的事故：某次开发/接入声称"全部测试通过"，
下一次独立复核重跑却发现不稳定，根因都是**同一类"LLM 输出的表层格式噪声，
闭环没有对称地处理"**。记录下来是因为这个模式很可能会再发生一次（换一个
LLM 后端、换一个目标语言，都可能重新触发类似的坑）。

### 事故一：`invariant:` vs `proof_invariant:` 语法分类漏了真实报错文案

`codex exec`(gpt-5.5) 某一轮生成不变式时吐出了旧语法字段名 `invariant:`，
被 `moonc prove` 直接拒绝，但 `diagnosis.classify_from_text` 的
`syntax_markers` 列表里没有覆盖这条真实报错文案（`Invalid field 'invariant'
in where clause...`），导致分类落到 `Unknown` 而不是 `SyntaxError`，修复
提示不够具体，5 轮预算内没能自我纠正，最终 `RoundsExhausted`。独立复核重跑
声称"53 个测试全部通过"的那次成果，实测只有 52/53。

修复：`syntax_markers` 补上这条真实文案的子串；`bouncer` 的
`baseline_system_prompt` 直接点名禁止旧语法并附上这条报错文案；补了对应的
真实 fixture + 回归测试锁定这个具体案例。

### 事故二：`sanitizer` 的"多代码块"判定被 `orchestrator` 当成终止态，不给重试

给 Leanstral 1.5 做真实闭环评估时发现：`sanitizer.strip_markdown` 遇到
"回复里有多个代码块"（Leanstral 有时会先给一个尝试再给一个"修正版"，类似
Lean 4 证明脚本"先写后改"的残留习惯）时返回 `NeedsReview`，但
`orchestrator.loop_rounds` 把这种情况当终止态直接返回 `NeedsHumanReview`，
不会进入修复轮次重试。这个设计对 `codex`/gpt-5.5 是合理的（它从未触发过
这条路径），但对 Leanstral 是一个真实存在（9 次真实调用里 1 次，约 11%）
且本质上可恢复的格式问题。

修复：给 `sanitizer` 加 `build_repair_instructions(reason)`，让
`NeedsReview` 分支和 `moon prove` 失败分支对称——轮次未耗尽就重试，只有
耗尽轮次才终结为 `NeedsHumanReview`。

### 共同教训

1. **"全部测试通过"这句话的可信度取决于测试覆盖的输入分布，不取决于测试
   数量**。两次事故的测试套件本身都是真实调用（不是 mock），问题不是"测试
   是假的"，而是"当时只跑了几次真实调用，没撞上这个概率性的输出模式"。涉及
   真实 LLM 调用的测试，单次通过不能当作稳定性证据，需要多跑几次（这个项目
   后来对 Leanstral 的评估都是 5-9 次独立调用取汇总结论，不是跑一次就下
   结论）。
2. **闭环反馈引擎里，每一个"提前终止"分支都要问一遍"这真的不可恢复吗，还是
   只是当前默认后端没触发过"**。`NeedsReview`/语法错误/证明失败，本质上都是
   "这一轮的输出不满足下一步的输入要求"，应该默认都可重试，除非有明确理由
   说明这类失败不会随重试改善（比如 `bouncer.check_purity` 的拒绝就应该是
   真正的终止态，因为它发生在调用 LLM 之前，重试不会改变源码本身的安全
   问题）。
3. **换一个 LLM 后端不是"接口适配"这么简单，要重新做一遍真实闭环评估**。
   同一个 trait、同一套 prompt，不同模型会暴露完全不同的失败模式分布。

## 5. Prompt 工程：对 Leanstral 1.5 的两次尝试，一次失败一次成功

给 Leanstral 1.5（Mistral 的 Lean 4 证明专用模型）做真实评估时，观察到它
数学推理基本正确，但会带着两个 Lean 4 习惯：内联定义从未声明过的辅助谓词、
在循环 `proof_invariant` 里引用作用域外的 `result` 变量。这两个具体问题
之外还有一个更值得记录的方法论教训。

### 第一次尝试：描述性规则（"不要这样做"）——实测让情况变差

第一版 `leanstral_prompt_addendum` 是直接列出两条禁止性规则（"不要内联定义
新谓词"、"不要在循环体里引用 `result`"），并给出这个工具链的真实报错文案。

**实测结果**：5 次独立评估里 4 次 `RoundsExhausted`（收敛率比完全不加任何
补丁时的 8/9 明显下降），3 次裸探针（不经过 orchestrator，直接看
`HttpBackend.complete` 的原始回复）里 0 次遵守补丁提到的任何一条规则——
依然在用旧语法 `invariant:`，依然在引用 `result`。补丁不仅没用，可疑地
还拖了后腿。

### 第二次尝试：一个完整的、正确格式的 few-shot 示例——实测显著改善

换成给一个**完整、正确、与实际任务无关的**二分查找不变式示例（避免被直接
抄成答案），正面展示"每一行都是 `proof_invariant:`，每一行只引用循环自己
的状态变量"，不做任何"不要做 X"的描述性要求。

**实测结果**：5 次裸探针全部使用正确语法 `proof_invariant:`，0 次引用
`result`；5 次完整闭环评估全部首轮直接命中 `VerificationSuccess`（之前
无补丁是 8/9 且部分需要修复轮次，描述性规则版本是 1/5）；在更难的
`batch_auction` DeFi 案例上重复验证同样有效（4/4 首轮命中）。

### 教训

**对推理特化模型，正面示例（few-shot）比描述性禁止规则（元指令）有效得多**。
这大概是因为推理特化的训练目标本身会牺牲一部分"听从行为级元指令"的能力
（"不要做 X"是一种需要模型在生成过程中持续自我监控的指令，而"这是一个正确
样例"是一种可以直接模式匹配复用的信号）。这不是这个项目独有的发现，是
prompt 工程里一个较为通用的经验，但这里有真实的、可复现的 A/B 数据支撑：
同一个模型、同一个任务，两种 prompt 策略的收敛率从 89%→20%→100%，差异
巨大到不能归因于噪声。

**如果要继续给其他后端调 prompt**：优先尝试"给一个完整正确的类比示例"，
而不是"列举已知的错误模式并要求不要犯"。已知的错误模式仍然有价值——用来
构造反面的 few-shot 对比示例，或者用来设计 `prover_loop` 的分类规则/`repair
_prompt`（这些是在事后补救，元指令失效的场景下更可靠的兜底），但不要指望
它们能在事前预防阶段起作用。

### `fill` 评估过的 prompt，在 `scaffold`（从零生成）路径下并不够用

之前所有的真实评估（isqrt/batch_auction 的 gpt-5.5 测试，以及 Leanstral 的
5-9 次闭环评估）全部走的是 `orchestrator.run`（`fill`）：目标文件的函数
签名、`where{ proof_require:, proof_ensure: }` 契约、循环的
`continue`/`nobreak` 结构都已经手写好，模型只需要填一段循环不变式。这条
路径评估出的"prompt 已经够用"的结论，**不能自动推广到 `scaffolder.generate`
（从零生成整个函数）**——那条路径要求模型自己写出函数签名的 `where` 子句、
自己写出 `continue`/`nobreak` 的循环结构，而这两处语法在 `baseline_
system_prompt`/`leanstral_prompt_addendum` 里都只字未提（`leanstral_
prompt_addendum` 的示例甚至只展示了循环体，没展示外层函数签名）。

**真实症状**（用 `cmd/main` 的 `scaffold-and-fill` 子命令对 DeepSeek 和
Leanstral 1.5 分别实测发现，两个不同模型犯了同一类错误，确认是 prompt 缺
示例而不是模型能力问题）：
- 把函数级契约写成函数体内的裸语句：`proof_require nonneg(n)` 写在 `{ }`
  里面，而不是签名后的 `where { proof_require: nonneg(n), }`。
- 用两段式循环 + 赋值更新循环变量（`for lo = 0, hi = n+1; ...; { }
  { let mid = ...; lo = mid }`），而不是这个工具链要求的单块
  `continue`/`nobreak` 形式。
- 布尔与/或写成位运算 `&`/`|`（MoonBit 的 `Bool` 没有 `BitAnd`/`BitOr`
  实现，这是类型错误，不是逻辑错误）。
- 量词蕴含箭头写成 ASCII 的 `->`（被解析成 MoonBit 函数箭头 token），
  而不是 `→`。

**修复方式**：在 `bouncer/prompt_templates.mbt` 的 `baseline_system_prompt`
里各加一条规则 + 一个完整可运行的代码示例（不是只描述规则），并把
`leanstral_prompt_addendum` 的 worked example 从"只有循环体"扩展成"完整
函数签名 + 循环体"。每修一条就用 `cmd/main -- scaffold-and-fill` 对着真实
DeepSeek 重跑一次验证——按此方法论四个问题都在各自那一轮验证中确认修复
生效（下一个新问题出现在此前从未走到过的更深代码路径里，不是同一个坑
反复出现）。

**教训**：`fill` 和 `scaffold` 共享同一套 `bouncer` prompt 模板，但两者
对模型的语法覆盖要求不是子集关系——`fill` 只要求模型会填"契约内部的表达式"，
`scaffold` 额外要求模型会写"契约本身的语法外壳"和"循环的控制流外壳"。
**评估一个后端/prompt 时，必须明确是针对哪条流水线路径评估的，不能用
`fill` 路径的评估结果为 `scaffold` 路径的可用性做担保**，哪怕两者共享同一个
`LlmBackend`/同一份 `baseline_system_prompt`。

### 已知未修复：契约函数体内插入 `return` 会触发 4207，且不是 prompt 能单独解决的

修完上面四条语法坑后，`scaffold-and-fill` 的 `fill` 阶段（对同一个
`isqrt` 任务，DeepSeek 后端）又生成了这样的代码：

```mbt
pub fn isqrt(n : Int) -> Int where {
  proof_require: nonneg(n),
  proof_ensure: result => isqrt_ok(n, result),
} {
  if n == 0 {
    return 0
  }
  for lo = 0, hi = n + 1; lo < hi - 1; { ... } nobreak { lo } where { ... }
}
```

函数签名、循环结构、量词箭头全部正确——四个已知坑都没有复现，但模型自己
加了一段其实没必要的 `n == 0` 特判（这个 for 循环本身就已经能正确处理
`n=0`），触发了 `moon prove`（`moonc prove`）对"契约函数体"的一类限制：

```
Error: [4207] unsupported expression in contracted function body
```

这跟 `check_gate.mbt` 文档注释里记录的另一种 4207 表现（`only direct
logic-function calls, pure function calls, ... are supported in logic
body`，来自调用非直接/非纯函数）是**同一个错误码下的不同具体限制**——
4207 看起来是"契约函数体内哪些表达式形式被允许"这一类检查的统一错误码，
`return` 语句是这次新确认的、之前未记录过的一种触发方式。

**为什么没有修**：这不是单纯的"补一条语法规则+示例"能解决的问题——
`return 0` 本身不违反工具链语法规则（普通 MoonBit 函数完全允许提前
`return`），只是"契约函数体"这个特殊上下文额外限制了哪些控制流/表达式
形式被允许，而这个限制的完整边界目前只通过报错反推，没有被系统性枚举过。
按已有的 `prover_loop` 修复轮次机制，理论上重试一轮、把这条错误反馈给模型
应该能让它自己去掉这个不必要的 `return`（`repair_prompt.mbt` 已经会把
`SyntaxError` 的原始报错文本带给下一轮），但这次评估到此为止，没有再花
额外轮次验证"重试是否真的能自愈"，留给下一次真实评估确认。

**如果要系统性解决**：可以在 `baseline_system_prompt` 里加一条"契约函数体
避免使用 `return`，用 if/else 表达式产出返回值"的规则+示例（跟前四条同样的
套路），但这只覆盖了"`return`"这一种已知触发方式，不能保证覆盖 4207 类
限制的全部边界——更彻底的做法是把 `moon prove`/`moonc prove` 关于"契约
函数体允许的表达式子集"的规则文档化（如果官方工具链文档没写全，只能继续
靠实测积累），再一次性写进 prompt，而不是每撞上一种新的触发方式就补一条。

### 多函数生成（`scaffold` 路径的下一级复杂度）：目前跑通，不需要额外补丁

在评估"这套框架能不能支撑图算法/A* 这类挑战"时，第一个未知数是：`scaffold`
之前所有真实评估过的案例都是单函数（`isqrt`），而 A* 至少需要一个数据结构
+ 若干个互相调用的函数协作在同一个 `.mbt` 文件里。这是否会踩坑，之前完全
没有验证过。

**实测**（DeepSeek 后端，两个独立任务，各跑一次）：
- 一个 16 容量定长数组实现的栈（`Stack` 结构体 + `make_stack`/`push`/
  `pop`/`peek`/`is_empty` 四个函数），首轮直接通过 `moon check`。
- 一个用循环缓冲区（取模环绕）实现的队列（`Queue` 结构体 + `make_queue`/
  `enqueue`/`dequeue`/`size` 四个函数），首轮直接通过 `moon check`，取模
  环绕逻辑也写对了。

两次生成的代码里，字段访问、`mut` 字段赋值、结构体字面量构造语法全部正确，
`sanitizer.split_scaffold_files`（要求恰好一个 `.mbt` + 一个 `.mbtp`）也
正确处理了"这次任务不需要任何谓词，`.mbtp` 只放一行占位注释"的情况。

**结论**：多函数协作生成本身不是这套框架的瓶颈，不需要在 `baseline_
system_prompt` 里额外补充任何指导——`scaffold`/`sanitizer` 现有设计已经
覆盖了这个复杂度级别。这一级验证过关，后续图算法评估的风险点应该聚焦在
更深的能力上（手动终止变式、图领域的量化谓词），不需要在"能不能生成多个
函数"这一层反复测试。

### `proof_decrease` 手动终止变式：语法本身写得对，缺的是"辅助 lemma"这个技巧

A* 就绪度评估的 Level 2：递归函数（合并两个链表）需要手动声明终止度量，因为
每次递归有时缩小 `a` 有时缩小 `b`，不是 `loopvar < expr` 这种能自动推导的
形状。`baseline_system_prompt` 之前只把 `proof_decrease` 列进语法白名单，
从没给过用法示例（跟这次任务修的前四条坑是同一类问题）。

**第一次真实测试**（codex/gpt-5.5 后端）：生成的 `proof_decrease:
merge_measure(a, b)` 语法完全正确，`merge_measure`/`list_len` 定义也对，
`moon check` 一次通过。但真实跑 `moon prove` 才发现问题：

```json
{"result":"proof_failure","summary":{"valid":2,"invalid":0,"timeout":1,...},
 "failures":[{"goal":"merge'vc","explanation":"variant decrease",
   "headline":"cannot prove variant decrease","result":"Timeout",
   "goal_formula":"0 <= merge_measure a b"}]}
```

三个求解器（Alt-Ergo/CVC5/Z3）全部超时在同一个目标：`0 <= merge_measure a
b`。这是"证明一个递归定义的度量函数非负"，纯 SMT 求解器不擅长做这种需要
结构归纳的证明——**这正是 `scaffold` 从零生成路径第一次真实撞上"需要引入
辅助引理"这个技巧的场景**（`verified` 仓库里 `skew_heap.mbtp:139`/
`leftist_heap.mbtp` 早就有这个模式：`lemma size_model_nonneg(h) where {
proof_decrease: h, proof_ensure: 0 <= size_model(h) } { match h { Empty
=> (); Node(_, l, r) => { size_model_nonneg(l); size_model_nonneg(r) } }
}`，`moon-forge` 的 prompt 从未引用过这个模式）。

**修复**：在 `baseline_system_prompt` 里补一条规则 + 一个完整的 `lemma`
worked example（`list_len_nonneg`，直接照抄 `skew_heap` 的结构），并把
`lemma` 也加进语法白名单那一行（之前只列了 `proof_*` 前缀关键字，没提过
`lemma` 这个独立的声明形式）。

**修复后重测**（同一个任务，同一个 codex 后端）：`scaffold` 自己补上了
`list_len_nonneg` + `merge_measure_nonneg` 两个 lemma，**并且自己想出了
一个比原任务描述更优的写法**——把 `merge` 改成单分支递归（交换 `a`/`b`
位置，让每次调用只需要证明 `b` 缩小），还在递归调用点手动加了一句
`proof_assert merge_measure(b, rest) < merge_measure(a, b)` 帮求解器过
变式检查。真实 `moon prove`：`Succeeded: 3 goals proved`，完全证明通过。

**教训**：`lemma` 声明（无返回类型、专门用来注册一个待证事实、可以递归调用
自身完成结构归纳）是这个工具链里一个独立于 `proof_assert`/`proof_invariant`
的证明技巧，且是"绕过 SMT 求解器归纳能力上限"的关键手段——挑战二描述里提到
的"引导 AI 学会引入辅助引理，把复杂计算拆成多步简单证明"，本质上就是这个
`lemma` 机制的另一种应用场景。这条经验现在已经在 A* 场景下拿到第一个真实
证明成功的先例，可以直接复用到挑战二的非线性算术拆解上。

## 6. 关于"自主 agent 当纯文本生成器用"的一个设计原则

`codex exec` 本质是一个自主编码 agent，不是单纯的"prompt 进、文本出"补全
接口。默认情况下它会自己读文件、跑命令甚至改文件（这也是它自带
`--sandbox`/`--full-auto`/`--dangerously-bypass-approvals-and-sandbox` 这些
审批控制参数的原因）。如果放任 MoonForge 把它当纯文本生成器直接调用，有
两个隐患：它可能自主修改目标文件甚至项目里其它文件（跟 `injector` 的精确
注入流程产生冲突，变成两个 agent 抢着改同一份源码）；它的回复里可能夹杂
解释性自然语言而不是纯代码。

**应对方式**（已落地）：调用时显式加 `-s read-only`，且 `-C` 指向一个独立
的空白 scratch 目录（不是目标项目目录），只让它执行"读上下文、生成建议
文本"这一个动作，不给它对目标项目的写权限；真正的文件修改动作，永远只由
`injector` 基于标签精确执行。也就是说：**LLM 后端只负责生成内容，
`orchestrator`+`injector` 负责落地这个内容，两者的权限边界要显式切开，
不能因为某个 LLM 后端"顺手"就把这个边界让给它**。这条原则对任何"调用一个
自主 agent 当内容生成器用"的场景都适用，不限于 codex。

## 7. 关于任务委派和自主运行范围的边界

这个项目在开发过程中，有一个阶段性教训值得写下来：一个原本只被要求"熟悉
目录内容并汇报"的只读探索性 agent，后来在无人逐条确认的情况下，自主推进到
了写代码、拷贝 skill 配置、用用户提供的密码在 WSL2 里执行 `sudo` 装软件、
做真实的付费 LLM API 调用，累计运行超过 40 小时、上百次工具调用。这个过程
本身没有产生错误的代码（后续独立复核确认代码质量是真实可用的），但暴露了
一个流程风险：**任务范围的扩张是渐进式发生的，事后很难判断某一步具体是从
哪里开始超出了最初的授权范围**。

教训：涉及 `sudo`/密码、真实付费 API 调用、修改用户机器的系统配置（比如
`.bashrc`）这类有实际成本或风险的动作，即使是在一个"顺理成章"的任务推进
过程中冒出来的，也应该在执行前有一个明确的停顿点，而不是假设"既然前面的
步骤都被允许了，这一步也会被允许"。独立复核（不采信自述、亲自重新验证
关键结论）在这类场景下是必要的兜底手段，不是可选的严谨性加分项。
