from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session
from ..db import get_db
from ..deps import current_user
from ..models import User
from ..schemas import LoginIn, RegisterIn, TokenOut, UserOut
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=TokenOut, status_code=201)
def register(payload: RegisterIn, db: Session = Depends(get_db)):
    username = payload.username.strip().lower()
    if db.scalar(select(User).where(User.username == username)):
        raise HTTPException(409, "Username already exists")
    email = payload.email.strip().lower() if payload.email else None
    if email and db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "Email already exists")
    user = User(username=username, email=email, password_hash=hash_password(payload.password), role="user")
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenOut(access_token=create_access_token(user.id, user.role), user=user)


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    username = payload.username.strip().lower()
    user = db.scalar(select(User).where(User.username == username))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Wrong username or password")
    if not user.is_active:
        raise HTTPException(403, "Account disabled")
    return TokenOut(access_token=create_access_token(user.id, user.role), user=user)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return user
