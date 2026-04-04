# Agent Prompt: Bootstrap a Claude Code Plugin Marketplace

You are setting up a **public Claude Code plugin marketplace** hosted on GitHub.
Work through each phase sequentially. Do not skip steps. After each file creation,
confirm it exists before moving on.

---

## Context: What You Are Building

A marketplace is a GitHub repo that Claude Code users can add with:

```
/plugin marketplace add <github-owner>/<repo-name>
```

It contains a catalog (`marketplace.json`) that lists plugins. Each plugin is a
directory with a `plugin.json` manifest and one or more component types:
skills, commands, agents, hooks, MCP servers.

Reference implementation: https://github.com/obra/superpowers

---

## Phase 0: Gather Information (Ask Before Proceeding)

Before writing any files, collect the following. Ask the user if any are missing:

- **MARKETPLACE_NAME**: kebab-case identifier (e.g. `pavel-tools`). No spaces.
  Must not impersonate Anthropic (reserved: `claude-code-marketplace`,
  `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`).
- **OWNER_NAME**: your full name or team name
- **OWNER_EMAIL**: contact email (optional but recommended)
- **GITHUB_HANDLE**: your GitHub username
- **REPO_NAME**: the GitHub repository name (often same as MARKETPLACE_NAME)
- **FIRST_PLUGIN_NAME**: name of the first plugin to scaffold (kebab-case)
- **FIRST_PLUGIN_DESCRIPTION**: one sentence — what does it do?

Store these as variables and substitute them throughout this prompt.

---

## Phase 1: Repository Skeleton

Create the following directory structure. All paths are relative to the repo root.

```
<REPO_NAME>/
├── .claude-plugin/
│   └── marketplace.json        ← marketplace catalog
├── plugins/
│   └── <FIRST_PLUGIN_NAME>/
│       ├── .claude-plugin/
│       │   └── plugin.json     ← plugin manifest
│       └── skills/
│           └── <FIRST_PLUGIN_NAME>/
│               └── SKILL.md    ← first skill
├── .github/
│   └── workflows/
│       └── validate.yml        ← CI validation
├── README.md
├── CONTRIBUTING.md
└── LICENSE                     ← MIT recommended for public marketplace
```

### 1a. Create `.claude-plugin/marketplace.json`

```json
{
  "name": "<MARKETPLACE_NAME>",
  "owner": {
    "name": "<OWNER_NAME>",
    "email": "<OWNER_EMAIL>"
  },
  "metadata": {
    "description": "A curated Claude Code plugin marketplace by <OWNER_NAME>",
    "version": "1.0.0",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "<FIRST_PLUGIN_NAME>",
      "source": "./<FIRST_PLUGIN_NAME>",
      "description": "<FIRST_PLUGIN_DESCRIPTION>",
      "version": "1.0.0",
      "author": {
        "name": "<OWNER_NAME>",
        "email": "<OWNER_EMAIL>"
      },
      "license": "MIT",
      "keywords": [],
      "category": "productivity"
    }
  ]
}
```

**Important constraints:**
- `name` must be kebab-case, no spaces, not a reserved Anthropic name
- `source` paths are relative to `pluginRoot` (which is `./plugins` above),
  so `"./<FIRST_PLUGIN_NAME>"` resolves to `./plugins/<FIRST_PLUGIN_NAME>`
- Relative paths only work when users add via git — not via raw URL

### 1b. Create `plugins/<FIRST_PLUGIN_NAME>/.claude-plugin/plugin.json`

```json
{
  "name": "<FIRST_PLUGIN_NAME>",
  "description": "<FIRST_PLUGIN_DESCRIPTION>",
  "version": "1.0.0",
  "author": {
    "name": "<OWNER_NAME>",
    "email": "<OWNER_EMAIL>"
  },
  "homepage": "https://github.com/<GITHUB_HANDLE>/<REPO_NAME>",
  "repository": "https://github.com/<GITHUB_HANDLE>/<REPO_NAME>",
  "license": "MIT",
  "keywords": []
}
```

