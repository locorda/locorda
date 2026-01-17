#!/bin/bash
set -e

echo "🧪 Verifying RDF code examples..."
echo ""

cd "$(dirname "$0")/examples/rdf"

echo "📦 Installing dependencies..."
dart pub get

echo ""
echo "🔍 Running example tests..."
dart test

echo ""
echo "✅ All examples verified successfully!"
