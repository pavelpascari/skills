# skills

> A curated Claude Code plugin marketplace by Pavel Pascari

## Install

```
/plugin marketplace add pavelpascari/skills
```

Then install individual plugins:

```
/plugin install <plugin-name>@skills
```

## Plugins

| Plugin | Description | Version |
|--------|-------------|---------|
| [`test-code-review`](./plugins/test-code-review) | Review test code changes for correctness, catching weakened assertions and tests rewritten to match buggy behavior. | 1.2.2 |
| [`software-engineering`](./plugins/software-engineering) | Encodes a coherent set of software engineering principles to apply during coding tasks, plus a pre-PR sweep that forces deferred findings to a decision and enumerates failure modes before review is requested. | 1.5.0 |
| [`hcampus`](./plugins/hcampus) | Durable, evidence-backed memory through the hcampus MCP server: a recall/remember/forget skill, a guard that stops secrets from reaching append-only memory, and nudges to recall before acting and persist durable outcomes. | 1.0.0 |

## Requirements

- [Claude Code](https://claude.ai/code) with plugin support enabled

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to submit new plugins.

## License

MIT — see [LICENSE](./LICENSE)
