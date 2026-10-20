#!/usr/bin/env python3
"""Decode one bounded image sample per source, not an exhaustive CDN audit.

Requires Pillow only for this optional image verification. Public image URLs
remain references; this never proxies, retries, bypasses blocks or publishes.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener

from PIL import Image
from refresh_grocery_catalogs import json_write
from online_catalog import timestamp
from retail.transport import SafeHttpClient, _NoRedirect, USER_AGENT


def verify_group(group, folder, previously_blocked):
    host, samples=group;results=[];blocked=host in previously_blocked
    guard=SafeHttpClient([host],max_requests=len(samples),timeout=12)
    opener=build_opener(_NoRedirect())
    for index,item in enumerate(samples):
        report={'source':item['source'],'product_name':item['source_product_name'],
                'product_url':item['store_product_url'],'image_url':item['image_url'],
                'verified_image':False,'requested':False,'checked_at':None}
        try:
            if blocked:raise RuntimeError('CDN previously rejected an image request; no additional request made')
            if index:time.sleep(5)
            guard._validate_url(item['image_url'])
            report.update(requested=True,checked_at=datetime.now(timezone.utc).isoformat())
            with opener.open(Request(item['image_url'],headers={'User-Agent':USER_AGENT}),timeout=12) as response:
                report['http_status']=response.status;report['content_type']=response.headers.get('Content-Type','')
                if response.status!=200 or not report['content_type'].startswith('image/'):
                    blocked=True;raise RuntimeError('Incomplete or non-image response')
                data=response.read(2*1024*1024+1)
                if len(data)>2*1024*1024:raise RuntimeError('Image exceeds sample size budget')
            im=Image.open(io.BytesIO(data));fmt,size=im.format,im.size;im.verify()
            extension={'JPEG':'jpg','PNG':'png','WEBP':'webp','GIF':'gif'}.get(fmt)
            if not extension:raise RuntimeError('Unsupported image type')
            name=item['source']+'.'+extension;(folder/name).write_bytes(data)
            report.update(verified_image=True,format=fmt,width=size[0],height=size[1],
                          bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),file=name)
        except Exception as error:
            if isinstance(error,HTTPError):report['http_status']=error.code;blocked=True
            report['failure']=str(error)
        results.append(report)
        print(json.dumps({k:report.get(k) for k in ('source','http_status','verified_image','requested')},ensure_ascii=False),flush=True)
    return results


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True)
    p.add_argument('--prior-report',type=Path)
    args=p.parse_args();args.out_dir.mkdir(parents=True,exist_ok=False)
    samples={}
    for line in args.input.open():
        item=json.loads(line)
        if item.get('image_url'):samples.setdefault(item['source'],item)
    groups={}
    for item in samples.values():groups.setdefault(urlsplit(item['image_url']).hostname,[]).append(item)
    blocked=set()
    if args.prior_report:
        prior=json.loads(args.prior_report.read_text())
        for item in prior.get('results',[]):
            at=item.get('checked_at') or item.get('observed_at')
            if (item.get('http_status') in (401,403,412,429) and at
                    and timestamp(at)>datetime.now(timezone.utc)-timedelta(hours=24)):
                blocked.add(urlsplit(item.get('url') or item.get('image_url')).hostname)
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures=[pool.submit(verify_group,group,args.out_dir,blocked) for group in groups.items()]
        results=[r for future in futures for r in future.result()]
    json_write(args.out_dir/'report.json',{'scope':'One decoded sample per source; remaining URLs not downloaded',
               'sample_count':len(results),'verified':sum(r['verified_image'] for r in results),'results':results})


if __name__=='__main__':main()
