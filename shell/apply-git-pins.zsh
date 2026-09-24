# Sourced by .zshrc before oh-my-zsh loads. When packages/git-pins has changed
# since this account last applied it (after a merged pin bump is pulled), it
# runs install/common/sync-git-pins.sh once, so oh-my-zsh and the plugins follow
# reviewed pins in every account that opens a shell, with no scheduler.
#
# An ordinary shell start only compares the pin file with the copy the sync
# recorded, using zsh builtins, so it costs no process and no network.

() {
  emulate -L zsh

  local root=$1
  local pins=$root/packages/git-pins
  local state=${XDG_CACHE_HOME:-$HOME/.cache}/ns-bootstrap
  local applied=$state/git-pins.applied failed=$state/git-pins.failed
  local lock=$state/git-pins.lock log=$HOME/.local/log/git-pins.log

  [[ -r $pins ]] || return 0
  local current="$(<$pins)"
  [[ -r $applied && $current == "$(<$applied)" ]] && return 0

  # This exact pin list failed within the hour (offline, say): wait, rather
  # than retrying on every shell. A different pin list is tried at once.
  local -a recent=( $failed(N.mm-60) )
  (( $#recent )) && [[ $current == "$(<$failed)" ]] && return 0

  mkdir -p $state ${log:h}
  # One shell applies at a time; a lock left by a killed shell expires.
  local -a stale=( $lock(N/mm+10) )
  (( $#stale )) && rmdir $lock 2>/dev/null
  mkdir $lock 2>/dev/null || return 0

  print -P "%F{cyan}ns-bootstrap:%f pinned plugins changed, applying..."
  if bash $root/install/common/sync-git-pins.sh >> $log 2>&1; then
    rm -f $failed
    print -P "%F{cyan}ns-bootstrap:%f done (details in ${log/#$HOME/~})"
  else
    print -r -- $current > $failed
    print -P "%F{yellow}ns-bootstrap:%f some pins were not applied, see ${log/#$HOME/~}; will retry within the hour"
  fi
  rmdir $lock
} ${${(%):-%x}:A:h:h}
