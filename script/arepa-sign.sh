#!/bin/sh

# Signs the repositories defined for Arepa. It just calls "arepa sign" as the
# arepa-master user

su - arepa-master -c "/usr/bin/arepa sign"
