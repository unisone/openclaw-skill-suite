---
name: graphrag
description: Build a GraphRAG pipeline over documents. Use when plain vector search returns chunks without connections, when questions need multi-hop reasoning ("what caused X, and who was involved?"), or when you want queryable knowledge extracted from unstructured text.
license: MIT
metadata:
  author: unisone
---

# GraphRAG Skill

Retrieval-augmented generation over a knowledge graph instead of flat chunks.
Entities and relationships are extracted from your documents, stored in a
graph database, and the LLM reasons over the graph structure at query time.

## Why a Graph Instead of Vectors

Vector search finds *similar* chunks. It can't follow connections:

- "Which suppliers were affected by the outage at plant X?" needs
  `Outage → affects → Plant → supplied_by → Supplier` — two hops no
  single chunk contains.
- "Summarize everything we know about project Y" needs the *community*
  of entities around Y, not the ten most similar paragraphs.

If your questions are single-fact lookups, stick with vector RAG — it's
simpler. Reach for GraphRAG when questions span relationships.

## Stack

- **Kuzu** — embedded graph database (`pip install kuzu`), no server to run,
  Cypher query language. Start here.
- **Neo4j** — when you outgrow embedded: multi-user, bigger graphs, Bloom
  visualization. Same Cypher skills transfer.
- **LLM extraction** — any strong model with structured output for
  entity/relation extraction.

## Pipeline

### 1. Define the schema first

Don't let the extractor invent types freely — you'll get 40 spellings of
the same relationship. Declare node and edge types up front:

```cypher
CREATE NODE TABLE Person(name STRING, PRIMARY KEY(name));
CREATE NODE TABLE Project(name STRING, status STRING, PRIMARY KEY(name));
CREATE NODE TABLE Document(title STRING, date DATE, PRIMARY KEY(title));
CREATE REL TABLE WORKS_ON(FROM Person TO Project, role STRING);
CREATE REL TABLE MENTIONS(FROM Document TO Person);
CREATE REL TABLE MENTIONS_PROJECT(FROM Document TO Project);
```

Keep the schema small (5-10 node types). You can extend it; you can't
un-extract a messy graph cheaply.

### 2. Extract entities and relationships

Chunk documents (500-1000 tokens, overlapping), then prompt the extractor:

```
Extract entities and relationships from the text below.

Allowed node types: Person, Project, Document
Allowed edge types: WORKS_ON (Person→Project), MENTIONS (Document→Person),
                    MENTIONS_PROJECT (Document→Project)

Rules:
- Normalize names ("J. Smith" and "John Smith" are the same Person)
- Only extract relationships stated or clearly implied in the text
- Return JSON: {"nodes": [...], "edges": [...]}

Text:
<chunk>
```

Spot-check 10-20 chunks by hand. Extraction quality is the ceiling for
everything downstream — a noisy graph gives noisy answers.

### 3. Load into Kuzu

```python
import kuzu
db = kuzu.Database("./knowledge.kz")
conn = kuzu.Connection(db)
# create schema, then parameterized MERGE/CREATE per extracted node/edge
```

Deduplicate on load (`MERGE` on primary key) — the same entity appears
in many chunks.

### 4. Query patterns

**Local lookup** — everything connected to an entity:
```cypher
MATCH (p:Person {name: $name})-[r]-(neighbor)
RETURN type(r), neighbor;
```

**Multi-hop reasoning** — follow relationships across the graph:
```cypher
// Who works on projects mentioned in docs about the outage?
MATCH (d:Document)-[:MENTIONS_PROJECT]->(proj:Project)<-[:WORKS_ON]-(p:Person)
WHERE d.title CONTAINS 'outage'
RETURN DISTINCT p.name, proj.name;
```

**Global summarization** — community detection, then summarize each community:
```cypher
// Find densely connected clusters (run once, store community id on nodes)
CALL show_tables();  // then use your graph's community detection
```
Summarize each community with the LLM: "these entities cluster around
topic X." This is the GraphRAG "global query" — questions like "what are
the main themes in these documents?"

### 5. Answer with the LLM

The query pattern that works:

1. Agent translates the question into 1-3 Cypher queries
2. Results come back as structured rows
3. LLM synthesizes the answer *from the rows*, citing node/edge evidence
4. If a query returns nothing, the agent reformulates — never hallucinates
   graph content

## Temporal knowledge (agent memory)

For agent memory across sessions, add time to the edges: `VALID_FROM` /
`VALID_TO` timestamps, superseded facts marked rather than deleted. This is
the temporal-knowledge-graph pattern (see Graphiti/Zep): "the user *used to*
prefer X, now prefers Y" stays queryable instead of being overwritten.

## Anti-patterns

- **Extracting without a schema.** Free-form extraction produces a graph
  nobody can query.
- **GraphRAG for everything.** Single-fact lookup over clean docs? Vector
  search is cheaper and better. Use the graph where relationships matter.
- **Trusting extraction blindly.** Every pipeline needs a spot-check loop;
  extraction errors compound silently.
- **Huge chunks.** Entity extraction degrades past ~1000 tokens — the model
  starts dropping relationships. Smaller chunks, more of them.
- **No dedup on load.** "John Smith", "J. Smith", "Smith" as three nodes
  silently breaks multi-hop queries.
