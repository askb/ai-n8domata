"""Configuration management for Dynamic Scaler service."""

import os
from typing import Optional

from pydantic import BaseModel, Field, validator


class RedisConfig(BaseModel):
    """Redis connection configuration."""

    host: str = Field(default="redis", description="Redis hostname")
    port: int = Field(default=6379, description="Redis port")
    password: Optional[str] = Field(default=None, description="Redis password")

    @validator("port")
    def port_must_be_valid(cls, v):
        if not 1 <= v <= 65535:
            raise ValueError("Port must be between 1 and 65535")
        return v


class QueueConfig(BaseModel):
    """Queue monitoring configuration."""

    name_prefix: str = Field(default="bull", description="BullMQ queue prefix")
    name: str = Field(default="jobs", description="Queue name")

    def get_queue_key(self, state: str = "wait") -> str:
        """Get the Redis key for a specific queue state."""
        return f"{self.name_prefix}:{self.name}:{state}"


class ScalingConfig(BaseModel):
    """Auto-scaling configuration."""

    min_replicas: int = Field(default=1, description="Minimum number of replicas")
    max_replicas: int = Field(default=5, description="Maximum number of replicas")
    scale_up_threshold: int = Field(
        default=5, description="Queue length to trigger scale up"
    )
    scale_down_threshold: int = Field(
        default=0, description="Queue length to trigger scale down"
    )

    @validator("min_replicas")
    def min_replicas_valid(cls, v):
        if v < 1:
            raise ValueError("Minimum replicas must be at least 1")
        return v

    @validator("max_replicas")
    def max_replicas_valid(cls, v, values):
        if "min_replicas" in values and v < values["min_replicas"]:
            raise ValueError("Maximum replicas must be >= minimum replicas")
        return v

    @validator("scale_up_threshold")
    def scale_up_threshold_valid(cls, v):
        if v < 0:
            raise ValueError("Scale up threshold must be >= 0")
        return v

    @validator("scale_down_threshold")
    def scale_down_threshold_valid(cls, v):
        if v < 0:
            raise ValueError("Scale down threshold must be >= 0")
        return v


class DockerConfig(BaseModel):
    """Docker Compose configuration."""

    compose_file: str = Field(
        default="/app/docker-compose.yml",
        description="Path to docker-compose.yml",
    )
    project_name: str = Field(..., description="Docker Compose project name")
    service_name: str = Field(
        default="n8n-worker", description="Name of the service to scale"
    )

    @validator("project_name")
    def project_name_required(cls, v):
        if not v or not v.strip():
            raise ValueError("Project name is required")
        return v.strip()


class TimingConfig(BaseModel):
    """Timing and polling configuration."""

    polling_interval: int = Field(default=30, description="Polling interval in seconds")
    cooldown_period: int = Field(
        default=120,
        description="Cooldown period between scaling actions in seconds",
    )

    @validator("polling_interval")
    def polling_interval_valid(cls, v):
        if v < 1:
            raise ValueError("Polling interval must be at least 1 second")
        return v

    @validator("cooldown_period")
    def cooldown_period_valid(cls, v):
        if v < 0:
            raise ValueError("Cooldown period must be >= 0")
        return v


class Config(BaseModel):
    """Main application configuration."""

    redis: RedisConfig
    queue: QueueConfig
    scaling: ScalingConfig
    docker: DockerConfig
    timing: TimingConfig

    @classmethod
    def from_env(cls) -> "Config":
        """Create configuration from environment variables."""
        return cls(
            redis=RedisConfig(
                host=os.getenv("REDIS_HOST", "redis"),
                port=int(os.getenv("REDIS_PORT", "6379")),
                password=os.getenv("REDIS_PASSWORD"),
            ),
            queue=QueueConfig(
                name_prefix=os.getenv("QUEUE_NAME_PREFIX", "bull"),
                name=os.getenv("QUEUE_NAME", "jobs"),
            ),
            scaling=ScalingConfig(
                min_replicas=int(os.getenv("MIN_REPLICAS", "1")),
                max_replicas=int(os.getenv("MAX_REPLICAS", "5")),
                scale_up_threshold=int(os.getenv("SCALE_UP_QUEUE_THRESHOLD", "5")),
                scale_down_threshold=int(os.getenv("SCALE_DOWN_QUEUE_THRESHOLD", "0")),
            ),
            docker=DockerConfig(
                compose_file=os.getenv("COMPOSE_FILE_PATH", "/app/docker-compose.yml"),
                project_name=os.getenv("COMPOSE_PROJECT_NAME", "").strip(),
                service_name=os.getenv("N8N_WORKER_SERVICE_NAME", "n8n-worker"),
            ),
            timing=TimingConfig(
                polling_interval=int(os.getenv("POLLING_INTERVAL_SECONDS", "30")),
                cooldown_period=int(os.getenv("COOLDOWN_PERIOD_SECONDS", "120")),
            ),
        )
