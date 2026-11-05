#!/usr/bin/env python3
"""Authenticate, list and download Instagram stories with a local Instaloader session."""

import argparse
import json
import sys
from pathlib import Path

import instaloader
from instaloader.exceptions import TwoFactorAuthRequiredException


def make_loader(output: str | None = None) -> instaloader.Instaloader:
    return instaloader.Instaloader(
        sleep=False,
        quiet=True,
        dirname_pattern=output or "{target}",
        filename_pattern="{date_utc}_UTC_{typename}",
        download_video_thumbnails=False,
        save_metadata=False,
        compress_json=False,
        storyitem_metadata_txt_pattern="",
    )


def load_session(loader: instaloader.Instaloader, username: str, session_file: str) -> None:
    loader.load_session_from_file(username, session_file)
    if not loader.test_login():
        raise RuntimeError("A sessão salva do Instagram expirou. Conecte a conta novamente.")


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


def login(args) -> int:
    payload = json.loads(sys.stdin.readline() or "{}")
    loader = make_loader()
    try:
        loader.login(args.username, payload.get("password", ""))
    except TwoFactorAuthRequiredException:
        print(json.dumps({"status": "two_factor_required"}), flush=True)
        payload = json.loads(sys.stdin.readline() or "{}")
        loader.two_factor_login(payload.get("code", ""))
    loader.save_session_to_file(args.session_file)
    print(json.dumps({"status": "authenticated", "username": args.username}), flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("login", "list", "download"), required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--session-username")
    parser.add_argument("--session-file", required=True)
    parser.add_argument("--output")
    parser.add_argument("--id", dest="ids", action="append", default=[])
    args = parser.parse_args()

    try:
        if args.mode == "login":
            return login(args)

        loader = make_loader(args.output)
        load_session(loader, args.session_username or args.username, args.session_file)
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
