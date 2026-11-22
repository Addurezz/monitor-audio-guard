#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
output="${1:-.build/Monitor-Audio-Guard-macOS.zip}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/monitor-audio-release.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
folder="$scratch/Monitor Audio Guard"
mkdir -p -- "$folder" "$(dirname -- "$output")"

for arch in arm64 x86_64; do
    xcrun swiftc -O -target "$arch-apple-macos15.0" -module-cache-path "$scratch/cache" \
        monitor-audio-guard.swift -o "$scratch/monitor-audio-guard-$arch"
done
xcrun lipo -create "$scratch/monitor-audio-guard-arm64" "$scratch/monitor-audio-guard-x86_64" \
    -output "$folder/monitor-audio-guard"
codesign --force --sign - "$folder/monitor-audio-guard"
xcrun lipo "$folder/monitor-audio-guard" -verify_arch arm64 x86_64
codesign --verify --strict --all-architectures "$folder/monitor-audio-guard"
install -m 755 setup.sh "$folder/setup.sh"

make_launcher() {
    local filename=$1
    shift
    {
        printf '%s\n' '#!/bin/bash' 'cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1'
        printf 'exec /bin/bash ./setup.sh%s\n' "${1:+ $1}"
    } > "$folder/$filename"
    chmod +x "$folder/$filename"
}

make_launcher Setup.command
make_launcher Uninstall.command --uninstall
ditto -c -k --keepParent "$folder" "$scratch/release.zip"
install -m 644 "$scratch/release.zip" "$output"
printf '%s\n' "$output"
