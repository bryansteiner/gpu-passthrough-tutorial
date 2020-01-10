## Linux KVM Gaming PC Tutorial

In this post, I will be giving detailed instructions on how to create a successful KVM setup with a Linux host (Pop!\_OS 19.10) and a Windows 10 guest VM.

### Considerations

The main reason I wanted to get this setup working was because I found myself tired of using a dual-boot setup. I wanted to be able to launch a Windows VM specifically for intensive gaming while still being able to use my Linux host for development work. Many of the GPU-passthrough tutorials actually discuss completely different setups. We need to distinguish between the two types:

- Single GPU-Passthrough
    - This setup invovles *only* a single GPU that is passed from the host OS to the guest VM.
    - Most of the time, these type of setups occur when you have only a dGPU with no iGPU.
    - The host has to suspend it's display whenever the VM is active.
- Multiple GPU-Passthrough
    - This setup involves multiple GPUs, where a non-primary GPU is passed from the host to the guest VM while the primary GPU (usually an iGPU or 2nd GPU) is used for the host display
    - This setup requires at minimum 2 GPUs: one for the host and one for the VM.

For this tutorial, I will be sticking to a multi GPU-Passthrough setup. Specifically, I will be passing through an NVIDIA GPU to my guest VM while using an AMD GPU for my host.

### Hardware Requirements

### Hardware
- CPU:
    - Intel i7-8700k
- Motherboard:
    - ROG Strix Z370-E Motherboard
- GPUs:
    - NVIDIA RTX 2080 Ti
    - AMD RX590
    - Intel UHD 630 (iGPU)
- Memory:
    - Corsair Vengeance LPX DDR4 3200 MHz 32GB (2x16)
- Disk:
    - Samsung 970 EVO Plus SSD 500GB - M.2 NVME (host)
    - Samsung 970 EVO Plus SSD 1TB - M.2 NVME (guest)

### Useful Resources
