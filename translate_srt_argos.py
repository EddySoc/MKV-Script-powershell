#!/usr/bin/env python3
"""
translate_srt_argos.py - Translate SRT subtitle files using Argos Translate (offline)

Usage:
    translate_srt_argos.exe --input INPUT.srt --output OUTPUT.srt --from en --to nl
    translate_srt_argos.exe --input INPUT.srt --output OUTPUT.srt --from eng --to dut

Supported language codes: 2-letter (en, nl, fr, de, ...) or 3-letter (eng, dut, fra, deu, ...)
Exit codes: 0 = success, 1 = error

Portable mode: argos-packages/ directory is read from next to the exe (or next to the .py script).
Translation engine: ctranslate2 batch mode (fast), falls back to argostranslate if needed.
"""

import argparse
import json
import re
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", message="Unable to find acceptable character detection dependency")

# ── Portable packages dir detection ───────────────────────────────────────────────────

def _find_packages_dir(override=None):
    if override and override.is_dir():
        return override
    if getattr(sys, 'frozen', False):
        candidate = Path(sys.executable).parent / "argos-packages"
    else:
        candidate = Path(__file__).parent / "argos-packages"
    return candidate if candidate.is_dir() else None


def _setup_portable_argos(override=None):
    pkg_dir = _find_packages_dir(override)
    if pkg_dir:
        try:
            import argostranslate.settings as _s
            _s.package_data_dir = pkg_dir
            _s.package_dirs = [pkg_dir]
        except ImportError:
            pass


_setup_portable_argos()

# ── Language code normalisation ────────────────────────────────────────────────────────

LANG_MAP = {
    "dut": "nl", "nld": "nl", "eng": "en", "fra": "fr", "fre": "fr",
    "deu": "de", "ger": "de", "spa": "es", "por": "pt", "ita": "it",
    "pol": "pl", "swe": "sv", "nor": "no", "dan": "da", "fin": "fi",
    "rus": "ru", "jpn": "ja", "kor": "ko", "chi": "zh", "ara": "ar",
    "tur": "tr", "cze": "cs", "slv": "sl", "slk": "sk", "ukr": "uk",
    "bul": "bg", "gre": "el", "heb": "he", "hin": "hi", "vie": "vi",
    "may": "ms", "ind": "id", "tam": "ta",
}

def normalize_lang(code):
    return LANG_MAP.get(code.lower().strip(), code.lower().strip())

# ── Package discovery ──────────────────────────────────────────────────────────────────

def _find_package(packages_dir, from_code, to_code):
    for pkg_dir in packages_dir.iterdir():
        if not pkg_dir.is_dir():
            continue
        meta = pkg_dir / "metadata.json"
        if not meta.exists():
            continue
        try:
            info = json.loads(meta.read_text(encoding='utf-8'))
        except Exception:
            continue
        if info.get("from_code") == from_code and info.get("to_code") == to_code:
            model_dir = pkg_dir / "model"
            sp_model  = pkg_dir / "sentencepiece.model"
            if model_dir.is_dir() and sp_model.exists():
                return model_dir, sp_model
    return None

# ── Translation engines ────────────────────────────────────────────────────────────────

class _Ct2Translator:
    """Fast batch translator using ctranslate2 + sentencepiece directly."""
    def __init__(self, model_dir, sp_model_path):
        import ctranslate2
        import sentencepiece as spm
        self._ct2 = ctranslate2.Translator(
            str(model_dir), device="cpu", inter_threads=4, compute_type="int8",
        )
        self._sp = spm.SentencePieceProcessor()
        self._sp.Load(str(sp_model_path))

    def translate_batch(self, texts):
        if not texts:
            return []
        tokenized = [self._sp.Encode(t, out_type=str) for t in texts]
        results   = self._ct2.translate_batch(tokenized, beam_size=2)
        # sp.Decode() on string pieces does not strip the ▁ word-boundary marker;
        # convert manually: ▁ (U+2581) marks a leading space for each piece.
        decoded = []
        for r in results:
            text = ''.join(p.replace('\u2581', ' ') for p in r.hypotheses[0]).strip()
            decoded.append(text)
        return decoded


class _ArgosTranslator:
    """One-by-one fallback using argostranslate (same batch interface)."""
    def __init__(self, at_translator):
        self._t = at_translator

    def translate_batch(self, texts):
        return [self._t.translate(t) for t in texts]

# ── SRT parsing/writing ────────────────────────────────────────────────────────────────

def parse_srt(content):
    content = content.replace('\r\n', '\n').replace('\r', '\n')
    blocks  = re.split(r'\n{2,}', content.strip())
    entries = []
    for block in blocks:
        lines = block.split('\n')
        if len(lines) < 3:
            continue
        if not re.match(r'^\d+$', lines[0].strip()):
            continue
        if '-->' not in lines[1]:
            continue
        entries.append((lines[0].strip(), lines[1].strip(), lines[2:]))
    return entries


def write_srt(entries, output_path):
    with open(output_path, 'w', encoding='utf-8') as f:
        for index, timing, text_lines in entries:
            f.write(f"{index}\n{timing}\n")
            f.write('\n'.join(text_lines))
            f.write('\n\n')

# ── Batch translation with progress ───────────────────────────────────────────────────

_OPEN_TAG_RE  = re.compile(r'^(<[^>]+>)+', re.IGNORECASE)
_CLOSE_TAG_RE = re.compile(r'(<\/[^>]+>)+$', re.IGNORECASE)