**Note:** Do not declare `skills`, `commands`, `agents` paths here unless you want
to override convention-based auto-discovery. Claude Code will find `skills/`
automatically.

### 1c. Create the first `SKILL.md`

Path: `plugins/<FIRST_PLUGIN_NAME>/skills/<FIRST_PLUGIN_NAME>/SKILL.md`

Use this template — fill in the bracketed sections based on what the skill does:

```markdown
---
name: <FIRST_PLUGIN_NAME>
description: >
  Use this skill when [TRIGGERING CONDITION — be specific about when, not how].
  Invoke it to [PRIMARY OUTCOME in 10 words or fewer].
disable-model-invocation: false
user-invocable: true
---

## When to use this skill

[1–3 sentences describing the exact situation that should trigger this skill.
Claude reads this to decide whether to activate it. Be concrete, not abstract.]

## What this skill does

[Brief outline of the process this skill enforces. Use numbered steps if it's
a workflow. Keep it under 500 words — Claude loads full content on demand.]

## Checklist

- [ ] [Step 1]
- [ ] [Step 2]
- [ ] [Step 3]

## Anti-patterns to avoid

- [Thing that looks right but isn't]
- [Common shortcut that breaks the outcome]

## Related skills

<!-- Reference other skills with their full name, e.g. my-other-skill -->
```

**SKILL.md authoring rules (from obra/superpowers):**
- Description is truncated at 250 chars in the listing — front-load the trigger condition
- Descriptions should say **when** to use the skill, not **how** it works
- Descriptions that explain the workflow cause Claude to shortcut it
- Use `disable-model-invocation: true` only for skills with irreversible side effects
- Use `user-invocable: false` for background knowledge skills Claude uses autonomously

---

## Phase 2: README and Docs

### 2a. Create `README.md`

The README is your marketplace's storefront. It must answer four questions:
what is this, who is it for, how do I install it, what's in it.

```markdown
# <MARKETPLACE_NAME>

> [One-sentence description of what this marketplace offers and who it's for]

## Install

```
/plugin marketplace add <GITHUB_HANDLE>/<REPO_NAME>
```

Then install individual plugins:

```
/plugin install <FIRST_PLUGIN_NAME>@<MARKETPLACE_NAME>
```

## Plugins

| Plugin | Description | Version |
|--------|-------------|---------|
| [`<FIRST_PLUGIN_NAME>`](./plugins/<FIRST_PLUGIN_NAME>) | <FIRST_PLUGIN_DESCRIPTION> | 1.0.0 |

## Requirements

- [Claude Code](https://claude.ai/code) with plugin support enabled

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to submit new plugins.

## License

MIT — see [LICENSE](./LICENSE)
```

### 2b. Create `CONTRIBUTING.md`

```markdown
# Contributing to <MARKETPLACE_NAME>

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
```

---

## Phase 3: CI Validation

### 3a. Create `.github/workflows/validate.yml`

```yaml
name: Validate plugins

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Validate marketplace
        run: claude plugin validate .

      - name: Validate each plugin
        run: |
          for dir in plugins/*/; do
            echo "Validating $dir"
            claude plugin validate "$dir"
          done
```

---

## Phase 4: Local Testing

Run these commands in order. Fix any errors before proceeding to the next step.

```bash
# Step 1: validate the marketplace catalog
claude plugin validate .

# Step 2: add your marketplace locally
/plugin marketplace add ./

# Step 3: list available plugins
/plugin marketplace list

# Step 4: install your first plugin
/plugin install <FIRST_PLUGIN_NAME>@<MARKETPLACE_NAME>

# Step 5: verify the skill is available
/                    # should show <FIRST_PLUGIN_NAME> in the slash menu

# Step 6: test the skill
/<FIRST_PLUGIN_NAME>
```

