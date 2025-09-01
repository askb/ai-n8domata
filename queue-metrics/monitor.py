"""Main queue monitoring service."""
import logging
import signal
import sys
import time

from config import Config
from redis_client import RedisClient

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)

logger = logging.getLogger("queue_monitor")


class QueueMonitor:
    """Queue monitoring service."""

    def __init__(self, config: Config):
        self.config = config
        self.redis_client = RedisClient(config.redis)
        self.running = False

    def start(self):
        """Start the monitoring service."""
        logger.info("Starting Queue Monitor service")

        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

        # Connect to Redis
        if not self.redis_client.connect():
            logger.error("Failed to connect to Redis, exiting")
            sys.exit(1)

        logger.info(
            f"Queue monitoring started for "
            f"{self.config.queue.name_prefix}:{self.config.queue.name}, "
            f"poll_interval={self.config.queue.poll_interval}s"
        )

        self.running = True
        self._monitor_loop()

    def _monitor_loop(self):
        """Main monitoring loop."""
        consecutive_errors = 0
        max_consecutive_errors = 5

        while self.running:
            try:
                # Check Redis connection
                if not self.redis_client.is_connected():
                    logger.warning("Redis connection lost, attempting to reconnect")
                    if not self.redis_client.connect():
                        consecutive_errors += 1
                        if consecutive_errors >= max_consecutive_errors:
                            logger.error(
                                "Max consecutive errors reached, shutting down"
                            )
                            break
                        time.sleep(
                            min(consecutive_errors * 2, 30)
                        )  # Exponential backoff
                        continue

                # Get queue metrics
                queue_length = self.redis_client.get_queue_length(
                    self.config.queue.name_prefix, self.config.queue.name
                )

                # Log current queue length
                logger.info(
                    f"Queue metrics: "
                    f"{self.config.queue.name_prefix}:{self.config.queue.name} "
                    f"waiting_jobs={queue_length}"
                )

                # Reset error counter on successful operation
                consecutive_errors = 0

                # Log detailed stats periodically (every 12 polls)
                current_time = int(time.time())
                poll_interval = self.config.queue.poll_interval
                if current_time % (poll_interval * 12) == 0:
                    stats = self.redis_client.get_queue_stats(
                        self.config.queue.name_prefix, self.config.queue.name
                    )
                    if stats:
                        stats_str = " ".join(f"{k}={v}" for k, v in stats.items())
                        logger.info(f"Detailed queue stats: {stats_str}")

                time.sleep(self.config.queue.poll_interval)

            except KeyboardInterrupt:
                logger.info("Received keyboard interrupt, shutting down")
                break
            except Exception as e:
                consecutive_errors += 1
                logger.error(
                    f"Error in monitoring loop: {str(e)}, "
                    f"consecutive_errors={consecutive_errors}"
                )

                if consecutive_errors >= max_consecutive_errors:
                    logger.error("Max consecutive errors reached, shutting down")
                    break

                time.sleep(min(consecutive_errors * 2, 30))  # Exponential backoff

        self._shutdown()

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        logger.info(f"Received shutdown signal: {signum}")
        self.running = False

    def _shutdown(self):
        """Graceful shutdown."""
        logger.info("Shutting down Queue Monitor")
        self.running = False
        self.redis_client.disconnect()
        logger.info("Queue Monitor stopped")


def main():
    """Entry point for the queue monitor service."""
    try:
        config = Config.from_env()
        monitor = QueueMonitor(config)
        monitor.start()
    except Exception as e:
        logger.error(f"Failed to start Queue Monitor: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
