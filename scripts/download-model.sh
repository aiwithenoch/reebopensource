#!/bin/bash
# Downloads the Whisper model Reeb bundles into the app (~31 MB).
# Run once after cloning, before building.
set -e

DEST="$(cd "$(dirname "$0")/.." && pwd)/Reeb/ggml-tiny.en-q5_1.bin"

if [ -f "$DEST" ]; then
  echo "Model already present at $DEST"
  exit 0
fi

echo "Downloading ggml-tiny.en-q5_1.bin (~31 MB)…"
curl -L --fail --progress-bar \
  -o "$DEST" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q5_1.bin"

echo "Done → $DEST"
