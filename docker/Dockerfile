# Stage 1: builder
FROM python:3.12-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn psutil

# Stage 2: runtime
FROM python:3.12-slim
WORKDIR /app

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

COPY ./server.py ./server.py
COPY ./frontend ./frontend
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/api/health')"] || exit 1
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]

