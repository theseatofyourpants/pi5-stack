#!/usr/bin/env python3
"""
GreyNoise MCP server (local, stdio).

Wraps the GreyNoise API for the Pi 5 red/blue stack. Works KEYLESS out of the
box via the free Community endpoint; upgrades to full Context / RIOT / GNQL
lookups automatically when GREYNOISE_API_KEY is set in the environment.

Tools:
  - greynoise_community_ip(ip)   keyless: noise/riot/classification/name
  - greynoise_context_ip(ip)     full API: actor, tags, metadata, first/last seen
  - greynoise_riot_ip(ip)        full API: known-benign service lookup (RIOT)
  - greynoise_quick_ip(ip)       full API: fast noise/riot booleans
  - greynoise_gnql(query, size)  full API: GNQL search across the noise dataset

Design notes:
  - Community endpoint is keyless and rate-limited; it is the default path.
  - Full endpoints require a key; without one they return a clear, non-fatal note
    so a Haiku subagent can still proceed with community data.
"""
import os
import httpx
from mcp.server.fastmcp import FastMCP

API_KEY = os.environ.get("GREYNOISE_API_KEY", "").strip()
BASE = "https://api.greynoise.io"
UA = "pi5-greynoise-mcp/1.0"
TIMEOUT = 15.0

mcp = FastMCP("greynoise")


def _headers(auth: bool) -> dict:
    h = {"Accept": "application/json", "User-Agent": UA}
    if auth and API_KEY:
        h["key"] = API_KEY
    return h


def _need_key() -> dict:
    return {
        "error": "no_api_key",
        "note": "GREYNOISE_API_KEY is not set. Only the keyless community lookup "
        "(greynoise_community_ip) is available. Add a key to ~/.claude.json "
        "greynoise env to enable context/riot/gnql.",
    }


def _get(path: str, auth: bool, params: dict | None = None,
         fallback_ip: str | None = None) -> dict:
    try:
        with httpx.Client(timeout=TIMEOUT) as c:
            r = c.get(f"{BASE}{path}", headers=_headers(auth), params=params)
        if r.status_code == 404:
            # GreyNoise returns 404 for IPs it has never observed — that's a
            # valid, meaningful answer, not an error.
            try:
                body = r.json()
            except Exception:
                body = {}
            if fallback_ip:
                body.setdefault("ip", fallback_ip)
            body.setdefault("seen", False)
            body.setdefault("note", "IP not observed by GreyNoise.")
            return body
        if r.status_code in (401, 403):
            return {"error": "auth_failed", "status": r.status_code,
                    "note": "GreyNoise rejected the API key."}
        if r.status_code == 429:
            return {"error": "rate_limited", "status": 429,
                    "note": "GreyNoise rate limit hit — back off and retry."}
        r.raise_for_status()
        return r.json()
    except httpx.HTTPError as e:
        return {"error": "http_error", "detail": str(e)}


@mcp.tool()
def greynoise_community_ip(ip: str) -> dict:
    """Keyless GreyNoise Community lookup. Returns whether the IP is internet
    background NOISE (mass scanner), a RIOT common-business-service, its
    classification (benign/malicious/unknown), actor name, and last seen.
    Use this first for any triage/OSINT IP — it needs no API key."""
    return _get(f"/v3/community/{ip}", auth=False, fallback_ip=ip)


@mcp.tool()
def greynoise_context_ip(ip: str) -> dict:
    """Full GreyNoise Context for an IP (requires API key): classification,
    actor, tags/TTPs, spoofable, VPN/TOR flags, metadata (ASN, org, country,
    OS), and raw scan behavior. Richer than community; use for UNKNOWN alerts
    that need attribution."""
    if not API_KEY:
        return _need_key()
    # v3 unified IP endpoint: internet_scanner_intelligence (noise) +
    # business_service_intelligence (RIOT) in a single response.
    return _get(f"/v3/ip/{ip}", auth=True, fallback_ip=ip)


@mcp.tool()
def greynoise_riot_ip(ip: str) -> dict:
    """GreyNoise RIOT lookup (requires API key): is this IP a known benign
    common service (Google, Microsoft, CDNs, etc.)? Use to quickly discount
    an alerting IP as expected business traffic."""
    if not API_KEY:
        return _need_key()
    # v3 folds RIOT/business-service data into the unified IP endpoint; read
    # the business_service_intelligence block of the response.
    return _get(f"/v3/ip/{ip}", auth=True, fallback_ip=ip)


@mcp.tool()
def greynoise_quick_ip(ip: str) -> dict:
    """Fast GreyNoise noise/riot boolean check for an IP (requires API key).
    Lightweight — use when batching many IPs and you only need noise=true/false."""
    if not API_KEY:
        return _need_key()
    return _get(f"/v3/ip/{ip}", auth=True, params={"quick": "true"},
                fallback_ip=ip)


@mcp.tool()
def greynoise_gnql(query: str, size: int = 20) -> dict:
    """GreyNoise Query Language (GNQL) search across the noise dataset (requires
    API key). Examples: 'classification:malicious tags:\"Mirai\"',
    'metadata.organization:\"DigitalOcean\" raw_data.scan.port:445'. Returns
    matching observed scanners. Use for hunting infra patterns during OSINT."""
    if not API_KEY:
        return _need_key()
    return _get("/v3/gnql", auth=True,
                params={"query": query, "size": size})


if __name__ == "__main__":
    mcp.run()
