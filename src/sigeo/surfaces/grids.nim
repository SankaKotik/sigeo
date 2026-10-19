import ../core/[vectors, points]

type
  GridKind* = enum
    Triangles
    TriangleStrip
    TriangleFan
    Quads

  Grid3* = object
    ## interconnected discrete 3d shell
    kind*: GridKind
    points*: seq[Point3]
    indices*: seq[int32]


proc triangulate*(grid: sink Grid3): Grid3 =
  result = move grid

  if result.kind == Quads:
    var indices = move result.indices
    result.indices = newSeqOfCap[int32]((indices.high div 4) * 6)
    for i in countup(0, indices.high, 4):
      result.indices.add [indices[i], indices[i+1], indices[i+2], indices[i], indices[i+2], indices[i+3]]
    result.kind = Triangles


proc computeVertexNormals*(vertices: openArray[Point3], indices: openArray[int]): seq[V3] =
  result = newSeq[V3](vertices.len)

  for i in countup(0, indices.high, 3):
    let a = vertices[indices[i]]
    let b = vertices[indices[i+1]]
    let c = vertices[indices[i+2]]
    var n = cross(b - a, c - a)
    result[indices[i]] += n
    result[indices[i+1]] += n
    result[indices[i+2]] += n

  for i, v in result.mpairs:
    v = v.normalize



