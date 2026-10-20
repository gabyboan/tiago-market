#!/usr/bin/env python3
"""Read saved Walmart/Sam's public homepage cards, preserving held candidates.

No network or publication. Homepage availability is useful discovery evidence,
but seller, membership, promotion and geographic scope need further validation.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit

from expand_grocery_sources import next_data, money, observed_presentation
from online_catalog import objects
from refresh_grocery_catalogs import json_write

HOSTS={'walmart-mx':'www.walmart.com.mx','sams-mx':'www.sams.com.mx'}


def inspect(body, metadata, source):
    if (metadata['url']!=f'https://{HOSTS[source]}/' or metadata['status']!=200
            or hashlib.sha256(body).hexdigest()!=metadata['sha256']):
        raise ValueError('Complete, hashed official homepage evidence required')
    props=next_data(body.decode())['props']['pageProps']
    if props.get('isMocksEnabled') is not False or props.get('isNextPublicMocksEnabled') is not False:
        raise ValueError('Mock storefront content must never become a capture')
    if props.get('bootstrapData',{}).get('cv',{}).get('shared',{}).get('_all_',{}).get('currency')!='MXN':
        raise ValueError('Explicit MXN storefront currency required')
    products=[p for p in objects(props.get('initialTempoData')) if 'priceInfo' in p and 'name' in p]
    candidates,issues,seen=[],[],set()
    for product in products:
        key=(product.get('usItemId'),product.get('sellerId'),product.get('offerId'))
        if key in seen:continue
        seen.add(key)
        try:
            amount=money(product['priceInfo']['currentPrice']['price'])
            available={'IN_STOCK':True,'OUT_OF_STOCK':False}.get(product.get('availabilityStatus'))
            if available is None:raise ValueError('Unknown card availability')
            url=urljoin(f'https://{HOSTS[source]}/',product.get('canonicalUrl') or '')
            parsed=urlsplit(url)
            if (parsed.netloc!=HOSTS[source] or not parsed.path.startswith('/ip/')
                    or parsed.path.rsplit('/',1)[-1]!=str(product.get('usItemId'))):
                raise ValueError('Product link and card identity disagree')
            presentation=None
            try:presentation=observed_presentation(product['name'])
            except ValueError:pass
            flags=(product.get('badges') or {}).get('flags') or []
            candidate={'source':source,'name':product['name'],'external_reference':product['usItemId'],
                'seller_id':product.get('sellerId'),'seller_name':product.get('sellerName'),
                'seller_type':product.get('sellerType'),'offer_id':product.get('offerId'),
                'price':amount,'currency':'MXN','available':available,'presentation':presentation,
                'product_url':f'https://{HOSTS[source]}{parsed.path}',
                'image_url':(product.get('imageInfo') or {}).get('thumbnailUrl'),
                'sales_unit_type':product.get('salesUnitType'),'fulfillment_type':product.get('fulfillmentType'),
                'price_info':product['priceInfo'],'promotion_flags':flags,
                'captured_at':metadata['observed_at'],'response_sha256':metadata['sha256'],
                'source_url':metadata['url'],'review_status':'held','is_synthetic':False,
                'hold_reason':('Membership, seller, promotion and fulfillment scope need verification' if source=='sams-mx'
                               else 'Seller and fulfillment scope need verification; product pages currently reject access')}
            candidates.append(candidate)
        except (ValueError,KeyError,TypeError) as error:
            issues.append({'external_reference':product.get('usItemId'),'reason':str(error)})
    return {'source':source,'cards_read':len(products),'unique_offers_read':len(seen),
            'candidates':candidates,'rejected':issues,'publishable':0,'published':False,
            'captured_at':metadata['observed_at'],'full_catalog_traversed':False}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--html',type=Path,required=True);p.add_argument('--metadata',type=Path,required=True)
    p.add_argument('--source',choices=HOSTS,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();report=inspect(args.html.read_bytes(),json.loads(args.metadata.read_text()),args.source)
    json_write(args.out,report)
    print(json.dumps({k:v for k,v in report.items() if k not in ('candidates','rejected')},ensure_ascii=False))


if __name__=='__main__':main()
