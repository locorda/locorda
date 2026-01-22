#!/bin/bash

# Script to copy sync-engine content locally for development
# Usage: ./copy-sync-engine-content.sh [path-to-sync-engine]

set -e

# Default to ../sync-engine if no path provided
SYNC_ENGINE_PATH="${1:-../sync-engine}"

# Check if sync-engine directory exists
if [ ! -d "$SYNC_ENGINE_PATH" ]; then
    echo "Error: sync-engine directory not found at: $SYNC_ENGINE_PATH"
    echo "Usage: $0 [path-to-sync-engine]"
    echo "Example: $0 ../sync-engine"
    exit 1
fi

# Check if required directories exist
if [ ! -d "$SYNC_ENGINE_PATH/spec/vocabularies" ]; then
    echo "Error: $SYNC_ENGINE_PATH/spec/vocabularies not found"
    exit 1
fi

if [ ! -d "$SYNC_ENGINE_PATH/spec/mappings" ]; then
    echo "Error: $SYNC_ENGINE_PATH/spec/mappings not found"
    exit 1
fi

echo "Copying sync-engine content from: $SYNC_ENGINE_PATH"

# Create target directory in public (for direct file access)
mkdir -p public/vocab
mkdir -p public/mappings

# Copy vocabularies
echo "Copying vocabularies..."
cp "$SYNC_ENGINE_PATH"/spec/vocabularies/*.ttl public/vocab/ 2>/dev/null || echo "  No vocabulary files found"

# Copy mappings
echo "Copying mappings..."
cp "$SYNC_ENGINE_PATH"/spec/mappings/*.ttl public/mappings/ 2>/dev/null || echo "  No mapping files found"

# Count copied files
VOCAB_COUNT=$(find public/vocab -name "*.ttl" 2>/dev/null | wc -l | tr -d ' ')
MAPPINGS_COUNT=$(find public/mappings -name "*.ttl" 2>/dev/null | wc -l | tr -d ' ')

echo "✓ Done!"
echo "  Vocabularies: $VOCAB_COUNT files"
echo "  Mappings: $MAPPINGS_COUNT files"
echo ""

# Extract metadata from TTL files
echo "Extracting metadata from TTL files..."
dart tools/extract_vocab_metadata.dart

echo ""
echo "You can now run 'npm run dev' or 'npm run build'"
