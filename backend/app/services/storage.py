from io import BytesIO
from minio import Minio
from minio.error import S3Error
from app.config import settings

_client: Minio | None = None


def _get_client() -> Minio:
    global _client
    if _client is None:
        _client = Minio(
            settings.MINIO_ENDPOINT,
            access_key=settings.MINIO_ACCESS_KEY,
            secret_key=settings.MINIO_SECRET_KEY,
            secure=settings.MINIO_SECURE,
        )
        _ensure_bucket(_client)
    return _client


def _ensure_bucket(client: Minio):
    if not client.bucket_exists(settings.MINIO_BUCKET):
        client.make_bucket(settings.MINIO_BUCKET)


async def upload_file(storage_path: str, data: bytes, content_type: str = "application/octet-stream") -> str:
    client = _get_client()
    client.put_object(
        settings.MINIO_BUCKET,
        storage_path,
        BytesIO(data),
        length=len(data),
        content_type=content_type,
    )
    return storage_path


async def get_file(storage_path: str) -> bytes:
    client = _get_client()
    try:
        response = client.get_object(settings.MINIO_BUCKET, storage_path)
        return response.read()
    except S3Error as e:
        if e.code == "NoSuchKey":
            raise FileNotFoundError(storage_path)
        raise


async def delete_file(storage_path: str):
    client = _get_client()
    client.remove_object(settings.MINIO_BUCKET, storage_path)


async def get_presigned_url(storage_path: str, expires: int = 3600) -> str:
    client = _get_client()
    return client.presigned_get_object(settings.MINIO_BUCKET, storage_path, expires=timedelta(seconds=expires))


from datetime import timedelta
