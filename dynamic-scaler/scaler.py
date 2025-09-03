"""Main dynamic scaling service."""

import logging
import signal
import sys
import time
from typing import Optional

import structlog
from config import Config
from docker_manager import DockerManager
from redis_client import RedisClient

# Configure simple logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer(),
    ],
    wrapper_class=structlog.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
    context_class=dict,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger("dynamic_scaler")


class DynamicScaler:
    """Dynamic scaling service for N8N workers based on queue metrics."""

    def __init__(self, config: Config):
        self.config = config
        self.redis_client = RedisClient(config.redis)
        self.docker_manager = DockerManager(config.docker)
        self.running = False
        self.last_scale_time = 0.0

    def start(self):
        """Start the dynamic scaling service."""
        logger.info("Starting Dynamic Scaler service")

        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

        # Validate configuration
        if not self._validate_setup():
            logger.error("Configuration validation failed, exiting")
            sys.exit(1)

        # Connect to services
        if not self._connect_services():
            logger.error("Failed to connect to required services, exiting")
            sys.exit(1)

        self._log_startup_info()

        self.running = True
        self._scaling_loop()

    def _validate_setup(self) -> bool:
        """Validate the scaling setup."""
        try:
            # Validate Docker setup
            if not self.docker_manager.validate_setup():
                return False

            logger.info("Configuration validation successful")
            return True
        except Exception as e:
            logger.error("Error during setup validation", error=str(e))
            return False

    def _connect_services(self) -> bool:
        """Connect to Redis and Docker."""
        # Connect to Redis
        if not self.redis_client.connect():
            return False

        # Connect to Docker
        if not self.docker_manager.connect():
            self.redis_client.disconnect()
            return False

        return True

    def _log_startup_info(self):
        """Log startup configuration information."""
        logger.info(
            "Dynamic Scaler started successfully",
            service=self.config.docker.service_name,
            project=self.config.docker.project_name,
            queue=(f"{self.config.queue.name_prefix}:{self.config.queue.name}"),
            min_replicas=self.config.scaling.min_replicas,
            max_replicas=self.config.scaling.max_replicas,
            scale_up_threshold=self.config.scaling.scale_up_threshold,
            scale_down_threshold=self.config.scaling.scale_down_threshold,
            polling_interval=self.config.timing.polling_interval,
            cooldown_period=self.config.timing.cooldown_period,
        )

    def _scaling_loop(self):
        """Main scaling loop."""
        consecutive_errors = 0
        max_consecutive_errors = 5

        while self.running:
            try:
                current_time = time.time()

                # Check cooldown period
                time_since_last_scale = current_time - self.last_scale_time
                if time_since_last_scale < self.config.timing.cooldown_period:
                    remaining_cooldown = (
                        self.config.timing.cooldown_period - time_since_last_scale
                    )
                    logger.debug(
                        "In cooldown period", remaining_seconds=int(remaining_cooldown)
                    )
                    time.sleep(self.config.timing.polling_interval)
                    continue

                # Check Redis connection
                if not self.redis_client.is_connected():
                    logger.warning("Redis connection lost, attempting to reconnect")
                    if not self.redis_client.connect():
                        consecutive_errors += 1
                        self._handle_consecutive_errors(
                            consecutive_errors, max_consecutive_errors
                        )
                        continue

                # Get current metrics
                queue_length = self.redis_client.get_queue_length(self.config.queue)
                current_replicas = self.docker_manager.get_current_replicas()

                logger.info(
                    "Current metrics",
                    queue_length=queue_length,
                    current_replicas=current_replicas,
                )

                # Determine scaling action
                scaling_decision = self._make_scaling_decision(
                    queue_length, current_replicas
                )

                if scaling_decision:
                    target_replicas, reason = scaling_decision
                    if self._execute_scaling(target_replicas, reason, current_time):
                        self.last_scale_time = current_time
                else:
                    logger.debug("No scaling action needed")

                # Reset error counter on successful operation
                consecutive_errors = 0
                time.sleep(self.config.timing.polling_interval)

            except KeyboardInterrupt:
                logger.info("Received keyboard interrupt, shutting down")
                break
            except Exception as e:
                consecutive_errors += 1
                logger.error(
                    "Error in scaling loop",
                    error=str(e),
                    consecutive_errors=consecutive_errors,
                )
                self._handle_consecutive_errors(
                    consecutive_errors, max_consecutive_errors
                )

        self._shutdown()

    def _make_scaling_decision(
        self, queue_length: int, current_replicas: int
    ) -> Optional[tuple[int, str]]:
        """
        Make scaling decision based on current metrics.

        Returns: (target_replicas, reason) or None if no scaling needed
        """
        # Scale up condition
        if (
            queue_length > self.config.scaling.scale_up_threshold
            and current_replicas < self.config.scaling.max_replicas
        ):
            target_replicas = min(
                current_replicas + 1, self.config.scaling.max_replicas
            )
            reason = (
                f"Queue length {queue_length} > threshold "
                f"{self.config.scaling.scale_up_threshold}"
            )
            return target_replicas, reason

        # Scale down condition
        elif (
            queue_length <= self.config.scaling.scale_down_threshold
            and current_replicas > self.config.scaling.min_replicas
        ):
            target_replicas = max(
                current_replicas - 1, self.config.scaling.min_replicas
            )
            reason = (
                f"Queue length {queue_length} <= threshold "
                f"{self.config.scaling.scale_down_threshold}"
            )
            return target_replicas, reason

        return None

    def _execute_scaling(
        self, target_replicas: int, reason: str, current_time: float
    ) -> bool:
        """Execute scaling action."""
        logger.info(
            "Scaling decision made",
            target_replicas=target_replicas,
            reason=reason,
        )

        success = self.docker_manager.scale_service(target_replicas)

        if success:
            logger.info("Scaling completed successfully", new_replicas=target_replicas)
        else:
            logger.error("Scaling failed")

        return success

    def _handle_consecutive_errors(self, consecutive_errors: int, max_errors: int):
        """Handle consecutive errors with exponential backoff."""
        if consecutive_errors >= max_errors:
            logger.error("Max consecutive errors reached, shutting down")
            self.running = False
            return

        backoff_time = min(consecutive_errors * 2, 60)  # Max 60 seconds
        logger.warning(
            "Backing off due to errors",
            consecutive_errors=consecutive_errors,
            backoff_seconds=backoff_time,
        )
        time.sleep(backoff_time)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        logger.info("Received shutdown signal", signal=signum)
        self.running = False

    def _shutdown(self):
        """Graceful shutdown."""
        logger.info("Shutting down Dynamic Scaler")
        self.running = False
        self.redis_client.disconnect()
        logger.info("Dynamic Scaler stopped")


def main():
    """Entry point for the dynamic scaler service."""
    try:
        config = Config.from_env()
        scaler = DynamicScaler(config)
        scaler.start()
    except Exception as e:
        logger.error("Failed to start Dynamic Scaler", error=str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
