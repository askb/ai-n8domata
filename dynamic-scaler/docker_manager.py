"""Docker management for service scaling."""

import subprocess
from typing import Optional

import docker
import structlog
from config import DockerConfig

logger = structlog.get_logger()


class DockerManager:
    """Docker client for managing service scaling."""

    def __init__(self, config: DockerConfig):
        self.config = config
        self._client: Optional[docker.DockerClient] = None

    def connect(self) -> bool:
        """Connect to Docker daemon."""
        try:
            self._client = docker.from_env()
            self._client.ping()
            logger.info("Connected to Docker daemon")
            return True
        except docker.errors.DockerException as e:
            logger.error("Failed to connect to Docker daemon", error=str(e))
            return False
        except Exception as e:
            logger.error("Unexpected error connecting to Docker", error=str(e))
            return False

    def get_current_replicas(self) -> int:
        """Get the current number of running replicas for the service."""
        if not self._client:
            logger.error("Docker client not connected")
            return 0

        try:
            filters = {
                "label": [
                    f"com.docker.compose.service={self.config.service_name}",
                    f"com.docker.compose.project={self.config.project_name}",
                ],
                "status": "running",
            }

            containers = self._client.containers.list(filters=filters)
            running_count = len([c for c in containers if c.status == "running"])

            logger.debug(
                "Current replicas counted",
                service=self.config.service_name,
                project=self.config.project_name,
                count=running_count,
            )
            return running_count

        except Exception as e:
            logger.error(
                "Error getting current replicas",
                service=self.config.service_name,
                project=self.config.project_name,
                error=str(e),
            )
            return 0

    def scale_service(self, target_replicas: int) -> bool:
        """Scale the service to the target number of replicas."""
        if target_replicas < 0:
            logger.error("Invalid target replicas", target_replicas=target_replicas)
            return False

        command = [
            "docker",
            "compose",
            "-f",
            self.config.compose_file,
            "--project-name",
            self.config.project_name,
            "--project-directory",
            "/app",
            "up",
            "-d",
            "--no-deps",
            "--scale",
            f"{self.config.service_name}={target_replicas}",
            self.config.service_name,
        ]

        logger.info(
            "Scaling service",
            service=self.config.service_name,
            target_replicas=target_replicas,
            command=" ".join(command),
        )

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True,
                timeout=120,  # 2 minute timeout
            )

            if result.stdout.strip():
                logger.info("Scale command output", stdout=result.stdout.strip())
            if result.stderr.strip():
                logger.warning("Scale command warnings", stderr=result.stderr.strip())

            return True

        except subprocess.CalledProcessError as e:
            logger.error(
                "Scale command failed",
                command=" ".join(e.cmd),
                return_code=e.returncode,
                stdout=e.stdout.strip() if e.stdout else "",
                stderr=e.stderr.strip() if e.stderr else "",
            )
            return False
        except subprocess.TimeoutExpired:
            logger.error("Scale command timed out", timeout=120)
            return False
        except FileNotFoundError:
            logger.error("docker compose command not found")
            return False
        except Exception as e:
            logger.error("Unexpected error during scaling", error=str(e))
            return False

    def validate_setup(self) -> bool:
        """Validate that the Docker setup is correct."""
        if not self.config.project_name:
            logger.error("Docker project name not configured")
            return False

        try:
            # Check if docker compose file exists
            import os

            if not os.path.exists(self.config.compose_file):
                logger.error(
                    "Docker compose file not found",
                    file=self.config.compose_file,
                )
                return False

            # Check if we can run docker compose commands
            result = subprocess.run(
                [
                    "docker",
                    "compose",
                    "-f",
                    self.config.compose_file,
                    "config",
                    "--quiet",
                ],
                capture_output=True,
                timeout=30,
            )

            if result.returncode != 0:
                logger.error(
                    "Docker compose configuration invalid",
                    stderr=result.stderr.decode() if result.stderr else "",
                )
                return False

            logger.info("Docker setup validated successfully")
            return True

        except Exception as e:
            logger.error("Error validating Docker setup", error=str(e))
            return False
