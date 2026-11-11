"""
Text similarity for Phlio Stream: "songs with similar lyrics" and "titles
with a similar story".

The idea follows Searchly (github.com/AlbertSuarez/searchly, MIT): turn each
song's lyrics into a vector and return the nearest neighbours. Searchly used
word2vec over ~150k lyrics scraped from AZLyrics, with an NMSLIB index. Phlio
has no lyrics corpus of its own (and does not scrape lyrics sites), so it
works on the fly over a candidate set fetched per request (tens to a few
hundred documents). At that size a weighted TF-IDF model with cosine
similarity is exact, needs no trained model or extra memory, and can explain
its answers ("shared words: rain, city, midnight").

* :func:`tokens` — lowercase words in any script, without stop words,
  lyric fillers ("oh", "yeah", "la") or numbers, with light plural folding.
* :class:`Document` — weighted fields (title, genres, lyrics, ...) merged
  into one bag of weighted terms. Field weights let genre or mood count more
  than a common word.
* :class:`TfidfIndex` — sublinear TF, smoothed IDF, L2-normalised sparse
  vectors in an inverted index; :meth:`TfidfIndex.nearest` returns
  ``(id, score, shared_terms)`` sorted by cosine similarity.
"""

from __future__ import annotations

import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from typing import Iterable

_WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)?", re.UNICODE)

STOP_WORDS = frozenset("""
a about above after again against all am an and any are aren't as at be because been before being below between
both but by can can't cannot could couldn't did didn't do does doesn't doing don't down during each few for from
further had hadn't has hasn't have haven't having he he'd he'll he's her here here's hers herself him himself his
how how's i i'd i'll i'm i've if in into is isn't it it's its itself let's me more most mustn't my myself no nor
not of off on once only or other ought our ours ourselves out over own same shan't she she'd she'll she's should
shouldn't so some such than that that's the their theirs them themselves then there there's these they they'd
they'll they're they've this those through to too under until up very was wasn't we we'd we'll we're we've were
weren't what what's when when's where where's which while who who's whom why why's with won't would wouldn't you
you'd you'll you're you've your yours yourself yourselves
im ive id youre dont cant wont aint gonna wanna gotta ya yo got get gets just like know now one see go come
oh ooh ohh yeah yea hey la na da woah whoa uh huh mm mmm ah ha hmm baby
also film movie series show story episode season new will may way back even still make made us
""".split())


def tokens(text: str | None) -> list[str]:
    """Content words of ``text`` (any language), stop words and fillers removed."""
    out: list[str] = []
    for word in _WORD.findall((text or "").lower()):
        word = word.replace("’", "'")
        if word.endswith("'s"):
            word = word[:-2]
        if len(word) < 3 or word in STOP_WORDS:
            continue
        if len(word) > 4 and word.endswith("s") and not word.endswith("ss"):
            word = word[:-1]  # light plural folding: dreams -> dream
        out.append(word)
    return out


@dataclass
class Document:
    """A weighted bag of terms built from named fields."""

    id: str
    terms: Counter[str] = field(default_factory=Counter)

    def add_text(self, text: str | None, weight: float = 1.0) -> "Document":
        """Adds the words of free text (lyrics, synopsis, title)."""
        for term in tokens(text):
            self.terms[term] += weight
        return self

    def add_tags(self, prefix: str, values: Iterable[str] | None, weight: float = 1.0) -> "Document":
        """Adds whole-value tags such as ``genre:hip-hop`` (not split into words)."""
        for value in values or []:
            value = " ".join(str(value).lower().split())
            if value:
                self.terms[f"{prefix}:{value}"] += weight
        return self

    @property
    def empty(self) -> bool:
        return not self.terms


class TfidfIndex:
    """Exact cosine-similarity search over TF-IDF vectors (sparse, inverted index)."""

    def __init__(self, documents: Iterable[Document]) -> None:
        docs = [d for d in documents if not d.empty]
        df: Counter[str] = Counter()
        for d in docs:
            df.update(d.terms.keys())
        n = len(docs)
        self.idf = {t: math.log((1 + n) / (1 + c)) + 1.0 for t, c in df.items()}
        self.vectors: dict[str, dict[str, float]] = {d.id: self.vector(d) for d in docs}
        self.postings: dict[str, list[tuple[str, float]]] = defaultdict(list)
        for doc_id, vec in self.vectors.items():
            for term, w in vec.items():
                self.postings[term].append((doc_id, w))

    def __len__(self) -> int:
        return len(self.vectors)

    def vector(self, doc: Document) -> dict[str, float]:
        """Sublinear-TF x IDF, L2-normalised. Unknown terms get the max IDF."""
        default = max(self.idf.values(), default=1.0)
        vec = {t: (1.0 + math.log(tf)) * self.idf.get(t, default) for t, tf in doc.terms.items() if tf > 0}
        norm = math.sqrt(sum(w * w for w in vec.values())) or 1.0
        return {t: w / norm for t, w in vec.items()}

    def nearest(self, query: Document | str, k: int = 10, exclude: Iterable[str] = (),
                min_score: float = 0.02, explain: int = 4) -> list[tuple[str, float, list[str]]]:
        """Top-``k`` documents by cosine similarity to ``query`` (a document or an indexed id)."""
        qvec = self.vectors.get(query, {}) if isinstance(query, str) else self.vector(query)
        skip = set(exclude) | ({query} if isinstance(query, str) else set())
        scores: dict[str, float] = defaultdict(float)
        for term, qw in qvec.items():
            for doc_id, dw in self.postings.get(term, ()):
                if doc_id not in skip:
                    scores[doc_id] += qw * dw
        ranked = sorted(((s, d) for d, s in scores.items() if s >= min_score), reverse=True)[:k]
        out = []
        for score, doc_id in ranked:
            dvec = self.vectors[doc_id]
            shared = sorted(((qw * dvec[t], t) for t, qw in qvec.items() if t in dvec), reverse=True)
            words = [t.split(":", 1)[-1] for _, t in shared[:explain]]
            out.append((doc_id, round(min(score, 1.0), 4), words))
        return out


def best_line(text: str | None, query_terms: Iterable[str]) -> str | None:
    """The line of ``text`` sharing the most terms with the query (a short snippet)."""
    wanted = set(query_terms)
    best, best_hits = None, 0
    for line in (text or "").splitlines():
        hits = len(wanted.intersection(tokens(line)))
        if hits > best_hits:
            best, best_hits = line.strip(), hits
    return best[:140] if best else None
