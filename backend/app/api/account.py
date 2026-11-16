"""Authentication, synchronisation (with conflict control and version
history), resumable uploads and account deletion."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import SyncItem, SyncItemVersion, Upload, User, get_db
from ..security import create_token, current_user, hash_password, verify_password

router = APIRouter()

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
ENTITIES = {"document", "recording", "settings"}


class Credentials(BaseModel):
    email: str = Field(max_length=320)
    password: str = Field(max_length=256)


@router.post("/auth/register", tags=["auth"])
def register(c: Credentials, db: Session = Depends(get_db)) -> dict:
    email = c.email.strip().lower()
    if not EMAIL_RE.match(email):
        raise HTTPException(422, "Correo electrónico no válido")
    if len(c.password) < get_settings().min_password_length:
        raise HTTPException(422, f"La contraseña debe tener al menos {get_settings().min_password_length} caracteres")
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "Ya existe una cuenta con ese correo")
    user = User(email=email, password_hash=hash_password(c.password))
    db.add(user)
    db.commit()
    return {"access_token": create_token(user.id), "token_type": "bearer"}


@router.post("/auth/login", tags=["auth"])
def login(c: Credentials, db: Session = Depends(get_db)) -> dict:
    user = db.scalar(select(User).where(User.email == c.email.strip().lower()))
    if user is None or not verify_password(c.password, user.password_hash):
        raise HTTPException(401, "Correo o contraseña incorrectos")
    return {"access_token": create_token(user.id), "token_type": "bearer"}


@router.get("/auth/me", tags=["auth"])
def me(user: User = Depends(current_user)) -> dict:
    return {"id": user.id, "email": user.email, "created_at": user.created_at.isoformat()}


# ------------------------------------------------------------------ sync


class PushItem(BaseModel):
    entity: str
    id: str = Field(min_length=1, max_length=128)
    base_version: int = Field(ge=0)
    deleted: bool = False
    payload: dict = Field(default_factory=dict)


class PushRequest(BaseModel):
    items: list[PushItem] = Field(max_length=500)


@router.post("/sync/push", tags=["sync"])
def push(req: PushRequest, user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    """Optimistic concurrency: a write is accepted only when base_version
    equals the server version; otherwise a conflict with the server copy is
    returned and nothing is overwritten."""
    results = []
    for it in req.items:
        if it.entity not in ENTITIES:
            raise HTTPException(422, f"Entidad no válida: {it.entity}")
        row = db.scalar(select(SyncItem).where(SyncItem.user_id == user.id, SyncItem.entity == it.entity,
                                               SyncItem.entity_id == it.id))
        current = row.version if row else 0
        if it.base_version != current:
            results.append({"entity": it.entity, "id": it.id, "status": "conflict", "server_version": current,
                            "server_payload": row.payload if row and not row.deleted else None})
            continue
        user.change_seq += 1
        if row is None:
            row = SyncItem(user_id=user.id, entity=it.entity, entity_id=it.id)
            db.add(row)
        row.version = current + 1
        row.seq = user.change_seq
        row.deleted = it.deleted
        row.payload = {} if it.deleted else it.payload
        db.flush()
        db.add(SyncItemVersion(item_pk=row.pk, version=row.version, deleted=row.deleted, payload=row.payload))
        results.append({"entity": it.entity, "id": it.id, "status": "ok", "server_version": row.version})
    db.commit()
    return {"results": results}


@router.get("/sync/changes", tags=["sync"])
def changes(since: int = Query(0, ge=0), limit: int = Query(500, ge=1, le=1000),
            user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.scalars(select(SyncItem).where(SyncItem.user_id == user.id, SyncItem.seq > since)
                      .order_by(SyncItem.seq).limit(limit)).all()
    cursor = rows[-1].seq if rows else since
    return {"cursor": cursor, "items": [{"entity": r.entity, "id": r.entity_id, "version": r.version,
                                         "deleted": r.deleted, "payload": r.payload} for r in rows]}


@router.get("/sync/history/{entity}/{entity_id}", tags=["sync"])
def history(entity: str, entity_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    row = db.scalar(select(SyncItem).where(SyncItem.user_id == user.id, SyncItem.entity == entity,
                                           SyncItem.entity_id == entity_id))
    if row is None:
        raise HTTPException(404, "No encontrado")
    versions = db.scalars(select(SyncItemVersion).where(SyncItemVersion.item_pk == row.pk)
                          .order_by(SyncItemVersion.version)).all()
    return {"versions": [{"version": v.version, "deleted": v.deleted, "created_at": v.created_at.isoformat(),
                          "payload": v.payload} for v in versions]}


# ---------------------------------------------------------------- uploads


def _user_dir(user_id: str) -> Path:
    d = get_settings().storage_dir / user_id
    d.mkdir(parents=True, exist_ok=True)
    return d


class UploadInit(BaseModel):
    filename: str = Field(min_length=1, max_length=255)
    size: int = Field(gt=0)
    entity_id: str = Field(min_length=1, max_length=128)


@router.post("/uploads", tags=["uploads"])
def upload_init(req: UploadInit, user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    if req.size > get_settings().max_upload_mb * 1024 * 1024:
        raise HTTPException(413, "Archivo demasiado grande")
    # Resume an unfinished upload of the same file.
    existing = db.scalar(select(Upload).where(Upload.user_id == user.id, Upload.entity_id == req.entity_id,
                                              Upload.size == req.size, Upload.completed.is_(False)))
    if existing:
        return {"upload_id": existing.id, "offset": existing.offset}
    up = Upload(user_id=user.id, entity_id=req.entity_id, filename=Path(req.filename).name, size=req.size)
    db.add(up)
    db.commit()
    return {"upload_id": up.id, "offset": 0}


def _get_upload(upload_id: str, user: User, db: Session) -> Upload:
    up = db.get(Upload, upload_id)
    if up is None or up.user_id != user.id:
        raise HTTPException(404, "Subida no encontrada")
    return up


@router.get("/uploads/{upload_id}", tags=["uploads"])
def upload_status(upload_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    up = _get_upload(upload_id, user, db)
    return {"upload_id": up.id, "offset": up.offset, "size": up.size, "completed": up.completed}


@router.put("/uploads/{upload_id}", tags=["uploads"])
async def upload_chunk(upload_id: str, request: Request, offset: int = Query(ge=0),
                       user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    up = _get_upload(upload_id, user, db)
    if up.completed:
        raise HTTPException(409, "La subida ya se completó")
    if offset != up.offset:
        raise HTTPException(409, f"Offset inesperado; continúe desde {up.offset}")
    body = await request.body()
    if up.offset + len(body) > up.size:
        raise HTTPException(422, "El bloque excede el tamaño declarado")
    part = _user_dir(user.id) / f"{up.id}.part"
    with part.open("ab") as f:
        f.write(body)
    up.offset += len(body)
    db.commit()
    return {"offset": up.offset}


@router.post("/uploads/{upload_id}/complete", tags=["uploads"])
def upload_complete(upload_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    up = _get_upload(upload_id, user, db)
    if up.offset != up.size:
        raise HTTPException(409, f"Faltan datos: {up.offset}/{up.size} bytes")
    d = _user_dir(user.id)
    final = d / f"{up.entity_id}{Path(up.filename).suffix}"
    (d / f"{up.id}.part").replace(final)
    up.completed = True
    db.commit()
    return {"file_id": up.id, "path": final.name}


# --------------------------------------------------------------- account


@router.delete("/account", tags=["auth"])
def delete_account(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    """Deletes the account, all synced items, version history and files."""
    item_pks = db.scalars(select(SyncItem.pk).where(SyncItem.user_id == user.id)).all()
    if item_pks:
        db.query(SyncItemVersion).filter(SyncItemVersion.item_pk.in_(item_pks)).delete(synchronize_session=False)
    db.query(SyncItem).filter(SyncItem.user_id == user.id).delete(synchronize_session=False)
    db.query(Upload).filter(Upload.user_id == user.id).delete(synchronize_session=False)
    db.delete(user)
    db.commit()
    shutil.rmtree(get_settings().storage_dir / user.id, ignore_errors=True)
    return {"deleted": True}
