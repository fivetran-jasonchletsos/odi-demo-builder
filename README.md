# ODI Demo Builder Skill

Claude Code skill that guides a facilitated, 3-hour hands-on build of a production-ready Fivetran ODI demo, end to end: SQL Server (CDC) to an MDLS-managed Iceberg layer on S3 (Glue catalog), dbt bronze/silver/gold transforms, and a React frontend. Built for the Andy + Niraj session.

The skill lives at `skills/odi-demo-builder/SKILL.md`.

## Quick start (do this once)

```bash
git clone https://github.com/fivetran-jasonchletsos/odi-demo-builder.git
cd odi-demo-builder
./setup.sh
```

`setup.sh` auto-installs every Homebrew-based prerequisite (Claude Code, git, gh, 1Password CLI, Terraform, AWS CLI, Node 20, dbt), installs the skill in the correct layout, then runs `preflight.sh` and prints exactly what is left for you to do. The only things it can't automate are the ones that need your own credentials — logins and the Fivetran API key — and it lists those for you.

When everything passes, **restart Claude Code** and verify:

```bash
claude skill list | grep odi-demo-builder
```

You should see `odi-demo-builder`, and `/odi-demo-builder` will work in a session.

## Check your machine any time

`preflight.sh` is read-only — it changes nothing, just reports. Run it whenever you want to confirm you are ready:

```bash
./preflight.sh
```

It checks every prerequisite and, for anything missing, prints the exact command to fix it. Exit code 0 means you are good to go. If you get stuck, paste its output in the shared Slack channel before the session.

## Scripts in this repo

- `setup.sh` — auto-install the tools, install the skill, then run preflight. Safe to re-run.
- `preflight.sh` — read-only check of every prerequisite with copy-paste fixes.
- `install.sh` — installs just the skill into `~/.claude/skills/odi-demo-builder/SKILL.md` (called by setup.sh; run it alone if you only need the skill).

## Install the skill manually (if you skip the scripts)

Claude Code loads a skill only when it sits in its own folder as `SKILL.md`. A loose `.md` file in the skills directory will **not** load — that was the original problem.

```bash
mkdir -p ~/.claude/skills/odi-demo-builder
cp skills/odi-demo-builder/SKILL.md ~/.claude/skills/odi-demo-builder/SKILL.md
```

Then restart Claude Code.

## Updating later

```bash
cd odi-demo-builder
git pull
./install.sh   # refresh the skill
```

Restart Claude Code afterward.

## Prerequisites at a glance

Full detail and verify steps live in the session prework. The scripts above cover all of these:

- Claude Code CLI + login
- This skill (`./install.sh`)
- git (with `user.name` / `user.email` set)
- GitHub CLI (`gh auth login`)
- 1Password CLI (`op signin`)
- Fivetran API key (`FIVETRAN_API_KEY` / `FIVETRAN_API_SECRET`)
- Terraform
- AWS CLI (`aws configure`)
- Node.js 20+
- dbt (`dbt-core` + adapter)
