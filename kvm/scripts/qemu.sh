#!/bin/bash

## Check if the script was executed as root
[[ "$EUID" -ne 0 ]] && echo "Please run as root" && exit 1

## Load the config file
source "/etc/libvirt/hooks/kvm.conf"

## Check libvirtd is running
[[ $(systemctl status libvirtd | grep running) ]] || systemctl start libvirtd && sleep 1 && LIBVIRTD=STOPPED

function bind_vfio {
    ## Unload nvidia
    modprobe -r nvidia_drm
    modprobe -r nvidia_uvm
    modprobe -r nvidia_modeset

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
}

function unbind_vfio {
    ## Unbind gpu from vfio and bind to nvidia
    virsh nodedev-reattach $VIRSH_GPU_VIDEO
    virsh nodedev-reattach $VIRSH_GPU_AUDIO
    virsh nodedev-reattach $VIRSH_GPU_USB
    virsh nodedev-reattach $VIRSH_GPU_SERIAL
    ## Unbind ssd from vfio and bind to nvme
    virsh nodedev-reattach $VIRSH_NVME_SSD

    ## Unload vfio
    modprobe -r vfio_pci
    modprobe -r vfio_iommu_type1
    modprobe -r vfio
}

function allocate_hugepages {
    HUGEPAGES="$(($MEMORY/$(($(grep Hugepagesize /proc/meminfo | awk '{print $2}')/1024))))"
    echo "Allocating hugepages..."
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
    ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)

    TRIES=0
    while (( $ALLOC_PAGES != $HUGEPAGES && $TRIES < 1000 ))
    do
        echo 1 > /proc/sys/vm/compact_memory            ## defrag ram
        echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
        ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)
        echo "Succesfully allocated $ALLOC_PAGES / $HUGEPAGES"
        let TRIES+=1
    done

    if [ "$ALLOC_PAGES" -ne "HUGEPAGES" ]
    then
        echo "Not able to allocate all hugepages. Reverting..."
        echo 0 > /proc/sys/vm/nr_hugepages
        exit 1
    fi
}

function deallocate_hugepages {
    echo 0 > /proc/sys/vm/nr_hugepages
}

function cpu_mode_performance {
    ## Enable CPU governor performance mode
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "performance" > $file; done
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

function cpu_mode_ondemand {
    ## Enable CPU governor on-demand mode
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "ondemand" > $file; done
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

## Kill the display manager
#systemctl stop display-manager.service

## Kill the console
#echo 0 > /sys/class/vtconsole/vtcon0/bind
#echo 0 > /sys/class/vtconsole/vtcon1/bind
#echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

bind_vfio
allocate_hugepages
cpu_mode_performance

## QEMU KVM
#TODO

cpu_mode_ondemand
deallocate_hugepages
unbind_vfio

## Start the display manager
#systemctl start display-manager.service

## Start the console
#echo 1 > /sys/class/vtconsole/vtcon0/bind
#echo 1 > /sys/class/vtconsole/vtcon1/bind
#echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind
