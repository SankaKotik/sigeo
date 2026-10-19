## unnamed vibe-coded triangulation algorithm
## this is currently overcomplicated and not polished by human, # todo
##
## 1. discretizes the closed boundary contours into polylines
## 2. computes a Delaunay triangulation of a uv grid of candidate points and adds
##    to the grid only the triangles with all 3 points inside the surface
## 3. connects the contour polylines with the boundary of the resulting triangulation
##    by a Delaunay triangulation of their points, adding the triangles of it that
##    fall into the part of the surface not covered yet

import std/[sequtils, math, tables, hashes]
import ../core/[vectors, points, bounds2]
import ../curves2d/[icurve2, paths, contours]
import ./[isurface3, grids]

type
  DelaunayTriangle* = tuple[a, b, c: int32]
    ## indexes into the point set passed to `delaunayTriangles`, counterclockwise


proc circumcircle(a, b, c: Point2): tuple[x, y, r2: Float] =
  ## circumcircle of triangle abc, `r2 = Inf` for degenerate (collinear) triangles
  let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
  if d == 0:
    return (0, 0, Inf)
  let a2 = a.x * a.x + a.y * a.y
  let b2 = b.x * b.x + b.y * b.y
  let c2 = c.x * c.x + c.y * c.y
  let x = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
  let y = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
  (x, y, (a.x - x) * (a.x - x) + (a.y - y) * (a.y - y))

proc jittered(p: Point2, amount: Float, seed: int): Point2 =
  ## point shifted by a tiny deterministic pseudo-random offset.
  ## used to break exactly cocircular point configurations
  ## (e.g. points of a regular grid), which are not handled
  ## by Bowyer-Watson because of floating point rounding
  var h = hash(seed) !& hash(p.x) !& hash(p.y)
  let a = (h mod 65536).Float / 65536 * 2 * Pi
  h = !$h
  let b = (h mod 65536).Float / 65536 * 2 * Pi
  p + amount * v2(cos(a), sin(b))

proc delaunayTriangles*(points: openArray[Point2]): seq[DelaunayTriangle] =
  ## Delaunay triangulation of a planar point set (incremental Bowyer-Watson algorithm).
  ## returns counterclockwise triangles as indexes into `points`,
  ## zero-area triangles are not returned
  if points.len < 3: return

  var box = bounds2(points[0])
  for p in points: box.add p
  let center = box.center
  let d = max(max(box.size.x, box.size.y), 1e-9) * 20

  # a super-triangle big enough to contain all points (and all their circumcircles)
  var pts: seq[Point2]
  pts.add points
  let jitter = max(max(box.size.x, box.size.y), 1e-9) * 1e-6
  for i, p in pts.mpairs:
    p = jittered(p, jitter, i)
  let super = pts.len.int32
  pts.add point2(center.x - 3 * d, center.y - d)
  pts.add point2(center.x + 3 * d, center.y - d)
  pts.add point2(center.x, center.y + 3 * d)

  type StoredTri = object
    tri: DelaunayTriangle
    ccx, ccy, r2: Float

  var tris: seq[StoredTri]

  proc addTri(a, b, c: int32) =
    let t: DelaunayTriangle = if skew(pts[b] - pts[a], pts[c] - pts[a]) < 0: (a, c, b) else: (a, b, c)
    let cc = circumcircle(pts[t.a], pts[t.b], pts[t.c])
    tris.add StoredTri(tri: t, ccx: cc.x, ccy: cc.y, r2: cc.r2)

  addTri super, super + 1, super + 2

  for pI in 0..<points.len:
    let p = pts[pI]

    # cavity: triangles whose circumcircle contains the new point
    var cavity: seq[int]
    for i, t in tris:
      let dx = p.x - t.ccx
      let dy = p.y - t.ccy
      if dx * dx + dy * dy <= t.r2:
        cavity.add i
    if cavity.len == 0: continue

    # cavity boundary: edges that belong to only one cavity triangle
    var boundary: seq[(int32, int32)]
    for i in cavity:
      let t = tris[i].tri
      for e in [(t.a, t.b), (t.b, t.c), (t.c, t.a)]:
        block found:
          for j in 0..<boundary.len:
            if boundary[j] == (e[1], e[0]):
              boundary.del j
              break found
          boundary.add e

    # remove the cavity and retriangulate its boundary with the new point
    for i in countdown(cavity.high, 0):
      tris.del cavity[i]
    for e in boundary:
      addTri e[0], e[1], pI.int32

  for t in tris:
    if t.tri.a < super and t.tri.b < super and t.tri.c < super and
        skew(pts[t.tri.b] - pts[t.tri.a], pts[t.tri.c] - pts[t.tri.a]) > 0:
      result.add t.tri


