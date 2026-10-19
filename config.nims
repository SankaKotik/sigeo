import os, strutils, strformat, sequtils, algorithm

const enable_incremental = NimMinor >= 3
const inecremental = if enable_incremental: "--ic:on" else: ""
let nim = getCurrentCompilerExe()

task test, "run tests":
  for (kind, path) in walkDir("tests").toSeq.sorted:
    if path.splitFile.ext == ".nim" and path.splitFile.name.startsWith("t_"):
      exec &"{nim} c {inecremental} -r {path}"

task vtest, "run visual tests":
  for (kind, path) in walkDir("tests").toSeq.sorted:
    if path.splitFile.ext == ".nim" and path.splitFile.name.startsWith("v_"):
      exec &"{nim} c {inecremental} -r {path}"

task vtestHeadless, "run visual tests headless (no window, auto-run + screenshots into ./local_screenshots)":
  for (kind, path) in walkDir("tests").toSeq.sorted:
    if path.splitFile.ext == ".nim" and path.splitFile.name.startsWith("v_"):
      exec &"{nim} c {inecremental} -d:headless -r {path}"