def _strip_tags(line):
    s   = line.strip()
    pre = _OPEN_TAG_RE.match(s)
    suf = _CLOSE_TAG_RE.search(s)
    p   = pre.group(0) if pre else ''
    q   = suf.group(0) if suf else ''
    return p, s[len(p):len(s) - len(q)].strip(), q


def translate_entries(entries, translators, verbose=True):
    """Collect all text, batch-translate in chunks, restore into entries."""
    jobs = []
    for ei, (_, _, text_lines) in enumerate(entries):
        for li, line in enumerate(text_lines):
            p, inner, q = _strip_tags(line)
            if inner:
                jobs.append((ei, li, p, inner, q))

    if not jobs:
        return list(entries)

    inner_texts  = [j[3] for j in jobs]
    chunk_size   = 150
    total_chunks = max(1, (len(inner_texts) + chunk_size - 1) // chunk_size)
    translated   = []

    for ci in range(total_chunks):
        chunk   = inner_texts[ci * chunk_size:(ci + 1) * chunk_size]
        current = chunk
        for tr in translators:
            current = tr.translate_batch(current)
        translated.extend(current)
        if verbose:
            print(f"{int((ci + 1) * 100 / total_chunks)}%", flush=True)

    job_map = {(j[0], j[1]): j[2] + translated[i] + j[4] for i, j in enumerate(jobs)}
    result  = []
    for ei, (index, timing, text_lines) in enumerate(entries):
        new_lines = [job_map.get((ei, li), line) for li, line in enumerate(text_lines)]
        result.append((index, timing, new_lines))
    return result

# ── Argostranslate chain fallback ─────────────────────────────────────────────────────

def _find_argos_chain(languages, from_code, to_code):
    from_obj = next((l for l in languages if l.code == from_code), None)
    to_obj   = next((l for l in languages if l.code == to_code),   None)
    if not from_obj:
        return None, None
    direct = from_obj.get_translation(to_obj) if to_obj else None
    if direct:
        return [_ArgosTranslator(direct)], f"{from_code} -> {to_code}"
    candidates = ['en'] + [l.code for l in languages if l.code not in (from_code, to_code, 'en')]
    for mid in candidates:
        mid_obj = next((l for l in languages if l.code == mid), None)
        if not mid_obj:
            continue
        t1 = from_obj.get_translation(mid_obj)
        t2 = mid_obj.get_translation(to_obj) if to_obj else None
        if t1 and t2:
            return [_ArgosTranslator(t1), _ArgosTranslator(t2)], f"{from_code} -> {mid} -> {to_code}"
    return None, None

# ── Main ───────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Translate SRT using Argos Translate (offline)')
    parser.add_argument('--input',        required=True)
    parser.add_argument('--output',       required=True)
    parser.add_argument('--from',         dest='from_lang', required=True)
    parser.add_argument('--to',           dest='to_lang',   required=True)
    parser.add_argument('--quiet',        action='store_true')
    parser.add_argument('--packages-dir', dest='packages_dir', default=None)
    args = parser.parse_args()

    if args.packages_dir:
        _setup_portable_argos(Path(args.packages_dir))

    from_code = normalize_lang(args.from_lang)
    to_code   = normalize_lang(args.to_lang)

    translators = None
    chain_desc  = f"{from_code} -> {to_code}"
    pkg_dir     = _find_packages_dir(Path(args.packages_dir) if args.packages_dir else None)

    if pkg_dir:
        # 1. Direct pair
        pkg = _find_package(pkg_dir, from_code, to_code)
        if pkg:
            try:
                translators = [_Ct2Translator(*pkg)]
            except Exception as e:
                print(f"WARNING: ctranslate2 direct failed ({e})", file=sys.stderr)

        # 2. Chain via English
        if translators is None and from_code != 'en' and to_code != 'en':
            pkg1 = _find_package(pkg_dir, from_code, 'en')
            pkg2 = _find_package(pkg_dir, 'en', to_code)
            if pkg1 and pkg2:
                try:
                    translators = [_Ct2Translator(*pkg1), _Ct2Translator(*pkg2)]
                    chain_desc  = f"{from_code} -> en -> {to_code}"
                except Exception as e:
                    print(f"WARNING: ctranslate2 chain failed ({e})", file=sys.stderr)

    # 3. Fallback: argostranslate
    if translators is None:
        try:
            import argostranslate.translate as at
            translators, chain_desc = _find_argos_chain(at.get_installed_languages(), from_code, to_code)
        except ImportError as e:
            print(f"ERROR: argostranslate not available: {e}", file=sys.stderr)

    if not translators:
        print(f"ERROR: No translation model for {from_code} -> {to_code}.", file=sys.stderr)
        if pkg_dir:
            pkgs = [p.name for p in pkg_dir.iterdir() if p.is_dir()]
            print(f"       Packages: {', '.join(pkgs)}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(args.input, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except Exception as e:
        print(f"ERROR: Cannot read '{args.input}': {e}", file=sys.stderr)
        sys.exit(1)

    entries = parse_srt(content)
    if not entries:
        print(f"ERROR: No valid SRT entries in '{args.input}'.", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        engine = "ctranslate2/batch" if isinstance(translators[0], _Ct2Translator) else "argostranslate"
        print(f"Translating {len(entries)} subtitle entries ({chain_desc}) [{engine}]...")

    translated = translate_entries(entries, translators, verbose=not args.quiet)

    try:
        write_srt(translated, args.output)
    except Exception as e:
        print(f"ERROR: Cannot write '{args.output}': {e}", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        print(f"Done -> {args.output}")


if __name__ == '__main__':
    main()
