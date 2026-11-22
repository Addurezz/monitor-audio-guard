#!/bin/bash
set -euo pipefail

label=io.github.monitor-audio-guard
domain="gui/$(id -u)"
service="$domain/$label"
agent_dir="$HOME/Library/LaunchAgents"
plist="$agent_dir/$label.plist"
app_dir="$HOME/Library/Application Support/Monitor Audio Guard"
binary="$app_dir/monitor-audio-guard"
log="$HOME/Library/Logs/$label.log"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

stop_agent() {
    if launchctl print "$service" >/dev/null 2>&1; then
        launchctl bootout "$service"
    fi
}

if [[ ${1:-} == --uninstall && $# == 1 ]]; then
    stop_agent
    rm -f -- "$plist" "$binary"
    printf 'Monitor Audio Guard was uninstalled. Your current audio output is still selected.\n'
    exit 0
fi

if [[ $# != 0 ]]; then
    printf 'Usage: ./setup.sh [--uninstall]\n'
    if [[ $# == 1 && $1 == --help ]]; then exit 0; fi
    exit 2
fi

version=$(sw_vers -productVersion)
if (( ${version%%.*} < 15 )); then
    printf 'Monitor Audio Guard requires macOS 15 or later.\n' >&2
    exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/monitor-audio-guard.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
program="$source_dir/monitor-audio-guard"
if [[ ! -x "$program" ]]; then
    program="$scratch/monitor-audio-guard"
    swiftc -O -module-cache-path "$scratch/cache" "$source_dir/monitor-audio-guard.swift" -o "$program"
fi

choices=$("$program" --outputs)
if [[ -z $choices ]]; then
    printf 'No eligible audio outputs found. Connect your speakers or headphones and retry.\n' >&2
    exit 1
fi

uids=()
names=()
while IFS=$'\t' read -r uid name; do
    [[ -n $uid && -n $name ]] || continue
    uids+=("$uid")
    names+=("$name")
done <<< "$choices"
if [[ ${#uids[@]} == 0 ]]; then
    printf 'No eligible audio outputs found.\n' >&2
    exit 1
fi

printf 'Choose your default audio output.\n' >&2
PS3='Enter a number: '
preferred=
select name in "${names[@]}"; do
    if [[ -n $name && $REPLY =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        preferred=${uids[10#${BASH_REMATCH[1]}-1]}
        break
    fi
    printf 'Choose a number from the list.\n' >&2
done
[[ -n $preferred ]] || exit 1

new_plist="$scratch/agent.plist"
plutil -create xml1 "$new_plist"
plutil -insert Label -string "$label" "$new_plist"
plutil -insert ProgramArguments -json '[]' "$new_plist"
plutil -insert ProgramArguments.0 -string "$binary" "$new_plist"
plutil -insert ProgramArguments.1 -string --preferred "$new_plist"
plutil -insert ProgramArguments.2 -string "$preferred" "$new_plist"
plutil -insert KeepAlive -bool YES "$new_plist"
plutil -insert StandardErrorPath -string "$log" "$new_plist"
plutil -lint "$new_plist" >/dev/null

"$program" --preferred "$preferred" --set-default
mkdir -p -- "$app_dir" "$agent_dir" "$(dirname -- "$log")"
stop_agent
install -m 755 "$program" "$binary"
install -m 644 "$new_plist" "$plist"
launchctl bootstrap "$domain" "$plist"
printf 'Monitor Audio Guard is running and will start when you sign in.\n'
