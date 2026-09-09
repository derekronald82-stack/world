import sys
import os
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Keep automated tests away from the user's legacy database and media folder.
# test_api.py uses setdefault, so these values are installed before it imports
# the FastAPI application.
TEST_RUNTIME = Path(tempfile.mkdtemp(prefix="catws-pytest-"))
os.environ.setdefault(
    "DATABASE_URL",
    f"sqlite:///{(TEST_RUNTIME / 'test_8d_music.db').as_posix()}",
)
os.environ.setdefault("MEDIA_ROOT", str(TEST_RUNTIME / "media"))
os.environ.setdefault("STORAGE_BACKEND", "local")
