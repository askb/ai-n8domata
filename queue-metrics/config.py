"""Configuration management for Queue Metrics service."""

import os
from typing import Optional

from pydantic import BaseModel, Field, validator


class RedisConfig(BaseModel):
    """Redis connection configuration."""

    host: str = Field(default="localhost", description="Redis hostname")
    port: int = Field(default=6379, description="Redis port")
    password: Optional[str] = Field(default=None, description="Redis password")
    decode_responses: bool = Field(
        default=True, description="Decode Redis responses to strings"
    )

    @validator("port")
    def port_must_be_valid(cls, v):
        if not 1 <= v <= 65535:
            raise ValueError("Port must be between 1 and 65535")
        return v


class QueueConfig(BaseModel):
    """Queue monitoring configuration."""

    name_prefix: str = Field(default="bull", description="BullMQ queue prefix")
    name: str = Field(default="jobs", description="Queue name")
    poll_interval: int = Field(default=5, description="Polling interval in seconds")

    @validator("poll_interval")
    def poll_interval_must_be_positive(cls, v):
        if v <= 0:
            raise ValueError("Poll interval must be positive")
        return v


class Config(BaseModel):
    """Main application configuration."""

    redis: RedisConfig
    queue: QueueConfig

    @classmethod
    def from_env(cls) -> "Config":
        """Create configuration from environment variables."""
        return cls(
            redis=RedisConfig(
                host=os.getenv("REDIS_HOST", "localhost"),
                port=int(os.getenv("REDIS_PORT", "6379")),
                password=os.getenv("REDIS_PASSWORD"),
            ),
            queue=QueueConfig(
                name_prefix=os.getenv("QUEUE_NAME_PREFIX", "bull"),
                name=os.getenv("QUEUE_NAME", "jobs"),
                poll_interval=int(os.getenv("POLL_INTERVAL_SECONDS", "5")),
            ),
        )
