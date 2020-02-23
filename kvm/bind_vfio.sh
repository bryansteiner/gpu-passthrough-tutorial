#!/bin/bash

## Load the config file
source "/etc/libvirt/hooks/kvm.conf"

## Load vfio
modprobe vfio
modprobe vfio_iommu_type1
modprobe vfio_pci

## Unbind gpu from nvidia and bind to vfio
virsh nodedev-detach $VIRSH_GPU_VIDEO
virsh nodedev-detach $VIRSH_GPU_AUDIO
virsh nodedev-detach $VIRSH_GPU_USB
virsh nodedev-detach $VIRSH_GPU_SERIAL
## Unbind ssd from nvme and bind to vfio
virsh nodedev-detach $VIRSH_NVME_SSD
