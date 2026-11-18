#!/usr/bin/env python3
"""Fetch the store demo's hero route and write it as Dart.

The record panel shows one run of the demo account: a counter-clockwise lap of
Central Park's full loop of drives from Columbus Circle (the Central Park
Conservancy gives the full loop as 6.1 miles). Its
line and its elevation are real, fetched here, and written to
apps/mobile_android/integration_test/store/hero_route.dart (and the iOS twin),
which demo_data.dart times and puts a heart rate on. Re-running this is a
deliberate step: the diff of the generated file shows what moved upstream.

Sources:
  - Geometry: OpenStreetMap via the Overpass API (ODbL, (c) OpenStreetMap
    contributors), the ways named East Drive, West Drive and Center Drive
    that cars, bikes and runners share (footway sidewalks excluded).
  - Elevation: USGS 3D Elevation Program, Elevation Point Query Service
    (public domain), sampled every SAMPLE_M metres along the line. Central
    Park is covered by the 1 m lidar DEM.

Run from the repo root:  python3 -I assets/store/demo/hero_route.py
Network only; it takes a few minutes, most of it EPQS.
"""

import concurrent.futures
import datetime
import heapq
import json
import math
import pathlib
import sys
import time
import urllib.parse
import urllib.request

USER_AGENT = 'threkir-store-demo/1.0 (+https://github.com/jaredhoward-dev/threkir)'
OVERPASS = 'https://overpass-api.de/api/interpreter'
EPQS = 'https://epqs.nationalmap.gov/v1/json'
QUERY = (
    '[out:json][timeout:60];'
    'way["name"~"^(East|West|Center) Drive$"]["highway"~"^(pedestrian|unclassified|service)$"]'
    '(40.763,-73.983,40.801,-73.947);out body;>;out skel qt;'
)
# Where the lap starts (the West Drive just inside Columbus Circle) and the
# points it passes, in order: along Center Drive under Central Park South,
# north on the East Drive, round the north end, south on the West Drive. From
# here Harlem Hill falls inside the sixth kilometre, in the second half.
VIA = [
    (40.76927, -73.97992),
    (40.76722, -73.97700),
    (40.77000, -73.97130),
    (40.77900, -73.96680),
    (40.78800, -73.95850),
    (40.79650, -73.95200),
    (40.79950, -73.95600),
    (40.79300, -73.96400),
    (40.78300, -73.97200),
    (40.77400, -73.97800),
]
# Way ends this close to another way's node are joined: OSM splits the drive
# at a few junctions without sharing the node.
JOIN_M = 25.0
SAMPLE_M = 20.0
REPO = pathlib.Path(__file__).resolve().parents[3]
TARGETS = [
    REPO / 'apps/mobile_android/integration_test/store/hero_route.dart',
    REPO / 'apps/mobile_ios/integration_test/store/hero_route.dart',
]


def get(url, data=None):
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, data=data, headers={'User-Agent': USER_AGENT})
            body = urllib.request.urlopen(req, timeout=60).read().decode()
            if body.strip():
                return json.loads(body)
        except Exception as err:  # noqa: BLE001 - retried, then raised below
            last = err
        time.sleep(2 ** attempt)
    raise RuntimeError(f'{url}: {last if "last" in locals() else "empty body"}')


