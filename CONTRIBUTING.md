# Contributing to skills

## Adding a new plugin

1. Fork this repository
2. Create `plugins/<your-plugin-name>/` with the structure below
3. Add an entry to `.claude-plugin/marketplace.json`
4. Run `claude plugin validate .` in the repo root
5. Open a pull request

## Required plugin structure

```
plugins/<your-plugin-name>/
├── .claude-plugin/
│   └── plugin.json        ← required
└── skills/
    └── <skill-name>/
        └── SKILL.md       ← at least one skill required
```

## plugin.json requirements

- `name`: kebab-case, matches directory name
- `version`: semver (e.g. `1.0.0`)
- `description`: one sentence, what does it do
- `author.name`: your name
- `license`: must be MIT or Apache-2.0 for inclusion

## SKILL.md requirements

- Frontmatter must include `name` and `description`
- `description` must state **when** to invoke, not **how** it works (≤250 chars)
- Content must be actionable: checklists, not essays

## Validation

Before submitting, run:

```bash
claude plugin validate ./plugins/<your-plugin-name>
```

All errors must be resolved. Warnings should be addressed.
