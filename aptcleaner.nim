import std/[sequtils, sets, strutils, tables]

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
  for fields in packageFields("pak/initial/status"):
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
  for fields in packageFields("pak/initial/extended_states"):
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

proc prunePackages(addPackages: openarray[string],
                   removePackages: openarray[string]) =
  let packageMap = readStatus()
  let initialDead = packageMap.autoRemoveSet
  let defaultAuto = toHashSet ["libs", "oldlibs", "python", "perl"]

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
      elif package.section in defaultAuto and package.name != "libc6":
        package.autoInstall = true
        setAuto.incl package.name

  var nowDead = packageMap.autoRemoveSet
  nowDead.excl initialDead
  var retain: seq[string]
  for name in nowDead:
    let package = packageMap[name]
    if name notin setAuto and
        (package.required or package.section notin defaultAuto):
      retain.add name
      package.autoInstall = false
  echo(" now dead: ", nowDead.toSeq.join(" "))

  var explicitRemove: seq[string]
  for name in setAuto.toSeq:
    let package = packageMap[name]
    if package.important and package.wouldBeRemoved:
      explicitRemove.add name
      setAuto.excl name

  for reduntant in reduntantSetAuto:
    setAuto.excl reduntant

  echo(" apt-mark manual ", retain.join(" "))
  echo(" apt-mark auto ", setAuto.toSeq.join(" "))
  echo(" apt-get install ", addPackageSet.toSeq.join(" "))
  echo(" apt-get purge ", explicitRemove.join(" "))

  # Maybe retain should be deduced automatically?
  # Basically first deduce packages that would get now autoremoved.
  # Then deduce packages that get autoremoved after the changes.
  # And if any of those are not in libs, python, perl or removePackages,
  # then mark them manual.
  #
  # Should mark all non-required libraries as auto.
  # Should mark all to be remove packages as auto.
  # Should remove explicitly all important packages, that would be marked auto
  # and can be removed without removing non-auto/essential/required packages.
  # Finally, should do autoremove, if there are any autoremovable packages
  # left that can be removed.

proc defaultPrune() =
  let remove = ["avahi-autoipd", "debian-faq", "discover", "doc-debian",
        "ifupdown", "installation-report", "isc-dhcp-client", "isc-dhcp-common",
        "liblockfile-bin", "nano", "netcat-traditional", "reportbug",
        "task-english", "task-laptop", "tasksel", "tasksel-data",
        "telnet", "vim-tiny", "vim-common"]
  prunePackages(# ["bluetooth", "ispell", "iw", "shared-mime-info"],
                ["elvis-tiny", "netcat-openbsd"], remove)

defaultPrune()

#var packages = readStatus()
#for p in packages.values:
#  var param = @[p.name]
#  if p.autoInstall:
#    param.add " auto"
#  if p.required:
#    param.add " required"
#  elif p.important:
#    param.add " important"
#  echo param.join
#  if p.depends.len != 0:
#    echo("  depends: ", p.depends.join(", "))
#  if p.dependedBy.len != 0:
#    echo("  depended by: ", p.dependedBy.mapIt(it.name).join(", "))
