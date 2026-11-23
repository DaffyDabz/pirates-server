# Patches

## server-tree/

371 patches made with `git format-patch`, one fix each, numbered in the order they go on.

- Base: [Pirates Online Classic](https://github.com/PiratesOnlineClassic/pirates-online-classic) at commit
  `741208881fdec30ee299b33897ef07648998faed`.
- Apply them all with `git am --keep-cr patches/server-tree/*.patch` in a clean checkout of that commit.
  `--keep-cr` matters: some upstream files use Windows line endings.
- They touch Python code, the `.dc` network definition files and three `.prc` config files (`dev.prc`,
  `general.prc`, `performance.prc`). They never touch `server.prc`, and none of them add game files.
- Each patch's message says what it fixes, in plain words.

## libotp-nametags.patch and libotp/

POC needs `libotp`, which was a compiled Disney library. The pure-Python
[libotp-nametags](https://github.com/PiratesOnlineClassic/libotp-nametags) (commit `75adedc`) stands in for it.

1. `git apply patches/libotp-nametags.patch` in that checkout.
2. Copy `libotp/NametagConstants.py` into its `libotp/` folder.
3. Link that `libotp/` folder into the POC tree as `libotp`.
