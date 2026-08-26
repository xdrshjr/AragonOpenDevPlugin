# Academic Paper Forge

Multi-agent academic paper writing system that analyzes code repositories, extracts innovations through structured debate, and collaboratively writes publication-quality papers targeting top CS conferences.

## Features

- **Multi-Agent Code Analysis**: Dynamic team of 3-5 specialized agents (Architecture Analyst, Algorithm Analyst, Innovation Extractor, Math Modeler, Literature Comparator) analyzes your codebase in parallel
- **Structured Debate**: Multi-round debate protocol with position submission, cross-examination, and convergence checks to reach consensus on core innovations
- **Three-Powers Separation**: Executor-Reviewer-Arbiter mechanism governs all collaboration steps — no agent can self-review, and disputes are resolved by binding arbitration
- **Six-Phase Pipeline**: Initialization, Code Analysis, Analysis Debate, Writing Plan Debate, Paper Writing, Assembly & Output
- **Multi-Format Output**: Markdown (default), LaTeX with venue-specific templates, or Word (.docx)
- **Venue-Aware Writing**: Targets NeurIPS, ICML, ICLR, CVPR, ACL, AAAI, and other top CS venues with venue-specific formatting
- **Anti-AI Writing Rules**: Enforced style constraints that eliminate common AI writing traces (forbidden phrases, active voice preference, thesis-first paragraphs)
- **Figure Integration**: Optional AI-assisted figure generation via nano-banana-draw skill
- **Citation Verification**: All references verified via WebSearch to prevent fabricated citations
- **Dependency-Ordered Writing**: Chapters written in dependency order (Related Work/Methodology first, then Introduction/Experiments, then Abstract/Conclusion) with auto-triggered review after each

## Quick Start

In Claude Code, invoke the skill:

```
/academic-paper-forge
```

Or use natural language:

```
"write a paper based on this code"
"write paper"
"论文写作"
"学术论文"
"paper forge"
"generate paper from code"
```

The skill will guide you through configuration (language, format, venue, mode, references, figures) before beginning analysis.

## Phase Overview

| Phase | Name | Description |
|-------|------|-------------|
| 0 | Initialization | Configure language, output format, target venue, writing mode, references, and figure generation |
| 1 | Code Analysis | 3-5 agents analyze architecture, algorithms, innovations, math, and literature in parallel |
| 2 | Analysis Debate | Multi-round structured debate (max 3 rounds) to reach consensus on core innovations and positioning |
| 3 | Writing Plan Debate | New team debates narrative strategy, section structure, and reviewer defense strategy |
| 4 | Paper Writing | 5-7 person writing team executes in dependency order with auto-triggered three-powers review |
| 5 | Assembly & Output | Chief Editor assembles full paper, final independent review, format conversion |

## Output Structure

All outputs are written to `{project_root}/paper-output/`:

```
paper-output/
├── analysis/
│   ├── core-insights.md          # Ranked innovation points with code locations
│   ├── literature-review.md      # Related work and SOTA comparison
│   ├── math-formulation.md       # Formal problem definition and equations
│   ├── code-index.md             # Method-to-code mapping table
│   └── debate-summary.md         # Debate rounds, disagreements, resolutions
├── writing-plan/
│   ├── narrative-strategy.md     # Consensus narrative arc and paper title
│   ├── section-outline.md        # Detailed outline with word counts
│   ├── reviewer-strategy.md      # Anticipated objections and defenses
│   └── task-dependency.md        # Writing task dependency graph
├── paper/
│   ├── 00-abstract.md
│   ├── 01-introduction.md
│   ├── 02-related-work.md
│   ├── 03-methodology.md
│   ├── 04-experiments.md
│   ├── 05-conclusion.md
│   ├── full-paper.md             # Assembled complete paper
│   ├── references.md             # Complete bibliography
│   └── figures/                  # Generated figures (if enabled)
├── review-logs/                  # All review reports and arbitration rulings
├── latex/                        # (Optional) LaTeX output
│   ├── main.tex
│   ├── sections/
│   ├── references.bib
│   └── Makefile
└── word/                         # (Optional) Word output
    └── paper.docx
```

## Configuration Options

| Setting | Options |
|---------|---------|
| Interaction Language | Chinese, English, Mixed, Japanese |
| Paper Language | English, Chinese, Bilingual, Same as interaction |
| Output Format | Markdown, LaTeX, Markdown + LaTeX, Word |
| Target Venue | NeurIPS/ICML/ICLR, CVPR/ECCV/ICCV, ACL/EMNLP/NAACL, AAAI/IJCAI, Other |
| Writing Mode | Full paper, Single chapter, Revision mode, Analysis only |
| References | Web search only, User-provided directory, Core refs + web search, Manual input |
| Figure Generation | nano-banana-draw enabled, Manual figures, Architecture only, Decide later |

