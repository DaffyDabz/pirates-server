# Family shim. Pirates Online Classic imports `libotp.NametagConstants`, but the pure-Python
# libotp-nametags package keeps those names in `libotp/_constants.py` and re-exports them from
# the package root. Drop this file into libotp/ next to _constants.py (both server and client).
from libotp._constants import *  # noqa: F401,F403
from libotp import *  # noqa: F401,F403
