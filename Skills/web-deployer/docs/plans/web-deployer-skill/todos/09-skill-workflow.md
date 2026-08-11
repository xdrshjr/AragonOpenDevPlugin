# TODO 09: SKILL Workflow & User Interaction

**Spec Reference:** [specs/09-skill-workflow.md](../specs/09-skill-workflow.md)

## Dependencies

- `depends_on: [01, 02, 03, 04, 05, 06, 07, 08]` — integrates all other modules
- `blocks: []` — final integration, blocks nothing
- `parallel_group: E`

## Tasks

- [x] Write SKILL.md frontmatter: name, description, activation triggers
- [x] Write Phase 1: Language selection + deployment mode prompt
- [x] Write Phase 2: Project analysis integration (invoke Spec 01 logic)
- [x] Write Phase 3: Server info collection integration (invoke Spec 03 logic)
- [x] Write Phase 4: Deployment configuration (variable resolution, Nginx/SSL decisions)
- [x] Write Phase 5: Template rendering + ops generation integration (invoke Spec 02 + 08)
- [x] Write Phase 6: Remote deployment execution (invoke Spec 04 or 05 + 06)
- [x] Write Phase 7: Post-deploy verification integration (invoke Spec 07)
- [x] Write Phase 8: Summary & handoff (deployment report, next steps, memory save)
- [x] Write guided mode flow: per-step AskUserQuestion confirmations
- [x] Write auto mode flow: env var detection, minimal prompts, auto-proceed
- [x] Write error recovery: per-phase error handling, retry, go-back options
- [x] Write multi-server orchestration flow: loop through servers, aggregate reports
- [x] Write _meta.json: version, tags, publication metadata
- [x] Write user-facing README.md for the skill
