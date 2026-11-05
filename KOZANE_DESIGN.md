# Kozane Design

Status: Proposed  
Last updated: 2026-11-05

## Purpose

Kozane lets a person think with many Apple Notes at once without turning Apple Notes into a new editor or forcing notes into a taxonomy.

Apple Notes remains the source of truth. Kozane stores its own short cards, arrangements, and references to source notes.

```text
Question / theme
  ↓
Write or extract small kozane
  ↓
Lay them out and reorder them
  ↓
Keep the arrangement that gains a coherent line of thought
  ↓
Return later, revise, combine, or use it to write
```

## Source principle

Umesao Tadao's kozane method is treated as a method for composing a specific argument, not as a universal classification system. Small slips are written for a theme, put into an order that has a logical thread, bundled, and then used to write. The initial arrangement may be discarded or recomposed.

References:

- [Review quoting the description of kozane in Intellectual Production Techniques, pp. 203–205](https://www.jstage.jst.go.jp/article/religionandsociety/27/0/27_175/_pdf)
- [National Museum of Ethnology bibliography entry for Kozane Method 2, identified as an excerpt from the 1969 book](https://htq-fs.minpaku.ac.jp/umesaoww/20103)

## Terms

| Term | Meaning |
|---|---|
| Source note | A read-only Apple Note identified by its UUID. |
| Kozane | A concise, user-owned card: one claim, observation, quotation, question, step, or fragment. It is written or explicitly extracted by the user. |
| Arrangement | A temporary 2D placement and ordering of kozane for one question. |
| Bundle | A saved arrangement whose cards currently form a coherent thread. It remains editable and may later be recomposed. |
| Source rail | The right-side list of related Apple Notes and existing kozane. It supplies material; it does not classify it. |

## User experience

### Start

1. The person writes a question or theme.
2. Kozane opens an empty work surface and a source rail.
3. The person writes a first kozane, or explicitly extracts a short passage from a source note.
4. The person places, moves, removes, and rewrites cards until a line of thought appears.
5. The arrangement is saved as a bundle when wanted. Saving never asserts that the arrangement is final.

### Work surface

- A card shows concise text and its source indicator when it has one.
- Cards can be dragged, selected in groups, aligned, stacked, or moved aside.
- A card can be edited in place; it should stay short enough to be grasped at a glance.
- There are no required tags, types, folders, or automatic group labels.
- Lines are absent by default. They may be added later only when a person wants to express a relationship.
- Clicking a source reference opens the original Apple Note.

### Source rail

The right side contains a small, changing set of material:

- related Apple Notes, showing title and a short relevant passage;
- existing kozane that may bear on the current one;
- explicit Apple Notes links when present.

A source item has one primary action: extract as kozane. It does not automatically become part of the arrangement.

Every suggestion has a modest provenance label, such as similar wording, explicit link, or same source note. Kozane does not invent a thematic explanation or declare that two notes are related.

## Embedding-assisted retrieval

Embeddings are an assistant for finding material, never an authority for arranging it.

### When suggestions update

1. Wait until typing pauses for about 1–2 seconds.
2. Ignore very short drafts.
3. Look up the content hash in the local embedding cache.
4. If absent and boco mothership is reachable, request one embedding asynchronously.
5. Compare it locally with cached note and kozane embeddings.
6. Refresh only the source rail with a small number of candidates.

Typing and card movement must never wait for a network request. Stale requests are cancelled or ignored.

### Candidate ranking

The initial source rail balances:

- semantic similarity to the active question or selected kozane;
- explicit Apple Notes links;
- existing kozane already used in the current bundle;
- diversity, so one repeated kind of note does not occupy every suggestion.

The user can always pin, dismiss, or manually search for a source note. Manual choice outranks retrieval.

### Offline behavior

When the remote model is unavailable, existing cards and arrangements remain fully editable. Cached embeddings still support suggestions; a new draft waits for connectivity before it receives fresh suggestions.

## Data ownership and persistence

Kozane uses a separate local database under NoteMap's Application Support directory. It never writes to the Apple Notes database.

| Record | Core data |
|---|---|
| Bundle | ID, title/question, timestamps, viewport |
| Kozane | ID, text, optional source Apple Note UUID, optional source excerpt/hash, timestamps |
| Placement | bundle ID, kozane ID, x/y/size/z-index |
| Source reference | kozane ID, Apple Note UUID, source excerpt/hash |
| Embedding | model ID, content hash, vector cache entry |

A source excerpt becomes persistent only after the person explicitly extracts it as a kozane. Ordinary source-rail previews are read from Apple Notes on demand.

Future cross-device sync should sync only this Kozane database or an exported bundle file—not the Apple Notes database and not an exposed Ollama endpoint.

## Technical shape

The existing D3/WebView stack is suitable for the first work surface because it already provides zoom, pan, and JavaScript-to-Swift messaging. Kozane should be a separate module rather than another section of the current large graph HTML builder.

Planned components:

- Swift: KozaneStore, KozaneCandidateProvider, KozanePersistence
- Web resource: a dedicated card surface for drag, selection, zoom, and in-place editing
- Existing services: EmbeddingCache, EmbeddingService, Apple Notes read-only queries and deep links
- Persistence: GRDB-backed local SQLite database, separate from Apple Notes

## Scope boundaries

Not in the first version:

- automatic note classification;
- automatic bundle labels or AI-generated conclusions;
- default semantic relation lines;
- editing Apple Notes from Kozane;
- iCloud sync;
- iPhone-first interaction.

## Delivery plan

### Phase 0 — Design baseline

- Preserve this design.
- Treat the original kozane method as the product constraint: compose first, classify later.

### Phase 1 — Manual card surface

- Create/open a bundle with a question.
- Add hand-written kozane.
- Drag, zoom, select, delete, and save placements.
- Reopen the same arrangement.
- No embeddings required.

Success: a person can form and return to a coherent card arrangement without changing Apple Notes.

### Phase 2 — Apple Notes material

- Search Apple Notes and add a source note to the rail.
- Show title and short passage.
- Extract a selected passage into a kozane.
- Open the original note from its source reference.

Success: Apple Notes functions as a material library, not a one-note-at-a-time constraint.

### Phase 3 — Embedding suggestions

- Reuse the existing cached embeddings.
- Rank source-rail candidates for a question or selected kozane.
- Add debounced, cancellable remote embedding only for new text.
- Provide cache/offline behavior.

Success: related material appears without interrupting thought or imposing an arrangement.

### Phase 4 — Writing handoff

- Read the arranged cards as a sequence.
- Export a selected sequence to a new Apple Note or copy it to the clipboard.
- Keep the bundle editable after export.

Success: a bundle can become a draft while remaining a living arrangement.

### Later

- Compare and recombine bundles.
- Optional, user-authored relations between kozane.
- Private sync of Kozane data after the local workflow proves useful.
