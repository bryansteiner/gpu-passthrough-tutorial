# GPU Passthrough Tutorial

In this post, I will be giving detailed instructions on how to run a KVM setup with GPU-passthrough. This setup uses a Linux host installed with [Pop!\_OS 19.10](https://system76.com/pop) and a guest VM running Windows 10.

<div align="center">
    <a href="https://events.static.linuxfound.org/sites/events/files/slides/KVM,%20OpenStack,%20and%20the%20Open%20Cloud%20-%20ANJ%20MK%20%20-%2013Oct14.pdf">
        <img src="./img/kvm-architecture.jpg" width="500">
    </a>
</div>

### Considerations

The main reason I wanted to get this setup working was because I found myself tired of using a dual-boot setup. I wanted to launch a Windows VM specifically for gaming while still be able to use my Linux host for development work.

At this point, you might be wondering... Why not just game on Linux? This is definitely an option for many people, but not one that suited my particular needs. Gaming on Linux requires the use of tools like [Wine](https://en.wikipedia.org/wiki/Wine_(software)) which act as a compatabilty layer for translating Windows system calls to Linux system calls. On the other hand, a GPU-passthrough setup utilizes [KVM](https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine) as a hypervisor to launch individual VMs with specific hardware attached to them. Performance wise, there are pros and cons to each approach.<sup>[1](#footnote1)</sup>

For this tutorial, I will be using a GPU-passthrough setup. Specifically, I will be passing through an Nvidia GPU to my guest VM while using an AMD GPU for my host. You could easily substitute an iGPU for the host but I chose to use a dGPU for performance reasons.<sup>[2](#footnote2)</sup>

### Hardware Requirements

You're going to need the following to achieve a high-performance VM:
- Two graphics cards.
- [Hardware the supports IOMMU](https://en.wikipedia.org/wiki/List_of_IOMMU-supporting_hardware).
- A monitor with two inputs.<sup>[3](#footnote3)</sup>

### My Hardware Setup
- CPU:
    - AMD Ryzen 9 3900X
- Motherboard:
    - Gigabyte X570 Aorus Pro Wifi
- GPUs:
    - NVIDIA RTX 2080 Ti
    - AMD RX 5700
- Memory:
    - Corsair Vengeance LPX DDR4 3200 MHz 32GB (2x16)
- Disk:
    - Samsung 970 EVO Plus SSD 500GB - M.2 NVMe (host)
    - Samsung 970 EVO Plus SSD 1TB - M.2 NVMe (guest)

### Part 1: Prerequisites

Boot into BIOS and enable IOMMU. Next, you'll need to enable CPU virtualization. For Intel processors, look for something called `VT-d`. For AMD, look for something called `AMD-Vi`. My system was different so I had to enable a feature called `SVM Mode`. Save any changes and restart the machine.

Once you've booted into the host, make sure that IOMMU is enabled: <br>
`$ dmesg | grep IOMMU`

Also check that CPU virtualization is enabled:<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; For Intel --> `$ dmesg | grep VT-d` <br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; For AMD --> `$ dmesg | grep AMD-Vi`

Now you're going to need to pass the hardware-enabled IOMMU functionality into the kernel as a [kernel parameter](https://wiki.archlinux.org/index.php/kernel_parameters). For our purposes, it makes the most sense to enable this feature at boot-time. Depending on your boot-loader (i.e. grub, systemd, rEFInd), you'll have to modify a specific configuration file. Since my machine uses systemd and these configuration files are often overwritten on updates, I will be using a tool called [kernelstub](https://github.com/pop-os/kernelstub).

For Intel: `$ sudo kernelstub --add-options "intel_iommu=on"`<br/>
For AMD: `$ sudo kernelstub --add-options "amd_iommu=on"`

When planning my GPU-passthrough setup, I discovered that many tutorials at this point will go ahead and have you blacklist the NVIDIA or AMD drivers. The logic stems from the idea that since the native drivers can't attach to the GPU at boot-time, the GPU will be freed-up and available to bind to the vfio drivers instead. Most tutorials will have you add another kernel parameter called `pci-stub`. I found that this solution wasn't suitable for me. I prefer to dynamically unbind the nvidia/amd drivers and bind the vfio drivers right before the VM starts and reversing these actions when the VM stops (see Part 3). That way, whenever the VM isn't in use, the GPU is available to the host machine.<sup>[4](#footnote4)</sup>

Next, we need to determine the IOMMU groups of the graphics card we want to pass through to the VM. We'll want to make sure that our system has an appropriate IOMMU grouping scheme. Essentially, we need to remember that devices residing within the same IOMMU group need to be passed through to the VM (they can't be separated). To determine your IOMMU grouping, use the following script:

```
#!/bin/bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"
  lspci -nns "${d##*/}"
done
```

For Intel systems, here's some sample output:
```
...
IOMMU Group 1 00:01.0 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x16) [8086:1901] (rev 07)
IOMMU Group 1 00:01.1 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x8) [8086:1905] (rev 07)
IOMMU Group 1 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU102 [GeForce RTX 2080 Ti Rev. A] [10de:1e07] (rev a1)
IOMMU Group 1 01:00.1 Audio device [0403]: NVIDIA Corporation TU102 High Definition Audio Controller [10de:10f7] (rev a1)
IOMMU Group 1 01:00.2 USB controller [0c03]: NVIDIA Corporation TU102 USB 3.1 Controller [10de:1ad6] (rev a1)
IOMMU Group 1 01:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU102 UCSI Controller [10de:1ad7] (rev a1)
IOMMU Group 1 02:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere [Radeon RX 470/480/570/570X/580/580X/590] [1002:67df] (rev e1)
IOMMU Group 1 02:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere HDMI Audio [Radeon RX 470/480 / 570/580/590] [1002:aaf0]
...
```

Here we see that both the NVIDIA and AMD GPUs reside in IOMMU group 1. This presents a problem. If you want to use the AMD GPU for the host machine while passing through the NVIDIA GPU to the guest VM, you need to figure out a way to separate their IOMMU groups.

1. One possible solution is to switch the PCI slot to which the AMD graphics card is attached. This may or may not produce the desired solution.
2. An alternative solution is something called the [ACS Override Patch](https://queuecumber.gitlab.io/linux-acs-override/). For an in-depth discussion, it's definitely worth checking out this post from [Alex Williamson](https://vfio.blogspot.com/2014/08/iommu-groups-inside-and-out.html). Make sure to consider the risks.<sup>[5](#footnote5)</sup>

For my system, I was lucky<sup>[6](#footnote6)</sup> because the NVIDIA and AMD GPUs resided in different IOMMU groups:

```
...
IOMMU Group 28 0a:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU102 [GeForce RTX 2080 Ti Rev. A] [10de:1e07] (rev a1)
IOMMU Group 28 0a:00.1 Audio device [0403]: NVIDIA Corporation TU102 High Definition Audio Controller [10de:10f7] (rev a1)
IOMMU Group 28 0a:00.2 USB controller [0c03]: NVIDIA Corporation TU102 USB 3.1 Controller [10de:1ad6] (rev a1)
IOMMU Group 28 0a:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU102 UCSI Controller [10de:1ad7] (rev a1)
...
IOMMU Group 31 0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 [1002:731f] (rev c4)
IOMMU Group 32 0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 HDMI Audio [1002:ab38]
...
```

If your setup is like mine<sup>[7](#footnote7)</sup> and you had isolated IOMMU groups, feel free to skip the following section. Otherwise, please continue reading...

#### ACS Override Patch [Optional]:

For most linux distributions, the ACS Override Patch requires you to download the kernel source code, manually insert the ACS patch, compile + install the kernel, and then boot directly from the newly patched kernel.<sup>[8](#footnote8)</sup>

Since I'm running a Debian-based distribution, I can use one of the [pre-compiled kernels](https://queuecumber.gitlab.io/linux-acs-override/) with the ACS patch already applied. After extracting the package contents, install the kernel and headers:

```
$ sudo dpkg -i linux-headers-5.3.0-acso_5.3.0-acso-1_amd64.deb
$ sudo dpkg -i linux-image-5.3.0-acso_5.3.0-acso-1_amd64.deb
$ sudo dpkg -i linux-libc-dev_5.3.0-acso-1_amd64.deb
```

Navigate to /boot and verify that you see the new initrd.img and vmlinuz:

```
$ ls
config-5.3.0-7625-generic    initrd.img-5.3.0-7625-generic  vmlinuz
config-5.3.0-acso            initrd.img-5.3.0-acso          vmlinuz-5.3.0-7625-generic
efi                          initrd.img.old                 vmlinuz-5.3.0-acso
initrd.img                   System.map-5.3.0-7625-generic  vmlinuz.old
initrd.img-5.3.0-24-generic  System.map-5.3.0-acso
```

We still have to copy the current kernel and initramfs image onto the ESP so that they are automatically loaded by EFI. We check the current configuration with [kernelstub](https://github.com/pop-os/kernelstub):

```
$ sudo kernelstub --print-config
kernelstub.Config    : INFO     Looking for configuration...
kernelstub           : INFO     System information:

    OS:..................Pop!_OS 19.10
    Root partition:....../dev/dm-1
    Root FS UUID:........2105a9ac-da30-41ba-87a9-75437bae74c6
    ESP Path:............/boot/efi
    ESP Partition:......./dev/nvme0n1p1
    ESP Partition #:.....1alt="virtman_3"
    NVRAM entry #:.......-1
    Boot Variable #:.....0000
    Kernel Boot Options:.quiet loglevel=0 systemd.show_status=false splash amd_iommu=on
    Kernel Image Path:.../boot/vmlinuz
    Initrd Image Path:.../boot/initrd.img
    Force-overwrite:.....False

kernelstub           : INFO     Configuration details:

   ESP Location:................../boot/efi
   Management Mode:...............True
   Install Loader configuration:..True
   Configuration version:.........3
```

You can see that the "Kernel Image Path" and the "Initrd Image Path" are symbolic links that point to the old kernel and initrd.

```
$ ls -l /boot
total 235488
-rw-r--r-- 1 root root   235833 Dec 19 11:56 config-5.3.0-7625-generic
-rw-r--r-- 1 root root   234967 Sep 16 04:31 config-5.3.0-acso
drwx------ 6 root root     4096 Dec 31  1969 efi
lrwxrwxrwx 1 root root       29 Dec 20 11:28 initrd.img -> initrd.img-5.3.0-7625-generic
-rw-r--r-- 1 root root 21197115 Dec 20 11:54 initrd.img-5.3.0-24-generic
-rw-r--r-- 1 root root 95775016 Jan 17 00:33 initrd.img-5.3.0-7625-generic
-rw-r--r-- 1 root root 94051072 Jan 18 19:57 initrd.img-5.3.0-acso
lrwxrwxrwx 1 root root       29 Dec 20 11:28 initrd.img.old -> initrd.img-5.3.0-7625-generic
-rw------- 1 root root  4707483 Dec 19 11:56 System.map-5.3.0-7625-generic
-rw-r--r-- 1 root root  4458808 Sep 16 04:31 System.map-5.3.0-acso
lrwxrwxrwx 1 root root       26 Dec 20 11:28 vmlinuz -> vmlinuz-5.3.0-7625-generic
-rw------- 1 root root 11398016 Dec 19 11:56 vmlinuz-5.3.0-7625-generic
-rw-r--r-- 1 root root  9054592 Sep 16 04:31 vmlinuz-5.3.0-acso
lrwxrwxrwx 1 root root       26 Dec 20 11:28 vmlinuz.old -> vmlinuz-5.3.0-7625-generic
```

Let's change that:

```
$ sudo rm /boot/vmlinuz
$ sudo ln -s /boot/vmlinuz-5.3.0-acso /boot/vmlinuz
$ sudo rm /boot/initrd.img
$ sudo ln -s /boot/initrd.img-5.3.0-acso /boot/initrd.img
```

Verify that the symbolic links now point to the correct kernel and initrd images:

```
$ ls -l /boot
total 235488
-rw-r--r-- 1 root root   235833 Dec 19 11:56 config-5.3.0-7625-generic
-rw-r--r-- 1 root root   234967 Sep 16 04:31 config-5.3.0-acso
drwx------ 6 root root     4096 Dec 31  1969 efi
lrwxrwxrwx 1 root root       27 Jan 18 20:02 initrd.img -> /boot/initrd.img-5.3.0-acso
-rw-r--r-- 1 root root 21197115 Dec 20 11:54 initrd.img-5.3.0-24-generic
-rw-r--r-- 1 root root 95775016 Jan 17 00:33 initrd.img-5.3.0-7625-generic
-rw-r--r-- 1 root root 94051072 Jan 18 19:57 initrd.img-5.3.0-acso
lrwxrwxrwx 1 root root       29 Dec 20 11:28 initrd.img.old -> initrd.img-5.3.0-7625-generic
-rw------- 1 root root  4707483 Dec 19 11:56 System.map-5.3.0-7625-generic
-rw-r--r-- 1 root root  4458808 Sep 16 04:31 System.map-5.3.0-acso
lrwxrwxrwx 1 root root       24 Jan 18 20:02 vmlinuz -> /boot/vmlinuz-5.3.0-acso
-rw------- 1 root root 11398016 Dec 19 11:56 vmlinuz-5.3.0-7625-generic
-rw-r--r-- 1 root root  9054592 Sep 16 04:31 vmlinuz-5.3.0-acso
lrwxrwxrwx 1 root root       26 Dec 20 11:28 vmlinuz.old -> vmlinuz-5.3.0-7625-generic
```

Finally, add the ACS Override Patch to your list of kernel parameter options:

```
$ sudo kernelstub --add-options "pcie_acs_override=downstream"
```

Reboot and verify that the IOMMU groups for your graphics cards are different:

```
...
IOMMU Group 15 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU102 [GeForce RTX 2080 Ti Rev. A] [10de:1e07] (rev a1)
IOMMU Group 15 01:00.1 Audio device [0403]: NVIDIA Corporation TU102 High Definition Audio Controller [10de:10f7] (rev a1)
IOMMU Group 15 01:00.2 USB controller [0c03]: NVIDIA Corporation TU102 USB 3.1 Controller [10de:1ad6] (rev a1)
IOMMU Group 15 01:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU102 UCSI Controller [10de:1ad7] (rev a1)
IOMMU Group 16 02:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere [Radeon RX 470/480/570/570X/580/580X/590] [1002:67df] (rev e1)
IOMMU Group 16 02:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere HDMI Audio [Radeon RX 470/480 / 570/580/590] [1002:aaf0]
...
```

#### Download the ISO files

Since we're building a Windows VM, we're going to need to download and use the virtIO drivers. [virtIO](https://www.linux-kvm.org/page/Virtio) is a virtualization standard for network and disk device drivers. Adding the virtIO drivers can be done by attaching its relevant ISO to the Windows VM during creation. Fedora provides the virtIO drivers for [direct download](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/#virtio-win-direct-downloads).

Since I am passing through an entire NVMe SSD (1 TB), I won't need to install any 3rd party drivers on top of the virtIO driver. Passing through the SSD as a PCI device lets Windows deal with it as a native NVMe device and therefore *should* offer better performance. If you choose to use a raw disk image instead, things are going to be a little different... Make sure to follow the instructions in [this guide](https://frdmtoplay.com/virtualizing-windows-7-or-linux-on-a-nvme-drive-with-vfio/#builddriveriso). The guide will show you how to add 3rd party drivers on top of the existing virtIO drivers by rebuilding the ISO.

For the final step, we're going to need to download the Windows 10 ISO from Microsoft which you can find [here](https://www.microsoft.com/en-us/software-download/windows10ISO).

### Part 2: Setting up the VM

We're ready to begin creating our VM. There are basically two options for how to achieve this: (1) If you prefer a GUI approach, then follow the rest of this tutorial. (2) If you prefer bash scripts, take a look at YuriAlek's series of [GPU-passthrough scripts](https://gitlab.com/YuriAlek/vfio) and customize them to fit your needs. The main difference between these two methods lies with the fact that the scripting approach uses [bare QEMU](https://manpages.debian.org/stretch/qemu-system-x86/qemu-system-x86_64.1.en.html) CLI commands, while the GUI approach uses [virt-manager](https://virt-manager.org/). Virt-manager essentially builds on-top of the QEMU base-layer and adds other features + complexity.<sup>[9](#footnote9)</sup>

Time to install some necessary packages:

`$ sudo apt install libvirt-daemon-system libvirt-clients qemu-kvm qemu-utils virt-manager ovmf`

You should now be able to start virt-manager from your list of applications. Select the button on the top left of the GUI to create a new VM:

<div align="center">
    <img src="./img/virtman_1.png" width="450">
</div><br>

Select the "Local install media" option. My ISOs are stored in my home directory `/home/user/.iso`, so I'll create a new pool and select the Windows 10 ISO from there:

<div align="center">
    <img src="./img/virtman_2.png" width="450">
</div><br>

Configure some custom RAM and CPU settings for your VM:

<div align="center">
    <img src="./img/virtman_3.png" width="450">
</div><br>

Next, the GUI asks us whether we want to enable storage for the VM. As already mentioned, my setup will be using SSD passthrough so I chose not to enable storage. You also have the option to create a raw disk image:

<div align="center">
    <img src="./img/virtman_4.png" width="450">
</div><br>

On the last step, review your settings and select a name for your VM. Make sure to select the checkbox "Customize configuration before installation" and click Finish:

<div align="center">
    <img src="./img/virtman_5.png" width="450">
</div><br>

A new window should appear with more advanced configuration options. You can alter these options through the GUI or the associated libvirt XML settings. Make sure that on the Overview page under Firmware you select `UEFI x86_64: /usr/share/OVMF/OVMF_CODE.fd`:

<div align="center">
    <img src="./img/virtman_6.png" width="450">
</div><br>

Go to the CPUs page and remove the check next to `Copy host CPU configuration` and under Model type `host-passthrough`. Also make sure to check the option for `Enable available CPU security flaw mitigations` to prevent against Spectre/Meltdown vulnerabilities.

<div align="center">
    <img src="./img/virtman_7.png" width="450">
</div><br>

I've chosen to remove several of the menu options that won't be useful to my setup (feel free to keep them if you'd like):

<div align="center">
    <img src="./img/virtman_8.png" width="450">
</div><br>

Let's add the virtIO drivers. Click 'Add Hardware' and under 'Storage', create a custom storage device of type `CDROM`. Make sure to locate the ISO image for the virtIO drivers from earlier:

<div align="center">
    <img src="./img/virtman_9.png" width="450">
</div><br>

Under the NIC menu, change the device model to `virtIO` for improved performance:

<div align="center">
    <img src="./img/virtman_10.png" width="450">
</div><br>

Now it's time to configure our passthrough devices! Click 'Add Hardware' and under 'PCI Host Device', select the Bus IDs corresponding to your GPU.

<div align="center">
    <img src="./img/virtman_11.png" width="450">
</div><br>

Make sure to repeat this step for all the devices associated with your GPU in the same IOMMU group (usually VGA, audio controller, etc.):

<div align="center">
    <img src="./img/virtman_12.png" width="450">
</div><br>

Since I'm passing through an entire disk to my VM, I selected the Bus ID corresponding to the 1TB Samsung NVMe SSD which has Windows 10 (and my games) installed on it.

<div align="center">
    <img src="./img/virtman_13.png" width="450">
</div><br>

Then under the 'Boot Options' menu, I added a check next to `Enable boot menu` and reorganized the devices so that I could boot directly from the 1TB SSD:

<div align="center">
    <img src="./img/virtman_14.png" width="450">
</div><br>

You can now go ahead and select the USB Host Devices you'd like to passthrough to your guest VM (usually a keyboard, mouse, etc.). Please note that these devices will be held by the guest VM from the moment it's created until its stopped and will be unavailable to the host.<sup>[10](#footnote10)</sup>

<div align="center">
    <img src="./img/virtman_15.png" width="450">
</div><br>

Unfortunately, not everything we need can be accomplished within the virt-manager GUI. For the rest of this section, we'll have to do some fine-tuning by directly editing the XML:


### Part 3: VM Logistics

### Part 4: Performance

### Credits + Useful Resources

- Wikis
    - [ArchWiki](https://wiki.archlinux.org/)
        - [QEMU](https://wiki.archlinux.org/index.php/QEMU)
        - [KVM](https://wiki.archlinux.org/index.php/KVM)
        - [Libvirt](https://wiki.archlinux.org/index.php/Libvirt)
        - [PCI Passthrough](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)
    - [Libvirt Wiki](https://wiki.libvirt.org/page/Main_Page)
        - [virtIO](https://wiki.libvirt.org/page/Virtio)
        - [Hooks](https://libvirt.org/hooks.html)
        - [Domain XML](https://libvirt.org/formatdomain.html)
- Tutorials
    - [Heiko Sieger - Running Windows 10 on Linux using KVM with VGA Passthrough](https://heiko-sieger.info/running-windows-10-on-linux-using-kvm-with-vga-passthrough)
    - Alex Williamson -VFIO GPU How To series
        - [Part 1 - The hardware](https://vfio.blogspot.com/2015/05/vfio-gpu-how-to-series-part-1-hardware.html)
        - [Part 2 - Expectations](https://vfio.blogspot.com/2015/05/vfio-gpu-how-to-series-part-2.html)
        - [Part 3 - Host configuration](https://vfio.blogspot.com/2015/05/vfio-gpu-how-to-series-part-3-host.html)
        - [Part 4 - Our first VM](https://vfio.blogspot.com/2015/05/vfio-gpu-how-to-series-part-4-our-first.html)
        - [Part 5 - A VGA-mode, SeaBIOS VM](https://vfio.blogspot.com/2015/05/vfio-gpu-how-to-series-part-5-vga-mode.html)
    - [David Yates - GPU passthrough: gaming on Windows on Linux](https://davidyat.es/2016/09/08/gpu-passthrough/)
    - [Wendell - VFIO in 2019 – Pop!_OS How-To](https://forum.level1techs.com/t/vfio-in-2019-pop-os-how-to-general-guide-though-draft/142287)
        - FYI: Wendell is from [Level1Techs](https://level1techs.com/). He has contributed to the FOSS community with a cool application called [Looking Glass](https://looking-glass.hostfission.com/). I recommend you check out this [video](https://www.youtube.com/watch?v=okMGtwfiXMo) for more information.
        - Wendell has even collaborated with Linus from "Linus Tech Tips" and put out this great [video](https://www.youtube.com/watch?v=SsgI1mkx6iw).
    - [Yuri Alek - Single GPU passthrough](https://gitlab.com/YuriAlek/vfio)
    - [bsilvereagle - Virtualizing Windows 7 (or Linux) on a NVMe drive with VFIO](https://frdmtoplay.com/virtualizing-windows-7-or-linux-on-a-nvme-drive-with-vfio/)
    - [GrayWolfTech - Play games in Windows on Linux! PCI passthrough quick guide](https://www.youtube.com/watch?v=dsDUtzMkxFk)
- Blogs
    - [The Passthrough Post](https://passthroughpo.st/)
        - [VFIO PC Builds](https://passthroughpo.st/vfio-increments/)
        - [Howto: Libvirt Automation Using VFIO-Tools Hook Helper](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/)
    - [Heiko Sieger](https://heiko-sieger.info/)
        - [Glossary of Virtualization Terms](https://heiko-sieger.info/glossary-of-virtualization-terms/)
        - [IOMMU Groups – What You Need to Consider](https://heiko-sieger.info/iommu-groups-what-you-need-to-consider/)
        - [Windows 10 Virtual Machine Benchmarks](https://heiko-sieger.info/windows-10-virtual-machine-benchmarks/)
        - [Windows 10 Benchmarks (Virtual Machine)](https://heiko-sieger.info/benchmarks/)
- Lectures
    - [Alex Williamson - An Introduction to PCI Device Assignment with VFIO](https://www.youtube.com/watch?v=WFkdTFTOTpA&feature=emb_title)

### Footnotes
<a name="footnote1">1</a>. Check out [this thread](https://news.ycombinator.com/item?id=18328323) from Hacker News for more information.
<br>

<a name="footnote2">2</a>. I'll be using the term *iGPU* to refer to Intel's line of integrated GPUs that usually come built into their processors, and the term *dGPU* to refer to dedicated GPUs which are much better performance-wise and meant for gaming or video editing (Nvidia/AMD).
<br>

<a name="footnote3">3</a>. Make sure that the monitor input used for your gaming VM supports FreeSync/G-Sync technology. In my case, I reserved the displayport 1.2 input for my gaming VM since G-Sync is not supported across HDMI (which was instead used for host graphics).
<br>

<a name="footnote4">4</a>. I specifically wanted my Linux host to be able to perform [CUDA](https://developer.nvidia.com/cuda-downloads) work on the attached NVIDIA gpu. Just because my graphics card wasn't attached to a display didn't stop me from wanting to use it [cuDNN](https://developer.nvidia.com/cudnn) for ML/AI applications.
<br>

<a name="footnote5">5</a>. **Applying the ACS Override Patch may compromise system security**. Check out this [reddit post](https://www.reddit.com/r/VFIO/comments/bvif8d/official_reason_why_acs_override_patch_is_not_in/) to see why the ACS patch will probably never make its way upstream to the mainline kernel.
<br>

<a name="footnote6">6</a>. I'm actually being a bit disingenuous here... I deliberately purchased hardware that I knew would provide ACS implementation (and hence good IOMMU isolation). After flashing the most recent version of my motherboard's BIOS, I made sure to enable the following features under the *AMD CBS* menu: `ACS Enable`, `AER CAP`, `ARI Support`.
<br>

<a name="footnote7">7</a>.
AMD CPUs/motherboards/chipsets tend to provide better ACS support than their Intel counterparts. The Intel Xeon family of processors is a notable exception. Xeon is mainly targeted at non-consumer workstations and thus are an excellent choice for PCI/VGA passthrough. Be aware that they do command a *hefty* price tag.
<br>

<a name="footnote8">8</a>. Credit to the solution presented in [this post](https://forum.level1techs.com/t/how-to-apply-acs-override-patch-kubuntu-18-10-kernel-4-18-16/134204).
<br>

<a name="footnote9">9</a>. See [this link](https://www.stratoscale.com/blog/compute/using-bare-qemu-kvm-vs-libvirt-virt-install-virt-manager/) for more details and comparison between QEMU and virt-manager
<br>

<a name="footnote10">10</a>. See [here](https://heiko-sieger.info/running-windows-10-on-linux-using-kvm-with-vga-passthrough/#About_keyboard_and_mouse) for several software and hardware solutions for sharing your keyboard and mouse across your host machine and guest VM.
