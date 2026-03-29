# AGENTS.md - git-chain

## Overview

Fork of [Shopify/git-chain](https://github.com/Shopify/git-chain) with
additional features for stacked PR workflows. A Ruby CLI tool that manages
chains of dependent git branches, handling rebasing, pushing, and status
tracking across the stack.

This fork adds: chain status with tree view, forge abstraction
(GitHub/GitLab), and is actively developing sync, PR creation, and landing
features.

## Repository Structure

```
bin/
  git-chain              # Entry point (executable)
lib/
  git_chain.rb           # Module root, autoloads, constants
  git_chain/
    commands.rb           # Command registry (autoloads all commands)
    commands/
      command.rb          # Base class for all commands
      branch.rb           # Create/insert branches in a chain
      list.rb             # List existing chains
      prune.rb            # Remove merged branches
      push.rb             # Push all chain branches
      rebase.rb           # Rebase all chain branches
      setup.rb            # Configure a new chain
      status.rb           # Show chain status with tree view (fork addition)
      teardown.rb         # Remove chain configuration
    entry_point.rb        # CLI argument parsing, command dispatch
    forge.rb              # Forge auto-detection factory (fork addition)
    forge/
      base.rb             # Forge interface (cli_available?, pr_for_branch)
      github.rb           # GitHub adapter (gh CLI)
      gitlab.rb           # GitLab adapter (glab CLI)
    git.rb                # Git command wrapper (shells out to git)
    models.rb             # Model registry
    models/
      model.rb            # Base model
      branch.rb           # Branch model (name, chain, parent, branch_point)
      chain.rb            # Chain model (name, sorted branches)
    options.rb            # Shared option modules
    options/
      chain_name.rb       # -c/--chain flag mixin
    util.rb               # Utility registry
    util/
      github.rb           # GitHub URL parser
      output.rb           # Output helpers (puts, puts_error, etc.)
vendor/
  bootstrap.rb            # Load path setup for vendored deps
  deps/
    cli-kit/              # Shopify CLI framework (vendored)
    cli-ui/               # Shopify CLI UI formatting (vendored)
fixtures/
  *.sh                    # Shell scripts that create test git repos
test/
  test_helper.rb          # Minitest setup, RepositoryTestHelper
  git_chain/
    command/              # Command tests
    forge/                # Forge adapter tests
    model/                # Model tests
    util/                 # Utility tests
```

## Build / Test Commands

```bash
# Run the full test suite
bundle exec rake test

# Run a single test file
bundle exec ruby -Itest test/git_chain/command/status_test.rb

# Run rubocop
bundle exec rubocop

# Run the CLI directly from source
bin/git-chain <command>
```

### Ruby Version

The upstream repo targets Ruby 2.6. This fork maintains compatibility with
Ruby 4.0+ (Homebrew default). If the system Ruby is too old, use the
Homebrew Ruby:

```bash
export PATH="/opt/homebrew/Cellar/ruby/4.0.1/bin:$PATH"
export GEM_HOME="$HOME/.gem/ruby/4.0.1"
export PATH="$GEM_HOME/bin:$PATH"
bundle exec rake test
```

### Test Fixtures

Test repositories are created by shell scripts in `fixtures/`. Each script
sets up a temporary git repo with branches and chain configuration. Tests
use `with_test_repository("fixture-name")` to run inside a temp directory
built from a fixture.

Available fixtures:
- `a-b` - Two branches (a, b), no chain configured
- `a-b-chain` - Two branches (a, b) in a chain called "default"
- `a-b-conflict` - Two branches with conflicting changes

## Architecture

### Command Pattern

All commands inherit from `Commands::Command` and implement:
- `description` - Help text
- `run(options)` - Command logic
- `configure_option_parser(opts, options)` - CLI flags (optional)

Commands that operate on a chain include `Options::ChainName` which adds
the `-c/--chain` flag and `current_chain(options)` helper.

New commands are registered by adding an `autoload` line in `commands.rb`.

### Output Formatting

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

### Git Operations

All git commands go through `GitChain::Git`, which shells out to `git` via
`Open3.capture3`. Use `Git.exec` for commands that must succeed (raises
`Git::Failure` on error) and `Git.capture3` when you need to check the
exit status yourself.

### Chain Metadata

Chain configuration is stored in git config (not files):

```
branch.<name>.chain = <chain-name>
branch.<name>.parentBranch = <parent-branch-name>
branch.<name>.branchPoint = <commit-sha>
```

`Models::Chain.from_config(name)` reconstructs the chain by reading these
config entries and sorting branches by parent relationships.

### Forge Abstraction

The `Forge` module detects GitHub or GitLab from the remote URL and
provides a common interface for PR/MR operations:

```ruby
forge = Forge.detect(remote_url: chain.remote_url)
if forge&.cli_available?
  pr = forge.pr_for_branch("feature-1")
  # => { number: 42, state: "OPEN", is_draft: false, review_decision: "APPROVED" }
end
```

Detection priority:
1. `git config chain.forge` override (for custom domains)
2. Remote URL hostname matching

States are normalized to `OPEN`, `MERGED`, `CLOSED` across forges.

When adding forge-dependent features, use this abstraction rather than
calling `gh` or `glab` directly.

## Code Style

### General

- `# frozen_string_literal: true` at the top of every Ruby file
- `require` statements at the top, after the frozen string literal comment
- 2-space indentation
- No trailing whitespace
- Trailing newline at end of file

### Naming

| Context | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `Commands::Status` |
| Methods | snake_case | `pr_for_branch` |
| Constants | UPPER_SNAKE_CASE | `TOOL_NAME` |
| Files | snake_case | `status.rb` |
| Test classes | PascalCase + Test | `StatusTest` |

### Testing

- Framework: Minitest (not MiniTest; the capital-T alias was removed in
  Ruby 4.0)
- Mocking: Mocha (`mocha/minitest`)
- Test helper: `include RepositoryTestHelper` for tests that need a git repo
- Use `capture_io { }` to capture command output
- Use `assert_raises(Abort) { }` for expected failures
- Use `--no-pr` flag in status tests to avoid forge CLI dependencies
- Skip tests that require external CLIs:
  ```ruby
  skip("gh not installed") unless gh_available?
  ```

### Adding a New Command

1. Create `lib/git_chain/commands/<name>.rb`
2. Inherit from `Command`, include `Options::ChainName` if needed
3. Add `autoload :<Name>, "git_chain/commands/<name>"` to `commands.rb`
4. Create `test/git_chain/command/<name>_test.rb`
5. Create a fixture in `fixtures/` if existing ones don't cover your case

### Adding a New Forge

1. Create `lib/git_chain/forge/<name>.rb` inheriting from `Forge::Base`
2. Implement `cli_available?` and `pr_for_branch`
3. Normalize state to `OPEN`/`MERGED`/`CLOSED`
4. Add autoload in `forge.rb`
5. Add detection pattern in `Forge.from_remote_url`
6. Create `test/git_chain/forge/<name>_test.rb`

## Git Workflow

### Branching

- Branch from `main` for all work
- Branch naming: `feat/<short-name>`, `fix/<short-name>`
- One branch per issue or logical change

### Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

<body>

Closes #N
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
Scopes: `status`, `sync`, `push`, `forge`, `branch`, `pr`, etc.

### Pull Requests

- PRs target `main`
- Squash merge (one commit per PR on main)
- PR title follows conventional commit format
- Link issues in the PR body with `Closes #N` or `Refs #N`

### Upstream Relationship

This is an independent fork of Shopify/git-chain. We do not track upstream
or maintain cherry-pick compatibility. If Shopify renews active development,
we can evaluate contributing features back, but we do not optimize for that.

## Security

- Do not commit secrets, API tokens, or credentials
- Forge adapters shell out to `gh`/`glab` which handle their own auth
- No API keys or tokens are stored in this repo
