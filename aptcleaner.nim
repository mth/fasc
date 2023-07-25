import std/[sequtils, sets, strutils, tables]
import utils

type Package = ref object
  name: string
  section: string
  depends: seq[seq[string]]
  recommends: seq[seq[string]]
  dependedBy: seq[Package]
  essential: bool
  important: bool
  required: bool
  autoInstall: bool

iterator packageFields(fileName: string): TableRef[string, string] =
  let f = open(fileName)
  defer: f.close
  var package = newTable[string, string]()
  while true:
    var line: string
    let eof = not f.readLine(line)
    if line.len != 0:
      let keyAndValue = line.split(": ", 1)
      if keyAndValue.len > 1:
        package[keyAndValue[0]] = keyAndValue[1]
    else:
      yield package
      package = newTable[string, string]()
      if eof:
        break

func addDepends(deps: var seq[seq[string]], str: string) =
  if str.len != 0:
    deps.add str.split(" | ").mapIt(it.split(", ").mapIt(it.split(' ', 1)[0]))

proc readStatus(): Table[string, Package] =
  for fields in packageFields("/var/lib/dpkg/status"):
    let name = fields.getOrDefault("Package")
    if name != "" and fields.getOrDefault("Status").endsWith(" ok installed"):
      let priority = fields.getOrDefault("Priority")
      let package = Package(name: name, section: fields.getOrDefault("Section"),
                            important: priority == "important",
                            essential: fields.getOrDefault("Essential") == "yes")
      package.required = package.essential or priority == "required"
      package.depends.addDepends fields.getOrDefault("Pre-Depends")
      package.depends.addDepends fields.getOrDefault("Depends")
      package.recommends.addDepends fields.getOrDefault("Recommends")
      result[name] = package
  for pkg in result.values:
    for depGroup in pkg.depends:
      block addGroup:
        var deps: seq[Package]
        for depName in depGroup:
          let dep = result.getOrDefault(depName, nil)
          if dep == nil:
            break addGroup # this dependency group couldn't have been used
          elif pkg notin dep.dependedBy:
            deps.add dep
        for dep in deps:
          dep.dependedBy.add pkg
  for fields in packageFields("/var/lib/apt/extended_states"):
    let package = result.getOrDefault(fields.getOrDefault("Package"))
    if package != nil and fields.getOrDefault("Auto-Installed") == "1":
      package.autoInstall = true

func wouldBeRemoved(package: Package): bool =
  return package.autoInstall and package.dependedBy.allIt(it.wouldBeRemoved)

func traceRecommends(trace: Package, packages: Table[string, Package],
                     recommended: var HashSet[string]) =
  for group in trace.recommends:
    for recommend in group:
      if recommend notin recommended:
        let package = packages.getOrDefault recommend
        if package != nil:
          recommended.incl recommend
          traceRecommends(package, packages, recommended)

func autoRemoveSet(packages: Table[string, Package]): HashSet[string] =
  for p in packages.values:
    if p.wouldBeRemoved:
      result.incl p.name
  var recommended: HashSet[string]
  for p in packages.values:
    if p.name notin result:
      traceRecommends(p, packages, recommended)
  result.excl recommended

proc prunePackages*(addPackages: openarray[string],
                    removePackages: openarray[string]) =
  let packageMap = readStatus()
  let initialDead = packageMap.autoRemoveSet
  let defaultAuto = toHashSet ["libs", "oldlibs", "perl", "python"]
  var protect = toHashSet ["libc6", "perl", "python3", "qtwayland5"]
  when defined(arm64) or defined(arm):
    protect.incl "ifupdown"

  # Should mark all removePackages and non-required libraries as auto
  var addPackageSet = addPackages.toHashSet
  var setAuto = removePackages.toHashSet
  var reduntantSetAuto: seq[string]
  for package in packageMap.values:
    if package.name in addPackageSet:
      package.autoInstall = false
      setAuto.excl package.name
      addPackageSet.excl package.name
    elif not package.required:
      if package.autoInstall:
        reduntantSetAuto.add package.name
      elif package.name in setAuto:
        package.autoInstall = true
      elif package.section in defaultAuto and package.name notin protect:
        package.autoInstall = true
        setAuto.incl package.name

  # Rescue earlier automatically installed packages, that are not libraries
  var nowDead = packageMap.autoRemoveSet
  nowDead.excl initialDead
  var retain: seq[string]
  for name in nowDead:
    let package = packageMap[name]
    if name notin setAuto and
        (package.required or package.section notin defaultAuto):
      retain.add name
      package.autoInstall = false

  # Should remove explicitly all important packages, that would be marked auto
  # and can be removed without removing non-auto/essential/required packages.
  var explicitRemove: seq[string]
  for name in setAuto.toSeq:
    let package = packageMap.getOrDefault(name)
    if package == nil:
      setAuto.excl name
    elif package.important and package.wouldBeRemoved:
      explicitRemove.add name
      setAuto.excl name

  for reduntant in reduntantSetAuto:
    setAuto.excl reduntant

  if retain.len != 0:
    runCmd("apt-mark", "manual" & retain)
  if setAuto.len != 0:
    runCmd("apt-mark", "auto" & setAuto.toSeq)
  if addPackageSet.len != 0:
    runCmd("apt-get", "update")
    runCmd("apt-get", @["install", "-y", "--no-install-recommends"] &
                      addPackageSet.toSeq)
  if explicitRemove.len != 0:
    runCmd("apt-get", "purge" & explicitRemove)
  if nowDead.len != 0:
    runCmd("apt-get", "autoremove", "--purge")
