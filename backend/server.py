import asyncio
import hashlib
import hmac
import os
import re
import secrets
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any

from fastapi import Cookie, FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

APP_PASSWORD = os.environ.get("APP_PASSWORD", "")
SESSION_SECRET = os.environ.get("SESSION_SECRET", secrets.token_hex(32))
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://ytdlp-tau.vercel.app")
DATA_DIR = Path(os.environ.get("DATA_DIR", "/tmp/ytdlp-jobs"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="YTDLP Studio Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in ALLOWED_ORIGIN.split(",") if origin.strip()],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)

jobs: dict[str, dict[str, Any]] = {}
job_tasks: dict[str, asyncio.Task] = {}


class LoginRequest(BaseModel):
    password: str = Field(min_length=1, max_length=256)


class DownloadOptions(BaseModel):
    kind: str = Field(default="video", pattern="^(video|audio)$")
    container: str = Field(default="mp4", pattern="^(mp4|webm|mkv|gif|mp3|m4a|opus|flac|wav)$")
    quality: str = Field(default="best", max_length=32)


class DownloadRequest(BaseModel):
    links: list[str] = Field(min_length=1, max_length=5)
    options: DownloadOptions = Field(default_factory=DownloadOptions)


def _session_value() -> str:
    return hmac.new(SESSION_SECRET.encode(), b"ytdlp-session", hashlib.sha256).hexdigest()


def _authenticated(session: str | None) -> bool:
    return bool(APP_PASSWORD and session and hmac.compare_digest(session, _session_value()))


def require_auth(session: str | None) -> None:
    if not APP_PASSWORD:
        raise HTTPException(status_code=503, detail="APP_PASSWORD is not configured")
    if not _authenticated(session):
        raise HTTPException(status_code=401, detail="Authentication required")


def _validate_url(url: str) -> str:
    url = url.strip()
    if not re.match(r"^https?://[^\s]+$", url, re.IGNORECASE):
        raise HTTPException(status_code=400, detail="Only http:// and https:// URLs are accepted")
    return url


def _job_view(job: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in job.items() if key != "path"}


def _command(job: dict[str, Any], destination: Path) -> list[str]:
    options = job["options"]
    args = ["yt-dlp", "--newline", "--no-playlist", "--restrict-filenames", "--no-warnings"]
    if options["kind"] == "audio":
        args.extend(["-x", "--audio-format", options["container"], "--audio-quality", "0"])
    else:
        height = {"2160p": 2160, "1440p": 1440, "1080p": 1080, "720p": 720}.get(options["quality"])
        selector = f"bestvideo[height<={height}]+bestaudio/best[height<={height}]" if height else "bestvideo+bestaudio/best"
        args.extend(["-f", selector, "--merge-output-format", options["container"]])
    args.extend(["-o", str(destination / "%(title)s.%(ext)s"), "--", job["url"]])
    return args


async def _run_job(job_id: str) -> None:
    job = jobs[job_id]
    destination = DATA_DIR / job_id
    destination.mkdir(parents=True, exist_ok=True)
    job["status"] = "active"
    job["startedAt"] = int(time.time())
    process = None
    try:
        process = await asyncio.create_subprocess_exec(
            *_command(job, destination),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        assert process.stdout is not None
        async for raw_line in process.stdout:
            line = raw_line.decode("utf-8", errors="replace").strip()
            job["log"] = line[-300:]
            match = re.search(r"(\d{1,3}(?:\.\d+)?)%", line)
            if match:
                job["progress"] = min(99, float(match.group(1)))
        exit_code = await process.wait()
        if exit_code != 0:
            raise RuntimeError(job.get("log") or f"yt-dlp exited with code {exit_code}")
        files = [file for file in destination.iterdir() if file.is_file() and not file.name.endswith(".part")]
        if not files:
            raise RuntimeError("yt-dlp finished without producing a file")
        output = max(files, key=lambda file: file.stat().st_mtime)
        job.update({"status": "done", "progress": 100, "fileName": output.name, "path": str(output), "downloadUrl": f"/api/downloads/{job_id}/file"})
    except asyncio.CancelledError:
        if process and process.returncode is None:
            process.kill()
            await process.wait()
        job["status"] = "cancelled"
    except Exception as exc:  # keep the error visible to the user, without exposing command details
        job.update({"status": "error", "error": str(exc)[:400]})
    finally:
        job["finishedAt"] = int(time.time())


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "ytdlp-studio-backend"}


@app.post("/api/auth/login")
async def login(payload: LoginRequest, response: Response) -> dict[str, bool]:
    if not APP_PASSWORD or not hmac.compare_digest(payload.password, APP_PASSWORD):
        raise HTTPException(status_code=401, detail="Senha incorreta")
    response.set_cookie("ytdlp_session", _session_value(), httponly=True, secure=True, samesite="none", max_age=60 * 60 * 24 * 30)
    return {"authenticated": True}


@app.get("/api/auth/session")
async def session(ytdlp_session: str | None = Cookie(default=None)) -> dict[str, bool]:
    return {"authenticated": _authenticated(ytdlp_session)}


@app.get("/api/downloads")
async def list_downloads(ytdlp_session: str | None = Cookie(default=None)) -> list[dict[str, Any]]:
    require_auth(ytdlp_session)
    return [_job_view(job) for job in sorted(jobs.values(), key=lambda item: item["createdAt"], reverse=True)]


@app.post("/api/downloads")
async def create_download(payload: DownloadRequest, ytdlp_session: str | None = Cookie(default=None)) -> dict[str, list[dict[str, Any]]]:
    require_auth(ytdlp_session)
    created = []
    for url in payload.links:
        job_id = uuid.uuid4().hex
        job = {"id": job_id, "url": _validate_url(url), "title": url.split("/")[2], "detail": f"{payload.options.kind.title()} · {payload.options.container.upper()}", "options": payload.options.model_dump(), "status": "queued", "progress": 0, "createdAt": int(time.time()), "path": None}
        jobs[job_id] = job
        job_tasks[job_id] = asyncio.create_task(_run_job(job_id))
        created.append(_job_view(job))
    return {"jobs": created}


@app.get("/api/downloads/{job_id}")
async def get_download(job_id: str, ytdlp_session: str | None = Cookie(default=None)) -> dict[str, Any]:
    require_auth(ytdlp_session)
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Download not found")
    return _job_view(jobs[job_id])


@app.get("/api/downloads/{job_id}/file")
async def download_file(job_id: str, ytdlp_session: str | None = Cookie(default=None)) -> FileResponse:
    require_auth(ytdlp_session)
    job = jobs.get(job_id)
    if not job or job.get("status") != "done" or not job.get("path"):
        raise HTTPException(status_code=409, detail="File is not ready")
    path = Path(job["path"])
    if not path.is_file():
        raise HTTPException(status_code=410, detail="File is no longer available")
    return FileResponse(path, filename=job.get("fileName", path.name), media_type="application/octet-stream")
