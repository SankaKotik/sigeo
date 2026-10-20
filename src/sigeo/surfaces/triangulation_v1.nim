## old unnamed triangulation algorithm
## has many bugs, but always produces quads
## well, "quads"
import std/[sequtils, algorithm, math, tables, hashes]
import ../core/[vectors, points, bounds2]
import ../curves2d/[icurve2, paths, contours]
import ./[isurface3, grids]


proc brepContains(brep: openArray[Curve2], p: Point2): bool =
  var c = 0
  
  # todo: intersections at same endpoints of multiple curves
  
  for curve in brep:
    for param in curve.xAxisIntersection(p.y):
      let curvePt = curve.pointAt(param)
      if curvePt.x < p.x: inc c
  c mod 2 == 1


proc makeGrid*(surface: Surface3, brep: openArray[Curve2], minU, minV, maxU, maxV, stepU, stepV: Float): Grid3 =
  result.kind = Quads

  assert minU <= maxU
  assert minV <= maxV
  assert stepU > 0
  assert stepV > 0

  let uCount = ((maxU - minU) / stepU).ceil.int
  let vCount = ((maxV - minV) / stepV).ceil.int
  if uCount * vCount <= 0: return

  var grid = newSeqOfCap[int32]((uCount + 2) * (vCount + 2))  # (uI * vCount + vI) -> (-1 if not in grid, index of the point in grid otherwise)
  template `[]`(grid: seq[int32], uI, vI: int): int32 = grid[(uI + 1) * (vCount + 2) + vI + 1]
  template exists(i: int32): bool = i >= 0
  template toU(uI: int): Float = minU + stepU * uI.Float
  template toV(vI: int): Float = minV + stepV * vI.Float

  for _ in 0..<(uCount+2): grid.add -1

  for uI in 0..<uCount:
    let u = uI.toU
    grid.add -1
    for vI in 0..<vCount:
      let v = minV + stepV * vI.Float
      let vert = point2(u, v)
      if brep.brepContains(vert):
        grid.add result.points.len.int32
        result.points.add surface.pointAt(vert)
      else:
        grid.add -1
    grid.add -1

  for _ in 0..<(uCount+2): grid.add -1

  for uI in 0..<uCount:
    let u = uI.toU
    var pts: seq[Point2]
    for curve in brep:
      for param in curve.yAxisIntersection(u):
        pts.add curve.pointAt(param)
    sort pts, proc(a, b: Point2): int = cmp(a.y, b.y)
    for ptI, pt in pts:
      let vIf = (pt.y - minV) / stepV
      let vI = (if ptI mod 2 == 0: vIf.floor.int else: vIf.ceil.int)
      if not grid[uI, vI].exists:
        grid[uI, vI] = result.points.len.int32
        result.points.add surface.pointAt(pt)
      else:
        result.points[grid[uI, vI]] = surface.pointAt(pt)
  
  for vI in 0..<vCount:
    let v = vI.toV
    var pts: seq[Point2]
    for curve in brep:
      for param in curve.xAxisIntersection(v):
        pts.add curve.pointAt(param)
    sort pts, proc(a, b: Point2): int = cmp(a.x, b.x)
    for ptI, pt in pts:
      let uIf = (pt.x - minU) / stepU
      let uI = (if ptI mod 2 == 0: uIf.floor.int else: uIf.ceil.int)
      if not grid[uI, vI].exists:
        grid[uI, vI] = result.points.len.int32
        result.points.add surface.pointAt(pt)
      else:
        result.points[grid[uI, vI]] = surface.pointAt(pt)
  
  for uI in -1..<uCount:
    for vI in -1..<vCount:
      if grid[uI, vI].exists and grid[uI + 1, vI].exists and grid[uI + 1, vI + 1].exists and grid[uI, vI + 1].exists:
        result.indices.add [grid[uI, vI], grid[uI + 1, vI], grid[uI + 1, vI + 1], grid[uI, vI + 1]]

      elif grid[uI, vI].exists and grid[uI + 1, vI].exists and grid[uI + 1, vI + 1].exists #[and grid[uI, vI + 1].exists]#:
        let p1 = result.points[grid[uI, vI]]
        let p2 = result.points[grid[uI+1, vI+1]]
        result.points.add p1 + (p2 - p1)/2
        result.indices.add [grid[uI, vI], result.points.high.int32, grid[uI + 1, vI + 1], grid[uI + 1, vI]]
      
      elif grid[uI, vI].exists and grid[uI + 1, vI].exists #[and grid[uI + 1, vI + 1].exists]# and grid[uI, vI + 1].exists:
        let p1 = result.points[grid[uI, vI+1]]
        let p2 = result.points[grid[uI+1, vI]]
        result.points.add p1 + (p2 - p1)/2
        result.indices.add [grid[uI, vI + 1], result.points.high.int32, grid[uI + 1, vI], grid[uI, vI]]
      
      elif grid[uI, vI].exists #[and grid[uI + 1, vI].exists]# and grid[uI + 1, vI + 1].exists and grid[uI, vI + 1].exists:
        let p1 = result.points[grid[uI+1, vI+1]]
        let p2 = result.points[grid[uI, vI]]
        result.points.add p1 + (p2 - p1)/2
        result.indices.add [grid[uI + 1, vI + 1], result.points.high.int32, grid[uI, vI], grid[uI, vI + 1]]
      
      elif #[grid[uI, vI].exists and]# grid[uI + 1, vI].exists and grid[uI + 1, vI + 1].exists and grid[uI, vI + 1].exists:
        let p1 = result.points[grid[uI, vI+1]]
        let p2 = result.points[grid[uI+1, vI]]
        result.points.add p1 + (p2 - p1)/2
        result.indices.add [grid[uI, vI + 1], result.points.high.int32, grid[uI + 1, vI], grid[uI + 1, vI + 1]]


proc makeGrid*(surface: Surface3, brep: openArray[Curve2], stepU, stepV: Float): Grid3 =
  let bounds = brep.mapIt(it.bounds).sum
  makeGrid(surface, brep, bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y, stepU, stepV)

proc makeGrid*(surface: Surface3, brep: openArray[Curve2], resolution = 16): Grid3 =
  let bounds = brep.mapIt(it.bounds).sum
  let stepU = bounds.size.x / resolution.Float
  let stepV = bounds.size.y / resolution.Float
  makeGrid(surface, brep, bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y, stepU, stepV)
