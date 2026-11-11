# A browser for this session

Copied from ocx-console (MIT, https://ollama.openbeagle.org/ocx-console), check-in 170ebb1105. Here it makes the Alpine static libraries that `crystal run ci.cr -- build OUT x86_64` links (`./browser_rootfs make-static`, about 17 MiB, at `$HOME/browser-rootfs`), as `patterns/stage.md` does in a stage run. `make` adds Chromium for headless page checks.

The session's host has no browser, and no root. `browser_rootfs.cr` makes an
Alpine root file system holding Chromium, and runs commands inside it, with
`bwrap` in a user namespace. Its seed is bootstrap-qcow2's: Alpine 3.23.2's
minirootfs, checked against Alpine's `.sha256`, `etc/resolv.conf` written
from outside, then `apk add` from inside.

Needs: Crystal (1.19.1 here), `bwrap`, `tar`, unprivileged user namespaces,
and about 760 MiB for the root file system. It is made at `$HOME/browser-rootfs`,
outside the checkout, unless a path is given.

Make it (about a minute; run again, it changes nothing but adds what's missing):

    crystal build tools/browser-rootfs/browser_rootfs.cr -o browser_rootfs
    ./browser_rootfs make

It ends by printing Chromium's version: `Chromium 149.0.7827.53 Alpine Linux`
on 2026-11-04.

Open a page and print what its script drew:

    ./browser_rootfs run -- chromium-browser --headless --no-sandbox \
      --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 \
      --dump-dom URL

`--no-sandbox` because Chromium's own sandbox can't nest in this one. It
shares the host's network, so `localhost` is the host's. D-Bus errors on
standard error are expected and harmless.
