"""Offline fixtures only; never published."""
import json
import unittest
from datetime import datetime, timezone, timedelta
from online_catalog import parse_product, validate

NOW = datetime(2026, 9, 23, 12, tzinfo=timezone.utc)
URL = 'https://www.smartnfinal.com.mx/tienda/fixture/'


def page(**changes):
    product = {'@type': 'Product', 'name': 'Fixture rice 1 kg', 'sku': 'fixture',
               'offers': {'@type': 'Offer', 'price': 12.5, 'priceCurrency': 'MXN',
                          'availability': 'https://schema.org/InStock', 'priceValidUntil': '2026-09-24'}}
    product['offers'].update(changes)
    return '<script type="application/ld+json">'+json.dumps(product)+'</script>'


def parse(html=None):
    return parse_product(html or page(), URL, 'smart-final', NOW.isoformat(), 'a'*64)


class OnlineCaptureTest(unittest.TestCase):
    def test_observation_and_trace_are_preserved(self):
        record = parse()
        validate(record, NOW)
        self.assertEqual(record['observed_at'], NOW.isoformat())
        self.assertEqual(record['source_url'], URL)
        self.assertEqual(record['presentation'], '1 kg')
        self.assertEqual(record['currency'], 'MXN')
        self.assertEqual(record['response_sha256'], 'a'*64)
        self.assertNotIn('branch_id', record)

    def test_expired_offer(self):
        with self.assertRaisesRegex(ValueError, 'Expired'):
            parse(page(priceValidUntil='2026-06-30'))

    def test_currency_and_unavailable(self):
        for changes in [{'priceCurrency': 'USD'}, {'availability': 'https://schema.org/OutOfStock'}, {'price': 0}]:
            with self.assertRaises(ValueError):
                parse(page(**changes))

    def test_old_or_future_receipt_is_not_relabelled(self):
        for offset in [-8, 1]:
            record = parse()
            record['observed_at'] = (NOW+timedelta(days=offset)).isoformat()
            with self.assertRaisesRegex(ValueError, 'Expired/future'):
                validate(record, NOW)

    def test_missing_presentation(self):
        with self.assertRaisesRegex(ValueError, 'presentation'):
            parse(page().replace('Fixture rice 1 kg', 'Fixture rice'))

    def test_no_branch_assignment_or_synthetic(self):
        for extra in [{'branch_id': 'fake'}, {'latitude': 19.43}, {'is_synthetic': True}]:
            with self.assertRaises(ValueError):
                validate(parse() | extra, NOW)

    def test_reject_ambiguous_multi_offer(self):
        with self.assertRaises(ValueError):
            parse(page()+page())

    def test_reject_visible_promotion_even_if_jsonld_claims_future(self):
        with self.assertRaisesRegex(ValueError, 'Promotion'):
            parse(page()+'<div class="summary entry-summary"><del>$99</del><div class="woocommerce-tabs">')


if __name__ == '__main__':
    unittest.main()
