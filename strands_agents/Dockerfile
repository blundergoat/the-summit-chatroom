# =============================================================================
# Dockerfile — Builds the Python agent container
# =============================================================================
#
# This container runs the FastAPI server that wraps the LLM with persona-specific
# system prompts. It's the "brain" that the PHP application talks to.
#
# WHAT IT DOES:
#   1. Starts from Python 3.12 slim image (minimal size)
#   2. Installs curl (needed for Docker healthcheck)
#   3. Installs Python dependencies (Strands SDK, FastAPI, Uvicorn)
#   4. Copies the agent code
#   5. Starts Uvicorn (ASGI server) to serve the FastAPI application
#
# UVICORN:
#   Uvicorn is an ASGI server (like Gunicorn for WSGI). It handles HTTP connections
#   and routes them to the FastAPI application. The [standard] extra includes
#   uvloop and httptools for better performance.
#
# PORTS:
#   8000 — The agent API. Docker Compose maps this to 8081 on the host.
# =============================================================================

FROM python:3.12-slim

# Install curl for Docker healthcheck (see docker-compose.yml)
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (better Docker layer caching —
# dependencies change less often than code, so this layer is cached)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the agent source code
COPY . .

# Expose the API port
EXPOSE 8000

# Start the FastAPI server with Uvicorn
# "api.server:app" means: import the "app" object from api/server.py
# --host 0.0.0.0 makes it accessible from outside the container
CMD ["uvicorn", "api.server:app", "--host", "0.0.0.0", "--port", "8000"]
