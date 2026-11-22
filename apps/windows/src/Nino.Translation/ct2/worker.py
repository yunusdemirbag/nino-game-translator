# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Nino'nun CTranslate2 çeviri işçisi. Kullanım: python -u worker.py <model klasörü> <cpu|cuda> <iş parçacığı>
# İlk çıktı satırı hazır bilgisidir; sonra stdin'deki her istek satırına stdout'a tek satır yanıt yazılır.
#   istek : {"tokens": [...], "beams": 4, "max_output": 24}
#   yanıt : {"tokens": [...]}  ya da satır hatasında {"error": "..."}

import json
import os
import sys


def say(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def add_cuda_folder():
    folder = os.environ.get("NINO_CUDA_DIR")
    if not folder:
        return
    if hasattr(os, "add_dll_directory"):
        try:
            os.add_dll_directory(folder)
        except OSError:
            pass
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.kernel32.SetDllDirectoryW(folder)
        except (OSError, AttributeError):
            pass


def open_translator(model, device, threads):
    import ctranslate2

    kind = "float16" if device == "cuda" else "int8"
    engine = ctranslate2.Translator(
        model, device=device, compute_type=kind, inter_threads=1, intra_threads=threads
    )
    # İlk çıkarım CUDA bağımlılıklarını yükler; sorun varsa burada çıksın.
    engine.translate_batch([["▁Hello", ".", "</s>"]], beam_size=1)
    return engine


def serve(engine):
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            request = json.loads(raw)
            result = engine.translate_batch(
                [request["tokens"]],
                beam_size=int(request.get("beams", 4)),
                max_decoding_length=int(request.get("max_output", 128)),
            )
            say({"tokens": list(result[0].hypotheses[0])})
        except Exception as problem:  # satır düşer, işçi ayakta kalır
            say({"error": str(problem)})


def main(argv):
    if len(argv) < 4:
        say({"ready": False, "error": "kullanım: worker.py <model> <cpu|cuda> <iş parçacığı>"})
        return 1
    model, device = argv[1], argv[2]
    try:
        threads = max(1, int(argv[3]))
    except ValueError:
        threads = 1
    try:
        add_cuda_folder()
        engine = open_translator(model, device, threads)
    except Exception as problem:
        say({"ready": False, "error": str(problem)})
        return 1
    say({"ready": True})
    serve(engine)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
