#!/usr/bin/env bats
# Rules for packages/Brewfile.work, the profile for a company-managed Mac:
# homebrew/core formulae only, nothing personal and nothing that needs a
# business licence. Licences themselves are checked against Homebrew by the
# Brew Bundle Check workflow, which needs the network.

setup() {
    PACKAGES="${BATS_TEST_DIRNAME}/../packages"
    WORK="${PACKAGES}/Brewfile.work"
}

# Entries, without comments or blank lines
entries() {
    grep -vE '^[[:space:]]*(#|$)' "$1"
}

formulae() {
    entries "$WORK" | sed -E 's/^brew "([^"]+)".*/\1/'
}

@test "Brewfile.work holds only plain formulae: no taps, casks or App Store apps" {
    run bash -c 'grep -vE "^[[:space:]]*(#|$)" "$1" | grep -vE "^brew \"[a-z0-9@+._-]+\"$"' _ "$WORK"
    [[ "$status" -eq 1 ]] || { echo "Not a plain formula line:"; echo "$output"; false; }
}

@test "Brewfile.work names no personal, VPN, tunnelling or scanning tool" {
    local denied="nmap sslscan telnet curl-impersonate doggo knot tor torsocks
        openvpn wireguard-tools wireguard-go sshuttle tailscale cloudflared ngrok
        signal-cli proxyman orbstack mas"
    local found=()
    while IFS= read -r f; do
        for d in $denied; do [[ "$f" == "$d" ]] && found+=("$f"); done
    done < <(formulae)
    [[ ${#found[@]} -eq 0 ]] || { echo "Not allowed in Brewfile.work: ${found[*]}"; false; }
}

@test "Brewfile.work lists each formula once" {
    run bash -c "$(declare -f formulae entries); WORK='$WORK'; formulae | sort | uniq -d"
    [[ -z "$output" ]] || { echo "Listed more than once: $output"; false; }
}

@test "every profile installs gitleaks, which the pre-push hook requires" {
    for f in "${PACKAGES}"/Brewfile.*; do
        grep -qx 'brew "gitleaks"' "$f" || { echo "No gitleaks in ${f##*/}"; false; }
    done
}
