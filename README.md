# ODI Demo Builder Skill

Claude Code skill that guides a facilitated, 3-hour hands-on build of a production-ready Fivetran ODI demo, end to end: SQL Server (CDC) to an MDLS-managed Iceberg layer on S3 (Glue catalog), dbt bronze/silver/gold transforms, and a React frontend. Built for the Andy + Niraj session.

The skill lives at `skills/odi-demo-builder/SKILL.md`.

## Install

Claude Code only loads a skill when it sits in its own folder as `SKILL.md` under `~/.claude/skills/`. A loose `.md` file in the skills directory will NOT load — that was the original problem.

### Option A: install script (recommended)

```bash
git clone https://github.com/fivetran-jasonchletsos/odi-demo-builder.git
cd odi-demo-builder
./install.sh
```

### Option B: manual

```bash
git clone https://github.com/fivetran-jasonchletsos/odi-demo-builder.git
mkdir -p ~/.claude/skills/odi-demo-builder
cp odi-demo-builder/skills/odi-demo-builder/SKILL.md ~/.claude/skills/odi-demo-builder/SKILL.md
```

### Verify

Restart Claude Code (skills are discovered at startup), then:

```bash
claude skill list | grep odi-demo-builder
```

Success looks like: `odi-demo-builder` appears in the list. In a session, `/odi-demo-builder` will resolve.

## Updating

To pull a newer version later:

```bash
cd odi-demo-builder
git pull
./install.sh
```

Then restart Claude Code.
