# TODO

Tracking future improvements and automation opportunities.

## GitHub Actions — Recurring Maintenance

- [ ] **Brewfile staleness checker** — Monthly job to flag deprecated/removed formulae and casks (see `.github/workflows/brew-check.yml` for starting point)
- [ ] **Oh-My-Zsh plugin version check** — Verify plugins in `.zshrc` still exist in the OMZ repo and check for renamed/deprecated plugins
- [ ] **Shell tool version tracker** — Check for new releases of tools installed via binary download or curl (atuin, mise, doggo) and open issues when updates are available
- [ ] **apt package audit** — Validate `apt-packages.*` lists against Ubuntu 24.04 package index, flag removed or renamed packages
- [ ] **Starship config validator** — Check `starship.toml` modules against the latest Starship schema for deprecated keys
- [ ] **ShellCheck severity escalation** — Gradually tighten ShellCheck from `warning` to `info` as issues are resolved
- [ ] **macOS version compatibility** — Test bootstrap on latest macOS runner to catch Homebrew/Xcode CLI tools changes early

## Features

- [ ] **Dotfile diff preview** — `bootstrap.sh --dry-run` flag to show what would change without modifying anything
- [ ] **Restore from backup** — `bootstrap.sh --restore <timestamp>` to roll back dotfiles from `~/.dotfiles-backup/`
- [ ] **Profile upgrade path** — Allow upgrading from `minimal` to `developer` without re-running the full bootstrap
- [ ] **Ubuntu dotfiles-only mode** — Extend `--dotfiles-only` to also work for bash on Ubuntu (currently zsh-focused)

## Security

- [ ] **Supply chain audit for git-cloned plugins** — Verify integrity of OMZ plugins (zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, fzf-tab) and vim plugins (fzf.vim, vim-ruby) by pinning to specific commit SHAs or tags rather than cloning HEAD
- [ ] **Binary provenance verification** — Create a plan to verify downloaded binaries (atuin via curl, mise, doggo snap) against published checksums or signatures; consider using Homebrew/apt as the sole install path where possible
- [ ] **GitHub Actions for dependency scanning** — Automated weekly check of cloned plugin repos for known vulnerabilities, compromised maintainers, or unexpected force-pushes (compare pinned SHAs against upstream)
- [ ] **Homebrew formula audit** — Verify all Brewfile entries install from official taps (no third-party taps with unreviewed code)
- [ ] **npm audit integration** — Even with `ignore-scripts=true`, run `npm audit` periodically on any Node projects bootstrapped by mise
- [ ] **Shell function injection review** — Audit all `eval "$(tool init zsh)"` calls (starship, zoxide, atuin, mise, brew shellenv) for unexpected side effects; consider redirecting init output to a cached file and diffing on update

## Housekeeping

- [ ] **Secrets rotation reminder** — GitHub Action to open an issue quarterly reminding to rotate API tokens
- [ ] **README badge** — Add CI status badge once lint workflow is confirmed working
- [ ] **Bats test coverage** — Add tests for `install-modern-tools.sh`, `bootstrap-secrets.sh`, and shell functions
