import asyncio
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi import HTTPException
from fastapi.testclient import TestClient

temporary = tempfile.TemporaryDirectory()
os.environ.update(APP_PASSWORD="local-test-password", SESSION_SECRET="local-test-secret", DATA_DIR=temporary.name)
import server
from instagram import InstagramService, download_media, media_url, profile_username

ORIGINAL_CLIENT = httpx.AsyncClient


def sample(story_id, video=False):
    item = {"pk": str(story_id), "taken_at": 1793880000,
            "image_versions2": {"candidates": [{"url": f"https://test.cdninstagram.com/{story_id}.jpg", "width": 1080}]}}
    if video:
        item["video_versions"] = [{"url": f"https://test.fbcdn.net/{story_id}.mp4", "width": 1080}]
    return item


class InstagramChecks(unittest.IsolatedAsyncioTestCase):
    async def test_completed_expire_after_24_hours_without_affecting_active_jobs(self):
        now = 2000000000
        old_id, fresh_id, active_id = 'a' * 32, 'b' * 32, 'c' * 32
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for job_id in (old_id, fresh_id, active_id):
                (base / job_id).mkdir()
                (base / job_id / 'video.mp4').write_bytes(b'video')
            records = {
                old_id: {'status': 'done', 'finishedAt': now - 86400},
                fresh_id: {'status': 'done', 'finishedAt': now - 86399},
                active_id: {'status': 'active', 'finishedAt': now - 90000},
            }
            with patch.object(server, 'DATA_DIR', base), patch.object(server, 'jobs', records), patch.object(server, 'job_tasks', {}):
                server.cleanup_completed(now)
                self.assertNotIn(old_id, records)
                self.assertFalse((base / old_id).exists())
                self.assertTrue((base / fresh_id / 'video.mp4').exists())
                self.assertTrue((base / active_id / 'video.mp4').exists())
                self.assertEqual(set(records), {fresh_id, active_id})

    async def test_cache_quota_and_public_response(self):
        calls = []
        def handler(request):
            calls.append(request)
            return httpx.Response(200, json={"result": [sample(1), sample(2, True)]})
        def client(**kwargs):
            return ORIGINAL_CLIENT(transport=httpx.MockTransport(handler), **kwargs)
        with tempfile.TemporaryDirectory() as directory, patch("instagram.httpx.AsyncClient", client):
            service = InstagramService("server-key-only", Path(directory), request_limit=1)
            first = await service.list_stories("@Virginia")
            cached = await service.list_stories("https://www.instagram.com/stories/virginia/123/")
            self.assertEqual(len(calls), 1)
            self.assertTrue(cached["cached"])
            self.assertEqual(first["collectionId"], cached["collectionId"])
            self.assertNotIn("server-key-only", str(first))
            self.assertNotIn("fbcdn", str(first))
            with self.assertRaises(HTTPException) as error:
                await service.list_stories("other")
            self.assertEqual(error.exception.status_code, 429)
            with self.assertRaises(HTTPException):
                service.selected(first["collectionId"], ["999"])

    async def test_cdn_redirect_cannot_reach_internal_host(self):
        requests = []
        def handler(request):
            requests.append(request)
            self.assertNotIn("x-rapidapi-key", request.headers)
            return httpx.Response(302, headers={"location": "http://127.0.0.1/private"})
        with tempfile.TemporaryDirectory() as directory, patch("instagram.httpx.AsyncClient", lambda **kw: ORIGINAL_CLIENT(transport=httpx.MockTransport(handler), **kw)):
            with self.assertRaises(HTTPException):
                await download_media("https://test.fbcdn.net/file", Path(directory) / "file", 1024)
            self.assertEqual(len(requests), 1)

    async def test_only_selected_files_are_delivered(self):
        async def fake_download(url, destination, maximum, **kwargs):
            destination.write_bytes(url.encode())
            return len(url)
        service = InstagramService("key", Path(temporary.name))
        collection_id = "a" * 32
        service.collections[collection_id] = {"id": collection_id, "username": "virginia", "expiresAt": 9999999999,
            "items": {str(i): {"id": str(i), "kind": "video" if i == 2 else "image", "media": f"https://test.fbcdn.net/{i}", "thumbnail": "https://test.fbcdn.net/image"} for i in (1,2,3)}}
        transport = httpx.ASGITransport(app=server.app)
        with patch.object(server, "instagram", service), patch.object(server, "download_media", fake_download):
            async with ORIGINAL_CLIENT(transport=transport, base_url="https://local.test") as client:
                self.assertEqual((await client.post("/api/instagram/stories", json={"username": "virginia"})).status_code, 401)
                self.assertEqual((await client.get(f"/api/instagram/collections/{collection_id}/stories/1/thumbnail")).status_code, 401)
                login = await client.post("/api/auth/login", json={"password": "local-test-password"})
                self.assertIn("HttpOnly", login.headers["set-cookie"])
                self.assertIn("SameSite=lax", login.headers["set-cookie"])
                response = await client.post("/api/instagram/downloads", json={"collectionId": collection_id, "storyIds": ["1", "2"]})
                self.assertEqual(response.status_code, 200)
                created = response.json()["jobs"]
                self.assertEqual(len(created), 2)
                results = {}
                for job in created:
                    await server.job_tasks[job["id"]]
                    file = await client.get(f'/api/downloads/{job["id"]}/file')
                    self.assertEqual(file.status_code, 200)
                    results[server.jobs[job["id"]]["fileName"]] = file.content
                self.assertEqual(results, {"virginia-story-1.jpg": b"https://test.fbcdn.net/1", "virginia-story-2.mp4": b"https://test.fbcdn.net/2"})
                single = await client.post("/api/instagram/downloads", json={"collectionId": collection_id, "storyIds": ["2"]})
                single_id = single.json()["jobs"][0]["id"]
                await server.job_tasks[single_id]
                self.assertTrue(server.jobs[single_id]["fileName"].endswith(".mp4"))
                invalid = await client.post("/api/instagram/downloads", json={"collectionId": collection_id, "storyIds": ["3", "3"]})
                self.assertEqual(invalid.status_code, 400)
                service.collections[collection_id]["expiresAt"] = 0
                self.assertEqual((await client.post("/api/instagram/downloads", json={"collectionId": collection_id, "storyIds": ["1"]})).status_code, 410)

    def test_input_validation(self):
        self.assertEqual(profile_username("@virginia"), "virginia")
        for url in ["https://127.0.0.1/a", "https://test.fbcdn.net.evil.com/a", "https://test.fbcdn.net:80/a", "http://test.fbcdn.net/a"]:
            with self.assertRaises(ValueError):
                media_url(url)


if __name__ == "__main__":
    unittest.main()
