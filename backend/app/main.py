"""Voice Studio backend. Run:  uvicorn app.main:app --host 127.0.0.1 --port 8765
OpenAPI docs at /docs (Swagger) and /openapi.json."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import account, ai
from .config import get_settings
from .db import init_engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("voicestudio")


@asynccontextmanager
async def lifespan(app: FastAPI):
    get_settings()  # creates data dirs and, if needed, the per-install secret key
    init_engine()
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Voice Studio API", version=ai.VERSION, lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=get_settings().cors_origins, allow_methods=["*"], allow_headers=["*"])
    app.include_router(ai.router, prefix="/api/v1")
    app.include_router(account.router, prefix="/api/v1")
    return app


app = create_app()
