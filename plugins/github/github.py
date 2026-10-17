"""GitHub – a plugin for Lotus (plugin.conf), in Python with nothing but its standard library.

    lotus repo <owner/name>    stars, forks and the newest release of a repository
    github.py zen              one of GitHub's zen lines (the start screen line)

The sandbox lets it use the internet (network = yes) and nothing of your files.
"""
import json
import os
import re
import sys
import urllib.request

API = "https://api.github.com"


def get(path):
    req = urllib.request.Request(API + path, headers={"Accept": "application/vnd.github+json", "User-Agent": "lotus-plugin-github"})
    with urllib.request.urlopen(req, timeout=10) as r:
        body = r.read().decode()
    return json.loads(body) if body.startswith(("{", "[")) else body


def repo(name):
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*", name or ""):
        print("Which repository? lotus repo owner/name")
        return 2
    try:
        r = get(f"/repos/{name}")
    except Exception as e:
        print(f"GitHub did not answer for {name}: {e}")
        return 1
    try:
        release = get(f"/repos/{name}/releases/latest").get("tag_name", "")
    except Exception:
        release = ""
    print(f"{r['full_name']} – {r.get('description') or 'no description'}")
    print(f"{r['stargazers_count']} stars · {r['forks_count']} forks · {r['open_issues_count']} open issues · {r.get('language') or 'no language'}"
          + (f" · newest release {release}" if release else ""))
    print(r["html_url"])
    return 0


def zen():
    try:
        print(get("/zen").strip())
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    word = sys.argv[1] if len(sys.argv) > 1 else ""
    if word == "repo":
        sys.exit(repo(sys.argv[2] if len(sys.argv) > 2 else os.environ.get("LOTUS_ARG_NAME", "")))
    if word == "zen":
        sys.exit(zen())
    print("lotus repo <owner/name>")
    sys.exit(2)
