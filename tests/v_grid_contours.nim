## Visual test: `makeTriangulatedGrid` overload taking arbitrary curves
## (openArray[Curve2]) without guarantees, and `collectClosedContours` used by it.
##
## Random curves are generated: closed shapes (polygons, circles), shapes that
## overlap or touch each other at a single point, a nearly-closed polygon
## (ends within the point match tolerance), and open polylines that can't form
## any contour and must be dropped.
##
## Gray — all generated curves, thick colored — collected closed contours,
## orange — the resulting triangulation.
##
## [Space] — regenerate, [↑/↓] — change resolution.

import std/[math, random]
import pkg/[chroma, siwin]
import rice
import sigeo/[core, curves2d, surfaces]
import ./drawutils

const
  winSize = 900
  margin = 60.0
  tolerance = 1e-6

let app = newVisualTest(
  title = "sigeo v_grid_contours - curve soup → collected contours → triangulation, [Space] regenerate, [↑/↓] resolution",
  size = ivec2(winSize, winSize),
  contentCenter = vec2(winSize / 2, winSize / 2),
)

var resolution = 40

proc randomPoint(): Point2 =
  point2(rand(margin..winSize.Float - margin), rand(margin..winSize.Float - margin))

proc randomCurves(): seq[OwnedCurve2] =
  # closed star-shaped polygons; remember the first one to attach other shapes to it
  var firstCenter = p2(winSize / 2, winSize / 2)
  var firstCorner = p2(0, 0)

  for i in 0..<rand(2..3):
    let n = rand(3..5)
    let center = randomPoint()
    let radius = rand(80.0..180.0)
    if i == 0: firstCenter = center
    var angle = rand(0.0..2 * Pi)
    var verts: seq[Point2]
    for j in 0..<n:
      verts.add center + radius * rand(0.6..1.0) * v2(cos(angle), sin(angle))
      angle += 2 * Pi / Float(n) + rand(-0.25..0.25)
    if i == 0: firstCorner = verts[0]
    for j in 0..<n:
      result.add lineSection(verts[j], verts[(j + 1) mod n]).toOwnedCurve2

  # a small triangle attached to the first polygon at a single shared point
  block:
    let dir = rand(0.0..2 * Pi)
    let a = firstCorner + rand(60.0..110.0) * v2(cos(dir), sin(dir))
    let b = firstCorner + rand(60.0..110.0) * v2(cos(dir + rand(0.8..2.4)), sin(dir + rand(0.8..2.4)))
    result.add lineSection(firstCorner, a).toOwnedCurve2
    result.add lineSection(a, b).toOwnedCurve2
    result.add lineSection(b, firstCorner).toOwnedCurve2

  # a circle near the first polygon's center — often ends up inside it, forming a hole
  block:
    result.add circleArc(
      firstCenter + v2(rand(-15.0..15.0), rand(-15.0..15.0)), rand(15.0..25.0)
    ).toOwnedCurve2

  # two overlapping circles: the even-odd region is their symmetric difference
  block:
    let c = randomPoint()
    let r = rand(90.0..140.0)
    result.add circleArc(c, r).toOwnedCurve2
    result.add circleArc(c + v2(r * rand(0.5..1.2), 0), r * rand(0.8..1.2)).toOwnedCurve2

  # a polygon whose ends almost meet: the ~5e-7 gap is within the 1e-6
  # point match tolerance, so it still forms a closed contour
  block:
    let center = randomPoint()
    let radius = rand(60.0..120.0)
    let angle = rand(0.0..2 * Pi)
    var verts: seq[Point2]
    for j in 0..<4:
      verts.add center + radius * v2(cos(angle + Pi / 2 * Float(j)), sin(angle + Pi / 2 * Float(j)))
    verts[^1] = verts[0] + v2(4e-7, -4e-7)
    for j in 0..<3:
      result.add lineSection(verts[j], verts[j + 1]).toOwnedCurve2

  # open polylines — can't form a contour, must be dropped
  for i in 0..<rand(2..4):
    var cur = randomPoint()
    for j in 0..<rand(1..3):
      let dir = rand(0.0..2 * Pi)
      let next = cur + rand(40.0..140.0) * v2(cos(dir), sin(dir))
      result.add lineSection(cur, next).toOwnedCurve2
      cur = next


var curves: seq[OwnedCurve2]
var contours: seq[Path2]
var grid: Grid3
var mesh: Mesh

let plane = Plane3(axisX: v3(1, 0, 0), axisY: v3(0, 1, 0), axisZ: v3(0, 0, 1))

proc rebuild() =
  grid = plane.triangulate(curves.view, resolution, tolerance)
  mesh = grid.toGpu
  echo "resolution: ", resolution,
    ", points: ", grid.points.len,
    ", triangles: ", grid.indices.len div 3

proc regenerate() =
  curves = randomCurves()
  contours = collectClosedContours(curves.view, tolerance)
  echo "curves: ", curves.len, " → contours: ", contours.len
  rebuild()

proc drawWireframe(ctx: DrawContext, grid: Grid3, wireColor: Color, thickness: float32 = 1) =
  let cameraDir = normalize(ctx.viewportMatrix.inverse * vec3(0, 0, -1))
  for i in countup(0, grid.indices.high, 3):
    for j in 0..<3:
      let a = grid.points[grid.indices[i + j]]
      let b = grid.points[grid.indices[i + (j + 1) mod 3]]
      if a.distanceTo(b) > 1e-9:
        ctx.fillCapsule(
          color = wireColor,
          radius = thickness / 2,
          a = a.V3.vec3,
          b = b.V3.vec3,
          normal = cameraDir,
        )

randomize()
regenerate()


app.onAutoRun proc(ctx: DrawContext) =
  ## regenerate a few times and change resolution, saving screenshots
  app.saveScreenshot "soup0"
  for i in 1..<4:
    app.keyTap Key.space
    app.saveScreenshot "soup" & $i
  app.keyTap Key.up
  app.keyTap Key.up
  app.saveScreenshot "resolution_up"
  for i in 0..<4:
    app.keyTap Key.down
  app.saveScreenshot "resolution_down"


app.onKey proc(e: KeyEvent) =
  if e.pressed:
    case e.key
    of Key.space:
      regenerate()
      redraw e.window
    of Key.up:
      resolution = clamp(resolution + 8, 12, 160)
      rebuild()
      redraw e.window
    of Key.down:
      resolution = clamp(resolution - 8, 12, 160)
      rebuild()
      redraw e.window
    else: discard


app.run proc(ctx: DrawContext) =
  # the triangulation as a translucent fill
  push_blendRgbx ctx
  ctx.fill3dMeshShadedByNormalsSingleSide(mesh, color(1.0, 0.55, 0.25) * 0.55, color(1.0, 0.55, 0.25) * 0.35)
  pop_blendRgbx ctx

  ctx.drawWireframe(grid, color(1.0, 0.55, 0.25), thickness = 0.7)

  # all generated curves in gray
  for c in curves:
    let n = clamp(int(c.length / 8), 2, 512)
    ctx.drawPolyline(c.points(n), color(0.45, 0.45, 0.5), thickness = 1.2)

  # collected closed contours, a color per contour
  for i, contour in contours:
    let hue = (i * 67) mod 360
    let n = clamp(int(contour.length / 4), 3, 2048)
    ctx.drawPolyline(contour.points(n), hsv(hue.Float, 80, 95).color, thickness = 2.5)
