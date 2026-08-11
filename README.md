# Aragon OpenDev

> 面向 AI Agent 的开源 Skill 与 Plugin 集合。
>
> An open-source collection of reusable skills and plugins for AI agents.

[中文](#中文) · [English](#english)

---

## 中文

### 项目简介

Aragon OpenDev 用于沉淀和共享可复用的 AI Agent 工作流，覆盖安全审计、远程运维、Web 部署及后续更多开发场景。

仓库中的 Skill 采用以 `SKILL.md` 为入口的开放目录结构，可包含说明文档、参考资料、模板和脚本。目前已提供独立 Skill；可安装 Plugin 和统一安装方式正在规划中。

### 可用 Skills

| Skill | 能力 | 典型场景 | 文档 |
| --- | --- | --- | --- |
| `security-scan` | 多智能体漏洞发现、交叉验证和 PoC 验证 | 代码库安全扫描、安全审计、漏洞研究 | [查看 SKILL](Skills/security-scan/SKILL.md) |
| `ssh-remote` | 基于 Python Paramiko 的 SSH/SFTP 操作 | 执行远程命令、上传下载文件、检查服务器状态 | [查看说明](Skills/ssh-remote/README.md) |
| `web-deployer` | 自动识别并部署 Web 项目到 Linux 服务器 | systemd/Docker 部署、Nginx 反向代理、多服务器发布、运维脚本生成 | [查看说明](Skills/web-deployer/README.md) |

### 快速开始

1. 克隆仓库：

```bash
git clone https://github.com/xdrshjr/AragonOpenDevPlugin.git
cd AragonOpenDevPlugin
```

2. 选择需要的 Skill，并复制其**完整目录**到 Agent 的 Skill 搜索路径。不要只复制 `SKILL.md`，部分 Skill 依赖同目录下的 references、templates、sections 或脚本。

| 平台 | 用户级安装目录 | 项目级安装目录 |
| --- | --- | --- |
| [Codex](https://learn.chatgpt.com/docs/build-skills) | `$HOME/.agents/skills/<skill-name>` | `<repo>/.agents/skills/<skill-name>` |
| [Claude Code](https://code.claude.com/docs/en/skills) | `~/.claude/skills/<skill-name>` | `<repo>/.claude/skills/<skill-name>` |
| 其他 Agent | 参照对应平台的 Agent Skills 文档 | 参照对应平台的 Agent Skills 文档 |

例如，将 `ssh-remote` 安装到 Codex 用户级目录：

```bash
mkdir -p "$HOME/.agents/skills"
cp -R Skills/ssh-remote "$HOME/.agents/skills/"
```

安装到 Claude Code 用户级目录：

```bash
mkdir -p "$HOME/.claude/skills"
cp -R Skills/ssh-remote "$HOME/.claude/skills/"
```

Windows 用户可以使用资源管理器或 PowerShell 完成等效的目录复制。若 Agent 未立即发现新 Skill，请重新加载 Skill 列表或重启对应客户端。

3. 使用 Skill：

- Codex：通过 `/skills` 选择，或使用 `$skill-name` 显式调用。
- Claude Code：使用 `/skill-name` 调用，也可由 Agent 根据 `description` 自动匹配。
- 使用前请阅读对应 Skill 文档，确认依赖、目标平台、权限和安全要求。

### 项目结构

```text
AragonOpenDevPlugin/
├── README.md
└── Skills/
    ├── security-scan/
    ├── ssh-remote/
    └── web-deployer/
```

每个 Skill 至少包含一个带有 `name` 和 `description` 元数据的 `SKILL.md`。`_meta.json` 是本仓库用于维护版本、标签和发布信息的约定文件；其他资源按 Skill 的实际需要组织。

### 兼容性

本项目以开放的 [Agent Skills](https://agentskills.io) 目录结构为基础，当前重点适配 Codex 与 Claude Code。其他支持 `SKILL.md` 工作流的 Agent 通常也可以使用，但具体的自动发现、调用语法、工具权限和扩展字段可能不同，请以目标平台文档为准。

### Roadmap

- [ ] 将成熟 Skill 打包为可安装 Plugin
- [ ] 提供统一安装与更新方式
- [ ] 增加更多开发、测试、运维和研究工作流
- [ ] 统一元数据、质量检查和兼容性测试
- [ ] 补充标准 `LICENSE`、`CONTRIBUTING.md` 和发布规范

### 贡献

欢迎通过 Issue 和 Pull Request 提交新 Skill、修复问题或改进文档。新增 Skill 建议遵循以下约定：

- 放置在 `Skills/<skill-name>/`，并提供 UTF-8 编码的 `SKILL.md`。
- 在 YAML frontmatter 中提供清晰的 `name` 和 `description`。
- 按仓库约定提供 `_meta.json`，并说明依赖、适用平台和触发场景。
- 不提交密码、令牌、私钥、服务器地址等敏感信息。
- 将大型说明、模板和脚本拆分为独立文件，并从 `SKILL.md` 中明确引用。

### License

MIT。标准 `LICENSE` 文件将在开源整理阶段补充。

---

## English

### Overview

Aragon OpenDev collects and shares reusable AI-agent workflows for security auditing, remote operations, web deployment, and more developer-focused use cases to come.

Each skill uses an open directory layout with `SKILL.md` as its entry point and may include documentation, references, templates, and scripts. Standalone skills are available today; installable plugins and a unified installation flow are on the roadmap.

### Available Skills

| Skill | Capability | Typical use cases | Documentation |
| --- | --- | --- | --- |
| `security-scan` | Multi-agent vulnerability discovery, cross-checking, and PoC validation | Codebase security scans, audits, and vulnerability research | [View SKILL](Skills/security-scan/SKILL.md) |
| `ssh-remote` | SSH/SFTP operations powered by Python Paramiko | Run remote commands, transfer files, and inspect server status | [View README](Skills/ssh-remote/README.md) |
| `web-deployer` | Auto-detect and deploy web projects to Linux servers | systemd/Docker deployments, Nginx reverse proxy, multi-server releases, and ops toolkit generation | [View README](Skills/web-deployer/README.md) |

### Quick Start

1. Clone the repository:

```bash
git clone https://github.com/xdrshjr/AragonOpenDevPlugin.git
cd AragonOpenDevPlugin
```

2. Choose a skill and copy its **entire directory** into your agent's skill search path. Do not copy only `SKILL.md`; some skills rely on adjacent references, templates, sections, or scripts.

| Platform | User-level location | Repository-level location |
| --- | --- | --- |
| [Codex](https://learn.chatgpt.com/docs/build-skills) | `$HOME/.agents/skills/<skill-name>` | `<repo>/.agents/skills/<skill-name>` |
| [Claude Code](https://code.claude.com/docs/en/skills) | `~/.claude/skills/<skill-name>` | `<repo>/.claude/skills/<skill-name>` |
| Other agents | Follow the platform's Agent Skills documentation | Follow the platform's Agent Skills documentation |

For example, install `ssh-remote` for the current Codex user:

```bash
mkdir -p "$HOME/.agents/skills"
cp -R Skills/ssh-remote "$HOME/.agents/skills/"
```

Install it for the current Claude Code user:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R Skills/ssh-remote "$HOME/.claude/skills/"
```

On Windows, use File Explorer or the equivalent PowerShell directory-copy command. If the agent does not detect the skill immediately, reload its skill list or restart the client.

3. Invoke the skill:

- Codex: select it through `/skills` or invoke it explicitly with `$skill-name`.
- Claude Code: invoke it with `/skill-name`, or let the agent match it automatically from its `description`.
- Read the skill's documentation first to understand dependencies, target platforms, permissions, and safety requirements.

### Repository Structure

```text
AragonOpenDevPlugin/
├── README.md
└── Skills/
    ├── security-scan/
    ├── ssh-remote/
    └── web-deployer/
```

Every skill contains at least a `SKILL.md` with `name` and `description` metadata. `_meta.json` is this repository's convention for version, tag, and release metadata; other resources are organized according to each skill's needs.

### Compatibility

This project follows the open [Agent Skills](https://agentskills.io) directory model and currently focuses on Codex and Claude Code. Other agents that support `SKILL.md` workflows may also work, but discovery behavior, invocation syntax, tool permissions, and extension fields can vary by platform.

### Roadmap

- [ ] Package mature skills as installable plugins
- [ ] Provide a unified installation and update flow
- [ ] Add more development, testing, operations, and research workflows
- [ ] Standardize metadata, quality checks, and compatibility tests
- [ ] Add canonical `LICENSE`, `CONTRIBUTING.md`, and release guidelines

### Contributing

Issues and pull requests for new skills, fixes, and documentation improvements are welcome. New skills should follow these conventions:

- Place the skill in `Skills/<skill-name>/` with a UTF-8 encoded `SKILL.md`.
- Include clear `name` and `description` values in the YAML frontmatter.
- Add `_meta.json` following the repository convention and document dependencies, supported platforms, and trigger scenarios.
- Never commit passwords, tokens, private keys, server addresses, or other sensitive information.
- Keep large references, templates, and scripts in separate files and link to them clearly from `SKILL.md`.

### License

MIT. A canonical `LICENSE` file will be added as part of the open-source project setup.
