"""Redis client wrapper for queue monitoring."""

import logging
from typing import Optional

import redis
from config import RedisConfig

logger = logging.getLogger(__name__)


class RedisClient:
    """Redis client wrapper with connection management and queue monitoring."""

    def __init__(self, config: RedisConfig):
        self.config = config
        self._client: Optional[redis.Redis] = None

    def connect(self) -> bool:
        """Establish connection to Redis."""
        try:
            self._client = redis.Redis(
                host=self.config.host,
                port=self.config.port,
                password=self.config.password,
                decode_responses=self.config.decode_responses,
                socket_connect_timeout=5,
                socket_timeout=5,
                retry_on_timeout=True,
            )
            self._client.ping()
            logger.info(f"Connected to Redis at {self.config.host}:{self.config.port}")
            return True
        except redis.ConnectionError as e:
            logger.error(f"Failed to connect to Redis at {self.config.host}: {str(e)}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error connecting to Redis: {str(e)}")
            return False

    def disconnect(self):
        """Close Redis connection."""
        if self._client:
            try:
                self._client.close()
                logger.info("Redis connection closed")
            except Exception as e:
                logger.warning(f"Error closing Redis connection: {str(e)}")
            finally:
                self._client = None

    def is_connected(self) -> bool:
        """Check if Redis connection is active."""
        if not self._client:
            return False
        try:
            self._client.ping()
            return True
        except redis.ConnectionError:
            return False

    def get_queue_length(self, queue_prefix: str, queue_name: str) -> int:
        """
        Get the length of a BullMQ queue.

        Tries multiple key patterns used by different BullMQ versions:
        - v3+: <prefix>:<name>:wait
        - v4+: <prefix>:<name>:waiting
        - legacy: <prefix>:<name>
        """
        if not self._client:
            logger.error("Redis client not connected")
            return 0

        # Try different BullMQ key patterns
        key_patterns = [
            f"{queue_prefix}:{queue_name}:wait",  # BullMQ v3+
            f"{queue_prefix}:{queue_name}:waiting",  # BullMQ v4+
            f"{queue_prefix}:{queue_name}",  # Legacy pattern
        ]

        for key_pattern in key_patterns:
            try:
                length = self._client.llen(key_pattern)
                if length is not None and length >= 0:
                    logger.debug(f"Queue length retrieved from {key_pattern}: {length}")
                    return length
            except redis.ResponseError as e:
                logger.debug(f"Key not a list or doesn't exist {key_pattern}: {str(e)}")
                continue
            except Exception as e:
                logger.warning(f"Error checking queue key {key_pattern}: {str(e)}")
                continue

        # If none of the patterns worked
        logger.warning(
            f"No valid queue keys found from {key_patterns}, assuming length 0"
        )
        return 0

    def get_queue_stats(self, queue_prefix: str, queue_name: str) -> dict:
        """Get comprehensive queue statistics."""
        if not self._client:
            return {}

        stats = {}
        queue_states = ["wait", "waiting", "active", "completed", "failed", "delayed"]

        for state in queue_states:
            key = f"{queue_prefix}:{queue_name}:{state}"
            try:
                count = self._client.llen(key) or 0
                stats[state] = count
            except Exception:
                stats[state] = 0

        return stats
