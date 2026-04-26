import json
from typing import Any

import redis.asyncio as aioredis

from .config import settings

_redis: aioredis.Redis | None = None


def _get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis


async def cache_get(key: str) -> Any | None:
    val = await _get_redis().get(key)
    return json.loads(val) if val is not None else None


async def cache_set(key: str, value: Any, ttl: int = 300) -> None:
    await _get_redis().set(key, json.dumps(value), ex=ttl)


async def cache_delete(*keys: str) -> None:
    if keys:
        await _get_redis().delete(*keys)
