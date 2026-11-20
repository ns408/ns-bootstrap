# Settings

ns-bootstrap reads a small set of settings. This page lists them all, and it is the contract for anything that configures a machine from outside the repository, such as a private machine-config repository: write the files named here, and never edit the clone.

## Where a setting comes from

Each setting is taken from the first place that has it:

1. the environment (an exported, non-empty variable);
2. `~/.config/ns-bootstrap/settings`;
3. the default for the profile.

`~/.config/ns-bootstrap/settings` is a file you own and ns-bootstrap never writes. Each line is `KEY=value`; quotes are optional, `#` starts a comment, and the last line for a key wins. The file is read, never run, so `$(...)` in it stays text. Start from [settings.example](settings.example).

A bad value stops `bootstrap.sh` with exit status 2 and names the setting.

## Bootstrap and updates

| Setting | Values | Personal default | Work default | Effect |
|---|---|---|---|---|
| `NS_BOOTSTRAP_EXTRA_APPS` | `on`, `off` | `on` | `off` (cannot be `on`) | The self-updating apps step (browsers, messaging, VPNs and others). |
| `NS_BOOTSTRAP_DAILY_UPDATE` | `on`, `off` | `on` | `off` | Installs the daily update LaunchAgent, or removes it. The daily job also checks this each time it runs. |
| `NS_BOOTSTRAP_DAILY_SCOPE` | `all`, `formulae` | `all` | `formulae` | `formulae` upgrades Homebrew formulae only, leaving casks, App Store and Microsoft apps alone, in the daily job and in `update-my-system`. |
| `NS_BOOTSTRAP_BREWFILE_LOCAL` | a path | unset | unset | A Brewfile of your own (apps the company prefers, say), installed after the profile's. A leading `~/` is expanded. |
| `HOMEBREW_NO_ANALYTICS` | any value | unchanged | `1` | Turns Homebrew analytics off. Homebrew's own variable. |

## Secrets and git identity

| Setting | Values | Default | Effect |
|---|---|---|---|
| `NS_BOOTSTRAP_OP_VAULT` | a vault name | `Personal` | The 1Password vault for the `ns-bootstrap` item. A business account's own vault is usually `Employee`. |
| `NS_BOOTSTRAP_OP_ACCOUNT` | an account | unset | Which 1Password account `op` uses (set as `OP_ACCOUNT`). |
| `NS_BOOTSTRAP_SECRETS_PROVIDER` | `none`, `1password` | `none` (work only) | Work: `1password` also keeps the work name, email and key in the item's `Git Work` section. A failing `op` only warns. |
| `NS_BOOTSTRAP_GIT_NAME`, `NS_BOOTSTRAP_GIT_EMAIL` | text | unset (work only) | The work identity, so `secrets/work-secrets.sh --yes` needs no prompts. |
| `NS_BOOTSTRAP_GIT_SIGNING` | `none`, `ssh-file`, `1password`, `gpg` | `none` (work only) | How work commits are signed. |
| `NS_BOOTSTRAP_GIT_SIGNING_KEY` | key file, public key, or GPG key ID | unset (work only) | The key for the signing method. |

## Git keys

These are git settings, read by the global hooks each time they run, so they can be set globally or per repository with `git config`.

| Key | Default | Effect |
|---|---|---|
| `ns-bootstrap.chainRepoHooks` | `false`; `true` on work | Each global hook also runs the repository's own hook of the same name, and Git LFS's where the repository has LFS objects. |
| `ns-bootstrap.stripAiTrailers` | `true` | Set `false` where a repository or employer requires AI-disclosure trailers. |
| `ns-bootstrap.pushScanners` | `true` | Set `false` to skip OSV-Scanner and Trivy on push. gitleaks always runs. |
| `publish-boundary.gate` | unset | A publish gate for pre-push to run; see the comments in `dotfiles/git/hooks/pre-push`. |

## Files ns-bootstrap reads and writes in your home directory

| File | Written by | Holds |
|---|---|---|
| `~/.config/ns-bootstrap/settings` | you | The settings above. |
| `~/.zshrc.local` | you | Personal shell additions, sourced last by ns-bootstrap's `.zshrc`. |
| `~/.config/ns-bootstrap/config` | bootstrap | Machine values, such as where the clone is. |
| `~/.config/ns-bootstrap/profile` | bootstrap | `work`, on a Mac set up with the work profile. Delete it to choose another profile. |
| `~/.config/ns-bootstrap/gitconfig` | `secrets/work-secrets.sh` | The work git identity and shared git settings, included from `~/.config/git/config`. |

A machine-config repository therefore needs only to write `~/.config/ns-bootstrap/settings` and `~/.zshrc.local`, then run `bootstrap.sh`.
