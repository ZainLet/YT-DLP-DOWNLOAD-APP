"""Server-side IG Downloader adapter. Credentials never enter the web frontend."""
import asyncio
import json
import re
import sqlite3
import time
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlsplit

import httpx
from fastapi import HTTPException

API_HOST = "ig-downloader-api.p.rapidapi.com"
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
COLLECTION_TTL = 10 * 60


def profile_username(value: str) -> str:
    value = value.strip()
    if value.startswith(("https://", "http://")):
        parsed = urlsplit(value)
        if (parsed.hostname or "").lower() not in {"instagram.com", "www.instagram.com", "m.instagram.com"}:
            raise HTTPException(400, "Use um perfil ou link de Story do Instagram.")
        parts = parsed.path.strip("/").split("/")
        value = parts[1] if parts[0] == "stories" and len(parts) > 1 else parts[0]
    value = value.lstrip("@").lower()
    if not re.fullmatch(r"[a-z0-9._]{1,30}", value) or value in {"p", "reel", "reels", "stories", "accounts", "explore", "highlights", "direct"}:
        raise HTTPException(400, "Informe o usuário, um perfil ou um link de Story válido.")
    return value


def media_url(value) -> str:
    if not isinstance(value, str):
        raise ValueError("Missing media URL")
    parsed = urlsplit(value)
    host = (parsed.hostname or "").lower()
    if (parsed.scheme != "https" or parsed.username or parsed.password or parsed.port not in (None, 443)
            or not (host.endswith(".cdninstagram.com") or host.endswith(".fbcdn.net"))):
        raise ValueError("Invalid media host")
    return value


def normalize_stories(payload: dict) -> list[dict]:
    if not isinstance(payload, dict):
        raise HTTPException(502, "A API não retornou uma resposta válida.")
    result = payload.get("result")
    if not isinstance(result, list):
        raise HTTPException(502, "A API não retornou uma lista válida de Stories.")
    stories = []
    seen = set()
    for item in result[:200]:
        if not isinstance(item, dict):
            continue
        story_id = str(item.get("pk", ""))
        if not re.fullmatch(r"\d{1,30}", story_id) or story_id in seen:
            continue
        try:
            images = item.get("image_versions2", {}).get("candidates", [])
            images = [image for image in images if isinstance(image, dict) and image.get("url")]
            image = max(images, key=lambda value: int(value.get("width", 0)))
            thumbnail = min(images, key=lambda value: abs(int(value.get("width", 0)) - 320))
            videos = [video for video in item.get("video_versions", []) if isinstance(video, dict) and video.get("url")]
            video = max(videos, key=lambda value: int(value.get("width", 0))) if videos else None
            stories.append({"id": story_id, "kind": "video" if video else "image",
                            "timestamp": int(item.get("taken_at", 0)),
                            "media": media_url((video or image)["url"]),
                            "thumbnail": media_url(thumbnail["url"])})
            seen.add(story_id)
        except (ValueError, TypeError, KeyError):
            continue
    if result and not stories:
        raise HTTPException(502, "Os Stories retornados não contêm mídias disponíveis para baixar.")
    return stories


