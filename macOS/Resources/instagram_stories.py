#!/usr/bin/env python3
"""List and download selected Instagram stories using the bundled Instaloader."""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import instaloader
from instaloader.__main__ import get_cookies_from_instagram


def build_loader(browser: str | None, output: str | None = None) -> instaloader.Instaloader:
    loader = instaloader.Instaloader(
        sleep=False,
        quiet=True,
        dirname_pattern=output or "{target}",
        filename_pattern="{date_utc}_UTC_{typename}",
        download_video_thumbnails=False,
        save_metadata=False,
        compress_json=False,
        storyitem_metadata_txt_pattern="",
    )
    if browser and browser != "none":
        cookies = get_cookies_from_instagram("instagram", browser)
        loader.context.update_cookies(cookies)
        if not loader.test_login():
            raise RuntimeError(f"Não foi possível autenticar no Instagram usando {browser}.")
    return loader


def story_items(loader: instaloader.Instaloader, username: str):
    profile = instaloader.Profile.from_username(loader.context, username)
    stories = list(loader.get_stories([profile.userid]))
    if not stories:
        return []
    return list(stories[0].get_items())


def item_json(item) -> dict:
    date = item.date_local
    return {
        "id": str(item.mediaid),
        "shortcode": item.shortcode,
        "date": date.isoformat(),
        "timestamp": date.timestamp(),
        "kind": "Vídeo" if item.is_video else "Imagem",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("list", "download"), required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--browser", default="none")
    parser.add_argument("--output")
    parser.add_argument("--id", dest="ids", action="append", default=[])
    args = parser.parse_args()

    try:
        loader = build_loader(args.browser, args.output)
        items = story_items(loader, args.username)
        if args.mode == "list":
            print(json.dumps({"username": args.username, "items": [item_json(item) for item in items]}, ensure_ascii=False))
            return 0

        wanted = set(args.ids)
        selected = [item for item in items if str(item.mediaid) in wanted]
        if not selected:
            raise RuntimeError("Nenhum Story selecionado ainda está disponível.")
        output = Path(args.output or ".")
        output.mkdir(parents=True, exist_ok=True)
        for item in selected:
            loader.download_storyitem(item, str(output))
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
