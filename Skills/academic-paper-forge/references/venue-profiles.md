# 目标会议/期刊档案

academic-paper-forge 支持的目标会议和期刊的详细信息。用于 Phase 0 目标选择和 Phase 4 写作风格适配。

---

## 机器学习顶会（ML Top-3）

### NeurIPS (Conference on Neural Information Processing Systems)

| 字段 | 内容 |
|------|------|
| **全称** | Conference on Neural Information Processing Systems |
| **级别** | CCF-A / CS Ranking Top |
| **频率** | 每年 12 月 |
| **论文类型** | 长文 (9 页正文 + 不限附录) |
| **审稿制度** | 双盲，3-4 位审稿人 + Area Chair |
| **录取率** | 约 25-26% |

**典型论文结构:**
1. Abstract (150-200 词)
2. Introduction (1-1.5 页)
3. Related Work (1 页，可放附录)
4. Method / Approach (2-3 页)
5. Experiments (2-3 页)
6. Conclusion / Discussion (0.5 页)
7. References (不计入页数)
8. Appendix (不限)

**页数限制:** 正文 9 页（不含参考文献），附录不限。首次提交时审稿人不一定看附录。

**风格偏好:**
- 重视理论贡献和新颖性
- 鼓励 Broader Impact 讨论
- 实验需包含消融实验
- 数学推导可放附录，正文给直觉和关键结果
- 接受纯理论论文

**审稿人常见期望:**
- 清晰的问题动机和贡献声明
- 与最新 SOTA 的充分对比
- 消融实验验证各组件贡献
- 计算效率/可扩展性分析
- 代码可复现性（鼓励提交代码）

