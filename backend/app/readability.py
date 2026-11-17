"""Flesch-Kincaid grade level (NFR9: everything Lumis says should read at grade 8 or below).

Grade = 0.39 * (words / sentences) + 11.8 * (syllables / words) - 15.59. Syllables are counted with the usual
vowel-group rule (silent final e dropped, at least one per word). That is an estimate, accurate enough to keep
texts plainly worded, which is the point; the CP2 report should say an estimate was used."""
import re

_word = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")


def syllables(word: str) -> int:
    w = word.lower().strip("'")
    if len(w) <= 3:
        return 1
    w = re.sub(r"(?:[^laeiouy]es|[^laeiouy]ed|[^laeiouy]e)$", "", w)   # silent endings: makes, used, skin-e
    w = re.sub(r"^y", "", w)
    return max(1, len(re.findall(r"[aeiouy]{1,2}", w)))


def fk_grade(text: str) -> float:
    words = _word.findall(text)
    if not words:
        return 0.0
    sentences = max(1, len([s for s in re.split(r"[.!?]+", text) if _word.search(s)]))
    syl = sum(syllables(w) for w in words)
    return round(0.39 * len(words) / sentences + 11.8 * syl / len(words) - 15.59, 1)
