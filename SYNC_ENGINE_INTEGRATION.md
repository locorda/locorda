# Sync-Engine Integration Setup

This document describes the integration between `locorda/locorda` (homepage) and `locorda/sync-engine` repositories.

## What Was Done

The GitHub Actions workflow at [.github/workflows/deploy.yml](.github/workflows/deploy.yml) has been updated to:

1. **Accept triggers from sync-engine**: Added `repository_dispatch` with type `sync-engine-update`
2. **Checkout both repositories**: Homepage and sync-engine are checked out during the build
3. **Setup Flutter and Melos**: Required for building the sync-engine Flutter example app
4. **Build sync-engine artifacts**: 
   - Bootstrap the melos workspace
   - Build the Flutter web app
   - Copy vocabularies, mappings, and the example app to the deployment directory
5. **Deploy combined content**: Everything is deployed together to GitHub Pages

## What Still Needs to Be Done

### 1. Setup in `locorda/sync-engine` Repository

You need to add a workflow in the sync-engine repository that triggers this homepage deployment when content changes.

#### Add Personal Access Token Secret

In the `locorda/sync-engine` repository:

1. Go to Settings → Secrets and variables → Actions
2. Add new repository secret: `HOMEPAGE_DISPATCH_TOKEN`
3. Create a fine-grained Personal Access Token (PAT) with:
   - Repository access: Only `locorda/locorda`
   - Permissions: Actions (read and write)

#### Create Trigger Workflow

Create `.github/workflows/trigger-homepage-deploy.yml` in `locorda/sync-engine`:

```yaml
name: Trigger Homepage Deployment

on:
  push:
    branches: [main]
    paths:
      - 'spec/vocabularies/**'
      - 'spec/mappings/**'
      - 'packages/locorda/example/**'

jobs:
  trigger:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger homepage deployment
        run: |
          curl -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${{ secrets.HOMEPAGE_DISPATCH_TOKEN }}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            https://api.github.com/repos/locorda/locorda/dispatches \
            -d '{"event_type":"sync-engine-update"}'
```

## Resulting URL Structure

After deployment, content will be available at:

```
locorda.dev/
├── rdf/                                    # RDF section (existing)
├── vocab/                                  # Vocabularies (*.ttl)
│   ├── crdt-algorithms.ttl
│   ├── crdt-mechanics.ttl
│   ├── idx.ttl
│   └── sync.ttl
├── mappings/                               # Core mappings (*.ttl)
│   └── core-v1.ttl
├── example/personal_notes_app/             # Example Flutter app
│   ├── mappings/                           # App-specific mappings
│   │   ├── category-v1.ttl
│   │   └── note-v1.ttl
│   ├── auth/
│   │   └── client-config.json
│   └── [flutter web app files]
└── ...
```

## w3id.org Redirects

The existing w3id.org redirects should work unchanged:

```
https://w3id.org/solid-crdt-sync/vocab/crdt-algorithms
  → https://locorda.dev/vocab/crdt-algorithms.ttl

https://w3id.org/solid-crdt-sync/mappings/core-v1
  → https://locorda.dev/mappings/core-v1.ttl
```

**No changes needed to existing w3id.org configuration.**

## Testing the Integration

1. After setting up the trigger workflow in sync-engine:
   - Push a change to `sync-engine/spec/vocabularies/` or the example app
   - Check Actions in `locorda/sync-engine` - should see trigger workflow run
   - Check Actions in `locorda/locorda` - should see deployment triggered
   - Verify content at `locorda.dev/sync-engine/vocab/` etc.

2. Manual testing:
   - You can manually trigger the homepage deployment:
     - Go to Actions tab in this repository
     - Select "Deploy to GitHub Pages" workflow
     - Click "Run workflow"

## Troubleshooting

**Trigger doesn't work:**
- Verify `HOMEPAGE_DISPATCH_TOKEN` secret exists in sync-engine repo
- Check token has correct permissions (Actions: read and write)
- Look for curl errors in trigger workflow logs
- Verify the token was created for the correct repository

**Content missing after deployment:**
- Check paths in the workflow match the sync-engine repository structure
   - Verify Flutter base-href matches deployment path (`/example/personal_notes_app/`)
- Ensure all source files exist in sync-engine repo

**Old content still deployed:**
- Clear GitHub Pages cache by making a trivial commit
- Check that both workflows completed successfully
- Verify the artifact upload step includes the new content

**Flutter build fails:**
- Check Flutter version compatibility (currently set to 3.35.4)
- Verify melos bootstrap completed successfully
- Check for any dependency issues in sync-engine

## Architecture Notes

- The homepage build now takes longer due to Flutter compilation
- All sync-engine content is rebuilt on every homepage deployment
- The integration is stateless - no caching between builds
- Both repositories are checked out fresh on each run
