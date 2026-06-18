# pocknix-os — Arch-ARM dual-session distro for the Retroid Pocket 6 (SM8550)
# See plan.md for the full phased build plan.
#
# Most targets build an aarch64 Linux image and must run on a Linux host as root
# (chroot/mount). Override config in config/pocknix.conf or via the environment.

SHELL   := /bin/bash
SCRIPTS := scripts

.DEFAULT_GOAL := help

.PHONY: help sync bootstrap build fast kernel packages sd-image install check du trim clean distclean

help: ## Show this help
	@echo "pocknix-os build targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

sync: ## Vendor ROCKNIX SM8550 kernel + device integration into vendor/
	@$(SCRIPTS)/sync.sh

bootstrap: ## Download + verify + extract the ALARM base rootfs (root, Linux)
	@$(SCRIPTS)/bootstrap.sh

build: ## Full build: bootstrap -> packages -> kernel -> assemble (root, Linux)
	@$(SCRIPTS)/build-image.sh

fast: ## Iterate on packages/config without re-bootstrapping (root, Linux)
	@$(SCRIPTS)/build-image-fast.sh

kernel: ## Build only the in-project kernel (linux-pocknix) [Phase 1]
	@if [ -x $(SCRIPTS)/build-kernel.sh ]; then $(SCRIPTS)/build-kernel.sh; \
	 else echo "Phase 1 not implemented: scripts/build-kernel.sh missing"; exit 1; fi

packages: ## Build local pocknix-* packages (makepkg in an Arch chroot) -> build/localrepo (root)
	@$(SCRIPTS)/build-packages.sh

sd-image: ## Build a flashable SD boot-test image (needs build + kernel) (root, Linux)
	@$(SCRIPTS)/build-sd-image.sh

install: ## Install to internal storage, preserving ABL [Phase 6] (on-device)
	@$(SCRIPTS)/install.sh

check: ## Preflight: validate harness + any built artifacts
	@$(SCRIPTS)/check.sh

du: ## Show build/ disk usage breakdown (find the space hogs)
	@du -sh build/* 2>/dev/null | sort -h; \
	 [ -d build/kernel ] && { echo '--- build/kernel ---'; du -sh build/kernel/* 2>/dev/null | sort -h; } || true

trim: ## Reclaim space: drop the regenerable kernel SOURCE tree (keeps KERNEL+modules+rootfs+image)
	@sudo rm -rf build/kernel/linux-* build/kernel/mkbootimg-src
	@echo "trimmed kernel source tree (regenerated on next 'make kernel'); kept out/, rootfs, image, cache"

clean: ## Remove build output: rootfs, image, kernel, package chroot (keeps download cache)
	@sudo rm -rf build/rootfs build/image build/localrepo build/kernel build/pkgbuild-root
	@echo "cleaned build artifacts (download cache kept)"

distclean: ## Remove all build output including caches
	@sudo rm -rf build/rootfs build/image build/localrepo build/kernel build/pkgbuild-root build/cache
	@echo "removed all build output"
