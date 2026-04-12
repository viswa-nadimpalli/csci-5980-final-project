from dataclasses import dataclass
from typing import Any

import jwt
from jwt import PyJWKClient
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from core.config import settings
from core.db import get_db
from core.models import AuthProvider, User, UserIdentities


bearer_scheme = HTTPBearer(auto_error=False)


@dataclass
class AuthenticatedUser:
    user: User
    clerk_user_id: str
    claims: dict[str, Any]


def _unauthorized(detail: str = "Invalid or missing authentication token") -> HTTPException:
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)


def verify_clerk_token(token: str) -> dict[str, Any]:
    try:
        jwks_client = PyJWKClient(settings.CLERK_JWKS_URL)
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=settings.CLERK_ISSUER,
            options={"verify_aud": False},  # Clerk session tokens are usually validated by issuer/azp here
        )
    except Exception as exc:
        raise _unauthorized("Could not verify Clerk token") from exc

    # Optional but recommended if you want to lock tokens to your app origin.
    if settings.CLERK_AUTHORIZED_PARTY:
        azp = claims.get("azp")
        if azp != settings.CLERK_AUTHORIZED_PARTY:
            raise _unauthorized("Token authorized party did not match")

    clerk_user_id = claims.get("sub")
    if not clerk_user_id:
        raise _unauthorized("Token did not contain a Clerk user id")

    return claims


def get_current_auth(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized("Missing bearer token")

    claims = verify_clerk_token(credentials.credentials)
    clerk_user_id = claims["sub"]

    identity = (
        db.query(UserIdentities)
        .filter(
            UserIdentities.provider == AuthProvider.clerk,
            UserIdentities.provider_user_id == clerk_user_id,
        )
        .first()
    )

    if identity:
        user = identity.user

        # Optional refresh if you later add email as a custom session claim.
        email = claims.get("email")
        if email and user.email != email:
            user.email = email
            identity.provider_email = email
            db.commit()
            db.refresh(user)

        return AuthenticatedUser(user=user, clerk_user_id=clerk_user_id, claims=claims)

    # First login for this Clerk user: provision a local user row.
    # Note: email is NOT a default Clerk session token claim. This will only be set
    # if you add it as a custom claim or fetch it separately from Clerk's Backend API.
    email = claims.get("email")

    user = User(
        email=email,
        hashed_password=None,
    )
    db.add(user)
    db.flush()

    identity = UserIdentities(
        user_id=user.id,
        provider=AuthProvider.clerk,
        provider_user_id=clerk_user_id,
        provider_email=email,
    )
    db.add(identity)
    db.commit()
    db.refresh(user)

    return AuthenticatedUser(user=user, clerk_user_id=clerk_user_id, claims=claims)
