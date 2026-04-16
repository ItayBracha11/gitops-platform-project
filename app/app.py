from fastapi import FastAPI
from fastapi.responses import JSONResponse
import time

app = FastAPI(title="Demo App", version="1.0")

# Main endpoint
@app.get("/")
def read_root():
    return {"message": "Hello from demo-app!"}

# Health endpoint for Kubernetes liveness/readiness probes
@app.get("/livez")
def liveness():
    return {"status": "alive"}

@app.get("/readyz")
def readiness():
    return {"status": "ready"}

# Metrics endpoint for Prometheus or custom monitoring
@app.get("/metrics")
def metrics():
    # Example metrics: uptime and request count can be added here
    # For now, just a placeholder
    return "demo_app_requests_total 0\n"