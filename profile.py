"""Variable number of nodes in a lan, automatically converted to NixOS.

Instructions:
Wait for the experiment to start. The nodes will boot a hidden Ubuntu base, automatically run
`nixos-infect` to install NixOS, and reboot. Once they come back online, you can
log in via SSH using the local username and GitHub keys you specified.
"""

import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

pc = portal.Context()
request = pc.makeRequestRSpec()

# --- NIXOS PARAMETERS ---
pc.defineParameter(
    "githubUser",
    "GitHub Username",
    portal.ParameterType.STRING,
    "yamada-sexta",
    longDescription="The GitHub username whose public SSH keys will be injected into NixOS.",
)

pc.defineParameter(
    "localUser",
    "Local NixOS Username",
    portal.ParameterType.STRING,
    "yamada",
    longDescription="The local user account that will be created on the NixOS system.",
)

# --- TOPOLOGY PARAMETERS ---
pc.defineParameter(
    "nodeCount",
    "Number of Nodes",
    portal.ParameterType.INTEGER,
    1,
    longDescription="If you specify more than one node, we will create a lan for you.",
)

pc.defineParameter(
    "phystype",
    "Optional physical node type",
    portal.ParameterType.NODETYPE,
    "",
    longDescription="Pick a single physical node type (pc3000,d710,etc).",
)

pc.defineParameter(
    "useVMs",
    "Use XEN VMs",
    portal.ParameterType.BOOLEAN,
    False,
    longDescription="Create XEN VMs instead of allocating bare metal nodes.",
)

pc.defineParameter(
    "startVNC",
    "Start X11 VNC on your nodes",
    portal.ParameterType.BOOLEAN,
    False,
    longDescription="Start X11 VNC server on your nodes.",
)

pc.defineParameter(
    "linkSpeed",
    "Link Speed",
    portal.ParameterType.INTEGER,
    0,
    [
        (0, "Any"),
        (100000, "100Mb/s"),
        (1000000, "1Gb/s"),
        (10000000, "10Gb/s"),
        (25000000, "25Gb/s"),
        (100000000, "100Gb/s"),
    ],
    advanced=True,
)

pc.defineParameter(
    "bestEffort", "Best Effort LAN", portal.ParameterType.BOOLEAN, False, advanced=True
)
pc.defineParameter(
    "sameSwitch",
    "No Interswitch Links",
    portal.ParameterType.BOOLEAN,
    False,
    advanced=True,
)
pc.defineParameter(
    "tempFileSystemSize",
    "Temporary Filesystem Size",
    portal.ParameterType.INTEGER,
    0,
    advanced=True,
)
pc.defineParameter(
    "tempFileSystemMax",
    "Temp Filesystem Max Space",
    portal.ParameterType.BOOLEAN,
    False,
    advanced=True,
)
pc.defineParameter(
    "tempFileSystemMount",
    "Temporary Filesystem Mount Point",
    portal.ParameterType.STRING,
    "/mydata",
    advanced=True,
)
pc.defineParameter(
    "exclusiveVMs",
    "Force use of exclusive VMs",
    portal.ParameterType.BOOLEAN,
    True,
    advanced=True,
)

params = pc.bindParameters()

# --- VALIDATION ---
if params.nodeCount < 1:
    pc.reportError(
        portal.ParameterError("You must choose at least 1 node.", ["nodeCount"])
    )
if params.tempFileSystemSize < 0 or params.tempFileSystemSize > 200:
    pc.reportError(
        portal.ParameterError(
            "Please specify a size between 0 and 200GB", ["tempFileSystemSize"]
        )
    )
if params.phystype != "":
    tokens = params.phystype.split(",")
    if len(tokens) != 1:
        pc.reportError(
            portal.ParameterError("Only a single type is allowed", ["phystype"])
        )

pc.verifyParameters()

# --- TOPOLOGY GENERATION ---
if params.nodeCount > 1:
    if params.nodeCount == 2:
        lan = request.Link()
    else:
        lan = request.LAN()

    if params.bestEffort:
        lan.best_effort = True
    elif params.linkSpeed > 0:
        lan.bandwidth = params.linkSpeed
    if params.sameSwitch:
        lan.setNoInterSwitchLinks()

for i in range(params.nodeCount):
    if params.useVMs:
        name = "vm" + str(i)
        node = request.XenVM(name)
        if params.exclusiveVMs:
            node.exclusive = True
    else:
        name = "node" + str(i)
        node = request.RawPC(name)

    # Hardcode the base OS to Ubuntu 22.04 so nixos-infect has a reliable starting point
    node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU22-64-STD"

    # Add to LAN
    if params.nodeCount > 1:
        iface = node.addInterface("eth1")
        lan.addInterface(iface)

    if params.phystype != "":
        node.hardware_type = params.phystype

    if params.tempFileSystemSize > 0 or params.tempFileSystemMax:
        bs = node.Blockstore(name + "-bs", params.tempFileSystemMount)
        if params.tempFileSystemMax:
            bs.size = "0GB"
        else:
            bs.size = str(params.tempFileSystemSize) + "GB"
        bs.placement = "any"

    if params.startVNC:
        node.startVNC()

    # CloudLab clones a repo-based profile into /local/repository on each node.
    # Run the infect script from there with sudo so it can write /root/*
    # and perform the OS replacement.
    node.addService(
        pg.Execute(
            shell="sh",
            command=(
                "sudo /bin/bash /local/repository/setup-nixos.sh {} {}".format(
                    params.githubUser, params.localUser
                )
            ),
        )
    )

pc.printRequestRSpec(request)
