# Contributing

## Before coding
1. Read the module map and API conventions.
2. Confirm the input/output contract with any module that consumes your feature.
3. Raise a GitHub issue or agree on a task so parallel work does not collide.

## Branches and commits
- Branch examples: `feature/inventory-batches`, `feature/purchase-scan`, `fix/duplicate-sales-report`.
- Use descriptive commits, for example: `Add batch quantity validation`.
- Do not commit generated files, secrets, database exports, or real pharmacy/customer records.

## Pull requests
- Explain the user-visible outcome and affected modules.
- Add or update tests. Include exact commands run and results.
- Call out API, collection, index, environment-variable, and migration changes.
- Include screenshots for UI changes.
- Request review from a teammate; merge only after checks and contract review.

## Shared files
Changes to API router registration, shared settings, common schemas, authentication, and database conventions can affect every module. Coordinate these changes before opening a PR.
