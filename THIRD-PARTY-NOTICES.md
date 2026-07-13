# Third-Party Notices

AfterglowKit derives data from a third-party source. This file records its
provenance and licensing. AfterglowKit's own source code is licensed under
Apache-2.0 (see [LICENSE](LICENSE)).

## UAO 2.50 Big5↔Unicode mapping data

**Derived file**

- `Sources/PTTBig5Codec/Generated/UAOTable.swift` — a compact (varint-delta)
  encoding of both the UAO 2.50 b2u (Big5→Unicode) and u2b (Unicode→Big5)
  mappings, produced at development time by `swift run afterglowdata generate`
  and committed to the repository.

**Provenance**

The mapping data is the UAO 2.50 (Unicode-At-On) Big5↔Unicode tables, compiled
and provided by **witchfive** as part of the UAO (Unicode-At-On) effort, and
**published by MozTW** at <https://moztw.org/docs/big5/>.

The source tables are **not redistributed in this repository**. The generator
fetches both from MozTW's official repository at commit-pinned URLs
(`moztw/www.moztw.org@bbb049de`, `docs/big5/table/uao250-b2u.txt` and
`uao250-u2b.txt`) and verifies each file's SHA-256 (`73e6457e…37995` for b2u,
`2edfd7b1…299cf` for u2b, both recorded in the generator source) before use;
any mismatch aborts generation. Consumer builds never fetch anything — the
derived table above is committed.

The u2b table mixes exact (round-trippable) mappings with best-fit
approximations for characters absent from Big5-UAO, and marks characters with
no mapping at all using a `0xFFFD` sentinel; AfterglowKit's encode table only
retains rows with an actual mapping and classifies exact vs. best-fit at query
time by cross-checking against the b2u table (see `UAO.encode(_:mode:)`).

**Licensing**

The raw character-code correspondence (Big5 code point ↔ Unicode scalar) is
factual data and is not, in itself, a copyrightable creative work. The
attribution above is provided as a courtesy and as a record of provenance. No
additional restrictions are imposed by AfterglowKit on the mapping data itself.
