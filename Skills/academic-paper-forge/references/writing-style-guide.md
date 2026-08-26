# 反 AI 写作风格指南

academic-paper-forge 中所有写作智能体必须遵守的写作风格规范。目标是确保产出的论文读起来像资深研究者手写，不带任何 AI 生成痕迹。

---

## 禁止模式（Forbidden Patterns）

以下模式在论文写作中严格禁止。每违反一条扣除 $1000。

### 禁止的开篇句式

| 禁止表达 | 问题 | 替代方式 |
|---------|------|---------|
| "In recent years, X has gained significant attention..." | AI 模板化开头，几乎每篇 AI 论文都这样开 | 直接陈述具体问题或挑战，例如 "Training large-scale transformers demands quadratic memory..." |
| "With the rapid development of..." | 空洞、无信息量 | 给出具体的技术挑战或数据，例如 "Modern language models now exceed 100B parameters, yet inference latency remains..." |
| "X plays a crucial/important/vital role in Y" | 过于笼统的重要性声明 | 用具体数据或事实说明重要性，例如 "X reduces inference cost by 40% on standard benchmarks" |
| "It is worth noting/mentioning that..." | 冗余的元叙述 | 直接陈述事实，删除引导语 |
| "To the best of our knowledge, this is the first work..." | 审稿人反感，且难以验证 | 如确实首创，用更谦逊的方式："We are not aware of prior work that..." |
| "The rest of the paper is organized as follows: Section 2..." | 机械的结构说明 | 如需结构说明，用自然过渡："We begin by formalizing the problem (Sec. 2), then present..." |

### 禁止的连接词堆叠

| 禁止模式 | 替代方式 |
|---------|---------|
| "Firstly, ... Secondly, ... Thirdly, ... Finally, ..." | 使用多样的过渡方式，或直接用段落结构组织 |
| 连续使用 "Moreover, ... Furthermore, ... Additionally, ..." | 每段用一个不同的连接方式，或用段落首句直接承接上文逻辑 |
| 过度使用 "However, ... Nevertheless, ... Nonetheless, ..." | 每页最多 2 个 "however"，优先用 "but"、"yet" 或句意自然转折 |

### 禁止的词汇

| 禁止词 | 替代词 |
|--------|--------|
| leverage | use |
| utilize | use |
| facilitate | enable, allow, help |
| delve into | examine, study, analyze |
| landscape (非地理含义) | field, area, domain |
| holistic | comprehensive, complete |
| paradigm shift | 具体描述变化内容 |
| cutting-edge | state-of-the-art (仅在适当时), recent, advanced |
| novel (过度使用时) | 仅在真正首创时使用一次，其他用 new, different, alternative |

---

## 硬性规则（Hard Rules）

以下规则在自审和审核时逐条检查。

### 规则列表

| # | 规则 | 阈值 | 检查方法 |
|---|------|------|---------|
| 1 | 每段不超过 1 个破折号（em dash "---"） | 最多 1 个/段 | 逐段计数 |
| 2 | 每页不超过 2 个 "however" | 最多 2 个/页（约 300 词） | 全文搜索 |
| 3 | 禁止上方列出的所有禁止表达 | 0 个 | 全文搜索 |
| 4 | 禁止连续使用 Firstly/Secondly/Thirdly/Finally | 0 次出现该模式 | 全文搜索 |
| 5 | 主动语态优先 | 被动语态不超过总句数的 30% | 抽样检查 |
| 6 | 每个段落的第一句话必须是该段的核心论点 | 100% | 逐段检查 |
| 7 | 技术术语首次出现时给出完整定义 | 100% | 逐术语检查 |
| 8 | 避免连续 2 个以上形容词修饰同一名词 | 最多 2 个 | 逐句检查 |
| 9 | 不使用感叹号 | 0 个 | 全文搜索 |
| 10 | 不使用 "leverage"、"utilize" | 0 个 | 全文搜索 |

---

## 正面写作指南（Positive Guidelines）

### 句子层面

- **主动语态优先**: "We propose X" 而非 "X is proposed"。被动语态仅在强调对象而非主体时使用（如 "The loss function is defined as..."）
- **简洁直接**: 一句话只说一件事。如果句子超过 30 词，考虑拆分
- **具体胜于抽象**: 用数据、指标、具体例子代替泛泛的形容词
- **精确用词**: 区分 "show"（展示数据）、"demonstrate"（证明）、"indicate"（暗示）、"suggest"（推测）的语义差异

### 段落层面

- **论点在首句**: 每段第一句话是该段的核心论点（topic sentence），后续句子提供证据和解释
- **段落长度适中**: 3-7 句话。单句段落仅在特殊强调时使用
- **段落间自然过渡**: 上一段末尾或下一段开头自然衔接，不依赖机械的连接词
- **一个段落一个论点**: 不在同一段落中讨论两个独立的论点

### 章节层面

- **清晰的层级结构**: 每个 section 有明确的小节划分，读者可以快速定位
- **前后呼应**: Introduction 中承诺的贡献必须在后续章节逐一兑现
- **渐进深入**: 从直觉到形式化，从概述到细节

### 数学写作

