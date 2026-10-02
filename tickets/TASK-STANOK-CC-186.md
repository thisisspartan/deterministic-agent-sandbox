# TASK-STANOK-CC-186: smoke binary-tree utilities

impl: src/smoke_tree.py
test: tests/smoke_tree_test.py
run.sh: exists

## Task

Implement small, pure binary-tree utilities in `src/smoke_tree.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_tree_test.py`.

A tree node is a dict `{'v': value, 'l': left, 'r': right}` where `l`
and `r` are either another node dict or `None`. An empty tree is
`None`.

Functions:

1. `tree_height(node) -> int` — height of the tree in nodes:
   `None` (empty) is `0`; a leaf is `1`; otherwise
   `1 + max(tree_height(l), tree_height(r))`.
   `tree_height(None) == 0`,
   `tree_height({'v': 1, 'l': None, 'r': None}) == 1`.
2. `inorder(node) -> list` — in-order traversal (left, node, right)
   returning the list of `v` values. `inorder(None) == []`.
   For a BST this yields the values sorted ascending.
3. `is_balanced(node) -> bool` — True iff for every node the heights of
   its left and right subtrees differ by at most 1. `None` and a leaf
   are balanced. Must run in O(n) (a single bottom-up pass, not
   recomputing heights per node).

## Requirements

- No network, no files, no global state.
- All functions are pure; input nodes are never mutated.
- `is_balanced` must be O(n): no repeated `tree_height` calls per node.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_tree_test.py` covers:
  - `tree_height`: `None` is 0; a leaf is 1; a 2-level tree is 2;
    a skewed 4-node chain is 4; a symmetric 3-level tree is 3.
  - `inorder`: `None` is `[]`; a single node; a small BST where the
    result equals the sorted values; a non-BST shape where the result
    follows left-node-right order (not sorted).
  - `is_balanced`: `None` and a leaf are True; a full 3-level tree is
    True; a skewed 4-node chain is False; a tree balanced at the root
    but unbalanced in a subtree is False (catches the naive
    root-only check).
  - depth safety: `is_balanced` on a 2000-node skewed chain returns
    `False` without raising `RecursionError` under Python's default
    recursion limit (1000) — a naive per-node recursive call stack
    cannot survive depth 2000, so the implementation must be iterative
    (explicit stack) or otherwise keep its call depth bounded; state
    the chosen approach in the module docstring.
