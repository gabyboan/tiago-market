"""Validated offers and conservative product identity, independent of any retailer."""
from dataclasses import asdict, dataclass, field, replace
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from enum import Enum
import re
import unicodedata
from urllib.parse import urlsplit


class PriceType(str, Enum):
    ONLINE = "ONLINE"
    STORE = "STORE"


def normalized_text(value: str) -> str:
    value = unicodedata.normalize("NFKD", value.casefold())
    value = "".join(c for c in value if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9.,]+", " ", value)).strip()


def valid_gtin(value: object) -> str | None:
    """Return the GS1-equivalent GTIN-14; never infer a barcode from a SKU."""
    if not isinstance(value, str) or not re.fullmatch(r"(?:\d{8}|\d{12}|\d{13}|\d{14})", value):
        return None
    if not any(c != "0" for c in value):
        return None
    checksum = sum(int(c) * (3 if i % 2 == 0 else 1)
                   for i, c in enumerate(reversed(value[:-1])))
    return value.zfill(14) if (checksum + int(value[-1])) % 10 == 0 else None


@dataclass(frozen=True)
class Presentation:
    quantity: Decimal
    unit: str
    pack_count: int

    @property
    def key(self) -> str:
        return f"{self.pack_count}x{self.quantity.normalize():f}{self.unit}"


_UNIT = r"(mililitros?|ml|litros?|ltos?|lts?|l|kilogramos?|kilos?|kg|gramos?|grs?|g|unidades?|piezas?|pzas?|rollos?)"
_AMOUNT = r"(\d+(?:[.,]\d+)?)"


def parse_presentation(value: str | None) -> Presentation | None:
    if not value:
        return None
    text = normalized_text(value)
    # A pack is a presentation, not just the sum of its contents.
    pack = re.search(r"\b(\d+)\s*(?:(?:piezas?|pzas?|pack|paquete|unidades?)\s*)?(?:de|x)\s*" + _AMOUNT + r"\s*" + _UNIT + r"\b", text)
    single = re.search(r"\b" + _AMOUNT + r"\s*" + _UNIT + r"\b", text)
    if pack:
        count, amount, unit = int(pack[1]), Decimal(pack[2].replace(",", ".")), pack[3]
    elif single:
        if re.search(r"\b(pack|paquete|multipack)\b|\bc\s*\d", text):
            return None  # Missing pack count is not evidence of a single item.
        count, amount, unit = 1, Decimal(single[1].replace(",", ".")), single[2]
    else:
        return None
    if count < 1 or count > 10000 or amount <= 0:
        return None
    if unit in ("kg", "kilo", "kilos", "kilogramo", "kilogramos"):
        amount, unit = amount * 1000, "g"
    elif unit.startswith("l"):
        amount, unit = amount * 1000, "ml"
    elif unit.startswith("mil") or unit == "ml":
        unit = "ml"
    elif unit.startswith("g"):
        unit = "g"
    elif unit.startswith("rollo"):
        unit = "rollo"
    else:
        unit = "unit"
    return Presentation(amount, unit, count)


