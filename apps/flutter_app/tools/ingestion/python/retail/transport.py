"""Bounded public HTTP: fixed origins, robots, pacing, cache, and no bypass."""
from collections import Counter, OrderedDict
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import ipaddress
import json
import socket
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.robotparser import RobotFileParser

USER_AGENT = "TiagoMarketBot/0.2 (+https://github.com/gabyboan/tiago-market)"


class FetchError(RuntimeError):
    def __init__(self, reason: str, status: int | None = None):
        super().__init__(reason)
        self.status = status


@dataclass(frozen=True)
class HttpResponse:
    url: str
    status: int
    text: str
    observed_at: str
    sha256: str
    content_type: str
    content_range: str | None = None


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class SafeHttpClient:
    def __init__(self, allow_hosts, *, timeout=20, delay=5, max_requests=30,
                 max_bytes=4 * 1024 * 1024, cache_ttl=900, cache_entries=32,
                 opener=None, resolver=socket.getaddrinfo,
                 clock=time.monotonic, sleep=time.sleep, accepted_statuses=(200,)):
        self.allow_hosts = frozenset(allow_hosts)
        self.accepted_statuses = frozenset(accepted_statuses)
        if self.accepted_statuses not in (frozenset({200}), frozenset({200, 206})):
            raise ValueError("Only explicit read-only partial responses may be enabled")
        if not self.allow_hosts or any("/" in h or ":" in h for h in self.allow_hosts):
            raise ValueError("Expected a fixed hostname allowlist")
        if not 1 <= timeout <= 60 or not 1 <= max_requests <= 500 or not 1 <= max_bytes <= 8 * 1024 * 1024 or cache_entries < 1:
            raise ValueError("Unsafe transport limits")
        self.timeout, self.delay = timeout, max(5, delay)
        self.max_requests, self.max_bytes = max_requests, max_bytes
        self.cache_ttl, self.cache_entries = max(0, cache_ttl), cache_entries
        self.opener = opener or build_opener(_NoRedirect())
        self.resolver, self.clock, self.sleep = resolver, clock, sleep
        self._cache, self._robots, self._last = OrderedDict(), {}, {}
        self._blocked = set()
        # A single worker per instance also coalesces concurrent identical requests.
        self._lock = threading.Lock()
        self.metrics = Counter()
        self.receipts = []

    def _validate_url(self, url):
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or parsed.hostname not in self.allow_hosts
                or parsed.username or parsed.password or parsed.port not in (None, 443)
                or parsed.fragment or len(url) > 2048 or any(ord(c) < 32 for c in url)):
            raise FetchError("URL outside the provider allowlist")
        try:
            addresses = self.resolver(parsed.hostname, 443, type=socket.SOCK_STREAM)
        except OSError:
            raise FetchError("DNS lookup failed") from None
        if not addresses or any(not ipaddress.ip_address(row[4][0]).is_global for row in addresses):
            raise FetchError("Non-public address rejected")
        return parsed

    def _request(self, url, data=None):
        parsed = self._validate_url(url)
        host = parsed.hostname
        if host in self._blocked:
            raise FetchError("Origin circuit open; no more requests this run")
        if self.metrics["requests"] >= self.max_requests:
            raise FetchError("Run request budget exhausted")
        delay = max(self.delay, self._robots[host].crawl_delay(USER_AGENT) or 0) if host in self._robots else self.delay
        if host in self._last:
            self.sleep(max(0, self._last[host] + delay - self.clock()))
        self._last[host] = self.clock()
        self.metrics["requests"] += 1
        started = self.clock()
        try:
            try:
                response = self.opener.open(Request(url, data=data, headers={
                    "User-Agent": USER_AGENT, "Accept": "text/html,application/json,text/plain",
                    "Accept-Encoding": "identity",
                    **({"Content-Type": "application/json"} if data is not None else {}),
                }), timeout=self.timeout)
            except HTTPError as error:
                response = error
            with response:
                status = response.status
                content_type = response.headers.get("Content-Type", "")
                content_range = response.headers.get("Content-Range")
                body = response.read(self.max_bytes + 1)
                if response.geturl() != url:
                    raise FetchError("Redirect rejected")
            observed = datetime.now(timezone.utc).isoformat()
            sha = hashlib.sha256(body).hexdigest()
            self.receipts.append({"url": url, "status": status, "observed_at": observed,
                                  "sha256": sha, "bytes": len(body), "content_range": content_range,
                                  "duration_ms": round((self.clock() - started) * 1000)})
            if status in (401, 403, 412, 429) or status >= 500:
                self._blocked.add(host)
                raise FetchError(f"Origin stopped at HTTP {status}", status)
            if status not in self.accepted_statuses:
                raise FetchError(f"Unexpected HTTP {status}", status)
            if len(body) > self.max_bytes:
                raise FetchError("Response exceeds byte budget")
            lower = body.lower()
            if any(marker in lower for marker in (b"cf-chl-", b"px-captcha", b"captcha challenge", b"incapsula incident id")):
                self._blocked.add(host)
                raise FetchError("Access challenge; origin stopped")
            result = HttpResponse(url, status, body.decode("utf-8"), observed, sha, content_type, content_range)
            self.metrics["success"] += 1
            return result
        except (TimeoutError, socket.timeout):
            self.metrics["timeouts"] += 1
            self.metrics["failures"] += 1
            self._blocked.add(host)
            raise FetchError("HTTP timeout; origin stopped") from None
        except (URLError, UnicodeError, OSError):
            self.metrics["failures"] += 1
            self._blocked.add(host)
            raise FetchError("HTTP transport failed; origin stopped") from None
        except FetchError:
            self.metrics["failures"] += 1
            raise
        finally:
            self.metrics["duration_ms"] += round((self.clock() - started) * 1000)

    def get(self, url: str) -> HttpResponse:
        return self._fetch(url)

    def post_json(self, url: str, payload: dict) -> HttpResponse:
        """For provider-owned, read-only search endpoints; never accepts client URLs."""
        data = json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
        if len(data) > 8192:
            raise FetchError("Search body exceeds byte budget")
        return self._fetch(url, data)

    def _fetch(self, url: str, data=None) -> HttpResponse:
        with self._lock:
            parsed = self._validate_url(url)
            key = (url, hashlib.sha256(data).hexdigest() if data is not None else None)
            cached = self._cache.get(key)
            if cached and self.clock() - cached[0] < self.cache_ttl:
                self.metrics["cache_hits"] += 1
                self._cache.move_to_end(key)
                return cached[1]  # Retain original capture time on cache hits.
            host = parsed.hostname
            if host not in self._robots:
                robots_url = f"https://{host}/robots.txt"
                try:
                    response = self._request(robots_url)
                    if response.status != 200:
                        raise FetchError("Incomplete robots response; no product request")
                    if "user-agent:" not in response.text.lower() or "<html" in response.text.lower():
                        raise FetchError("Invalid robots response; no product request")
                    rules = RobotFileParser(robots_url)
                    rules.parse(response.text.splitlines())
                except FetchError as error:
                    if error.status != 404:
                        raise
                    rules = RobotFileParser(robots_url)
                    rules.parse([])
                self._robots[host] = rules
            if not self._robots[host].can_fetch(USER_AGENT, url):
                raise FetchError("robots.txt disallows this resource")
            result = self._request(url, data)
            self._cache[key] = (self.clock(), result)
            while len(self._cache) > self.cache_entries:
                self._cache.popitem(last=False)
            return result
