# TASK-STANOK-CC-184: smoke graph utilities

impl: src/smoke_graph.py
test: tests/smoke_graph_test.py
run.sh: exists

## Task

Implement small, pure graph utilities in `src/smoke_graph.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_graph_test.py`.

Graphs are represented as adjacency structures: a dict mapping each node
to a list of neighbour nodes (e.g. `{'a': ['b', 'c'], 'b': ['c'], 'c': []}`).
Nodes are hashable; edges are directed unless stated otherwise.

Functions:

1. `bfs_shortest_path(adj, start, goal) -> list | None` — breadth-first
   search for a shortest path (fewest edges) from `start` to `goal` in a
   directed graph. Returns the path as a list of nodes including both
   endpoints, or `None` if `goal` is unreachable. `start == goal` returns
   `[start]`. Ties are broken deterministically: neighbours are explored
   in the order they appear in the adjacency list.
   `bfs_shortest_path({'a': ['b', 'c'], 'b': ['d'], 'c': ['d'], 'd': []}, 'a', 'd') == ['a', 'b', 'd']`.
   Raises `ValueError` if `start` or `goal` is not a key of `adj`.
2. `topological_order(adj) -> list` — Kahn's algorithm topological sort of
   a directed graph. Returns a list of all nodes such that for every edge
   `u -> v`, `u` appears before `v`. Deterministic: among all nodes with
   in-degree 0, always pick the smallest (by `<` comparison) next.
   Raises `ValueError` if the graph contains a cycle.
   `topological_order({'a': ['b'], 'b': ['c'], 'c': []}) == ['a', 'b', 'c']`.
3. `has_cycle(adj) -> bool` — detect whether a directed graph contains a
   cycle (a node reachable from itself via one or more edges). Uses
   iterative or recursive DFS with three-color marking; must not recurse
   deeper than the graph length (iterative preferred).
   `has_cycle({'a': ['b'], 'b': ['a']}) is True`,
   `has_cycle({'a': ['b'], 'b': []}) is False`.

## Requirements

- No network, no files, no global state.
- All functions are pure; no mutation of the input `adj`.
- All three functions accept the same dict-of-lists representation.
- `topological_order` and `has_cycle` must agree: `has_cycle(adj) is True`
  if and only if `topological_order(adj)` raises `ValueError`.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_graph_test.py` covers:
  - `bfs_shortest_path`: the example above; `start == goal`; unreachable
    goal returns `None`; a graph where the lexicographically-first neighbour
    leads to a longer path (verifies BFS picks fewest edges, not first
    found); missing `start` or `goal` key raises `ValueError`; empty graph
    with valid keys.
  - `topological_order`: the chain example; a diamond graph
    (`{'a': ['b', 'c'], 'b': ['d'], 'c': ['d'], 'd': []}`) where the
    deterministic smallest-first rule gives `['a', 'b', 'c', 'd']`;
    a disconnected graph; a two-node cycle raises `ValueError`;
    a self-loop (`{'a': ['a']}`) raises `ValueError`.
  - `has_cycle`: the two examples above; self-loop is `True`;
    a longer cycle `a -> b -> c -> a` is `True`; a DAG is `False`.
  - agreement property: for a set of small graphs (DAGs and cyclic ones),
    `has_cycle(adj) == (topological_order raises ValueError)`.