**Common errors and fixes:**

| Error | Fix |
|-------|-----|
| `File not found: .claude-plugin/marketplace.json` | Create the file at repo root |
| `Duplicate plugin name` | Each plugin must have a unique `name` in marketplace.json |
| `Path contains ".."` | Source paths must not traverse up from the plugin root |
| `Plugin name is not kebab-case` | Rename: lowercase letters, digits, hyphens only |
| Skill not in `/` menu | Check SKILL.md frontmatter YAML is valid |

---

## Phase 5: Publish

```bash
# Initialize git
git init
git add .
git commit -m "feat: initial marketplace with <FIRST_PLUGIN_NAME>"

# Create GitHub repo (public)
gh repo create <GITHUB_HANDLE>/<REPO_NAME> --public --push --source=.

# Verify users can add it
# (Run this in a different Claude Code session to test)
/plugin marketplace add <GITHUB_HANDLE>/<REPO_NAME>
```

Add the GitHub topic `claude-code-plugin` to your repo for discoverability:

```bash
gh repo edit <GITHUB_HANDLE>/<REPO_NAME> --add-topic claude-code-plugin
gh repo edit <GITHUB_HANDLE>/<REPO_NAME> --add-topic claude-code-marketplace
```

---

## Phase 6: Adding More Plugins (Repeat Pattern)

For each new plugin, do the following:

1. Create `plugins/<NEW_PLUGIN_NAME>/` with the structure from Phase 1b–1c
2. Add an entry to `.claude-plugin/marketplace.json` under `plugins[]`
3. Add a row to the README table
4. Run `claude plugin validate .`
5. Bump `metadata.version` in `marketplace.json` (minor for new plugin, patch for fixes)
6. Commit and push — users get updates automatically via `/plugin marketplace update`

**Versioning rules:**
- Version in `plugin.json` always wins over `marketplace.json` — set it in only one place
- For relative-path plugins (same repo), set version in `marketplace.json`
- For external-source plugins (GitHub, npm), set version in the plugin's own `plugin.json`
- Same version = Claude Code skips the update — always bump on changes

---

## Phase 7: Advanced Components (Optional, After First Plugin Works)

Only add these after your first skill is validated and tested.

### Hooks (session bootstrap)

To inject a skill automatically on every session start, add to your plugin:

```
plugins/<PLUGIN_NAME>/
└── hooks/
    └── hooks.json
```

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "cat ${CLAUDE_PLUGIN_ROOT}/skills/using-<PLUGIN_NAME>/SKILL.md"
        }
      ]
    }
  ]
}
```

Use `${CLAUDE_PLUGIN_ROOT}` for paths inside the plugin — never hardcode paths,
as plugins are copied to a cache directory on install.

### Agents

Create `plugins/<PLUGIN_NAME>/agents/<agent-name>.md`:

```markdown
---
name: <agent-name>
description: When and why to use this agent
model: claude-sonnet-4-5
effort: high
maxTurns: 20
tools:
  - Read
  - Write
  - Bash
skills:
  - <PLUGIN_NAME>/<skill-name>
---

[Agent instructions here]
```

### MCP Servers

Only add MCP servers if skills + hooks can't solve the problem. They require
a running process and add installation complexity. Define in `plugin.json`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
    }
  }
}
```

---

## Completion Checklist

Before considering the marketplace ready to share:

- [ ] `claude plugin validate .` passes with no errors
- [ ] Marketplace loads via `/plugin marketplace add ./`
- [ ] First plugin installs and skill appears in `/` menu
- [ ] Skill invocation works end-to-end
- [ ] README has working install instructions
- [ ] CI workflow validates on every PR
- [ ] Repo is public on GitHub
- [ ] GitHub topics `claude-code-plugin` and `claude-code-marketplace` added
- [ ] (Optional) Submitted to https://www.claudepluginhub.com