import std/[sequtils, strutils, tables]

type Package = ref object
  name: string
  section: string
  depends: seq[seq[string]]
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
  result = initTable[string, Package]()
  for fields in packageFields("pak/status"):
    let name = fields.getOrDefault("Package")
    if name != "" and fields.getOrDefault("Status").endsWith(" ok installed"):
      let priority = fields.getOrDefault("Priority")
      let package = Package(name: name, section: fields.getOrDefault("section"),
                            important: priority == "important",
                            essential: fields.getOrDefault("Essential") == "yes")
      package.required = package.essential or priority == "required"
      package.depends.addDepends fields.getOrDefault("Pre-Depends")
      package.depends.addDepends fields.getOrDefault("Depends")
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
  for fields in packageFields("pak/extended_states"):
    let package = result.getOrDefault(fields.getOrDefault("Package"))
    if package != nil and fields.getOrDefault("Auto-Installed") == "1":
      package.autoInstall = true


proc prunePackages(retainPackages: openarray[string],
                   addPackages: openarray[string],
                   removePackages: openarray[string]) =
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
  echo "Do something"

proc defaultPrune() =
  let remove = ["debian-faq", "discover", "doc-debian", "ifupdown",
        "installation-report", "isc-dhcp-client", "isc-dhcp-common",
        "liblockfile-bin", "nano", "netcat-traditional",
        "python3-reportbug", "reportbug", "task-english", "task-laptop",
        "tasksel", "tasksel-data", "telnet", "vim-tiny", "vim-common"]
  prunePackages(["bluetooth", "ispell", "iw", "shared-mime-info"],
                ["elvis-tiny", "netcat-openbsd"], remove)

var packages = readStatus()
for p in packages.values:
  var param = @[p.name]
  if p.autoInstall:
    param.add " auto"
  if p.required:
    param.add " required"
  elif p.important:
    param.add " important"
  echo param.join
  if p.depends.len != 0:
    echo("  depends: ", p.depends.join(", "))
  if p.dependedBy.len != 0:
    echo("  depended by: ", p.dependedBy.mapIt(it.name).join(", "))
