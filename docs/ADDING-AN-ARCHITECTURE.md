# Adding an architecture

Each architecture lives in its own folder under `architectures/` and must be deployable and removable without touching any other folder.

## Steps

1. Copy the folder structure of `architectures/01-transit-hub-peering-ad/` as a starting point.
2. Name the folder `NN-short-descriptive-name` (for example `02-enclave-only`).
3. Write a `README.md` in the folder using the template below.
4. Add a row to the **Architectures** table in the root `README.md`.

## Folder conventions

```
architectures/NN-name/
  README.md
  Deploy-<Name>.ps1      # deploy / resume / teardown
  bicep/
    <name>.bicepparam    # the one settings file users edit
    modules/
  scripts/               # validation scripts
```

## README template

```markdown
# Architecture NN: <title>

One or two sentences on what this shows.

## Architecture
<mermaid diagram + table of resources>

## Prerequisites
## Quick start
## Stages
## Configuration
## Validate
## Teardown
## Troubleshooting
## Cost and known caveats
```

## Checklist before publishing

- [ ] No customer, company, or employee names; use `contoso` and example IP ranges.
- [ ] No subscription IDs, tenant IDs, object IDs, emails, or passwords.
- [ ] Secrets come from prompts or environment variables, never from files.
- [ ] `bicep build` passes for every template.
- [ ] Teardown removes everything the deployment created.
- [ ] Cost drivers are listed in the README.
