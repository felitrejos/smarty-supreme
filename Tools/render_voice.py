"""Render every referee and computer line with Kokoro into Assets/Voice.

    swift run --package-path FlickCore flick-voice-lines > lines.json
    python render_voice.py lines.json Assets/Voice

Needs `pip install kokoro soundfile` and macOS's afconvert.
"""
import json
import os
import subprocess
import sys
import tempfile

import misaki.espeak
import numpy as np
import soundfile as sf


class NoFallback:
    def __init__(self, *args, **kwargs):
        raise RuntimeError("espeak fallback disabled; every line is in Kokoro's own dictionary")


misaki.espeak.EspeakFallback = NoFallback
from kokoro import KPipeline  # noqa: E402

VOICES = {"referee": ("b", "bm_george", 0.95), "computer": ("a", "am_puck", 1.05)}


def main(lines_path, out_dir):
    lines = json.load(open(lines_path))
    pipelines = {}
    for role, entries in lines.items():
        language, voice, speed = VOICES[role]
        pipeline = pipelines.setdefault(language, KPipeline(lang_code=language))
        folder = os.path.join(out_dir, role)
        os.makedirs(folder, exist_ok=True)
        for entry in entries:
            audio = np.concatenate([chunk.audio for chunk in pipeline(entry["text"], voice=voice, speed=speed)])
            with tempfile.NamedTemporaryFile(suffix=".wav") as wav:
                sf.write(wav.name, audio, 24000)
                target = os.path.join(folder, entry["file"] + ".m4a")
                subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", wav.name, target], check=True)
        print(role, len(entries), "lines")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
