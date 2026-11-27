#!/bin/bash
# Regenerates THIRD_PARTY_NOTICES.md from the resolved Swift packages.
# Run after changing dependencies: scripts/gen-notices.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHECKOUTS="${CHECKOUTS:-build/SourcePackages/checkouts}"
if [ ! -d "$CHECKOUTS" ]; then
  xcodebuild -resolvePackageDependencies -project Lingo.xcodeproj -scheme Lingo \
    -clonedSourcePackagesDirPath build/SourcePackages >/dev/null
fi

entry() { # name, url, license file
  printf '## %s\n\n%s\n\n```\n' "$1" "$2"
  cat "$3"
  printf '\n```\n\n'
}

{
  echo "# Third-party notices"
  echo
  echo "Lingo includes the following open-source software. Their licenses are reproduced below."
  echo
  entry "mlx-audio-swift" "https://github.com/Blaizzy/mlx-audio-swift" "$CHECKOUTS/mlx-audio-swift/LICENSE"
  entry "mlx-swift" "https://github.com/ml-explore/mlx-swift" "$CHECKOUTS/mlx-swift/LICENSE"
  entry "MLX" "https://github.com/ml-explore/mlx" "$CHECKOUTS/mlx-swift/Source/Cmlx/mlx/LICENSE"
  entry "mlx-c" "https://github.com/ml-explore/mlx-c" "$CHECKOUTS/mlx-swift/Source/Cmlx/mlx-c/LICENSE"
  entry "metal-cpp" "https://developer.apple.com/metal/cpp/" "$CHECKOUTS/mlx-swift/Source/Cmlx/metal-cpp/LICENSE.txt"
  entry "fmt" "https://github.com/fmtlib/fmt" "$CHECKOUTS/mlx-swift/Source/Cmlx/fmt/LICENSE"
  entry "JSON for Modern C++" "https://github.com/nlohmann/json" "$CHECKOUTS/mlx-swift/Source/Cmlx/json/LICENSE.MIT"
  entry "mlx-swift-lm" "https://github.com/ml-explore/mlx-swift-lm" "$CHECKOUTS/mlx-swift-lm/LICENSE"
  entry "KeyboardShortcuts" "https://github.com/sindresorhus/KeyboardShortcuts" "$CHECKOUTS/KeyboardShortcuts/license"
  entry "swift-transformers" "https://github.com/huggingface/swift-transformers" "$CHECKOUTS/swift-transformers/LICENSE"
  entry "swift-huggingface" "https://github.com/huggingface/swift-huggingface" "$CHECKOUTS/swift-huggingface/LICENSE"
  entry "swift-jinja" "https://github.com/huggingface/swift-jinja" "$CHECKOUTS/swift-jinja/LICENSE"
  entry "EventSource" "https://github.com/mattt/EventSource" "$CHECKOUTS/EventSource/LICENSE.md"
  entry "yyjson" "https://github.com/ibireme/yyjson" "$CHECKOUTS/yyjson/LICENSE"
  entry "swift-crypto" "https://github.com/apple/swift-crypto" "$CHECKOUTS/swift-crypto/LICENSE.txt"
  entry "swift-asn1" "https://github.com/apple/swift-asn1" "$CHECKOUTS/swift-asn1/LICENSE.txt"
  entry "swift-collections" "https://github.com/apple/swift-collections" "$CHECKOUTS/swift-collections/LICENSE.txt"
  entry "swift-numerics" "https://github.com/apple/swift-numerics" "$CHECKOUTS/swift-numerics/LICENSE.txt"
} > THIRD_PARTY_NOTICES.md
echo "Wrote THIRD_PARTY_NOTICES.md"
