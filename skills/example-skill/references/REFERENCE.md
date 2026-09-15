# Example Skill Reference Guide

This reference guide contains supplementary documentation loaded on demand by AI coding agents.

## Design Principles

1. **Focused Scope**: Each skill should do one job well.
2. **Deterministic Instructions**: Provide clear, unambiguous steps.
3. **Progressive Disclosure**:
   - Keep `SKILL.md` under 500 lines for quick context loading.
   - Place large tables, exhaustive API references, or detailed guides in `references/`.
   - Place reusable executable scripts in `scripts/`.
   - Place templates or static data in `assets/`.
