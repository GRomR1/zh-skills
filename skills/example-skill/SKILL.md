---
name: example-skill
description: A template skill demonstrating the Agent Skills directory structure and conventions. Use when creating new agent skills or testing skill installation.
license: MIT
---

# Example Skill

This is an example agent skill following the [Agent Skills specification](https://agentskills.io/specification).

## Usage

Use this template as a reference when developing new skills for use with `gh skill`.

## Structure

```
skills/example-skill/
├── SKILL.md                 # Required: metadata and instructions
├── scripts/                 # Optional: executable scripts
├── references/              # Optional: reference documentation
│   └── REFERENCE.md
└── assets/                  # Optional: templates or static assets
```

See [the reference guide](references/REFERENCE.md) for design principles and progressive disclosure details.

## Guidelines

- Keep `name` matching the parent directory name.
- Name must only contain lowercase alphanumeric characters (`a-z`, `0-9`) and single hyphens (`-`).
- Description must be non-empty, max 1024 characters, explaining what the skill does and when to activate it.
- Keep the main `SKILL.md` focused, moving detailed documentation to `references/`.
