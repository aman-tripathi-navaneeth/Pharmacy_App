# Module packages

Each module has its own folder, README, and `router.py`. The starter intentionally registers only the inventory scaffold router in `app/api/v1/router.py`. Coordinate module router registration so concurrent branches do not overwrite the shared router file. Add authentication and store-level authorization before exposing real store data.
