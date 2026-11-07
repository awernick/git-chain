# Architecture

## Command Pattern

All commands inherit from `Commands::Command` and implement:
- `description` - Help text
- `run(options)` - Command logic
- `configure_option_parser(opts, options)` - CLI flags (optional)

Commands that operate on a chain include `Options::ChainName` which adds
the `-c/--chain` flag and `current_chain(options)` helper.

New commands are registered by adding an `autoload` line in `commands.rb`.

## Output Formatting

All output goes through `Util::Output` (included in `Command`). Use the
`puts` method with cli-ui formatting tags:

```ruby
puts("{{bold:title}}")              # Bold
puts("{{cyan:branch_name}}")        # Colored
puts("{{green:success message}}")   # Green
puts("{{red:error message}}")       # Red
puts("{{yellow:warning}}")          # Yellow
puts("{{info:name}} {{reset:text}}")  # Info style
```

Do not use `$stdout.puts` or `Kernel#puts` directly.

## Git Operations

All git commands go through `GitChain::Git`, which shells out to `git` via
`Open3.capture3`. Use `Git.exec` for commands that must succeed (raises
`Git::Failure` on error) and `Git.capture3` when you need to check the
exit status yourself.

## Chain Metadata

Chain configuration is stored in git config (not files):

```
branch.<name>.chain = <chain-name>
branch.<name>.parentBranch = <parent-branch-name>
branch.<name>.branchPoint = <commit-sha>
```

`Models::Chain.from_config(name)` reconstructs the chain by reading these
config entries and sorting branches by parent relationships.

## Chain Rebase

`ChainRebase` is the shared service behind `git chain rebase` and
`git chain sync`. It finds the stale segment (branches whose `branchPoint`
no longer matches their parent's tip) and rebases it in one of two ways:

- **Single pass** (Git 2.38+): one `git rebase --keep-empty --update-refs`
  replays the whole segment and moves every branch ref. Used only when the
  segment is strictly nested (each branch contains its parent's tip), no
  segment branch is checked out in another worktree (or, apart from the
  tip, in the current one), and no branch outside the segment points into
  the replayed range. Git snapshots worktree state when the rebase starts
  and silently skips refs checked out elsewhere, so these guards are
  correctness requirements, not optimizations.
- **Per-branch fallback**: each branch is rebased onto its parent with
  `git rebase --keep-empty --onto <parent> <branchPoint> <branch>`.

Both paths persist `branchPoint` only after the rebase succeeds. The fast
path verifies every branch ref before writing configs. Commands pass a
block to render progress events (`:up_to_date`, `:auto_forward`,
`:rebase_branch`, `:rebase_command`).

## Forge Abstraction

The `Forge` module detects GitHub or GitLab from the remote URL and
provides a common interface for PR/MR operations:

```ruby
forge = Forge.detect(remote_url: chain.remote_url)
if forge&.cli_available?
  pr = forge.pr_for_branch("feature-1")
  # => { number: 42, state: "OPEN", is_draft: false, review_decision: "APPROVED", url: "https://github.com/owner/repo/pull/42" }
end
```

Detection priority:
1. `git config chain.forge` override (for custom domains)
2. Remote URL hostname matching

States are normalized to `OPEN`, `MERGED`, `CLOSED` across forges.

When adding forge-dependent features, use this abstraction rather than
calling `gh` or `glab` directly.
