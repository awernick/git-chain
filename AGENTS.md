# AGENTS.md - git-chain

## Overview

Fork of [Shopify/git-chain](https://github.com/Shopify/git-chain) with
additional features for stacked PR workflows. A Ruby CLI tool that manages
chains of dependent git branches, handling rebasing, pushing, and status
tracking across the stack.

This fork adds: chain status with tree view, forge abstraction
(GitHub/GitLab), and is actively developing sync, PR creation, and landing
features.

## Build / Test Commands

```bash
# Install dependencies
bundle install

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

The project targets Ruby 2.6+ (rubocop enforces this via
`TargetRubyVersion: 2.6`). Development uses Ruby 3.2 via rbenv
(`.ruby-version` is 3.2.11). rbenv auto-activates the correct version
when entering the project directory:

```bash
rbenv install 3.2.11   # one-time setup
bundle install
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
- `a-b-c-chain` - Three branches (a, b, c) in a chain
- `a-b-conflicts` - Two branches with conflicting changes
- `a-b-merged-chain` - Chain with a merged branch
- `doc-example` - Example chain for documentation
- `orphan` - Orphan branch scenario

Verify with: `ls fixtures/*.sh`

## Definition of Done

A task is complete when:
1. `bundle exec rake test` exits 0
2. `bundle exec rubocop` exits 0
3. Changes are committed following conventional commits
4. Commits reference a tracked issue (footer: `Closes #N` or `Fixes #N`)

## When Blocked

- If a test fails after 3 attempts: stop and report the failure with full output
- If a dependency or gem is missing: run `bundle install`, then retry
- If a fixture doesn't cover your test case: create a new one in `fixtures/`
- If requirements are ambiguous: ask for clarification, don't guess
- Never: delete tests to resolve errors, skip rubocop, or force push

## Repository Structure

```
bin/git-chain              # Entry point (executable)
lib/git_chain/
  commands/                # Command implementations (one file per command)
  forge/                   # Forge adapters: GitHub (gh), GitLab (glab)
  models/                  # Branch and Chain data models
  git.rb                   # Git command wrapper (shells out via Open3)
fixtures/*.sh              # Shell scripts that create test git repos
test/git_chain/            # Minitest tests (mirrors lib/ structure)
vendor/deps/               # Vendored Shopify CLI framework (cli-kit, cli-ui)
```

## Architecture

See `docs/architecture.md` for full details (command pattern, chain
metadata, forge abstraction). Key constraints:

- **Output**: Use `Util::Output#puts` with cli-ui tags, not `$stdout.puts`
  or `Kernel#puts`. Verify: `grep -rn '\$stdout\.puts\|Kernel\.puts' lib/ test/`
- **Git operations (lib/)**: Use `GitChain::Git.exec` (raises on failure)
  or `Git.capture3` (check exit status). Do not use `%x`, backticks, or
  `system("git")` in lib/. Tests may shell out to git when simulating
  rebase-in-progress or setting up state.
- **Forge**: Use the `Forge` abstraction for PR/MR operations. Do not
  call `gh` or `glab` directly.
- **Commands**: Register new commands with `autoload` in `commands.rb`.

## Code Style

Style is enforced by `bundle exec rubocop` (exit 0 = pass). The rules
below are checked automatically; they're documented here for context.

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
- Use `assert_raises(Abort)` or `assert_raises(AbortSilent)` to match
  the error class raised by the code under test
- Use `--no-pr` flag in status tests to avoid forge CLI dependencies
- Skip tests that require external CLIs:
  ```ruby
  skip("gh not installed") unless gh_available?
  ```

### Adding a New Command

1. Create `lib/git_chain/commands/<name>.rb`
2. Inherit from `Command`, include `Options::ChainName` if needed
3. Add `autoload :<Name>, "git_chain/commands/<name>"` to `commands.rb`
   Verify: `grep -n 'autoload' lib/git_chain/commands.rb`
4. Create `test/git_chain/command/<name>_test.rb`
5. Create a fixture in `fixtures/` if existing ones don't cover your case
6. Verify: `bundle exec rake test && bundle exec rubocop`

### Adding a New Forge

1. Create `lib/git_chain/forge/<name>.rb` inheriting from `Forge::Base`
2. Implement `cli_available?` and `pr_for_branch`
3. Normalize state to `OPEN`/`MERGED`/`CLOSED`
4. Add autoload in `forge.rb`
   Verify: `grep -n 'autoload' lib/git_chain/forge.rb`
5. Add detection pattern in `Forge.from_remote_url`
6. Create `test/git_chain/forge/<name>_test.rb`
7. Verify: `bundle exec rake test && bundle exec rubocop`

## Git Workflow

- Branch from `main`; naming: `feat/<short-name>`, `fix/<short-name>`
- Follow [Conventional Commits](https://www.conventionalcommits.org/):
  `<type>(<scope>): <description>`
- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
- Scopes: `status`, `sync`, `push`, `forge`, `branch`, `pr`, `ruby`, `docs`
- Link issues in commit footer: `Closes #N`
- PRs target `main`, squash merge (one commit per PR on main)
- PR title follows conventional commit format
- This is an independent fork of Shopify/git-chain. We do not track
  upstream or maintain cherry-pick compatibility.

## Security

- Do not commit secrets, API tokens, or credentials
- Forge adapters shell out to `gh`/`glab` which handle their own auth
- No API keys or tokens are stored in this repo
