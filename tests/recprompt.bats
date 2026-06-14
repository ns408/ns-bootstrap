#!/usr/bin/env bats
# Tests for shell/functions/recprompt.sh
# bats runs under bash; the zsh-specific invariants are checked by shelling out to
# `zsh -c`. Behavioural bits (HISTSIZE, bindkey, Atuin/Starship pause) need an
# interactive shell and are verified manually, not here.

RECPROMPT="${BATS_TEST_DIRNAME}/../shell/functions/recprompt.sh"

@test "no-ops cleanly when sourced under bash (guard)" {
    run bash -c "source '${RECPROMPT}' && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "defines recprompt-on and recprompt-off under zsh" {
    run zsh -c "source '${RECPROMPT}'; whence -w recprompt-on && whence -w recprompt-off"
    [ "$status" -eq 0 ]
}

@test "recprompt-on replaces precmd_functions, recprompt-off restores it" {
    # PROMPT must be non-empty: recprompt uses saved-PROMPT as its is-active sentinel
    # (always true interactively; empty under a bare non-interactive zsh).
    run zsh -c "
        source '${RECPROMPT}'
        PROMPT='test%# '
        precmd_functions=(hook_a hook_b)
        recprompt-on >/dev/null 2>&1
        print -r -- \"on=\${#precmd_functions}\"
        recprompt-off >/dev/null 2>&1
        print -r -- \"off=\${precmd_functions[*]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"on=1"* ]]
    [[ "$output" == *"off=hook_a hook_b"* ]]
}

@test "second recprompt-on is guarded (no double snapshot)" {
    run zsh -c "
        source '${RECPROMPT}'
        PROMPT='test%# '
        recprompt-on >/dev/null 2>&1
        recprompt-on
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"already active"* ]]
}
