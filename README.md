# zh-skills

Agent skills repository compatible with [GitHub CLI Agent Skills (`gh skill`)](https://cli.github.com/manual/gh_skill) and the [Agent Skills specification](https://agentskills.io/specification).

## Repository Structure

Skills are organized according to standard Agent Skills conventions under the `skills/` directory:

```
zh-skills/
├── .github/
│   └── workflows/
│       └── validate.yml      # CI workflow validating skills with `gh skill publish --dry-run`
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md          # Required: skill metadata (frontmatter) and instructions
│       ├── scripts/          # Optional: executable scripts used by agents
│       ├── references/       # Optional: deep-dive references and documentation
│       └── assets/           # Optional: templates and static assets
├── .gitignore
├── LICENSE
└── README.md
```

## Available Skills

| Skill | Description |
|---|---|
| [`example-skill`](skills/example-skill/SKILL.md) | A template skill demonstrating the Agent Skills directory structure and conventions. |

---

## Usage with `gh skill`

Ensure you have GitHub CLI installed (version `v2.90.0+` with the `gh skill` extension):

```bash
gh --version
```

### 1. Install Skills

#### From a remote GitHub repository

```bash
# Install a specific skill for GitHub Copilot (default)
gh skill install <owner>/zh-skills example-skill

# Install for a specific agent (e.g. claude-code, cursor, codex, gemini-cli)
gh skill install <owner>/zh-skills example-skill --agent claude-code

# Install at user scope (available across all projects in ~/.claude/skills or ~/.agents/skills)
gh skill install <owner>/zh-skills example-skill --agent claude-code --scope user

# Install all skills from the repository
gh skill install <owner>/zh-skills --all
```

#### From a local directory (development / testing)

```bash
# List available skills from local directory
gh skill install . --from-local

# Install a specific skill from the current directory
gh skill install . example-skill --from-local --agent github-copilot

# Install all skills from local directory
gh skill install . --all --from-local
```

### 2. Preview Skills

Preview a skill's file tree and rendered `SKILL.md` directly in the terminal without installing:

```bash
gh skill preview <owner>/zh-skills example-skill
```

### 3. List Installed Skills

```bash
gh skill list
```

### 4. Update Installed Skills

```bash
# Update all installed skills
gh skill update --all

# Update a specific skill
gh skill update example-skill
```

---

## Adding a New Skill

1. Create a new directory under `skills/`:
   ```bash
   mkdir -p skills/my-new-skill
   ```

2. Create `skills/my-new-skill/SKILL.md` with required frontmatter:
   ```markdown
   ---
   name: my-new-skill
   description: Detailed description of what the skill does and when the agent should use it. Include relevant keywords and triggers.
   license: MIT
   ---

   # My New Skill

   ## Instructions
   Provide clear, step-by-step guidance for the agent...
   ```

3. Adhere to specification rules:
   - **`name`**: Must match the directory name (`skills/<name>/`). 1–64 characters, lowercase alphanumeric (`a-z`, `0-9`) and single hyphens (`-`). Cannot begin or end with a hyphen; no consecutive hyphens (`--`).
   - **`description`**: 1–1024 characters. Explicitly describe what the skill does and trigger scenarios.
   - **`license`**: Recommended license identifier (e.g. `MIT`).
   - **`allowed-tools`**: If specified, must be a space-separated string (e.g. `Bash(git:*) Read`), not an array.
   - Keep `SKILL.md` under 500 lines for fast context loading; put larger references in `references/`.

---

## Validation and Publishing

### Validate Skills

Use `gh skill publish --dry-run` to validate all skills against the Agent Skills specification:

```bash
gh skill publish --dry-run
```

If committed files contain install tracking metadata (`metadata.github-*`), strip it with:

```bash
gh skill publish --fix
```

### Publish to GitHub

1. Ensure the repository has a GitHub remote:
   ```bash
   gh repo create zh-skills --public --source=. --push
   ```

2. Add the `agent-skills` topic to the repository (makes it discoverable via `gh skill search`):
   ```bash
   gh repo edit --add-topic agent-skills
   ```

3. Publish a release:
   ```bash
   # Interactive publish
   gh skill publish

   # Non-interactive with a version tag
   gh skill publish --tag v1.0.0
   ```
