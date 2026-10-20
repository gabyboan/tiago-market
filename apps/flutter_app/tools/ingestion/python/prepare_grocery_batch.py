#!/usr/bin/env python3
"""Reconcile fresh observations with saved identities before generic staging.

Input is captured observations, not discovered product counts. Unknown unit or
identity conflicts remain held. This tool does not write to the database.
"""
import argparse
from collections import Counter, defaultdict
from copy import deepcopy
import hashlib
from html import unescape
import json
from pathlib import Path
import re

from online_catalog import timestamp
from retail.domain import normalized_text, parse_presentation
from refresh_grocery_catalogs import json_write


def comparable_name(name):
    text=normalized_text(unescape(unescape(name)))
    # Equivalent observed unit spellings and whitespace are identity aliases.
    text=re.sub(r'\b(?:grs?|gramos?)\b','g',text)
    text=re.sub(r'\b(?:ltos?|lts?|litros?)\b','l',text)
    text=re.sub(r'(\d)\s*(?:grs?|gramos?)\b',r'\1g',text)
    text=re.sub(r'(\d)\s*(?:ltos?|lts?|litros?)\b',r'\1l',text)
    text=re.sub(r'(\d)\s+(kg|ml|g|l)\b',r'\1\2',text)
    return text


def reconcile(rows, known):
    saved=defaultdict(list)
    for item in known:saved[(item['source'],item['store_product_url'])].append(item)
    accepted,held,identities,sku_conflicts=[],[],{},set()
    for original in rows:
        item=deepcopy(original);key=(item['source'],item['store_product_url'])
        evidence=item.get('raw_payload',{}).get('evidence') or {}
        if item['source'] in ('chedraui-mx','gran-bodega-mx'):
            sku=evidence.get('items',[{}])[0]
            if sku.get('measurementUnit') not in (None,'un') or sku.get('unitMultiplier') not in (None,1):
                held.append({'source':item['source'],'url':key[1],'sku':item['external_reference'],
                             'reason':'Weighted or multiplied price unit requires review'})
                continue
        product=evidence.get('store_api_product')
        if isinstance(product,dict):
            # Full replies remain in immutable HTTP evidence. Keep the facts
            # needed to substantiate this offer in staging, rather than repeating
            # large HTML descriptions and image srcsets for every snapshot.
            fields=('id','sku','name','type','variation','permalink','on_sale','prices',
                    'has_options','variations','is_purchasable','is_in_stock',
                    'is_on_backorder','stock_availability','low_stock_remaining','is_password_protected')
            projected={k:product.get(k) for k in fields}
            projected['categories']=[{k:c.get(k) for k in ('id','name','slug')} for c in product.get('categories',[])]
            projected['images']=[{k:i.get(k) for k in ('id','src','alt')} for i in product.get('images',[])]
            if item['source']=='smart-final-public-web':projected['short_description']=product.get('short_description')
            evidence['store_api_product']=projected
            evidence['projection_note']='Relevant public offer fields; original response retained separately with response_sha256'
        product=evidence.get('catalog_product')
        if item['source'] in ('garis-mx','mas-bodega-mx') and isinstance(product,dict):
            selected=evidence['selected_variant_id']
            variants=product.get('variants') or []
            projected={k:product.get(k) for k in ('id','title','handle','product_type','vendor')}
            projected['variants']=[{k:v.get(k) for k in
                (('id','product_id','title','sku','price','compare_at_price','available') if v['id']==selected
                 else ('id','product_id','title','available'))} for v in variants]
            projected['images']=[{k:i.get(k) for k in ('id','product_id','variant_ids','src')} for i in product.get('images',[])]
            evidence['catalog_product']=projected
            evidence['projection_note']='Selected piece price, variant identities and product images; full response retained with response_sha256'
        if item['source'] in ('chedraui-mx','gran-bodega-mx') and isinstance(evidence,dict) and 'productId' in evidence:
            sku=evidence['items'][0]
            seller=next(s for s in sku['sellers'] if s['sellerId']=='1')
            offer=seller['commertialOffer']
            fields=('Price','ListPrice','AvailableQuantity','IsAvailable','PriceValidUntil')
            projected={k:evidence.get(k) for k in ('productId','productName','link','categories')}
            projected['items']=[{'itemId':sku.get('itemId'),'ean':sku.get('ean'),
                'measurementUnit':sku.get('measurementUnit'),'unitMultiplier':sku.get('unitMultiplier'),
                'images':[{k:i.get(k) for k in ('imageId','imageUrl','imageLabel')} for i in sku.get('images',[])],
                'sellers':[{'sellerId':'1','commertialOffer':{k:offer.get(k) for k in fields}}]}]
            projected['all_seller_ids']=[s.get('sellerId') for s in sku['sellers']]
            projected['observed_presentation']=item['presentation']
            projected['projection_note']='First-party public price and declared quantity; original response retained with response_sha256'
            item['raw_payload']['evidence']=projected
        candidates=saved.get(key,[])
        matching=[p for p in candidates if comparable_name(p['external_name'])==comparable_name(item['source_product_name'])]
        shared_new=(item['source']=='compro-super-mx' and not matching)
        if candidates and len(matching)!=1 and not shared_new:
            held.append({'source':item['source'],'url':key[1],'sku':item['external_reference'],
                         'reason':'Existing URL has a different or ambiguous product identity'})
            continue
        if matching:
            previous=matching[0]
            new_pack,old_pack=parse_presentation(item['presentation']),parse_presentation(previous['presentation'])
            if (new_pack is None or old_pack is None or new_pack.key!=old_pack.key
                    or item['store_slug']!=previous['store_slug']):
                held.append({'source':item['source'],'url':key[1],'sku':item['external_reference'],
                             'reason':'Existing listing presentation or store changed'})
                continue
            # Preserve canonical spelling from saved listings after equivalence
            # is proven, rather than creating another global product.
            if item['normalized_name']!=previous['normalized_name']:
                item['raw_payload']['identity_reconciliation']={
                    'captured_normalized_name':item['normalized_name'],
                    'saved_normalized_name':previous['normalized_name'],
                    'basis':'same official product URL, equivalent name and presentation'}
                item['normalized_name']=previous['normalized_name']
            if not item.get('image_url') and previous.get('image_url'):
                item['image_url']=previous['image_url']
                item['raw_payload']['image_reference_note']='Retained prior image for the same validated listing; not a newly fetched image'
        identity=(item['source'],item['store_product_url'],item['normalized_name'])
        previous=identities.get(identity)
        if previous:
            if previous['external_reference']!=item['external_reference']:
                sku_conflicts.add(identity)
                held.append({'source':item['source'],'url':key[1],'sku':item['external_reference'],
                             'reason':'Different SKU shares the publication identity'})
                continue
            if timestamp(item['captured_at'])<=timestamp(previous['captured_at']):continue
        item.pop('content_hash',None)
        item['content_hash']=hashlib.sha256(json.dumps(item,sort_keys=True,ensure_ascii=False,allow_nan=False).encode()).hexdigest()
        identities[identity]=item
    accepted=[item for identity,item in identities.items() if identity not in sku_conflicts]
    # One normalized identity cannot describe different package sizes, even
    # across sources. Keep conflicting groups out of global products.
    packs=defaultdict(set)
    for previous in known:
        pack=parse_presentation(previous.get('presentation'))
        if pack:packs[previous['normalized_name']].add(pack.key)
    for item in accepted:
        pack=parse_presentation(item['presentation'])
        packs[item['normalized_name']].add(pack.key if pack else item['presentation'].casefold())
    conflicts={name for name,values in packs.items() if len(values)>1}
    sku_groups=defaultdict(set)
    for item in accepted:sku_groups[(item['source'],item['normalized_name'])].add(item['external_reference'])
    ambiguous_skus={key for key,values in sku_groups.items() if len(values)>1}
    safe=[]
    for item in accepted:
        if (item['source'],item['normalized_name']) in ambiguous_skus:
            held.append({'source':item['source'],'url':item['store_product_url'],'sku':item['external_reference'],
                         'reason':'Different SKUs share the same source product name and package'})
        elif item['normalized_name'] in conflicts:
            held.append({'source':item['source'],'url':item['store_product_url'],'sku':item['external_reference'],
                         'reason':'Normalized product identity has conflicting package sizes'})
        else:safe.append(item)
    return safe,held


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,action='append',required=True)
    p.add_argument('--known',type=Path,required=True)
    p.add_argument('--out-dir',type=Path,required=True)
    args=p.parse_args();args.out_dir.mkdir(parents=True,exist_ok=False)
    rows=[json.loads(line) for path in args.input for line in path.read_text().splitlines() if line.strip()]
    accepted,held=reconcile(rows,json.loads(args.known.read_text()))
    (args.out_dir/'accepted.ndjson').write_text(''.join(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n' for r in accepted))
    report={'input_rows':len(rows),'accepted':len(accepted),'held':held,
            'by_source':dict(Counter(r['source'] for r in accepted)),
            'images':sum(bool(r.get('image_url')) for r in accepted),'published':False}
    json_write(args.out_dir/'report.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='held'},ensure_ascii=False))


if __name__=='__main__':main()
