#!/usr/bin/env bash
# Shared helper: strip AI-attribution lines from a commit message file.
# Sourced by prepare-commit-msg and commit-msg. Installed by ns-bootstrap.
#
# Removes: Co-Authored-By trailers naming an AI tool, "Generated with <tool>"
# footers, and robot-emoji lines. Trailing blank lines left behind are trimmed.
strip_ai_trailers() {
    local msg_file="$1"
    [ -f "$msg_file" ] || return 0
    local tools='Claude|Claude Code|Copilot|GitHub Copilot|GPT|ChatGPT|OpenAI|Anthropic|Gemini|Codeium|Cursor|Windsurf|Codex|Aider|Cody'
    local pattern="(^Co-Authored-By:.*(${tools})|Generated with.*(${tools})|🤖)"
    if grep -qiE "$pattern" "$msg_file"; then
        grep -ivE "$pattern" "$msg_file" > "${msg_file}.tmp" || true
        # Collapse trailing blank lines (portable across macOS and Linux).
        awk '/^[[:space:]]*$/ { blank = blank "\n"; next } { printf "%s%s\n", blank, $0; blank = "" }' \
            "${msg_file}.tmp" > "$msg_file"
        rm -f "${msg_file}.tmp"
    fi
}
