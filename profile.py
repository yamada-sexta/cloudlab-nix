"""An automated NixOS-infect profile for CloudLab.

Instructions:
This profile boots an Ubuntu 22.04 base image and automatically runs `nixos-infect` on boot.
It will pull your SSH keys directly from GitHub, configure CloudLab-compatible networking,
and install the `miniond` client so the CloudLab web UI recognizes the node as "Ready".

The node will reboot on its own during the installation process. Once it comes back online,
you can SSH in as your configured user.
"""

import geni.portal as portal
import geni.rspec.pg as rspec

request = portal.context.makeRequestRSpec()

# Parameter for the GitHub user (keys)
portal.context.defineParameter(
    "github_user", "GitHub Username", portal.ParameterType.STRING, "yamada-sexta"
)
params = portal.context.bindParameters()

node = request.RawPC("nixos-node")
node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU22-64-STD"

# IMPORTANT: In repository-based profiles, your repo is cloned to /local/repository
# We call the setup script directly from that location.
node.addService(
    rspec.Execute(
        shell="bash",
        command="bash /local/repository/setup-nixos.sh %s" % params.github_user,
    )
)

portal.context.printRequestRSpec()
