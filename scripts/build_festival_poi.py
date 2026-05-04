#!/usr/bin/env python3
"""Build offline POI bundles for each festival in Resources/festivals.json.

Queries OpenStreetMap (via the Overpass API) for amenity tags within a radius
around each festival's coordinates, then writes one GeoJSON file per festival
to Resources/festival_pois/<id>.geojson.

The radius scales with attendance:
  ≥40k → 4 km
  ≥10k → 2.5 km
  else → 1.5 km

We only fetch POI categories that genuinely matter to a festival-goer who
just lost cell signal: toilets, drinking water, first aid, defibrillators,
generic emergency, tourism info, fuel (some festivals are remote enough
that fuel matters), and parking.

Politeness: 2-second sleep between requests, automatic retry with
exponential backoff on transient errors. The script is idempotent — already
written files are skipped unless --force is passed.
"""
from __future__ import annotations
import argparse, json, sys, time
from pathlib import Path
from urllib import request, error

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "Resources" / "festivals.json"
OUT_DIR = REPO / "Resources" / "festival_pois"
OVERPASS = "https://overpass-api.de/api/interpreter"

# (osm_tag, festivair_category)
POI_TAGS = [
    ('amenity=toilets',           'toilet'),
    ('amenity=drinking_water',    'water'),
    ('amenity=first_aid',         'first_aid'),
    ('emergency=defibrillator',   'aed'),
    ('amenity=hospital',          'hospital'),
    ('amenity=clinic',            'clinic'),
    ('amenity=fuel',              'fuel'),
    ('amenity=parking',           'parking'),
    ('tourism=information',       'info'),
    ('amenity=charging_station',  'charging'),
    ('shop=convenience',          'shop'),
    ('amenity=cafe',              'cafe'),
]

def radius_m(attendance: int) -> int:
    if attendance >= 40_000: return 4000
    if attendance >= 10_000: return 2500
    return 1500

def overpass_query(lat: float, lon: float, radius: int) -> str:
    parts = []
    for tag, _ in POI_TAGS:
        key, val = tag.split("=", 1)
        parts.append(f'node["{key}"="{val}"](around:{radius},{lat},{lon});')
        parts.append(f'way["{key}"="{val}"](around:{radius},{lat},{lon});')
    return f"[out:json][timeout:30];\n(\n  " + "\n  ".join(parts) + "\n);\nout center;"

def fetch(query: str, retries: int = 3) -> dict:
    body = ("data=" + query).encode("utf-8")
    headers = {"User-Agent": "FestivAir-POI-Builder/1.0 (jax26ca@gmail.com)"}
    last_err = None
    for attempt in range(retries):
        try:
            req = request.Request(OVERPASS, data=body, headers=headers, method="POST")
            with request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (error.HTTPError, error.URLError, TimeoutError) as e:
            last_err = e
            wait = 5 * (2 ** attempt)
            print(f"    transient error: {e}; retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"Overpass failed after {retries} retries: {last_err}")

def to_geojson(osm: dict) -> dict:
    features = []
    tag_to_cat = {tag: cat for tag, cat in POI_TAGS}
    for el in osm.get("elements", []):
        tags = el.get("tags", {})
        cat = None
        for tag, c in tag_to_cat.items():
            k, v = tag.split("=", 1)
            if tags.get(k) == v:
                cat = c
                break
        if cat is None:
            continue
        if el.get("type") == "node":
            lat, lon = el.get("lat"), el.get("lon")
        else:
            center = el.get("center") or {}
            lat, lon = center.get("lat"), center.get("lon")
        if lat is None or lon is None:
            continue
        name = tags.get("name") or tags.get("operator") or cat.replace("_", " ").title()
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {
                "id": f"osm-{el.get('type','x')[0]}-{el.get('id')}",
                "category": cat,
                "name": name,
                "wheelchair": tags.get("wheelchair"),
                "fee": tags.get("fee"),
                "opening_hours": tags.get("opening_hours"),
                "source": "osm",
            }
        })
    return {"type": "FeatureCollection", "features": features}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="re-fetch festivals already on disk")
    ap.add_argument("--only", nargs="*", help="restrict to these festival ids")
    ap.add_argument("--sleep", type=float, default=2.0, help="seconds between Overpass requests (default 2)")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    festivals = json.loads(SRC.read_text())
    if args.only:
        festivals = [f for f in festivals if f["id"] in args.only]

    summary = []
    for i, f in enumerate(festivals, 1):
        out = OUT_DIR / f"{f['id']}.geojson"
        if out.exists() and not args.force:
            try:
                count = len(json.loads(out.read_text()).get("features", []))
                print(f"[{i}/{len(festivals)}] {f['id']}: SKIP ({count} features cached)")
                summary.append((f["id"], count, "cached"))
                continue
            except Exception:
                pass

        radius = radius_m(int(f.get("attendance", 0)))
        print(f"[{i}/{len(festivals)}] {f['id']} @ ({f['lat']}, {f['lon']}) r={radius}m ...", end=" ", flush=True)
        try:
            osm = fetch(overpass_query(f["lat"], f["lon"], radius))
            gj = to_geojson(osm)
            out.write_text(json.dumps(gj, indent=2))
            print(f"{len(gj['features'])} features")
            summary.append((f["id"], len(gj["features"]), "fetched"))
        except Exception as e:
            print(f"FAIL ({e})")
            summary.append((f["id"], 0, f"fail: {e}"))
        time.sleep(args.sleep)

    manifest = {
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "festivals": [
            {"id": fid, "feature_count": count, "status": status}
            for fid, count, status in summary
        ],
        "total_features": sum(c for _, c, _ in summary),
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2))

    fetched = sum(1 for _, _, s in summary if s == "fetched")
    cached = sum(1 for _, _, s in summary if s == "cached")
    failed = sum(1 for _, _, s in summary if s.startswith("fail"))
    print(f"\nDone. fetched={fetched} cached={cached} failed={failed} total_features={manifest['total_features']}")

if __name__ == "__main__":
    main()
