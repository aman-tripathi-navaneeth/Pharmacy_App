from typing import Any

from pymongo import AsyncMongoClient
from pymongo.server_api import ServerApi


def create_mongo_client(uri: str) -> AsyncMongoClient[dict[str, Any]]:
    """Create the async Atlas client. Keep credentials on the server only."""
    return AsyncMongoClient(uri, server_api=ServerApi("1"))
