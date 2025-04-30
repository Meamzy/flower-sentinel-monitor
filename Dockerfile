# Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt requirements.txt

# install lm-sensors (for psutil thermal support) + python deps
RUN apt-get update \
 && apt-get install -y --no-install-recommends lm-sensors \
 && pip install --no-cache-dir -r requirements.txt \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY monitor.py ./
COPY .env .env

CMD ["python", "monitor.py", "report"]