def hav(a, b):
    r = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def trace(osm):
    ways = [e for e in osm['elements'] if e['type'] == 'way']
    nodes = {e['id']: (e['lat'], e['lon']) for e in osm['elements'] if e['type'] == 'node'}
    adj, way_of = {}, {}
    for w in ways:
        for a, b in zip(w['nodes'], w['nodes'][1:]):
            d = hav(nodes[a], nodes[b])
            adj.setdefault(a, []).append((b, d))
            adj.setdefault(b, []).append((a, d))
            way_of[(a, b)] = way_of[(b, a)] = w['id']
    for w in ways:
        for end in (w['nodes'][0], w['nodes'][-1]):
            if len(adj[end]) > 1:
                continue
            near = [(hav(nodes[end], nodes[n]), n) for n in adj
                    if n != end and all(v != n for v, _ in adj[end])]
            d, n = min(near)
            if d < JOIN_M:
                adj[end].append((n, d))
                adj[n].append((end, d))

    def nearest(p):
        return min(adj, key=lambda n: hav(nodes[n], p))

    def shortest(s, t):
        dist, prev, pq = {s: 0.0}, {}, [(0.0, s)]
        while pq:
            d, u = heapq.heappop(pq)
            if u == t:
                break
            if d > dist[u]:
                continue
            for v, w in adj[u]:
                if d + w < dist.get(v, math.inf):
                    dist[v], prev[v] = d + w, u
                    heapq.heappush(pq, (d + w, v))
        path = [t]
        while path[-1] != s:
            path.append(prev[path[-1]])
        return path[::-1]

    via = [nearest(p) for p in VIA]
    lap = [via[0]]
    for a, b in zip(via, via[1:] + via[:1]):
        lap += shortest(a, b)[1:]
    used = sorted({way_of[(a, b)] for a, b in zip(lap, lap[1:]) if (a, b) in way_of})
    points = [nodes[lap[0]]]
    for n in lap[1:]:
        if hav(points[-1], nodes[n]) > 0.5:
            points.append(nodes[n])
    return points, used


def resample(points):
    cum = [0.0]
    for a, b in zip(points, points[1:]):
        cum.append(cum[-1] + hav(a, b))
    out, j = [], 0
    for k in range(int(cum[-1] // SAMPLE_M) + 1):
        d = k * SAMPLE_M
        while j < len(cum) - 2 and cum[j + 1] < d:
            j += 1
        f = (d - cum[j]) / (cum[j + 1] - cum[j])
        a, b = points[j], points[j + 1]
        out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    if hav(out[-1], points[-1]) > 1:
        out.append(points[-1])
    return out, cum[-1]


def elevation(p):
    q = urllib.parse.urlencode({'x': f'{p[1]:.7f}', 'y': f'{p[0]:.7f}', 'wkid': 4326,
                                'units': 'Meters', 'includeDate': 'false'})
    value = float(get(f'{EPQS}?{q}')['value'])
    if value < -500:
        raise RuntimeError(f'no USGS elevation at {p}')
    return value


def main():
    osm = get(OVERPASS, urllib.parse.urlencode({'data': QUERY}).encode())
    points, ways = trace(osm)
    samples, length = resample(points)
    with concurrent.futures.ThreadPoolExecutor(6) as pool:
        heights = list(pool.map(elevation, samples))
    rows = '\n'.join(f'  ({lat:.6f}, {lng:.6f}, {ele:.2f}),'
                     for (lat, lng), ele in zip(samples, heights))
    today = datetime.date.today().isoformat()
    dart = f'''// GENERATED by assets/store/demo/hero_route.py on {today}: do not edit.
//
// A counter-clockwise lap of Central Park's full loop of drives, starting on
// the West Drive just inside Columbus Circle: along Center Drive, north on the
// East Drive, round the north end, up Harlem Hill and south on the West Drive.
// {length:.0f} m traced; the park gives the full loop as 6.1 miles.
//
// Line: (c) OpenStreetMap contributors, ODbL 1.0, via the Overpass API; ways
// {', '.join(str(w) for w in ways)}.
// Elevation: USGS 3D Elevation Program, Elevation Point Query Service (public
// domain), one sample every {SAMPLE_M:.0f} m. Bare-earth heights, so the drive
// reads low where it crosses an arch; demo_data.dart smooths that out.

/// (latitude, longitude, elevation in metres) every {SAMPLE_M:.0f} m along the lap.
const List<(double, double, double)> kHeroRoute = [
{rows}
];
'''
    for target in TARGETS:
        target.write_text(dart)
        print(f'{target.relative_to(REPO)}: {len(samples)} points, {length:.0f} m')


if __name__ == '__main__':
    sys.exit(main())
