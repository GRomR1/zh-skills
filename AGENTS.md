# Agent Guidelines

Repository containing Agent Skills compatible with [GitHub CLI Agent Skills (`gh skill`)](https://cli.github.com/manual/gh_skill) and the [Agent Skills specification](https://agentskills.io/specification).

## Available Skills

- `skills/asllm-nerdctl`: Run and manage LLM inference servers (vLLM / SGLang) using `nerdctl` and `asllm` images on Alibaba 890P (AliXPU) hardware.
- `skills/guidellm-benchmark`: Run GuideLLM load benchmarks across all profiles in nerdctl/docker containers and generate environment reports.
- `skills/example-skill`: Template demonstrating standard skill layout and frontmatter.

## Authoring and Modifying Skills

When creating or editing skills in `skills/`:

1. **Naming**: The directory name and `name` in `SKILL.md` frontmatter must match exactly. Use lowercase alphanumeric characters and single hyphens only (`^[a-z0-9]+(-[a-z0-9]+)*$`).
2. **Frontmatter**:
   - `name`: Max 64 characters, identical to directory name.
   - `description`: 1–1024 characters, explicitly defining what the skill does and when the agent should trigger it.
   - `license`: Required or recommended license tag (e.g. `MIT`).
   - `allowed-tools`: Optional. If used, must be a space-separated string, never an array or list.
3. **Structure & Progressive Disclosure**:
   - Keep `SKILL.md` focused and under 500 lines.
   - Place long guides, tables, or API references in `references/`.
   - Place executable automation code in `scripts/` (ensure executable permissions).
   - Place templates or static data in `assets/`.
4. **Maintenance**: When adding a new skill, update `README.md` and this file.

## Essential Commands

```bash
# Validate all skills against Agent Skills specification
gh skill publish --dry-run

# Strip install-tracking metadata if accidentally committed
gh skill publish --fix

# Test local skill discovery
gh skill install . --from-local

# Test local installation into a temporary directory
gh skill install . <skill-name> --from-local --dir /tmp/test-skills
```
