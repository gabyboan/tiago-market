"""Ingestion orchestration. No paid fallback can be activated implicitly."""
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
import time
from typing import Protocol

from .domain import Capabilities, Location, RetailOffer, validate_offer


class RetailProvider(Protocol):
    retailer: str
    capabilities: Capabilities

    def search_products(self, query: str, location: Location | None = None,
                        limit: int = 5) -> list[RetailOffer]: ...

    def get_product(self, external_id: str, location: Location | None = None) -> RetailOffer: ...


@dataclass
class ProviderRegistration:
    provider: RetailProvider
    paid: bool = False
    enabled: bool = True
    fallbacks: list[str] = field(default_factory=list)


class RetailService:
    def __init__(self, providers: dict[str, ProviderRegistration]):
        self.providers = providers
        self.metrics = {}

    def search(self, retailer: str, query: str, location: Location | None = None,
               limit: int = 5) -> list[RetailOffer]:
        query = query.strip()
        if not 1 <= len(query) <= 100 or any(ord(c) < 32 for c in query) or not 1 <= limit <= 10:
            raise ValueError("Invalid query or bounded page size")
        if retailer not in self.providers:
            raise ValueError("Unknown retailer")
        primary = self.providers[retailer]
        candidates = [retailer, *primary.fallbacks]
        last_error = None
        for key in dict.fromkeys(candidates):
            registration = self.providers[key]
            if not registration.enabled or registration.paid:
                continue  # Paid integration needs a separate explicit execution path.
            metrics = self.metrics.setdefault(key, Counter())
            started = time.monotonic()
            try:
                items = registration.provider.search_products(query, location, limit)
                metrics["items_found"] += len(items)
                unique = {}
                for item in items:
                    offer = validate_offer(item)
                    if offer.retailer != registration.provider.retailer:
                        raise ValueError("Provider returned a different retailer")
                    unique[offer.identity] = offer
                metrics["items_parsed"] += len(unique)
                metrics["success"] += 1
                metrics["last_success_at"] = datetime.now(timezone.utc).isoformat()
                return list(unique.values())[:limit]
            except (RuntimeError, ValueError, KeyError, TypeError) as error:
                metrics["failures"] += 1
                metrics["last_failure_at"] = datetime.now(timezone.utc).isoformat()
                last_error = error
            finally:
                metrics["duration_ms"] += round((time.monotonic() - started) * 1000)
        if last_error:
            raise last_error
        raise ValueError("No enabled own provider for this retailer")
