"""Regression tests for product identity reconciliation before publication."""
from copy import deepcopy
import unittest

from prepare_grocery_batch import reconcile
from refresh_grocery_catalogs import parse_woo_product
from test_refresh_grocery_catalogs import response, woo


class ReconciliationTests(unittest.TestCase):
    def row(self):return parse_woo_product(woo(),response([woo()]),'fenix-mx')

    def known(self,item):
        return {'source':item['source'],'store_product_url':item['store_product_url'],
                'external_name':item['source_product_name'],'normalized_name':item['normalized_name'],
                'presentation':item['presentation'],'store_slug':item['store_slug'],'image_url':item['image_url']}

    def test_same_official_listing_keeps_canonical_identity_and_historical_image(self):
        item=self.row();known=self.known(item);known['normalized_name']='arroz fixture (500 g)'
        item['image_url']=None;before=deepcopy(item)
        rows,held=reconcile([item],[known])
        self.assertFalse(held);self.assertEqual(rows[0]['normalized_name'],known['normalized_name'])
        self.assertEqual(rows[0]['image_url'],known['image_url'])
        self.assertEqual(rows[0]['captured_at'],item['captured_at'])
        self.assertIn('Retained prior image',rows[0]['raw_payload']['image_reference_note'])
        self.assertEqual(item,before)

    def test_changed_presentation_on_existing_url_is_held(self):
        item=self.row();known=self.known(item);known['presentation']='1 kg'
        rows,held=reconcile([item],[known]);self.assertFalse(rows);self.assertEqual(len(held),1)

    def test_shared_compro_url_accepts_new_product_without_merging_saved_item(self):
        item=self.row();item.update(source='compro-super-mx',store_product_url='https://www.comprov.com.mx/tienda.html')
        known=self.known(item);known.update(external_name='Leche Otra 1 l',normalized_name='leche otra 1 l',presentation='1 l')
        rows,held=reconcile([item],[known]);self.assertEqual(len(rows),1);self.assertFalse(held)

    def test_same_name_pack_with_different_skus_are_both_held(self):
        a=self.row();b=deepcopy(a);b['external_reference']='another-sku';b['store_product_url']+='different/'
        rows,held=reconcile([a,b],[]);self.assertFalse(rows);self.assertEqual(len(held),2)

    def test_equivalent_unit_spelling_does_not_create_another_global_product(self):
        item=self.row();item.update(source_product_name='Arroz Fixture 500gr',normalized_name='arroz fixture 500gr')
        known=self.known(item);known.update(external_name='Arroz Fixture 500 g',normalized_name='arroz fixture 500 g')
        rows,held=reconcile([item],[known]);self.assertEqual(len(rows),1);self.assertFalse(held)
        self.assertEqual(rows[0]['normalized_name'],'arroz fixture 500 g')


if __name__=='__main__':unittest.main()