**LaTeX 模板:** `neurips_2024.sty` — [NeurIPS Style Files](https://neurips.cc/Conferences/2024/PaperInformation/StyleFiles)

---

### ICML (International Conference on Machine Learning)

| 字段 | 内容 |
|------|------|
| **全称** | International Conference on Machine Learning |
| **级别** | CCF-A / CS Ranking Top |
| **频率** | 每年 7 月 |
| **论文类型** | 长文 (8 页正文 + 不限附录) |
| **审稿制度** | 双盲，3 位审稿人 + Area Chair |
| **录取率** | 约 25-28% |

**典型论文结构:**
1. Abstract (150-200 词)
2. Introduction (1-1.5 页)
3. Preliminaries / Background (0.5-1 页)
4. Method (2-3 页)
5. Experiments (2-3 页)
6. Related Work (0.5-1 页，常放在 Experiments 之后)
7. Conclusion (0.5 页)

**页数限制:** 正文 8 页（不含参考文献和附录）。

**风格偏好:**
- 偏好有理论支撑的方法论文
- Related Work 常放在正文后部（与 NeurIPS 不同）
- 重视方法的通用性和理论优雅性
- Preliminaries 小节用于定义符号和背景知识
- 实验部分需要严谨的统计分析

**审稿人常见期望:**
- 理论分析或充分的实证证据
- 清晰的数学符号和公式推导
- 多数据集、多指标的实验对比
- 与近2年最新工作的对比
- 对方法局限性的诚实讨论

**LaTeX 模板:** `icml2024.sty` — [ICML Style Files](https://icml.cc/Conferences/2024/StyleAuthorInstructions)

---

### ICLR (International Conference on Learning Representations)

| 字段 | 内容 |
|------|------|
| **全称** | International Conference on Learning Representations |
| **级别** | CCF-A (非正式) / CS Ranking Top |
| **频率** | 每年 5 月 |
| **论文类型** | 长文 (不限页数，通常 8-10 页正文) |
| **审稿制度** | 开放评审（OpenReview），3-4 位审稿人 + Area Chair |
| **录取率** | 约 30-32% |

**典型论文结构:**
1. Abstract
2. Introduction (1-1.5 页)
3. Related Work (1 页)
4. Method (2-3 页)
5. Experiments (2-4 页)
6. Conclusion (0.5 页)
7. References
8. Appendix

**页数限制:** 无硬性限制，但通常 8-10 页正文。过长会影响审稿体验。

**风格偏好:**
- 开放评审制度，审稿过程公开可见
- 重视表征学习（representation learning）方向
- 偏好 clean、elegant 的方法
- 强调可复现性（OpenReview 讨论会追问实现细节）
- 接受大规模实验论文

**审稿人常见期望:**
- 方法简洁优雅，避免过度工程化
- 开放讨论中能回应所有质疑
- 与同期 arXiv 论文的对比
- 代码开源（强烈推荐）
- 对 hyperparameter sensitivity 的分析

**LaTeX 模板:** `iclr2024_conference.sty` — [ICLR Style Files](https://iclr.cc/Conferences/2024/AuthorGuide)

---

## 计算机视觉顶会（CV）

### CVPR (IEEE/CVF Conference on Computer Vision and Pattern Recognition)

| 字段 | 内容 |
|------|------|
| **全称** | IEEE/CVF Conference on Computer Vision and Pattern Recognition |
| **级别** | CCF-A / CS Ranking Top |
| **频率** | 每年 6 月 |
| **论文类型** | 长文 (8 页正文 + 不限参考文献和附录) |
| **审稿制度** | 双盲，3 位审稿人 + Area Chair |
| **录取率** | 约 25-26% |

**典型论文结构:**
1. Abstract
2. Introduction (1 页，含贡献列表)
3. Related Work (0.5-1 页)
4. Method (2-3 页，重视可视化)
5. Experiments (2-3 页，大量表格和图)
6. Conclusion (0.3-0.5 页)

**页数限制:** 正文 8 页（不含参考文献）。

**风格偏好:**
- 高度重视可视化结果（定性对比图）
- Figure 1 通常是方法概览 + teaser result
- 实验部分表格和图很多
- 偏好有实际应用价值的工作
- 写作清晰简洁，避免过度理论化

**审稿人常见期望:**
- 在主流 benchmark（ImageNet, COCO 等）上的对比
- 充分的定性可视化结果
- 效率分析（FLOPs, 参数量, 推理速度）
- 消融实验
- 与最新 arXiv 论文的对比

**LaTeX 模板:** `cvpr.sty` — [CVPR Author Kit](https://cvpr.thecvf.com/Conferences/2024/AuthorGuidelines)

---

### ECCV (European Conference on Computer Vision)

| 字段 | 内容 |
|------|------|
| **全称** | European Conference on Computer Vision |
| **级别** | CCF-B (但影响力接近 A) |
| **频率** | 每两年一次（偶数年 10 月） |
| **论文类型** | 长文 (14 页正文 LNCS 格式) |
| **审稿制度** | 双盲，3 位审稿人 + Area Chair |
| **录取率** | 约 28-30% |

**典型论文结构:** 与 CVPR 类似，但使用 Springer LNCS 格式（双栏变单栏、字体更大，实际内容量与 CVPR 8 页相当）。

**页数限制:** 正文 14 页（LNCS 格式），附录不限。

**风格偏好:**
- 与 CVPR 类似，重视视觉结果
- LNCS 格式，单栏排版
- 偏好方法创新性和实用性的平衡
- 鼓励视频结果提交（supplementary）

**LaTeX 模板:** Springer LNCS — `llncs.cls`

---

### ICCV (IEEE/CVF International Conference on Computer Vision)

| 字段 | 内容 |
|------|------|
| **全称** | IEEE/CVF International Conference on Computer Vision |
| **级别** | CCF-A |
| **频率** | 每两年一次（奇数年 10 月） |
| **论文类型** | 长文 (8 页正文 + 不限参考文献和附录) |
| **审稿制度** | 双盲，3 位审稿人 + Area Chair |
| **录取率** | 约 25-27% |

**典型论文结构:** 与 CVPR 基本一致。

**页数限制:** 正文 8 页（不含参考文献）。

**风格偏好:**
- 与 CVPR 非常接近
- 偏好有深度的技术贡献
- 理论和实验并重
- 重视跨领域影响力

**LaTeX 模板:** 与 CVPR 共用 IEEE 格式

---

## 自然语言处理顶会（NLP）

### ACL (Annual Meeting of the Association for Computational Linguistics)

| 字段 | 内容 |
|------|------|
| **全称** | Annual Meeting of the Association for Computational Linguistics |
| **级别** | CCF-A |
| **频率** | 每年 7-8 月 |
| **论文类型** | 长文 (8 页正文) / 短文 (4 页正文) |
| **审稿制度** | 双盲（通过 ARR），3 位审稿人 + Area Chair |
| **录取率** | 约 20-25% |

**典型论文结构:**
1. Abstract
2. Introduction (1 页)
3. Related Work (0.5-1 页)
4. Method / Approach (2-3 页)
5. Experimental Setup (0.5-1 页)
6. Results and Analysis (1-2 页)
7. Conclusion (0.3-0.5 页)
8. Limitations (必须，不计入页数)
9. Ethics Statement (必须，不计入页数)

**页数限制:** 长文 8 页，短文 4 页（不含参考文献、Limitations 和 Ethics Statement）。

**风格偏好:**
- 必须包含 Limitations 小节（2023 年起强制）
- 必须包含 Ethics Statement
- 重视语言学动机和分析
- 偏好在多语言/多任务上的评估
- 注重 human evaluation（如适用）
- 使用 ARR (ACL Rolling Review) 提交系统

**审稿人常见期望:**
- 清晰的语言学或任务动机
- 在标准 NLP benchmark 上的对比
- Error analysis（错误分析）
- Human evaluation（如涉及生成任务）
- 对模型 bias 和 fairness 的讨论
- Limitations 小节内容充实

**LaTeX 模板:** `acl.sty` — [ACL Style Files](https://github.com/acl-org/acl-style-files)

---

### EMNLP (Conference on Empirical Methods in Natural Language Processing)

| 字段 | 内容 |
|------|------|
| **全称** | Conference on Empirical Methods in Natural Language Processing |
| **级别** | CCF-B (但影响力接近 A) |
| **频率** | 每年 12 月 |
| **论文类型** | 长文 (8 页) / 短文 (4 页) |
| **审稿制度** | 双盲（通过 ARR），3 位审稿人 |
| **录取率** | 约 22-25% |

**典型论文结构:** 与 ACL 基本一致，同样要求 Limitations 和 Ethics Statement。

**风格偏好:**
- 偏好 empirical 方法（实验驱动）
- 对实验的严谨性要求极高
- 统计显著性测试（推荐）
- 重视 error analysis 和 qualitative analysis

**LaTeX 模板:** 与 ACL 共用 `acl.sty`

---

### NAACL (North American Chapter of the ACL)

| 字段 | 内容 |
|------|------|
| **全称** | Annual Conference of the North American Chapter of the ACL |
| **级别** | CCF-B |
| **频率** | 每年 6 月 |
| **论文类型** | 长文 (8 页) / 短文 (4 页) |
| **审稿制度** | 双盲（通过 ARR） |
| **录取率** | 约 22-25% |

**典型论文结构:** 与 ACL/EMNLP 一致。

**风格偏好:**
- 与 ACL/EMNLP 类似
- 稍偏好应用导向的工作
- 对 industry track 的论文更友好

**LaTeX 模板:** 与 ACL 共用 `acl.sty`

---

## 综合人工智能顶会（General AI）

### AAAI (AAAI Conference on Artificial Intelligence)

| 字段 | 内容 |
|------|------|
| **全称** | AAAI Conference on Artificial Intelligence |
| **级别** | CCF-A |
| **频率** | 每年 2 月 |
| **论文类型** | 长文 (7 页正文 + 1 页参考文献 + 2 页附录) |
| **审稿制度** | 双盲，3 位审稿人 + Meta-Reviewer |
| **录取率** | 约 20-23% |

**典型论文结构:**
1. Abstract
2. Introduction
3. Related Work
4. Method / Approach
5. Experiments
6. Conclusion

**页数限制:** 正文 7 页 + 参考文献最多 1 页 + 附录最多 2 页（共 10 页上限）。

**风格偏好:**
- 覆盖 AI 所有子领域（不局限于 ML）
- 偏好有清晰问题定义的工作
- 重视方法的通用性
- 接受 AI 应用论文（education, healthcare 等）
- 格式要求严格（AAAI 自有格式）

**审稿人常见期望:**
- 清晰的问题定义和动机
- 方法描述自包含（审稿人可能非专业领域）
- 充分的实验对比
- 合理的页面分配（不要实验占 4 页而方法只有 1 页）

**LaTeX 模板:** `aaai24.sty` — [AAAI Author Kit](https://aaai.org/authorkit24/)

---

### IJCAI (International Joint Conference on Artificial Intelligence)

| 字段 | 内容 |
|------|------|
| **全称** | International Joint Conference on Artificial Intelligence |
| **级别** | CCF-A |
| **频率** | 每年 8 月 |
| **论文类型** | 长文 (7 页正文 + 2 页参考文献/附录) |
| **审稿制度** | 双盲，3 位审稿人 + Meta-Reviewer |
| **录取率** | 约 15-20% |

**典型论文结构:** 与 AAAI 类似。

**页数限制:** 正文 7 页 + 参考文献/附录最多 2 页。

**风格偏好:**
- 最广泛的 AI 会议，覆盖 ML、NLP、CV、知识表示、规划等
- 偏好跨领域/跨方向的工作
- 重视论文的自包含性（不同领域的审稿人需要能理解）
- 比 AAAI 更强调国际化视角

**审稿人常见期望:**
- 方法描述对非专业读者友好
- 清晰的假设条件和适用范围
- 与多个相关方向的工作对比
- 理论贡献或显著的实证贡献

**LaTeX 模板:** `ijcai24.sty` — [IJCAI Author Kit](https://www.ijcai.org/authors_kit)

---

## 会议速查对比表

| 会议 | 领域 | 正文页数 | 录取率 | 审稿制度 | Related Work 位置 | 特殊要求 |
|------|------|---------|--------|---------|-----------------|---------|
| NeurIPS | ML | 9 页 | ~25% | 双盲 | 靠前 | Broader Impact |
| ICML | ML | 8 页 | ~26% | 双盲 | 靠后 | Preliminaries |
| ICLR | ML | ~8-10 页 | ~31% | 开放 | 灵活 | OpenReview 讨论 |
| CVPR | CV | 8 页 | ~25% | 双盲 | 靠前 | 视觉结果 |
| ECCV | CV | 14 页(LNCS) | ~29% | 双盲 | 靠前 | LNCS 格式 |
| ICCV | CV | 8 页 | ~26% | 双盲 | 靠前 | 视觉结果 |
| ACL | NLP | 8/4 页 | ~22% | 双盲(ARR) | 靠前 | Limitations + Ethics |
| EMNLP | NLP | 8/4 页 | ~23% | 双盲(ARR) | 靠前 | Limitations + Ethics |
| NAACL | NLP | 8/4 页 | ~23% | 双盲(ARR) | 靠前 | Limitations + Ethics |
| AAAI | General | 7+1+2 页 | ~21% | 双盲 | 靠前 | 严格格式 |
| IJCAI | General | 7+2 页 | ~17% | 双盲 | 靠前 | 自包含性 |

---

## 使用说明

1. **Phase 0** 中，用户选择目标会议后，将对应档案加载到所有智能体的上下文中
2. **Phase 4** 写作时，根据目标会议的页数限制和结构偏好调整写作计划
3. **Phase 5** 输出时，如用户选择 LaTeX 格式，使用对应会议的模板
4. 如用户选择"自定义"会议，要求用户提供页数限制、格式要求和参考论文