class InstagramService:
    def __init__(self, key: str, data_dir: Path, request_limit: int = 900):
        self.key = key
        self.data_dir = data_dir
        self.request_limit = request_limit
        self.collections: dict[str, dict] = {}
        self.lock = asyncio.Lock()
        self.ledger = data_dir / "instagram-usage.sqlite"
        with closing(sqlite3.connect(self.ledger)) as connection, connection:
            connection.execute("CREATE TABLE IF NOT EXISTS usage (month TEXT PRIMARY KEY, calls INTEGER NOT NULL)")

    def _reserve_call(self) -> None:
        month = datetime.now(timezone.utc).strftime("%Y-%m")
        with closing(sqlite3.connect(self.ledger)) as connection, connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT calls FROM usage WHERE month = ?", (month,)).fetchone()
            calls = row[0] if row else 0
            if calls >= self.request_limit:
                raise HTTPException(429, "O limite mensal de consultas do app foi atingido.")
            connection.execute("INSERT INTO usage VALUES (?, 1) ON CONFLICT(month) DO UPDATE SET calls = calls + 1", (month,))

    async def list_stories(self, username: str) -> dict:
        username = profile_username(username)
        if not self.key:
            raise HTTPException(503, "A API do Instagram ainda não foi configurada no servidor.")
        async with self.lock:
            now = time.time()
            self.collections = {key: value for key, value in self.collections.items() if value["expiresAt"] > now}
            cached = next((value for value in self.collections.values() if value["username"] == username), None)
            if cached:
                return self.view(cached, cached=True)
            self._reserve_call()
            try:
                async with httpx.AsyncClient(timeout=45, follow_redirects=False, trust_env=False) as client:
                    async with client.stream("POST", f"https://{API_HOST}/api/instagram/stories",
                                             headers={"X-RapidAPI-Key": self.key, "X-RapidAPI-Host": API_HOST},
                                             json={"username": username}) as response:
                        if response.status_code == 429:
                            raise HTTPException(429, "A cota da API foi atingida. Tente novamente após a renovação.")
                        if response.status_code in (401, 403):
                            raise HTTPException(502, "A API recusou o acesso. Confira a assinatura no servidor.")
                        if response.status_code != 200:
                            raise HTTPException(502, "O serviço do Instagram está indisponível no momento.")
                        data = bytearray()
                        async for chunk in response.aiter_bytes():
                            data.extend(chunk)
                            if len(data) > MAX_RESPONSE_BYTES:
                                raise HTTPException(502, "A resposta do serviço excedeu o limite permitido.")
                items = normalize_stories(json.loads(data))
            except (httpx.HTTPError, ValueError, TypeError):
                raise HTTPException(502, "Não foi possível consultar o Instagram agora. Tente novamente em instantes.") from None
            collection_id = uuid.uuid4().hex
            collection = {"id": collection_id, "username": username, "expiresAt": int(now + COLLECTION_TTL),
                          "items": {item["id"]: item for item in items}}
            self.collections[collection_id] = collection
            return self.view(collection)

    @staticmethod
    def view(collection: dict, cached: bool = False) -> dict:
        prefix = f'/api/instagram/collections/{collection["id"]}/stories'
        return {"collectionId": collection["id"], "username": collection["username"],
                "expiresAt": collection["expiresAt"], "cached": cached,
                "stories": [{"id": item["id"], "kind": item["kind"], "timestamp": item["timestamp"],
                             "thumbnailUrl": f'{prefix}/{item["id"]}/thumbnail'} for item in collection["items"].values()]}

    def selected(self, collection_id: str, story_ids: list[str]) -> tuple[dict, list[dict]]:
        collection = self.collections.get(collection_id)
        if not collection or collection["expiresAt"] <= time.time():
            raise HTTPException(410, "Esta lista expirou. Consulte o perfil novamente.")
        if len(story_ids) != len(set(story_ids)) or any(story_id not in collection["items"] for story_id in story_ids):
            raise HTTPException(400, "A seleção contém um Story inválido.")
        return collection, [collection["items"][story_id] for story_id in story_ids]


async def download_media(url: str, destination: Path, maximum: int, image_only: bool = False) -> int:
    """Fetch provider-returned media without passing the RapidAPI key to the CDN."""
    try:
        async with httpx.AsyncClient(timeout=60, follow_redirects=False, trust_env=False) as client:
            for _ in range(4):
                url = media_url(url)
                async with client.stream("GET", url) as response:
                    if response.is_redirect:
                        url = urljoin(url, response.headers.get("location", ""))
                        continue
                    if response.status_code != 200:
                        raise HTTPException(502, "O Instagram recusou o arquivo ou o link expirou. Consulte os Stories novamente.")
                    content_type = response.headers.get("content-type", "").split(";")[0]
                    allowed = ("image/",) if image_only else ("image/", "video/")
                    if not content_type.startswith(allowed):
                        raise HTTPException(502, "O serviço não retornou um arquivo de mídia válido.")
                    total = 0
                    with destination.open("wb") as output:
                        async for chunk in response.aiter_bytes(65536):
                            total += len(chunk)
                            if total > maximum:
                                raise HTTPException(413, "A seleção excedeu o limite de tamanho. Escolha menos Stories.")
                            output.write(chunk)
                    if total == 0:
                        raise HTTPException(502, "O arquivo retornado está vazio.")
                    return total
        raise HTTPException(502, "O arquivo retornou redirecionamentos demais.")
    except (httpx.HTTPError, ValueError):
        raise HTTPException(502, "Não foi possível baixar a mídia. Consulte o perfil novamente.") from None
    finally:
        if destination.exists() and destination.stat().st_size == 0:
            destination.unlink()
