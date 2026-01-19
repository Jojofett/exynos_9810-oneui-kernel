#!/bin/bash
# Save as fix_rkp_issues.sh and run: sudo bash fix_rkp_issues.sh

set -e

echo "=== Fixing RKP compilation issues ==="

# 1. Create necessary directories
sudo mkdir -p drivers/rkp
sudo mkdir -p scripts/ld

# 2. Create RKP physical allocator implementation
sudo tee drivers/rkp/rkp_phys.c << 'EOF'
#include <linux/rkp.h>
#include <linux/mm.h>
#include <linux/slab.h>
#include <asm/page.h>

#ifdef CONFIG_RKP
phys_addr_t rkp_ro_alloc_phys(void)
{
    void *virt_addr;
    phys_addr_t phys_addr = 0;

    virt_addr = rkp_ro_alloc();
    if (virt_addr) {
        phys_addr = __pa(virt_addr);
    }

    return phys_addr;
}
EXPORT_SYMBOL(rkp_ro_alloc_phys);
#endif
EOF

# 3. Create RKP Kconfig
sudo tee drivers/rkp/Kconfig << 'EOF'
config RKP_PHYS_ALLOC
    bool "RKP Physical Allocator"
    depends on RKP
    default y
    help
      Enable RKP physical memory allocator for ARM64 MMU.
EOF

# 4. Create RKP Makefile
sudo tee drivers/rkp/Makefile << 'EOF'
obj-$(CONFIG_RKP_PHYS_ALLOC) += rkp_phys.o
EOF

# 5. Update drivers/Kconfig to include RKP
if ! grep -q "source \"drivers/rkp/Kconfig\"" drivers/Kconfig; then
    sudo sed -i '/endmenu/i source "drivers/rkp/Kconfig"' drivers/Kconfig
fi

# 6. Add missing function prototype to rkp.h
if ! sudo grep -q "rkp_ro_alloc_phys" include/linux/rkp.h; then
    sudo tee -a include/linux/rkp.h << 'EOF'

#ifndef CONFIG_RKP_DEBUG
static inline phys_addr_t rkp_ro_alloc_phys(void)
{
    void *addr = rkp_ro_alloc();
    return addr ? __pa(addr) : 0;
}
#endif
EOF
fi

# 7. Fix cred.h structure (add missing fields)
if sudo grep -q "struct user_namespace \*user_ns;" include/linux/cred.h; then
    if ! sudo grep -q "bp_pgd" include/linux/cred.h; then
        sudo sed -i '/struct user_namespace \*user_ns;/a \
#ifdef CONFIG_RKP_CRED_PROT\
    void *bp_pgd;\
    void *bp_task;\
    unsigned int type;\
    atomic_t use_cnt;\
#endif' include/linux/cred.h
    fi
fi

# 8. Create a wrapper for LLVM linker
sudo tee scripts/ld/ld.lld << 'EOF'
#!/bin/bash
# Wrapper script for ld.lld
if [ "$1" = "-r" ]; then
    shift
    exec /usr/bin/ld.lld -r "$@"
else
    exec /usr/bin/ld.lld "$@"
fi
EOF

sudo chmod +x scripts/ld/ld.lld

# 9. Fix main.c compilation
if sudo grep -q "cred.bp_pgd_cred.*=.*offsetof.*cred,bp_pgd" init/main.c; then
    # Wrap the problematic code with #ifdef CONFIG_RKP_CRED_PROT
    sudo sed -i 's/^\s*cred\.bp_pgd_cred.*=.*offsetof.*cred,bp_pgd);/#ifdef CONFIG_RKP_CRED_PROT\n&/' init/main.c
    sudo sed -i '/cred\.usage_cred.*=.*offsetof.*cred,use_cnt);/a #endif' init/main.c
fi

echo "=== All fixes applied! ==="
echo "Now you need to:"
echo "1. Enable RKP in your kernel config:"
echo "   CONFIG_RKP=y"
echo "   CONFIG_RKP_PHYS_ALLOC=y"
echo "   CONFIG_RKP_CRED_PROT=y"
echo "2. Or run: ./scripts/config --enable RKP --enable RKP_PHYS_ALLOC --enable RKP_CRED_PROT"