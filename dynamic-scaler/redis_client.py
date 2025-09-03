"""Redis client for queue monitoring in Dynamic Scaler."""

from typing import Optional

import redis
import structlog
from config import QueueConfig, RedisConfig

logger = structlog.get_logger()


class RedisClient:
    """Redis client for monitoring queue metrics."""

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
                decode_responses=True,
                socket_connect_timeout=10,
                socket_timeout=10,
                retry_on_timeout=True,
            )
            self._client.ping()
            logger.info(
                "Connected to Redis",
                host=self.config.host,
                port=self.config.port,
            )
            return True
        except redis.ConnectionError as e:
            logger.error(
                "Failed to connect to Redis",
                error=str(e),
                host=self.config.host,
            )
            return False
        except Exception as e:
            logger.error("Unexpected error connecting to Redis", error=str(e))
            return False

    def disconnect(self):
        """Close Redis connection."""
        if self._client:
            try:
                self._client.close()
                logger.info("Redis connection closed")
            except Exception as e:
                logger.warning("Error closing Redis connection", error=str(e))
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

    def get_queue_length(self, queue_config: QueueConfig) -> int:
        """
        Get the length of the waiting queue.

        Returns the number of jobs waiting to be processed.
        """
        if not self._client:
            logger.error("Redis client not connected")
            return 0

        # Try different BullMQ key patterns
        key_patterns = [
            queue_config.get_queue_key("wait"),  # BullMQ v3+
            queue_config.get_queue_key("waiting"),  # BullMQ v4+
            f"{queue_config.name_prefix}:{queue_config.name}",  # Legacy
        ]

        for key_pattern in key_patterns:
            try:
                length = self._client.llen(key_pattern)
                if length is not None and length >= 0:
                    logger.debug(
                        "Queue length retrieved",
                        key=key_pattern,
                        length=length,
                    )
                    return length
            except redis.ResponseError as e:
                logger.debug(
                    "Key not found or not a list", key=key_pattern, error=str(e)
                )
                continue
            except Exception as e:
                logger.warning(
                    "Error checking queue key", key=key_pattern, error=str(e)
                )
                continue

        logger.warning(
            "No valid queue keys found, assuming length 0", patterns=key_patterns
        )
        return 0
