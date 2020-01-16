# GPU Passthrough Tutorial

In this post, I will be giving detailed instructions on how to run a KVM setup with GPU-passthrough. This setup uses a Linux host installed with [Pop!\_OS 19.10](https://system76.com/pop) and a guest VM running Windows 10.

### Considerations

The main reason I wanted to get this setup working was because I found myself tired of using a dual-boot setup. I wanted to launch a Windows VM specifically for gaming while still be able to use my Linux host for development work.

At this point, you might be wondering... Why not just game on Linux? This is definitely an option for many people, but not one that suited my particular needs. Gaming on Linux requires the use of tools like [Wine](https://en.wikipedia.org/wiki/Wine_(software)) which act as a compatabilty layer for translating Windows system calls to Linux system calls. On the other hand, a GPU-passthrough setup utilizes [KVM](https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine) as a hypervisor to launch individual VMs with specific hardware attached to them. Performance wise, there are pros and cons to each approach.<sup>[1](#footnote1)</sup>

For this tutorial, I will be using a GPU-passthrough setup. Specifically, I will be passing through an Nvidia GPU to my guest VM while using an AMD GPU for my host. You could easily substitute an iGPU for the host but I chose to upgrade to a dGPU for performance reasons.<sup>[2](#footnote2)</sup>

### Hardware Requirements

You're going to need the following to achieve a high-performance VM:
- Two graphics cards.
- [Hardware the supports IOMMU](https://en.wikipedia.org/wiki/List_of_IOMMU-supporting_hardware).
- A motherboard that supports IOMMU.
- A monitor with two inputs.<sup>[3](#footnote3)</sup>

### My Hardware Setup
- CPU:
    - Intel i7-8700k
- Motherboard:
    - ROG Strix Z370-E Motherboard
- GPUs:
    - NVIDIA RTX 2080 Ti
    - AMD RX590
- Memory:
    - Corsair Vengeance LPX DDR4 3200 MHz 32GB (2x16)
- Disk:
    - Samsung 970 EVO Plus SSD 500GB - M.2 NVME (host)
    - Samsung 970 EVO Plus SSD 1TB - M.2 NVME (guest)
    
### Part 1: Prerequisites

Boot into BIOS and enable IOMMU. For Intel processors, look for something called VT-d. For AMD, look for something called AMD-Vi. Save the changes and restart the machine. Once you've booted into the host, make sure that IOMMU is enabled.

For Intel:
```
$ dmesg | grep -e DMAR -e IOMMU
...
DMAR:DRHD base: 0x000000feb03000 flags: 0x0
IOMMU feb03000: ver 1:0 cap c9008020e30260 ecap 1000
...
```
For AMD:
```
$ dmesg | grep AMD-Vi
...
AMD-Vi: Enabling IOMMU at 0000:00:00.2 cap 0x40
AMD-Vi: Lazy IO/TLB flushing enabled
AMD-Vi: Initialized for Passthrough Mode
...
```

Now you're going to need to pass the hardware-enabled IOMMU functionality into the kernel as a [kernel parameter](https://wiki.archlinux.org/index.php/kernel_parameters). For our purposes, it makes the most sense to enable this feature at boot-time. Depending on your boot-loader (i.e. grub, systemd, rEFInd), you'll have to modify a specific configuration file. Since my machine uses systemd, I'll be editing `/boot/efi/loader/loader.conf` and adding the following:

For Intel:
```
options root= quiet splash intel_iommu=on
```
For AMD:
```

```

### Part 4: Performance

### Credits + Useful Resources

- ArchWiki
    - [QEMU](https://wiki.archlinux.org/index.php/QEMU)
    - [Libvirt](https://wiki.archlinux.org/index.php/Libvirt)
    - [PCI Passthrough](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)
- [Heiko Sieger - Running Windows 10 on Linux using KVM with VGA Passthrough](https://heiko-sieger.info/running-windows-10-on-linux-using-kvm-with-vga-passthrough)
    - An excellent resource. Written for setups with 2 GPUs: 1 iGPU + 1 dGPU or 2 dGPUs. 
    - Unlike the tutorial here, Heiko's binds the dGPU at boot time rather than dynamically before VM starts. This is fine for most setups, but not for those who want to use their dGPU on a host whenever the VM shutdown. *TODO: link to bind/unbind vfio section.*
    - The same goes for hugepages. Heiko's tutorial allocates hugepages at boot-time whereas this tutorial does it dynamically. Again this is fine for most setups, but those who want to free up RAM space whenever their VM is shutdown benefit more from dynamic allocation. *TODO: link to hugepage section.*
- [The Passthrough Post](https://passthroughpo.st/) - A blog dedicated to the latest PCI passthrough/VFIO related news, guides, benchmarks and tools
    - [VFIO PC Builds](https://passthroughpo.st/vfio-increments/) - a list of parts for VFIO-focused PC builds at different price ranges

### Footnotes
<a name="footnote1">1</a>. Check out [this thread](https://news.ycombinator.com/item?id=18328323) from Hacker News for more information. <br/>
<a name="footnote2">2</a>. I'll be using the term *iGPU* to refer to Intel's line of integrated GPUs that usually come built into their processors, and the term *dGPU* to refer to dedicated GPUs which are much better performance-wise and meant for gaming or video editing (Nvidia/AMD).
<a name="footnote3">3</a>. Make sure that the monitor input used for your gaming VM supports FreeSync/G-Sync technology. In my case, I reserved the displayport 1.2 input for my gaming VM since G-Sync is not supported across HDMI (which was instead used for host graphics).
