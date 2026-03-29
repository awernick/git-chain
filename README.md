# Git Chain

Tool to manage stacked pull requests with dependent Git branches.

Fork of [Shopify/git-chain](https://github.com/Shopify/git-chain) with
additional features: chain status with tree view, forge abstraction
(GitHub/GitLab), and more.

## What does Git Chain do?

If you're working on a larger feature that you want to ship in smaller,
easier reviewable pull requests, there's a big chance that you're creating
separate branches for each of them. If the changes don't depend on each
other, you can simply base all branches on the main branch and work on them
independently.

But if your second branch depends on changes in the first and your third
branch on changes in the second, you'll end up doing a lot of manual
rebases when a base branch changes (e.g. because you addressed a comment
in a review).

Git Chain automates this. You specify a chain of branches and manage them
with a single set of commands.

## Requirements

- Git
- Ruby (>= 2.6; tested with Ruby 4.0)
- `gh` (GitHub CLI) or `glab` (GitLab CLI) for PR/MR status features
  (optional)

## Installation

```sh
git clone https://github.com/awernick/git-chain /usr/local/share/git-chain
ln -sv /usr/local/share/git-chain/bin/git-chain /usr/local/bin/

git chain # Should now work
```

## Demo

![Demo recording](docs/demo.gif)

## Quick Start

### Setting up a chain

Tell Git Chain about your branch order:

```
$ git chain setup -c awesome-feature main feature-database feature-model feature-ui
Setting up chain awesome-feature
```

The `-c` option names the chain. The first argument (`main`) is the base
branch that the chain rebases onto. This setup only needs to be done once
per chain.

### Checking chain status

See the state of your chain at a glance:

```
$ git chain status
awesome-feature
  main
  ├── feature-database (2 ahead, #10 open)
  ├── feature-model (HEAD) (1 ahead, #11 open)
  └── feature-ui (1 ahead, #12 draft)
```

Shows ahead/behind counts, current branch, and PR/MR status (if `gh` or
`glab` is installed). Use `--no-pr` to skip PR lookups.

### Rebasing a chain

Rebase all branches in one go:

```
$ git chain rebase
Rebasing the following branches: ["main", "feature-database", "feature-model", "feature-ui"]
```

Git Chain detects the current chain based on your checked-out branch. Use
`-c` to target a specific chain if you're not on a chain branch.

### Pushing a chain

Push all branches to the remote:

```
$ git chain push
```

## Commands

| Command | Description |
|---------|-------------|
| `git chain setup -c <name> <base> <branch>...` | Configure a chain |
| `git chain status` | Show chain tree with branch and PR state |
| `git chain rebase` | Rebase all branches onto their parents |
| `git chain push` | Push all chain branches to remote |
| `git chain branch <name>` | Create a new branch in the chain |
| `git chain list` | List existing chains |
| `git chain prune` | Remove merged branches from chain |
| `git chain teardown` | Remove chain configuration |

## Example

Imagine the following feature: You want to add a new database table (PR 1),
add a model using the table (PR 2), and build a user interface for editing
records (PR 3).

At the beginning you have a clean git history:

```
* e7888f9 (HEAD -> feature-ui) feature-ui.2
* a743802 (feature-model) feature-model.1
* 9cc4914 (feature-database) feature-database.1
* f6ba0e9 (main) main.1
```

After working on branches and others merging into main, the history
diverges:

```
* 56b953a (feature-model) feature-model.2
| * e7888f9 (HEAD -> feature-ui) feature-ui.2
| * 14090bb feature-ui.1
|/
* a743802 feature-model.1
| * 8c46072 (feature-database) feature-database.2
|/
* 9cc4914 feature-database.1
| * fdca13e (main) main.2
|/
* f6ba0e9 main.1
```

Getting back to a linear history requires manually rebasing each branch.
With Git Chain:

```
$ git chain rebase
Rebasing the following branches: ["main", "feature-database", "feature-model", "feature-ui"]
```

Result:

```
* 7974771 (HEAD -> feature-ui) feature-ui.2
* 1427391 feature-ui.1
* 9877787 (feature-model) feature-model.2
* 3ad1096 feature-model.1
* 8e333d6 (feature-database) feature-database.2
* 00ac4d1 feature-database.1
* fdca13e (main) main.2
* f6ba0e9 main.1
```

## Handling Conflicts

When a rebase hits a conflict, Git Chain stops and leaves the repository at
that state. Resolve the conflict, finish the rebase, and run
`git chain rebase` again:

```
$ git chain rebase
Cannot merge b onto a. Fix the rebase and run 'git chain rebase' again.

# ...resolve the conflict...
$ git rebase --continue
Successfully rebased and updated refs/heads/b.

$ git chain rebase
Rebasing the following branches: ["main", "a", "b", "c"]
```

## Forge Support

Git Chain auto-detects GitHub or GitLab from your remote URL for PR/MR
status features. No configuration needed for standard github.com or
gitlab.com remotes.

For custom domains (e.g. GitHub Enterprise, self-hosted GitLab):

```sh
git config chain.forge github   # or gitlab
```

## Pull Requests

GitHub and GitLab support setting a base branch on pull requests. For
stacked PRs, each branch's PR should target the previous branch in the
chain (not main).

`git chain status` shows which branches have PRs and their current state,
making it easy to track your stack.

## License

MIT. See [LICENSE](LICENSE).
