A session commits and pushes the check-in to build, then sends this run from its clone: `ocx2 create "stage CHECKIN" --pattern URL --login LOGIN --clone CODE --to POST --of CHECKIN`. LOGIN and CODE name the builder's acting login and its clone's server-code; POST is in the session's thread. URL is this file's content-addressed raw URL on crystal-robots, `https://ollama.openbeagle.org/crystal-robots/raw/HASH?m=text/plain`, HASH being this file's SHA3-256 at the check-in that holds it. It is ocx-console's stage pattern (ocx-console `patterns/stage.md`, check-in 170ebb1105) for crystal-robots, for OCX's web install of crystal-robots as an app (`import RUN --app crystal-robots`, then `accept --app crystal-robots`), served at `/crystal-robots/ext/ocx2-cgi/app/crystal-robots`.

`--of` must be the check-in's full hash.

The run clones crystal-robots anonymously into its workspace and opens CHECKIN. The static build links Alpine's static libraries, so the run first makes an Alpine root holding only those (`browser_rootfs make-static`, about 17 MiB, without Chromium, which is bigger than a stage run may write), at `$HOME/browser-rootfs`, where `ci.cr` looks. Then `crystal run ci.cr -- build $$workspace$$/release x86_64`, niced: the whole of `crystal run ci.cr` (shards, the API docs, the specs, the format check, the example robots, the CLI smoke; node, wasmer and browser specs pending), then, only if all is green, the static `crystal-robots`, with the API docs embedded, checked to answer `usage: crystal-robots` with no arguments and an empty environment, as import checks it, and `gate.txt` and `release.txt` (each file's SHA-256, by name) in the workspace's `release/`. The run exits with the build's status. OCX sends those three files as unversioned files under `releases/$$run$$/`; on failure they are absent.

This pattern is for x86_64 builders. The run has no homes or secrets, writes only in its workspace and ends with its parent. It needs the network (the clone, shards, Alpine's packages), `bwrap` with user namespaces (the Alpine root is entered with it), and `fossil`, `crystal`, `shards` and libyaml on the builder.

```json
{
  "workspace": [
    {
      "step": "directory",
      "at": "$$root$$/$$process_user$$/projects/$$repository_name$$/$$run$$",
      "remove_on": "saved"
    }
  ],
  "sandbox": {
    "uid": 1000,
    "gid": 1000,
    "linux_capabilities": [],
    "network": true,
    "isolate_terminal": true,
    "ends_with_parent": true,
    "read_only": [
      "/usr", "/bin", "/sbin", "/lib", "/lib64",
      "/etc/resolv.conf", "/etc/hosts", "/etc/nsswitch.conf", "/etc/ssl/certs"
    ],
    "read_write": ["$$workspace$$"],
    "homes": [],
    "created_files": [
      {
        "at": "/etc/passwd",
        "text": "$$process_user$$:x:1000:1000::$$workspace$$:/bin/sh\n"
      }
    ],
    "proc": "/proc",
    "dev": "/dev",
    "tmp": "/tmp"
  },
  "limits": {
    "wall": "2h",
    "cpu": 3600,
    "processes": 512,
    "file_size": "256M"
  },
  "process": {
    "user": "stage-task",
    "command": [
      "/bin/sh", "-c",
      "fossil clone $$server_url$$ $$workspace$$/clone.fossil && mkdir $$workspace$$/tree && fossil open $$workspace$$/clone.fossil $$checkin$$ --chdir $$workspace$$/tree --nosync && cd $$workspace$$/tree && crystal build tools/browser-rootfs/browser_rootfs.cr -o $$workspace$$/browser_rootfs && $$workspace$$/browser_rootfs make-static && nice -n 19 ionice -c3 crystal run ci.cr -- build $$workspace$$/release x86_64"
    ],
    "cwd": "$$workspace$$",
    "keep": {"stderr": "4K", "stdout": "4K", "stdout_when": "always"},
    "unversioned_files": [
      {"at": "$$workspace$$/release/crystal-robots", "as": "releases/$$run$$/crystal-robots"},
      {"at": "$$workspace$$/release/release.txt", "as": "releases/$$run$$/release.txt"},
      {"at": "$$workspace$$/release/gate.txt", "as": "releases/$$run$$/gate.txt"}
    ],
    "env": {"HOME": "$$workspace$$", "USER": "$$process_user$$", "PATH": "/usr/local/bin:/usr/bin:/bin"}
  }
}
```