- **符号首次使用时定义**: 例如 "Let $\mathcal{D} = \{(x_i, y_i)\}_{i=1}^N$ denote the training set"
- **公式有文字说明**: 不出现"孤岛公式"（公式前后无文字解释）
- **符号全文一致**: 同一概念在全文中使用同一符号
- **编号一致**: 所有被引用的公式编号，未引用的可不编号

---

## 各章节风格要点

### Introduction

- **开篇**: 用具体问题或场景引入，避免宏大叙事
- **痛点**: 现有方法的不足要具体（什么方法、什么问题、量化影响）
- **我们的方法**: 高层概述，一段话讲清核心思路，不展开细节
- **贡献列表**: 3-4 个 bullet points，每个必须具体且可验证。使用 "We" 开头
- **长度**: 1-1.5 页

**示例贡献列表写法:**
```
- We propose {Method Name}, a {one-line description} that achieves {specific improvement}.
- We introduce a {component name} that addresses {specific problem} by {key mechanism}.
- We conduct extensive experiments on {N} benchmarks, showing {X}% improvement over {baseline}.
```

### Related Work

- **分组而非时间线**: 按技术路线或方法类别分组，每组 1-2 段
- **公正比较**: 承认已有方法的优点，然后指出其局限
- **连接本文**: 每组末尾自然引出本文方法的对应优势
- **最后一段**: 总结性地说明本文方法与所有已有工作的关键区别
- **长度**: 1-1.5 页

### Methodology

- **Overview 小节**: 先给高层概述 + 方法概览图（Figure），让读者建立整体印象
- **逐模块描述**: 每个模块：直觉解释 → 数学形式化 → 设计选择的 justification
- **Why, not just What**: 不仅描述"做了什么"，还要解释"为什么这样做"
- **可复现性**: 读者仅凭此章节应能复现方法
- **伪代码**: 完整算法的伪代码放在方法末尾
- **长度**: 2-4 页

### Experiments

- **实验设置**: 数据集、评价指标、基线、实现细节，段落紧凑但信息完整
- **主实验**: 与 SOTA 全面对比，表格 + 深入分析（不只报数字）
- **消融实验**: 验证每个组件的贡献，表格 + 分析
- **分析实验**: 可视化、case study、效率分析、参数敏感性
- **每张表/图都需要讨论**: 至少 2-3 句话分析关键观察
- **长度**: 2-4 页

### Conclusion

- **不重复 Introduction**: 从更高的角度总结，强调方法的意义和影响
- **诚实的 Limitations**: 承认方法的局限性（审稿人看重这一点）
- **Future Work**: 2-3 个具体方向，不是空话
- **结尾有力**: 最后一句话有总结性和前瞻性
- **长度**: 0.5 页

### Abstract

- **结构**: 问题 → 现有方法不足（1句） → 我们的方法（1-2句） → 关键结果（1-2句） → 意义（1句）
- **具体数据**: 必须包含关键的量化结果
- **独立可读**: 不引用图表编号、不使用缩写（除非极常见如 NLP、CNN）
- **长度**: 150-250 词

---

## 自审检查清单

每个写作智能体在提交前必须逐项自查。

```markdown
## 写作自审检查清单

### 禁止模式检查
- [ ] 全文无 "In recent years" 等禁止开篇句式
- [ ] 全文无 "leverage"、"utilize" 等禁止词汇
- [ ] 无 Firstly/Secondly/Thirdly/Finally 连续使用
- [ ] 全文无感叹号

### 硬性规则检查
- [ ] 每段破折号不超过 1 个
- [ ] 每 300 词 "however" 不超过 2 个
- [ ] 被动语态比例不超过 30%
- [ ] 每段首句是核心论点
- [ ] 所有技术术语首次出现时有定义
- [ ] 无 2 个以上形容词连续修饰同一名词

### 内容质量检查
- [ ] 所有事实声明有证据支撑
- [ ] 所有数学公式格式正确、符号有定义
- [ ] 所有引用的文献真实存在
- [ ] 与其他章节无矛盾（术语、符号、事实）
- [ ] 字数在预期范围内

### 可读性检查
- [ ] 段落长度适中（3-7 句）
- [ ] 句子长度适中（大部分不超过 30 词）
- [ ] 段落间过渡自然
- [ ] 章节结构清晰，小节划分合理
```

---

## 常见 AI 写作痕迹及修正

| AI 痕迹 | 出现频率 | 修正方法 |
|---------|---------|---------|
| 过度使用 "Furthermore" 等连接词 | 极高 | 删除或用自然过渡替代 |
| 每段都以 "This/These" 开头 | 高 | 变换段落开头方式 |
| 过度使用被动语态 | 高 | 改为主动语态 |
| 列举时用 "various"、"numerous" | 高 | 给出具体数量或具体例子 |
| 结论中重复 Introduction 的表述 | 高 | 从更高视角重新总结 |
| 过度修饰（"significantly"、"dramatically"） | 极高 | 用具体数据替代形容词 |
| 所有段落长度接近 | 中 | 根据内容自然变化段落长度 |
| 缺乏具体例子和数据 | 中 | 补充具体的数字、案例 |
