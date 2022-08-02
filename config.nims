from macros import error

# --mm:arc

when defined(musl):
  let muslGCC = findExe("musl-gcc")
  if muslGCC == "":
    error("musl-gcc not found in the PATH")
  --d:release
  --opt:size
  switch("gcc.exe", muslGCC)
  switch("gcc.linkerexe", muslGCC)
  switch("passL", "-static")

when defined(tcc):
  let tcc = findExe("tcc")
  if tcc == "":
    error("tcc not found in the PATH")
  --d:release
  --opt:size
  switch("gcc.exe", tcc)
  switch("gcc.linkerexe", tcc)
