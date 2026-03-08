import boto3
from .config import settings


def _client():
    return boto3.client(
        "s3",
        region_name=settings.AWS_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    )


def presigned_upload_url(s3_key: str) -> str:
    """Return a presigned PUT URL the client can use to upload a file directly to S3."""
    return _client().generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": s3_key},
        ExpiresIn=settings.PRESIGN_EXPIRES_SECONDS,
    )


def presigned_download_url(s3_key: str) -> str:
    """Return a presigned GET URL the client can use to download a file from S3."""
    return _client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": s3_key},
        ExpiresIn=settings.PRESIGN_EXPIRES_SECONDS,
    )
