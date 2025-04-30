# Makefile for building and managing the server-monitor Docker container

# Image, container, and volume names
IMAGE_NAME := server-monitor
CONTAINER_NAME := server-monitor
VOLUME_NAME := server-monitor-data

# Environment file path
env_file := .env

# Docker flags for host integration
network_flag := --network host
pid_flag := --pid host
cap_flags := --cap-add SYS_RAWIO --cap-add SYS_ADMIN
thermal_vol := -v /sys/class/thermal:/sys/class/thermal:ro

env_vol := --env-file $(env_file) --env DB_PATH=/app/metrics.db

.PHONY: build volume run stop sample report logs exec

# Build the image
build:
	docker build -t $(IMAGE_NAME) .

# Create Docker volume for metrics DB
volume:
	docker volume create $(VOLUME_NAME)

# Run a dummy container to keep it alive (for exec/logs)
# Uses a named volume to persist metrics.db inside the container
run: stop volume
	docker run -d \
		--name $(CONTAINER_NAME) \
		$(env_vol) \
		$(network_flag) \
		$(pid_flag) \
		$(cap_flags) \
		$(thermal_vol) \
		-v $(VOLUME_NAME):/data \
		--restart unless-stopped \
		$(IMAGE_NAME) tail -f /dev/null

# Stop and remove the dummy container
stop:
	docker rm -f $(CONTAINER_NAME) 2>/dev/null || true

# Trigger a single sample collection inside the dummy container
sample:
	docker exec $(CONTAINER_NAME) python /app/monitor.py

# Trigger a single report inside the dummy container
report:
	docker exec $(CONTAINER_NAME) python /app/monitor.py report
