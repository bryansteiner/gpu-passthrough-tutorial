#!/bin/bash

## Load the config file
source "/home/bsteiner/.kvm/kvm.conf"

echo 0 > /proc/sys/vm/nr_hugepages
