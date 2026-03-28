"""SKWhisper → skgraph (FalkorDB) client.

Writes session digest Memory nodes + Tag/Person relationships into
the FalkorDB knowledge graph at 192.168.0.59:16379.

Graph: lumina_knowledge
Node types:     Memory, Tag, Person, Project
Relationships:  TAGGED_WITH, MENTIONS, PART_OF, RELATED_TO
"""

import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ..config import Config

log = logging.getLogger("skwhisper.skgraph")

# Default connection
FALKOR_HOST = "192.168.0.59"
FALKOR_PORT = 16379
GRAPH_NAME  = "lumina_knowledge"

# Known projects for auto-linking
KNOWN_PROJECTS = [
    "SKStacks", "Chiropps", "SwapSeat", "SKGentis", "SKWhisper",
    "Brother John", "FORGEPRINT", "NAMStacks", "Sovereign AI",
]


def _escape(s) -> str:
    """Escape a string for use inside single-quoted Cypher literals."""
    if not s:
        return ""
    return str(s).replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"') \
                 .replace("\n", " ").replace("\r", "")[:400]


class SKGraphWriter:
    """Synchronous FalkorDB writer used by the SKWhisper daemon."""

    def __init__(self, host: str, port: int, graph: str = GRAPH_NAME):
        from redis import Redis
        self._redis = Redis(
            host=host, port=port, decode_responses=True,
            socket_connect_timeout=5, socket_timeout=15,
        )
        self._graph = graph
        # Verify connection
        self._redis.ping()
        log.info("skgraph: connected to FalkorDB at %s:%d graph=%s", host, port, graph)

    # ─── Factory ─────────────────────────────────────────────────────────────

    @classmethod
    def from_config(cls, config: "Config") -> "SKGraphWriter | None":
        """Build from SKWhisper Config. Returns None (with warning) if unavailable."""
        host = getattr(config, "falkordb_host", FALKOR_HOST)
        port = int(getattr(config, "falkordb_port", FALKOR_PORT))
        graph = getattr(config, "falkordb_graph", GRAPH_NAME)
        try:
            return cls(host=host, port=port, graph=graph)
        except Exception as e:
            log.warning("skgraph unavailable (%s:%d): %s — skipping graph writes", host, port, e)
            return None

    # ─── Core query helper ────────────────────────────────────────────────────

    def _q(self, query: str):
        try:
            return self._redis.execute_command("GRAPH.QUERY", self._graph, query)
        except Exception as e:
            log.debug("skgraph query error: %s | query: %.120s", e, query)
            return None

    # ─── Node helpers ─────────────────────────────────────────────────────────

    def _merge_node(self, label: str, name: str, props: dict | None = None):
        safe = _escape(name)
        if not safe.strip():
            return
        if props:
            set_clause = ", ".join(
                f"n.{k} = '{_escape(v)}'" for k, v in props.items() if v is not None
            )
            self._q(f"MERGE (n:{label} {{name: '{safe}'}}) SET {set_clause}")
        else:
            self._q(f"MERGE (n:{label} {{name: '{safe}'}})")

    def _merge_rel(self, from_label: str, from_name: str,
                   rel: str, to_label: str, to_name: str, weight: float = 1.0):
        sf = _escape(from_name)
        st = _escape(to_name)
        if not sf.strip() or not st.strip():
            return
        self._q(
            f"MATCH (a:{from_label} {{name: '{sf}'}}), (b:{to_label} {{name: '{st}'}}) "
            f"MERGE (a)-[r:{rel}]->(b) "
            f"ON CREATE SET r.weight = {weight} "
            f"ON MATCH SET r.weight = r.weight + {weight}"
        )

    # ─── Main write method ────────────────────────────────────────────────────

    def write_memory(
        self,
        session_id: str,
        title: str,
        summary: str,
        topics: list[str],
        people: list[str],
        projects: list[str],
        created_at: str,
    ):
        """
        Write a session digest to the knowledge graph.

        Creates/updates:
          - Memory node (keyed by title)
          - Tag nodes for topics → Memory -[TAGGED_WITH]-> Tag
          - Person nodes for people → Memory -[MENTIONS]-> Person
          - Project nodes for projects → Memory -[PART_OF]-> Project
          - Updates Tag co-occurrence weights (RELATED_TO) for frequently paired topics
        """
        safe_title   = _escape(title[:120])
        safe_summary = _escape(summary[:300])
        safe_date    = _escape(created_at)
        safe_sid     = _escape(session_id[:36])

        if not safe_title.strip():
            return

        # Upsert Memory node
        self._q(
            f"MERGE (m:Memory {{name: '{safe_title}'}}) "
            f"SET m.summary = '{safe_summary}', "
            f"m.date = '{safe_date}', "
            f"m.session_id = '{safe_sid}'"
        )

        # Topic tags → TAGGED_WITH
        clean_topics = [t for t in (topics or []) if t and t not in ("skwhisper", "auto-digest")][:8]
        for topic in clean_topics:
            self._merge_node("Tag", topic)
            self._merge_rel("Memory", title, "TAGGED_WITH", "Tag", topic)

        # People → MENTIONS
        for person in (people or [])[:6]:
            self._merge_node("Person", person)
            self._merge_rel("Memory", title, "MENTIONS", "Person", person)

        # Projects → PART_OF (explicit + auto-detected from title/summary)
        all_projects = set(projects or [])
        combined_text = (title + " " + summary).lower()
        for proj in KNOWN_PROJECTS:
            if proj.lower() in combined_text:
                all_projects.add(proj)

        for proj in list(all_projects)[:5]:
            self._merge_node("Project", proj)
            self._merge_rel("Memory", title, "PART_OF", "Project", proj)

        # Bump co-occurrence weights between paired topics
        for i, t1 in enumerate(clean_topics):
            for t2 in clean_topics[i + 1:]:
                s1, s2 = _escape(t1), _escape(t2)
                # Keep alphabetical order for dedup
                a, b = (s1, s2) if s1 < s2 else (s2, s1)
                self._q(
                    f"MATCH (ta:Tag {{name: '{a}'}}), (tb:Tag {{name: '{b}'}}) "
                    f"MERGE (ta)-[r:RELATED_TO]->(tb) "
                    f"ON CREATE SET r.weight = 1 "
                    f"ON MATCH SET r.weight = r.weight + 1"
                )

        log.debug("skgraph: Memory '%s' written (topics=%d people=%d projects=%d)",
                  title[:40], len(clean_topics), len(people or []), len(all_projects))
