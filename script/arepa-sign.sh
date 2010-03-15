#!/bin/sh

# Signs the repositories defined for Arepa. It just calls "arepa sign" as the
# arepa-master user
# You probably want to add a line like this to your /etc/sudoers file:
# 
#     %arepa ALL=(ALL) NOPASSWD: /usr/bin/arepa-sign

su - arepa-master -c "/usr/bin/arepa sign"
