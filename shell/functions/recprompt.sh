#!/usr/bin/env zsh
# Recording prompt (Starship + Atuin aware): recprompt-on / recprompt-off.
# Flip the terminal into a clean, minimal, history-paused state for screen-recorded
# demos, then restore it. Reversible; the snapshot is taken lazily inside recprompt-on
# so load order relative to Starship/Atuin does not matter.
# Source doc: impacteng-content/drafts/youtube/RECORDING-HYGIENE.md
# NOTE: recprompt-on sets HISTSIZE=0, discarding the current shell's in-memory history;
# HISTFILE on disk and Atuin's SQLite store are untouched.

# zsh-only (typeset -ga, precmd_functions, vcs_info, ${var##* }). loader.sh sources every
# functions/*.sh in both shells, so no-op cleanly under bash rather than erroring.
[[ -n "${ZSH_VERSION:-}" ]] || return 0

typeset -g _RECPROMPT_SAVED_PROMPT=""
typeset -g _RECPROMPT_SAVED_RPROMPT=""
typeset -ga _RECPROMPT_SAVED_PRECMD
typeset -ga _RECPROMPT_SAVED_PREEXEC
typeset -g _RECPROMPT_SAVED_HISTSIZE=""
typeset -g _RECPROMPT_SAVED_BIND_CR=""
typeset -g _RECPROMPT_SAVED_BIND_UP_RAW=""
typeset -g _RECPROMPT_SAVED_BIND_UP_APP=""
typeset -g _RECPROMPT_SAVED_BIND_DOWN_RAW=""
typeset -g _RECPROMPT_SAVED_BIND_DOWN_APP=""
typeset -g _RECPROMPT_SAVED_BIND_CP=""
typeset -g _RECPROMPT_SAVED_BIND_CN=""
typeset -g _RECPROMPT_SAVED_AUTOSUGGEST=""

_recprompt_vcs_update() { vcs_info }

_recprompt_restore_bindkey() {
    local saved="$1" key="$2" widget
    [[ -z "$saved" ]] && return 0
    # bindkey output format: "key" widget   (e.g. `"^R" atuin-search`)
    # Strip everything up to and including the last space, leaving the widget name.
    widget=${saved##* }
    if [[ -n "$widget" && "$widget" != "undefined-key" ]]; then
        bindkey "$key" "$widget"
    fi
}

recprompt-on() {
    if [[ -n "$_RECPROMPT_SAVED_PROMPT" ]]; then
        echo "Recording prompt already active. Run 'recprompt-off' first if you want a fresh start."
        return 0
    fi

    _RECPROMPT_SAVED_PROMPT="${PROMPT}"
    _RECPROMPT_SAVED_RPROMPT="${RPROMPT-}"
    _RECPROMPT_SAVED_PRECMD=("${precmd_functions[@]}")
    _RECPROMPT_SAVED_PREEXEC=("${preexec_functions[@]}")
    _RECPROMPT_SAVED_HISTSIZE="$HISTSIZE"
    _RECPROMPT_SAVED_BIND_CR=$(bindkey '^R')
    _RECPROMPT_SAVED_BIND_UP_RAW=$(bindkey '^[[A')
    _RECPROMPT_SAVED_BIND_UP_APP=$(bindkey '^[OA')
    _RECPROMPT_SAVED_BIND_DOWN_RAW=$(bindkey '^[[B')
    _RECPROMPT_SAVED_BIND_DOWN_APP=$(bindkey '^[OB')
    _RECPROMPT_SAVED_BIND_CP=$(bindkey '^P')
    _RECPROMPT_SAVED_BIND_CN=$(bindkey '^N')

    autoload -Uz vcs_info
    zstyle ':vcs_info:git:*' formats ' (%b)'

    # Pause Starship (precmd) and Atuin (precmd + preexec record).
    precmd_functions=(_recprompt_vcs_update)
    preexec_functions=()

    # Pause every key that surfaces history: Atuin search (^R), arrow history
    # (^[[A/^[OA/^[[B/^[OB), AND emacs-keymap history nav (^P/^N), plus zsh's native
    # history-search fallback.
    bindkey -r '^R' '^[[A' '^[OA' '^[[B' '^[OB' '^P' '^N' 2>/dev/null

    # Pause zsh-autosuggestions: its precmd hook is one-shot (installs ZLE widget
    # wrappers then removes itself), so clearing precmd_functions is not enough — it
    # would still show history-based suggestions as you type. Snapshot prior state so
    # recprompt-off only re-enables it if it was enabled before recording.
    if (( $+functions[_zsh_autosuggest_disable] )); then
        _RECPROMPT_SAVED_AUTOSUGGEST=$(( ${+_ZSH_AUTOSUGGEST_DISABLED} ))
        _zsh_autosuggest_disable
    fi

    # Belt-and-braces: zero in-memory history so even an accidental re-bind finds nothing.
    # NOTE: this discards the current shell's pre-recording in-memory history; daily
    # HISTFILE on disk and Atuin's SQLite store are untouched.
    HISTSIZE=0

    setopt PROMPT_SUBST
    PROMPT='%F{cyan}%1~%f%F{green}${vcs_info_msg_0_}%f %# '
    RPROMPT=''
    clear
    echo "Recording prompt active. Starship + Atuin + history search + autosuggestions paused. Run 'recprompt-off' to restore."
}

recprompt-off() {
    if [[ -z "$_RECPROMPT_SAVED_PROMPT" ]]; then
        echo "Recording prompt was not active."
        return 0
    fi

    PROMPT="${_RECPROMPT_SAVED_PROMPT}"
    RPROMPT="${_RECPROMPT_SAVED_RPROMPT}"
    precmd_functions=("${_RECPROMPT_SAVED_PRECMD[@]}")
    preexec_functions=("${_RECPROMPT_SAVED_PREEXEC[@]}")
    HISTSIZE="$_RECPROMPT_SAVED_HISTSIZE"

    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_CR"        '^R'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_UP_RAW"    '^[[A'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_UP_APP"    '^[OA'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_DOWN_RAW"  '^[[B'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_DOWN_APP"  '^[OB'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_CP"        '^P'
    _recprompt_restore_bindkey "$_RECPROMPT_SAVED_BIND_CN"        '^N'

    # Re-enable autosuggestions only if it was enabled before recprompt-on.
    if (( $+functions[_zsh_autosuggest_enable] )) && [[ "$_RECPROMPT_SAVED_AUTOSUGGEST" == 0 ]]; then
        _zsh_autosuggest_enable
    fi

    _RECPROMPT_SAVED_PROMPT=""
    _RECPROMPT_SAVED_RPROMPT=""
    _RECPROMPT_SAVED_PRECMD=()
    _RECPROMPT_SAVED_PREEXEC=()
    _RECPROMPT_SAVED_HISTSIZE=""
    _RECPROMPT_SAVED_BIND_CR=""
    _RECPROMPT_SAVED_BIND_UP_RAW=""
    _RECPROMPT_SAVED_BIND_UP_APP=""
    _RECPROMPT_SAVED_BIND_DOWN_RAW=""
    _RECPROMPT_SAVED_BIND_DOWN_APP=""
    _RECPROMPT_SAVED_BIND_CP=""
    _RECPROMPT_SAVED_BIND_CN=""
    _RECPROMPT_SAVED_AUTOSUGGEST=""

    echo "Daily prompt restored. Starship + Atuin + history search + autosuggestions re-enabled."
}
