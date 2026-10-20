import copy
import unittest
from prepare_reviewed_basket import prepare


def fixture():
    listings = [{'source': source, 'url': 'https://example.org/'+source,
                 'observed_name': source+' fixture 1 l', 'observed_presentation': '1 l'}
                for source in ['chedraui-mx', 'merco-mx']]
    manifest = {'reviewed_at': '2026-09-23T19:00:00Z', 'items': [{
        'canonical_variant_key': 'reviewed:fixture', 'label': 'Fixture',
        'brand': 'Fixture', 'category': 'Test', 'net_quantity': 1, 'unit': 'l',
        'pack_count': 1, 'match_basis': 'Synthetic test only', 'listings': listings}]}
    rows = [{'source': x['source'], 'store_product_url': x['url'],
             'source_product_name': x['observed_name'], 'presentation': '1 l',
             'price_scope': 'online', 'available': True, 'is_synthetic': False,
             'review_status': 'accepted', 'raw_payload': {'receipt': 'fixture'},
             'observed_at': '2026-09-23T19:00:00Z', 'content_hash': 'original'} for x in listings]
    return manifest, rows


class ReviewedBasketTest(unittest.TestCase):
    def test_preserves_receipts_identity_and_observation(self):
        manifest, rows = fixture()
        original = copy.deepcopy(rows)
        prepared, mapping = prepare(manifest, rows)
        self.assertEqual(rows, original)
        self.assertEqual(prepared[0]['observed_at'], rows[0]['observed_at'])
        self.assertEqual(prepared[0]['source_product_name'], rows[0]['source_product_name'])
        self.assertEqual(prepared[0]['content_hash'], 'original')
        self.assertEqual(prepared[0]['raw_payload']['receipt'], 'fixture')
        self.assertEqual(mapping[0]['canonical_variant_key'], mapping[1]['canonical_variant_key'])

    def test_rejects_partial_duplicate_extra_or_changed_input(self):
        manifest, rows = fixture()
        cases = [rows[:1], rows+rows[:1], rows+[dict(rows[0], store_product_url='https://example.org/extra')]]
        for field, value in [('presentation', '1.8 l'), ('source_product_name', 'Changed'),
                             ('price_scope', 'branch_local'), ('is_synthetic', True), ('available', False)]:
            changed = copy.deepcopy(rows)
            changed[0][field] = value
            cases.append(changed)
        for data in cases:
            with self.assertRaises(ValueError):
                prepare(manifest, data)


if __name__ == '__main__':
    unittest.main()
