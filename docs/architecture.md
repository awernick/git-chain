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
