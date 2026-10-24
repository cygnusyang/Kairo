# Quickstart

Five minutes from nothing to a scheduled project, then one line to hand it to an AI agent.
Every command below is meant to be copied as-is.

## 1. Install the app

```bash
brew install --cask cygnusyang/kairo/kairo
```

No Homebrew? Download `Kairo-vX.Y.Z.dmg` from the [latest release](https://github.com/cygnusyang/Kairo/releases/latest) and drag it to Applications.

> The app is currently **ad-hoc signed, not notarized**. On first launch macOS blocks it:
> allow it in **System Settings → Privacy & Security → Open Anyway**. See
> [SECURITY.md](SECURITY.md) for what that means for provenance.

## 2. Get the CLI and the MCP server

Prebuilt universal binaries (Apple Silicon and Intel in one file):

```bash
VER=$(curl -sS https://api.github.com/repos/cygnusyang/Kairo/releases/latest \
  | sed -n 's/.*"tag_name": *"\(v[^"]*\)".*/\1/p')
BASE="https://github.com/cygnusyang/Kairo/releases/download/$VER"

curl -sSL -O "$BASE/kairo-$VER-macos-universal.tar.gz"
curl -sSL -O "$BASE/kairo-$VER-macos-universal.tar.gz.sha256"

# verify before unpacking: a truncated download fails right here
[ "$(cat kairo-$VER-macos-universal.tar.gz.sha256)" = \
  "$(shasum -a 256 kairo-$VER-macos-universal.tar.gz | awk '{print $1}')" ] \
  && echo "checksum ok"

tar xzf "kairo-$VER-macos-universal.tar.gz"
sudo install -m 755 "kairo-$VER-macos-universal/bin/kairo" \
  "kairo-$VER-macos-universal/bin/kairo-mcp" /usr/local/bin/
kairo
```

Or build from source (Swift 5.9+, Xcode 16+):

```bash
git clone https://github.com/cygnusyang/Kairo.git
cd Kairo
swift build -c release
```

The binaries land in `.build/release/` as `KairoCLI` and `KairoMCP`.

## 3. Schedule a project

```bash
kairo project create "Example project" --start 2026-11-02 --end 2026-11-20 --file demo.kairo

cat > wbs.json <<'EOF'
[
  {"title": "Payments", "kind": "group", "children": [
    {"title": "API design", "effortHours": 16},
    {"title": "Server implementation", "effortHours": 40},
    {"title": "Client integration", "effortHours": 24},
    {"title": "Joint acceptance", "kind": "milestone"}
  ]}
]
EOF

kairo wbs import wbs.json --file demo.kairo
kairo task list --file demo.kairo
```

Add the dependency chain (IDs accept a unique prefix of four or more characters, so you do
not have to copy UUIDs):

```bash
id() { kairo task list --file demo.kairo --json | python3 -c "import json,sys;print([t['id'][:4] for t in json.load(sys.stdin) if t['title']=='$1'][0])"; }

kairo task update "$(id 'Server implementation')" --dep "$(id 'API design'):fs" --file demo.kairo
kairo task update "$(id 'Client integration')" --dep "$(id 'Server implementation'):fs" --file demo.kairo
kairo task update "$(id 'Joint acceptance')" --dep "$(id 'Client integration'):fs" --file demo.kairo

kairo schedule compute --file demo.kairo     # dates
kairo schedule path --file demo.kairo        # critical path and slack
kairo violations --file demo.kairo           # cycles, out-of-range, deadline conflicts
```

Open the same file in the app (**File → Open**, or double-click the `.kairo`) and you see
the outline and the timeline aligned row by row.

> Since **v0.9.0** both the app and the CLI speak English and Simplified Chinese; see
> [Language](#4-language). The `.kairo` file, the flags and the MCP tool names are
> language-neutral either way.

## 4. Language

Both the app and the CLI speak English and Simplified Chinese.

**App** — follows the system language (System Settings → General → Language & Region) and is
resolved at launch: switch the language, then relaunch. Nothing to configure.

**CLI** — resolves its language in this order:

1. `--lang <bcp47>` (or `--lang=<bcp47>`)
2. the `KAIRO_LANG` environment variable
3. the system language
4. **Simplified Chinese**, when the system language cannot be determined — v0.9.0 deliberately
   keeps existing Chinese scripts working. If you match on output text, pin English explicitly.

| `--lang` value | Output |
|---|---|
| `en` | English |
| `zh-Hans` | Simplified Chinese |

```bash
kairo task list --file demo.kairo --lang en          # English (needs v0.9.0 or newer)
KAIRO_LANG=zh-Hans kairo violations --file demo.kairo # pinned via environment
kairo task list --file demo.kairo --lang en --json    # --json ignores the language
```

`--json` output never depends on the language: same bytes, same keys, same codes under either
setting. An unsupported `--lang` value is a usage error and exits **2**; success exits 0 and a
runtime failure exits 1.

> `--lang` and `KAIRO_LANG` exist from **v0.9.0**. On v0.8.5 the CLI is Chinese-only and
> rejects the flag as an unknown option.

## 5. Hand it to an agent

**Claude Code plugin** — slash commands plus automatic status write-back:

```bash
claude --plugin-dir /path/to/Kairo/Plugins/claude-code
```

Then `/kairo plan <requirement>`, `/kairo done <task-id>`, `/kairo status`.

**Codex / CodeBuddy / Claude Code over plain MCP** — a project-root `.mcp.json`:

```bash
cat > .mcp.json <<EOF
{ "mcpServers": { "kairo": { "command": "$(command -v kairo-mcp)" } } }
EOF
```

Then tell the agent, in `AGENTS.md` (or `CODEBUDDY.md` / `CLAUDE.md`): use Kairo's MCP tools
for planning, mark completion with `status_update`, and never edit the `.kairo` file directly.
The exact wording to copy lives in [Plugins/README.md](Plugins/README.md).

## 6. What just happened

- `demo.kairo` is the whole project: one JSON file, human-readable, diffable, safe to commit.
- The schedule is derived, not stored: change an effort or a dependency and `schedule_compute`
  recomputes dates; violations are reported rather than silently fixed.
- AI and human read and write the same file through different doors: MCP/CLI for the agent,
  the app for review.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "Kairo can't be opened because Apple cannot check it" | not notarized yet | System Settings → Privacy & Security → Open Anyway |
| `kairo: command not found` | `/usr/local/bin` not on PATH | move the binaries somewhere on `PATH`, or export it |
| `task update: 用法错误` | ID prefix ambiguous | use more characters from `task list --json` |
| Schedule unchanged after editing | schedule is derived | run `kairo schedule compute` again |
