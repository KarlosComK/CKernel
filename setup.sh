#!/usr/bin/env bash
# =============================================================================
# ONE-SHOT SETUP: CKernel (dandelion, kernel 4.19.275) -> KernelSU-Next + SUSFS
# Run this on a Linux machine / WSL / Codespace with internet access and git.
# It clones the proven-working CKernel V2 source, swaps its root driver
# (ReSukiSU) for KernelSU-Next+SUSFS, patches configs, and leaves you a
# ready-to-push repo with a GitHub Actions build workflow already inside.
# =============================================================================
set -e

WORKDIR="CKernel-KSUN"
REPO_URL="https://github.com/KarlosComK/CKernel.git"
KSUN_SUSFS_URL="https://github.com/wshamroukh/KernelSU-Next-SUSFS-kernelv4.19.git"
SUSFS_PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI-SUSFS-Mainline/main/Patches/Patch/susfs_patch_to_4.19.patch"
SUSFS_HOOK_SCRIPT_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI-SUSFS-Mainline/main/Patches/susfs_inline_hook_patches.sh"

echo "=== [1/8] Cloning CKernel (full history, so we can reach tag 2) ==="
if [ ! -d "$WORKDIR" ]; then
    git clone "$REPO_URL" "$WORKDIR"
fi
cd "$WORKDIR"

echo "=== [2/8] Checking out the V2 source (tag '2') ==="
git fetch --tags
if git rev-parse "2" >/dev/null 2>&1; then
    git checkout "tags/2" -b ksun-work 2>/dev/null || git checkout ksun-work
else
    echo "  -> WARNING: tag '2' not found. Listing available tags/branches instead:"
    git tag -l
    git branch -a
    echo "  -> Manually checkout the correct one, then re-run this script from inside the repo with SKIP_CLONE=1."
    exit 1
fi

echo "=== [3/8] Locating the existing root driver (ReSukiSU or similar) ==="
EXISTING_ROOT_DIR=$(find drivers -maxdepth 1 -iname "*ksu*" -o -iname "*suki*" -o -iname "*resukisu*" 2>/dev/null | head -n1)
if [ -n "$EXISTING_ROOT_DIR" ]; then
    echo "  -> Found existing root driver at: $EXISTING_ROOT_DIR"
else
    echo "  -> Could not auto-detect existing root driver folder under drivers/."
    echo "     Listing drivers/ contents for manual inspection:"
    ls drivers/ | head -50
fi

echo "=== [4/8] Backing up and removing existing root driver ==="
if [ -n "$EXISTING_ROOT_DIR" ]; then
    mkdir -p ../backup_reference
    cp -r "$EXISTING_ROOT_DIR" ../backup_reference/ 2>/dev/null || true
    git rm -r --cached "$EXISTING_ROOT_DIR" >/dev/null 2>&1 || true
    rm -rf "$EXISTING_ROOT_DIR"
    echo "  -> Old driver removed (backup kept at ../backup_reference/ for reference)."
fi

echo "=== [5/8] Adding KernelSU-Next + SUSFS as the new root driver ==="
git submodule add -b legacy "$KSUN_SUSFS_URL" drivers/kernelsu
git submodule update --init --recursive

echo "=== [6/8] Wiring drivers/Kconfig and drivers/Makefile ==="
if ! grep -q "kernelsu/Kconfig" drivers/Kconfig; then
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi
# Remove any old reference to the previous root driver's Makefile line if it lingers
if [ -n "$EXISTING_ROOT_DIR" ]; then
    OLDNAME=$(basename "$EXISTING_ROOT_DIR")
    sed -i "/${OLDNAME}\//d" drivers/Makefile 2>/dev/null || true
fi
if ! grep -q "kernelsu/" drivers/Makefile; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
fi

echo "=== [7/8] Applying SUSFS patch + defconfig changes ==="
curl -LSs -o /tmp/susfs_patch_to_4.19.patch "$SUSFS_PATCH_URL"
set +e
patch -p1 --forward < /tmp/susfs_patch_to_4.19.patch
set -e
find . -name "*.rej" -exec echo "  -> REVIEW MANUALLY: {}" \;

curl -LSs -o /tmp/susfs_inline_hook_patches.sh "$SUSFS_HOOK_SCRIPT_URL"
chmod +x /tmp/susfs_inline_hook_patches.sh
echo "  -> Run /tmp/susfs_inline_hook_patches.sh manually once .rej files (if any) are resolved."

DEFCONFIG=$(find arch/arm64/configs -iname "*dandelion*" -o -iname "*blossom*" -o -iname "*9a*" 2>/dev/null | head -n1)
if [ -n "$DEFCONFIG" ]; then
    echo "  -> Appending KSU/SUSFS config to: $DEFCONFIG"
    cat >> "$DEFCONFIG" <<'EOF'

# --- KernelSU-Next + SUSFS ---
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_MODULES=y
CONFIG_KPROBES=y
EOF
    echo "DEFCONFIG_USED=$DEFCONFIG" > ../defconfig_used.txt
else
    echo "  -> Could not auto-find defconfig. Search manually:"
    echo "       find arch/arm64/configs -iname '*dandelion*'"
fi

echo "=== [8/8] Copying the ready-made build workflow into place ==="
mkdir -p .github/workflows
cp ../build.yml .github/workflows/build.yml 2>/dev/null || echo "  -> build.yml not found alongside this script; copy it manually into .github/workflows/"

echo ""
echo "=========================================================================="
echo " DONE. Remaining manual checks before pushing:"
echo "  1. Resolve any '*.rej' files listed above."
echo "  2. Verify drivers/Kconfig placement of the new 'source' line looks sane."
echo "  3. Run /tmp/susfs_inline_hook_patches.sh if using manual hooks."
echo "  4. Check defconfig_used.txt to confirm the right defconfig was edited."
echo "  5. git add -A && git commit -m 'Swap to KernelSU-Next + SUSFS' && git push"
echo "  6. On GitHub: Actions tab -> run the build workflow -> download artifact."
echo "  7. Backup your current boot partition before flashing the result."
echo "=========================================================================="
