#!/bin/bash
set -e

echo "🧪 Verifying RDF code examples..."
echo ""

# Verify core examples
echo "📦 Core: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/core"
dart pub get

echo ""
echo "🔍 Core: Running example tests..."
dart test

popd

# Verify mapper examples
echo ""
echo "📦 Mapper: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/mapper"
dart pub get

echo ""
echo "⚙️ Mapper: Generating code..."
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "🔍 Mapper: Running example tests..."
dart test
popd

# Verify mapper annotations examples
echo ""
echo "📦 Mapper Annotations: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/mapper/annotations"
dart pub get

echo ""
echo "⚙️ Mapper Annotations: Generating code..."
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "🔍 Mapper Annotations: Running example tests..."
dart test
popd

# Verify canonicalization examples
echo ""
echo "📦 Canonicalization: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/canonicalization"
dart pub get

echo ""
echo "🔍 Canonicalization: Running example tests..."
dart test
popd

# Verify XML examples
echo ""
echo "📦 XML: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/xml"
dart pub get

echo ""
echo "🔍 XML: Running example tests..."
dart test
popd

# Verify vocabularies examples
echo ""
echo "📦 Vocabularies: Installing dependencies..."
pushd "$(dirname "$0")/examples/rdf/vocabularies"
dart pub get

echo ""
echo "🔍 Vocabularies: Running example tests..."
dart test
popd

echo ""
echo "✅ All examples verified successfully!"
