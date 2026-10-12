"""Where inputs and outputs live, anchored at the repository root so any working folder works."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Everything written lands under build/, which git ignores.
BUILD = ROOT / "build" / "audio"
PACKS = ROOT / "build" / "audio-packs"
MODEL_CACHE = BUILD / "hf"
DB = ROOT / "assets" / "berea.sqlite"
CACHE = ROOT / "packages" / "harness" / ".cache"
BSB_TXT = CACHE / "bsb.txt"
# The older BSB copy Berea used before 0.3.0; build_db.dart fetches it for its diff report.
READ_TEXT = CACHE / "BSB-scrollmapper-e1b254c.csv"
