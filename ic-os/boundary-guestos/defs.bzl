"""
Hold manifest common to all Boundary GuestOS variants.
"""

# Declare the dependencies that we will have for the built filesystem images.
# This needs to be done separately from the build rules because we want to
# compute the hash over all inputs going into the image and derive the
# "version.txt" file from it.

def image_deps(mode, sev = False):
    """
    Define all Boundary GuestOS inputs.

    Args:
      mode: Variant to be built, dev or prod.
      sev: if True, build an SEV-SNP enabled image
    Returns:
      A dict containing all file inputs to build this image.
    """

    extra_rootfs_deps = {
        "dev": {
            "//typescript/service-worker:favicon.png": "/var/www/html/favicon.png:0644",
            "//typescript/service-worker:index.html": "/var/www/html/index.html:0644",
            "//typescript/service-worker:install-script.js": "/var/www/html/install-script.js:0644",
            "//typescript/service-worker:install-script.js.map": "/var/www/html/install-script.js.map:0644",
            "//typescript/service-worker:style.css": "/var/www/html/style.css:0644",
            "//typescript/service-worker:sw.js": "/var/www/html/sw.js:0644",
            "//typescript/service-worker:sw.js.map": "/var/www/html/sw.js.map:0644",
            "//typescript/service-worker:web_bg.wasm": "/var/www/html/web_bg.wasm:0644",
        },
        "prod": {},
    }
    sev_rootfs_deps = {
        "@sevtool": "/opt/ic/bin/sevtool:0755",
    }
    deps = {
        "bootfs": {
            # base layer
            ":rootfs-tree.tar": "/",

            # We will install extra_boot_args onto the system, after substituting the
            # hash of the root filesystem into it. Track the template (before
            # substitution) as a dependency so that changes to the template file are
            # reflected in the overall version hash (the root_hash must include the
            # version hash, it cannot be the other way around).
            "//ic-os/boundary-guestos:bootloader/extra_boot_args.template": "/boot/extra_boot_args.template:0644",
        },
        "rootfs": {
            # base layer
            ":rootfs-tree.tar": "/",

            # additional files to install
            "//publish/binaries:boundary-node-control-plane": "/opt/ic/bin/boundary-node-control-plane:0755",
            "//publish/binaries:boundary-node-prober": "/opt/ic/bin/boundary-node-prober:0755",
            "//publish/binaries:certificate-issuer": "/opt/ic/bin/certificate-issuer:0755",
            "//publish/binaries:certificate-syncer": "/opt/ic/bin/certificate-syncer:0755",
            "//publish/binaries:denylist-updater": "/opt/ic/bin/denylist-updater:0755",
            "//publish/binaries:ic-balance-exporter": "/opt/ic/bin/ic-balance-exporter:0755",
            "//publish/binaries:ic-registry-replicator": "/opt/ic/bin/ic-registry-replicator:0755",
            "//publish/binaries:icx-proxy": "/opt/ic/bin/icx-proxy:0755",
            "//publish/binaries:systemd-journal-gatewayd-shim": "/opt/ic/bin/systemd-journal-gatewayd-shim:0755",
        },
    }
    deps["rootfs"].update(extra_rootfs_deps[mode])
    if sev:
        deps["rootfs"].update(sev_rootfs_deps)

    return deps
