# Makefile for building and managing the server-monitor Docker container and systemd integration

# Show available commands
help:
	@echo "Available make commands:"
	@grep -E '^[a-zA-Z_-]+:' Makefile | cut -d: -f1 | sort | uniq

# Image and container names
IMAGE_NAME := server-monitor
CONTAINER_NAME := server-monitor

# Environment file and project directory paths
env_file := .env
project_dir := $(PWD)
service_dir := deploy

# Docker flags for host integration
network_flag := --network host
pid_flag := --pid host
cap_flags := --cap-add SYS_RAWIO --cap-add SYS_ADMIN
thermal_vol := -v /sys/class/thermal:/sys/class/thermal:ro

# Combined environment flags
env_vol := --env-file $(env_file)

# Systemd unit files (in $(service_dir))
service_files := \
	server-monitor-sample.service \
	server-monitor-sample.timer   \
	server-monitor-report.service \
	server-monitor-report.timer

.PHONY: help build run stop sample report logs exec install-systemd uninstall-systemd debug

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Run a dummy container to keep it alive (for exec/logs)
# Mount the entire project directory so metrics.db can be created
run: stop
	docker run -d \
		--name $(CONTAINER_NAME) \
		$(env_vol) \
		$(network_flag) \
		$(pid_flag) \
		$(cap_flags) \
		$(thermal_vol) \
		-v $(project_dir):/app \
		--restart unless-stopped \
		$(IMAGE_NAME) tail -f /dev/null

# Stop and remove the dummy container
stop:
	docker rm -f $(CONTAINER_NAME) 2>/dev/null || true

# Trigger a single sample collection inside the container
sample:
	docker exec $(CONTAINER_NAME) python /app/monitor.py

# Trigger a single report inside the container
report:
	docker exec $(CONTAINER_NAME) python /app/monitor.py report

# Follow logs of the running container
logs:
	docker logs -f $(CONTAINER_NAME)

# Exec into the running container
exec:
	docker exec -it $(CONTAINER_NAME) /bin/bash

# Install systemd unit files and enable timers (run as root)
install-systemd:
	cp $(service_dir)/*.service /etc/systemd/system/
	cp $(service_dir)/*.timer   /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable --now server-monitor-sample.timer server-monitor-report.timer
	# Trigger initial runs
	systemctl start server-monitor-sample.service
	systemctl start server-monitor-report.service

# Disable and remove systemd units
uninstall-systemd:
	systemctl disable --now server-monitor-sample.timer server-monitor-report.timer
	rm -f /etc/systemd/system/$(service_files)
	systemctl daemon-reload

# Debug: show timers and service statuses
debug:
	@echo "Active server-monitor timers:"
	@systemctl list-timers --all | grep server-monitor
	@echo "Service statuses (oneshot services finish inactive after run, that's expected):"
	- systemctl status server-monitor-sample.service server-monitor-report.service || true
