from sqlalchemy import select
from .config import settings
from .db import SessionLocal
from .models import User
from .security import hash_password, verify_password


def seed_admin():
    if not settings.admin_username or not settings.admin_password or settings.admin_password.startswith("CHANGE_THIS"):
        return
    username = settings.admin_username.strip().lower()
    sync_requested = settings.admin_sync_password
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == username))
        if user:
            changed = False
            if user.role != "admin":
                user.role = "admin"
                changed = True
            if settings.admin_sync_password and not verify_password(settings.admin_password, user.password_hash):
                user.password_hash = hash_password(settings.admin_password)
                changed = True
            if changed:
                db.commit()
            # Treat synchronization as a one-shot action for this process. The
            # environment flag should still be set back to false for the next
            # deployment/restart, as documented in the deployment guides.
            if sync_requested:
                settings.admin_sync_password = False
            return
        db.add(User(username=username, password_hash=hash_password(settings.admin_password), role="admin"))
        db.commit()
        if sync_requested:
            settings.admin_sync_password = False