## Requirements

- Claude Code with **Agent** tool support (required for multi-agent phases)
- WebSearch tool (for literature retrieval and citation verification)
- Optionally: nano-banana-draw skill (for AI-assisted figure generation)

## Trigger Phrases

```
"write a paper"
"write paper"
"paper forge"
"generate paper from code"
"论文写作"
"学术论文"
"写论文"
/academic-paper-forge
```

---

# Academic Paper Forge (中文)

多 Agent 学术论文写作系统，可分析代码仓库、通过结构化辩论提取创新点，并协作撰写面向顶级 CS 会议的高质量论文。

## 功能特性

- **多 Agent 代码分析**：3-5 名专业 Agent（架构分析师、算法分析师、创新提取器、数学建模师、文献比较器）并行分析代码库
- **结构化辩论**：多轮辩论协议，包含立场提交、交叉质询和收敛检查，就核心创新点达成共识
- **三权分立机制**：执行者-审查者-仲裁者机制贯穿所有协作步骤——任何 Agent 不得自审，争议由仲裁者做出终局裁决
- **六阶段流水线**：初始化、代码分析、分析辩论、写作计划辩论、论文写作、组装与输出
- **多格式输出**：Markdown（默认）、LaTeX（含会议专属模板）、Word (.docx)
- **会议感知写作**：适配 NeurIPS、ICML、ICLR、CVPR、ACL、AAAI 等顶级 CS 会议的格式要求
- **反 AI 写作规则**：强制执行消除常见 AI 写作痕迹的风格约束（禁用短语、主动语态偏好、论点先行段落）
- **图表集成**：可选通过 nano-banana-draw 技能生成 AI 辅助图表
- **引用验证**：通过 WebSearch 验证所有参考文献，防止捏造引用
- **依赖顺序写作**：按依赖顺序撰写章节（先 Related Work/Methodology，再 Introduction/Experiments，最后 Abstract/Conclusion），每章完成后自动触发审查

## 快速开始

在 Claude Code 中调用技能：

```
/academic-paper-forge
```

或使用自然语言：

```
"写论文"
"论文写作"
"学术论文"
"基于代码写论文"
"paper forge"
"write a paper"
```

技能将引导您完成配置（语言、格式、目标会议、写作模式、参考文献、图表）后开始分析。

## 阶段概览

| 阶段 | 名称 | 描述 |
|------|------|------|
| 0 | 初始化 | 配置语言、输出格式、目标会议、写作模式、参考文献和图表生成 |
| 1 | 代码分析 | 3-5 名 Agent 并行分析架构、算法、创新点、数学公式和文献 |
| 2 | 分析辩论 | 多轮结构化辩论（最多 3 轮）就核心创新点和定位达成共识 |
| 3 | 写作计划辩论 | 新团队辩论叙事策略、章节结构和审稿人应对策略 |
| 4 | 论文写作 | 5-7 人写作团队按依赖顺序执行，自动触发三权分立审查 |
| 5 | 组装与输出 | 主编组装完整论文、独立终审、格式转换 |

## 输出结构

所有输出写入 `{project_root}/paper-output/`：

```
paper-output/
├── analysis/                     # 分析产物
│   ├── core-insights.md          # 排序后的创新点及代码定位
│   ├── literature-review.md      # 相关工作与 SOTA 比较
│   ├── math-formulation.md       # 形式化问题定义与公式
│   ├── code-index.md             # 方法到代码的映射表
│   └── debate-summary.md         # 辩论轮次、分歧和决议
├── writing-plan/                 # 写作计划
│   ├── narrative-strategy.md     # 共识叙事弧线和论文标题
│   ├── section-outline.md        # 详细大纲含字数目标
│   ├── reviewer-strategy.md      # 预期审稿意见及应对策略
│   └── task-dependency.md        # 写作任务依赖图
├── paper/                        # 论文章节
│   ├── full-paper.md             # 组装后的完整论文
│   ├── references.md             # 完整参考文献
│   └── figures/                  # 生成的图表（如启用）
├── review-logs/                  # 所有审查报告和仲裁裁决
├── latex/                        # （可选）LaTeX 输出
└── word/                         # （可选）Word 输出
```

## 系统要求

- 支持 **Agent** 工具的 Claude Code（多 Agent 阶段必需）
- WebSearch 工具（用于文献检索和引用验证）
- 可选：nano-banana-draw 技能（用于 AI 辅助图表生成）

## 触发短语

```
"write a paper"
"论文写作"
"学术论文"
"写论文"
"基于代码写论文"
"paper forge"
/academic-paper-forge
```
