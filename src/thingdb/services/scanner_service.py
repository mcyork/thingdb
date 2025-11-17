"""
Scanner Service for ThingDB
Manages ephemeral secrets for scanner authentication
"""
import secrets

# Ephemeral secret - generated on first use, persists until system reboot
_ephemeral_secret = None


def generate_ephemeral_secret():
    """Generate a new ephemeral secret if one doesn't exist"""
    global _ephemeral_secret
    if _ephemeral_secret is None:
        # Generate a secure random token (32 bytes = 43 characters in base64)
        _ephemeral_secret = secrets.token_urlsafe(32)
    return _ephemeral_secret


def get_ephemeral_secret():
    """Get the current ephemeral secret (generates if needed)"""
    return generate_ephemeral_secret()


def validate_secret(secret):
    """Validate that the provided secret matches the ephemeral secret"""
    if _ephemeral_secret is None:
        return False
    return secrets.compare_digest(secret, _ephemeral_secret)


def reset_secret():
    """Reset the secret (for testing or manual reset)"""
    global _ephemeral_secret
    _ephemeral_secret = None