proc polylinesContain(polylines: openArray[seq[Point2]], p: Point2): bool =
  ## even-odd point containment test for a set of closed polylines
  var crossings = 0
  for poly in polylines:
    for i in 0..<poly.len:
      let a = poly[i]
      let b = poly[(i + 1) mod poly.len]
      if (a.y > p.y) != (b.y > p.y):
        let t = (p.y - a.y) / (b.y - a.y)
        if a.x + t * (b.x - a.x) > p.x:
          inc crossings
  crossings mod 2 == 1


proc triangulate*(
  surface: Surface3, contours: openArray[Path2],
  minU, minV, maxU, maxV: Float,
  stepU, stepV: Float,
): Grid3 =
  ## triangulated grid bounded by closed 2d contours, an alternative to `makeGrid`
  ## that outputs `GridKind.Triangles` (see the comment above the Delaunay utils).
  ## the surface is locally tested at discrete points, so it is an approximation:
  ## triangles may slightly overshoot at concave boundary parts
  result.kind = Triangles

  assert minU <= maxU
  assert minV <= maxV
  assert stepU > 0
  assert stepV > 0

  let step = min(stepU, stepV)

  # --- 1. contours → closed polylines ---
  var polylines: seq[seq[Point2]]
  for contour in contours:
    if contour.curves.len == 0: continue
    let n = clamp(ceil(contour.length / step).int, 6, 4096)
    var poly: seq[Point2]
    for i in 0..<n:
      poly.add contour.pointAt(i / n)
    polylines.add move poly

  proc inside(p: Point2): bool = polylinesContain(polylines, p)

  proc centroid(a, b, c: Point2): Point2 =
    ((a.V2 + b.V2 + c.V2) / 3).toPoint

  var points3: seq[Point3]

  template vertexFor(map: var seq[int32], i: int, uv: Point2): int32 =
    ## index of the point `uv` in the resulting grid, computing it on first use
    if map[i] < 0:
      map[i] = points3.len.int32
      points3.add surface.pointAt(uv)
    map[i]

  # --- 2. interior triangulation: grid of candidate points, triangles with
  #        all 3 points inside the surface are kept ---
  let uCount = ((maxU - minU) / stepU).ceil.int
  let vCount = ((maxV - minV) / stepV).ceil.int
  if uCount < 1 or vCount < 1: return

  var gridPts: seq[Point2]
  for uI in 0..<uCount:
    for vI in 0..<vCount:
      gridPts.add point2(minU + stepU * uI.Float, minV + stepV * vI.Float)

  var kept: seq[DelaunayTriangle]
  for tri in delaunayTriangles(gridPts):
    if inside(gridPts[tri.a]) and inside(gridPts[tri.b]) and inside(gridPts[tri.c]):
      kept.add tri

  var gridVertexMap = newSeqWith(gridPts.len, -1'i32)
  for tri in kept:
    result.indices.add [
      gridVertexMap.vertexFor(tri.a, gridPts[tri.a]),
      gridVertexMap.vertexFor(tri.b, gridPts[tri.b]),
      gridVertexMap.vertexFor(tri.c, gridPts[tri.c]),
    ]

  # directed boundary edges of the interior triangulation
  # (the triangulated region stays on the left, as around counterclockwise triangles)
  var boundaryEdges: seq[(int32, int32)]
  block:
    var useCount: Table[(int32, int32), int]
    var direction: Table[(int32, int32), (int32, int32)]
    for tri in kept:
      for e in [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)]:
        let key = (min(e[0], e[1]), max(e[0], e[1]))
        inc useCount.mgetOrPut(key, 0)
        direction[key] = e
    for key, n in useCount:
      if n == 1:
        boundaryEdges.add direction[key]

  # --- 3. connect contour polylines with the interior triangulation boundary ---
  var bandPts: seq[Point2]
  var bandHash: Table[(int64, int64), seq[int]]
  let mergeTol = step * 1e-3
  let mergeCell = max(mergeTol * 2, 1e-12)

  proc bandPoint(p: Point2): int =
    ## index of a point in `bandPts`, merging points closer than `mergeTol`
    let cell = (int64(floor(p.x / mergeCell)), int64(floor(p.y / mergeCell)))
    for dx in -1'i64..1'i64:
      for dy in -1'i64..1'i64:
        for i in bandHash.getOrDefault((cell[0] + dx, cell[1] + dy)):
          if bandPts[i].distanceTo(p) <= mergeTol:
            return i
    result = bandPts.len
    bandPts.add p
    bandHash.mgetOrPut(cell, @[]).add result

  for poly in polylines:
    for p in poly:
      discard bandPoint(p)

  var coveredEdges: seq[(int, int)]
  for e in boundaryEdges:
    coveredEdges.add (bandPoint(gridPts[e[0]]), bandPoint(gridPts[e[1]]))

  var bandVertexMap = newSeqWith(bandPts.len, -1'i32)

  proc covered(p: Point2): bool =
    ## point inside the region already occupied by the interior triangulation
    ## (winding number over its boundary, region on the left)
    var winding: Float = 0
    for e in coveredEdges:
      let u = bandPts[e[0]] - p
      let v = bandPts[e[1]] - p
      winding += arctan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
    abs(winding) > Pi

  if bandPts.len >= 3:
    for tri in delaunayTriangles(bandPts):
      let cen = centroid(bandPts[tri.a], bandPts[tri.b], bandPts[tri.c])
      if inside(cen) and not covered(cen):
        result.indices.add [
          bandVertexMap.vertexFor(tri.a, bandPts[tri.a]),
          bandVertexMap.vertexFor(tri.b, bandPts[tri.b]),
          bandVertexMap.vertexFor(tri.c, bandPts[tri.c]),
        ]

  result.points = move points3


proc triangulate*(surface: Surface3, contours: openArray[Path2], stepU, stepV: Float): Grid3 =
  let bounds = contours.mapIt(it.bounds).sum
  if bounds.empty: return Grid3(kind: Triangles)
  triangulate(
    surface, contours,
    bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y,
    max(stepU, 1e-9), max(stepV, 1e-9),
  )

proc triangulate*(surface: Surface3, contours: openArray[Path2], resolution = 16): Grid3 =
  let bounds = contours.mapIt(it.bounds).sum
  if bounds.empty: return Grid3(kind: Triangles)
  let stepU = max(bounds.size.x / resolution.Float, 1e-9)
  let stepV = max(bounds.size.y / resolution.Float, 1e-9)
  triangulate(
    surface, contours,
    bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y,
    stepU, stepV,
  )


proc triangulate*(
  surface: Surface3, brep: openArray[Curve2],
  minU, minV, maxU, maxV: Float,
  stepU, stepV: Float,
  tolerance: Float = 1e-6,
): Grid3 =
  ## version taking arbitrary curves without guarantees that they form contours:
  ## closed contours are first collected out of them (see `collectClosedContours`),
  ## parts of curves that don't form closed loops are dropped
  triangulate(
    surface, collectClosedContours(brep, tolerance),
    minU, minV, maxU, maxV,
    max(stepU, 1e-9), max(stepV, 1e-9),
  )

proc triangulate*(surface: Surface3, brep: openArray[Curve2], stepU, stepV: Float, tolerance: Float = 1e-6): Grid3 =
  let bounds = brep.mapIt(it.bounds).sum
  if bounds.empty: return Grid3(kind: Triangles)
  triangulate(
    surface, brep,
    bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y,
    stepU, stepV,
    tolerance,
  )

proc triangulate*(surface: Surface3, brep: openArray[Curve2], resolution = 16, tolerance: Float = 1e-6): Grid3 =
  let bounds = brep.mapIt(it.bounds).sum
  if bounds.empty: return Grid3(kind: Triangles)
  let stepU = max(bounds.size.x / resolution.Float, 1e-9)
  let stepV = max(bounds.size.y / resolution.Float, 1e-9)
  triangulate(
    surface, brep,
    bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y,
    stepU, stepV,
    tolerance,
  )