@dataclass(frozen=True)
class Location:
    latitude: float | None = None
    longitude: float | None = None
    postal_code: str | None = None
    store_id: str | None = None

    def __post_init__(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Coordinates must be paired")
        if self.latitude is not None and not (-90 <= self.latitude <= 90 and -180 <= self.longitude <= 180):
            raise ValueError("Invalid coordinates")
        if self.postal_code is not None and not re.fullmatch(r"\d{5}", self.postal_code):
            raise ValueError("Invalid Mexican postal code")
        if self.store_id is not None and not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", self.store_id):
            raise ValueError("Invalid store identifier")


@dataclass(frozen=True)
class Capabilities:
    location: bool = False
    store_pricing: bool = False
    stock: bool = False
    gtin: bool = False
    discovery: str = "reviewed_catalog"


@dataclass(frozen=True)
class RetailOffer:
    retailer: str
    external_id: str
    name: str
    price: Decimal
    currency: str
    product_url: str
    source: str
    captured_at: str
    price_type: PriceType = PriceType.ONLINE
    gtin: str | None = None
    ean: str | None = None
    upc: str | None = None
    sku: str | None = None
    brand: str | None = None
    description: str | None = None
    presentation: str | None = None
    quantity: Decimal | None = None
    unit: str | None = None
    pack_count: int | None = None
    category: str | None = None
    image_url: str | None = None
    previous_price: Decimal | None = None
    discount: Decimal | None = None
    promotion: str | None = None
    availability: bool | None = None
    stock: int | None = None
    store_id: str | None = None
    store_name: str | None = None
    postal_code: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    pickup: bool | None = None
    delivery: bool | None = None
    membership_required: bool | None = None
    source_metadata: dict = field(default_factory=dict)
    quality_flags: tuple[str, ...] = ()

    @property
    def normalized_name(self):
        return normalized_text(self.name)

    @property
    def canonical_gtin(self):
        values = {g for value in (self.gtin, self.ean, self.upc) if (g := valid_gtin(value))}
        return next(iter(values)) if len(values) == 1 else None

    @property
    def identity(self):
        return (self.retailer, self.external_id, self.price_type.value, self.store_id,
                self.postal_code, self.membership_required)

    def to_dict(self):
        def encode(value):
            if isinstance(value, Decimal):
                return str(value)
            if isinstance(value, Enum):
                return value.value
            if isinstance(value, dict):
                return {k: encode(v) for k, v in value.items()}
            if isinstance(value, (tuple, list)):
                return [encode(v) for v in value]
            return value
        return {**encode(asdict(self)), "normalized_name": self.normalized_name}


def _money(value, field_name):
    if isinstance(value, bool):
        raise ValueError(f"Invalid {field_name}")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValueError(f"Invalid {field_name}") from None
    if not result.is_finite() or not 0 < result < 1000000:
        raise ValueError(f"Invalid {field_name}")
    return result


def validate_offer(offer: RetailOffer, now: datetime | None = None) -> RetailOffer:
    now = now or datetime.now(timezone.utc)
    if not re.fullmatch(r"[a-z0-9-]{1,60}", offer.retailer):
        raise ValueError("Invalid retailer")
    if not offer.name.strip() or len(offer.name) > 500 or not offer.external_id or len(offer.external_id) > 200:
        raise ValueError("Missing or invalid product identity")
    if not offer.source or len(offer.source) > 100:
        raise ValueError("Missing source")
    price = _money(offer.price, "price")
    if offer.currency != "MXN":
        raise ValueError("Only observed MXN offers are accepted")
    observed = datetime.fromisoformat(offer.captured_at.replace("Z", "+00:00"))
    if observed.tzinfo is None or observed > now + timedelta(minutes=5):
        raise ValueError("Invalid observation timestamp")
    if observed < now - timedelta(days=7):
        raise ValueError("Expired observation; cannot republish historical evidence as current")
    for url in (offer.product_url, offer.image_url):
        if url is not None:
            parsed = urlsplit(url)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError("Invalid HTTPS evidence URL")
    if not isinstance(offer.price_type, PriceType):
        raise ValueError("Invalid price type")
    if offer.price_type == PriceType.STORE and not offer.store_id:
        raise ValueError("Store price requires observed store ID")
    if offer.price_type == PriceType.ONLINE and any(v is not None for v in (
            offer.store_id, offer.store_name, offer.address, offer.latitude, offer.longitude)):
        raise ValueError("Online offer cannot claim a physical branch")
    Location(offer.latitude, offer.longitude, offer.postal_code, offer.store_id)
    if offer.availability is not None and type(offer.availability) is not bool:
        raise ValueError("Invalid availability")
    if offer.stock is not None and (type(offer.stock) is not int or offer.stock < 0):
        raise ValueError("Invalid stock")
    for value in (offer.membership_required, offer.pickup, offer.delivery):
        if value is not None and type(value) is not bool:
            raise ValueError("Invalid fulfillment or membership")
    flags = set(offer.quality_flags)
    barcodes = [b for b in (offer.gtin, offer.ean, offer.upc) if b is not None]
    if any(valid_gtin(b) is None for b in barcodes):
        flags.add("invalid_gtin")
    if len({valid_gtin(b) for b in barcodes if valid_gtin(b)}) > 1:
        flags.add("conflicting_gtin")
    pack = parse_presentation(offer.presentation or offer.name)
    if pack is None:
        flags.add("unknown_presentation")
    previous = _money(offer.previous_price, "previous price") if offer.previous_price is not None else None
    if previous is not None and previous <= price:
        flags.add("previous_price_not_higher")
    if offer.availability is None:
        flags.add("unknown_availability")
    if offer.stock == 0 and offer.availability is True:
        flags.add("inconsistent_stock")
    return replace(offer, price=price, previous_price=previous,
                   quantity=pack.quantity if pack else None, unit=pack.unit if pack else None,
                   pack_count=pack.pack_count if pack else None, quality_flags=tuple(sorted(flags)))


def match_offers(left: RetailOffer, right: RetailOffer) -> str | None:
    """Only strong identifiers or exact brand + variant + presentation auto-match.

    Fuzzy similarity can inform a human review; it never publishes a merge.
    Unknown presentations remain separate unless a valid GTIN resolves identity.
    """
    lpack, rpack = parse_presentation(left.presentation or left.name), parse_presentation(right.presentation or right.name)
    if lpack and rpack and lpack != rpack:
        return None
    if left.canonical_gtin and right.canonical_gtin:
        return "gtin" if left.canonical_gtin == right.canonical_gtin else None
    # Do not let corrupt or conflicting barcodes fall through into textual matching.
    if any(flag in ("invalid_gtin", "conflicting_gtin") for flag in (*left.quality_flags, *right.quality_flags)):
        return None
    if left.retailer == right.retailer and left.external_id == right.external_id:
        return "retailer_external_id"
    if not left.brand or not right.brand or normalized_text(left.brand) != normalized_text(right.brand):
        return None
    if lpack is None or rpack is None or lpack != rpack:
        return None
    def variant(offer):
        text = normalized_text(offer.name)
        text = re.sub(r"\b\d+\s*(?:(?:pack|paquete|piezas?)\s*)?(?:x|de)\s*" + _AMOUNT + r"\s*" + _UNIT + r"\b", " ", text)
        text = re.sub(r"\b" + _AMOUNT + r"\s*" + _UNIT + r"\b", " ", text)
        return re.sub(r"\s+", " ", text).strip()
    lname, rname = variant(left), variant(right)
    return "brand_variant_presentation" if lname and lname == rname else None
