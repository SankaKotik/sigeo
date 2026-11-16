import ./[vectors, points]


type
  Bounds3* = object
    min*: Point3 = point3(+Inf)
    max*: Point3 = point3(-Inf)

  BvhNodeKind* = enum
    bvhBrunch
    bvhLeaf
  
  HasBounds3* = concept x
    x.bounds3 is Bounds3

  BvhNode3*[T: HasBounds3] {.acyclic.} = ref object
    bounds3*: Bounds3
    case kind*: BvhNodeKind
    of bvhBrunch:
      left*, right*: BvhNode3
    of bvhLeaf:
      objects*: seq[T]


template bounds3*(b: Bounds3): untyped = b


proc center*(b: Bounds3): Point3 =
  ((b.min.V3 + b.max.V3) / 2).P3


proc isEmpty*(b: Bounds3): bool =
  b.min.x > b.max.x


proc add*(a: var Bounds3, p: Point3) =
  a.min.x = min(a.min.x, p.x)
  a.min.y = min(a.min.y, p.y)
  a.min.z = min(a.min.z, p.z)
  a.max.x = max(a.max.x, p.x)
  a.max.y = max(a.max.y, p.y)
  a.max.z = max(a.max.z, p.z)

proc add*(a: var Bounds3, b: Bounds3) =
  a.min.x = min(a.min.x, b.min.x)
  a.min.y = min(a.min.y, b.min.y)
  a.min.z = min(a.min.z, b.min.z)
  a.max.x = max(a.max.x, b.max.x)
  a.max.y = max(a.max.y, b.max.y)
  a.max.z = max(a.max.z, b.max.z)


proc `+`*(a: Bounds3, b: Point3|Bounds3): Bounds3 =
  result = a
  result.add b

template `+`*(a: Point3, b: Bounds3): Bounds3 = b + a


template bounds3FromIterator*(v: iterable[HasBounds3]): Bounds3 =
  var res = Bounds3()
  for x in v:
    res.add x.bounds3
  res



when isMainModule:
  let objects = [
    (bounds3: Bounds3(min: p3(0, 0, 0), max: p3(100, 100, 100))),
    (bounds3: Bounds3(min: p3(50, 20, 70), max: p3(150, 40, 90))),
    (bounds3: Bounds3(min: p3(60, -20, 70), max: p3(70, -10, 90))),
    (bounds3: Bounds3(min: p3(0, 0, 0), max: p3(0, 0, 0))),
    (bounds3: Bounds3(min: p3(0, 0, 0), max: p3(0, 100, 0))),
    (bounds3: Bounds3()),
  ]

  echo bounds3FromIterator(objects.items)


