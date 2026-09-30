#!/usr/bin/env python3
"""Snapshot QXO pack sizes for Versico fasteners and plates.

Queries the gorilla-integrations gateway (itemDetails) for each product family
and prints every variant as: family | size | pack | itemNumber | name.
Used to regenerate lib/data/qxo_pack_sizes.dart.

Usage: GORILLA_GATEWAY_KEY=... python3 tools/qxo_pack_sizes.py
"""
import json, os, re, sys, urllib.request

GATEWAY = os.environ.get("GORILLA_GATEWAY_URL", "https://gorilla-integrations.vercel.app")
KEY = os.environ["GORILLA_GATEWAY_KEY"]

def call(path, body):
    req = urllib.request.Request(GATEWAY + path, data=json.dumps(body).encode(),
        headers={"content-type": "application/json", "x-gorilla-key": KEY})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def pack(text):
    m = re.search(r"([\d,]+)\s*(carton|case|box|bucket|pail|bag|pack)", text or "", re.I)
    return int(m.group(1).replace(",", "")) if m else None

def search(q, n=25):
    return (call("/api/qxo/product", {"query": q, "pageSize": n}).get("data") or {}).get("items") or []

def variants(item_number):
    d = call("/api/qxo/product", {"itemNumber": item_number}).get("data") or {}
    for s in d.get("skuList") or []:
        v = s.get("variations") or {}
        size = ((v.get("length") or v.get("size") or v.get("diameter") or [None])[0])
        yield size, pack((v.get("packaging") or [""])[0]) or pack(s.get("productName")), s.get("itemNumber"), s.get("productName")

queries = sys.argv[1:] or ["Versico HPV Fasteners", "Versico HPVX Fasteners", "Versico HPV-XL",
    "Versico MP 14-10 Fasteners", "Versico CD-10", "Versico Insulation Fastening Plates",
    "Versico Seam Fastening Plates", "Versico HPVX Fastening Plates", "Versico RhinoBond Plates",
    "Versico Polymer Gyptec", "Versico Termination Bar Fasteners"]
seen = set()
for q in queries:
    for it in search(q):
        if (it.get("brand") or "").lower() != "versico":
            continue
        base = (it.get("currentSKU") or {}).get("itemNumber") or it.get("itemNumber")
        fam = it.get("internalProductName") or it.get("productName")
        if fam in seen or not re.search(r"fasten|plate|screw|anchor", fam or "", re.I):
            continue
        seen.add(fam)
        for size, pk, num, name in variants(base):
            print(f"{fam} | {size} | {pk} | {num} | {name}")
