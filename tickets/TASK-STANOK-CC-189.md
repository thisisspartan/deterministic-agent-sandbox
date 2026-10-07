# TASK-STANOK-CC-189: smoke pair statistics

impl: src/smoke_pairs.py
test: tests/smoke_pairs_test.py
run.sh: exists

## Task

Implement a small, pure pair-statistics utility in `src/smoke_pairs.py`
(pure stdlib, no third-party imports) and cover it with pytest in
`tests/smoke_pairs_test.py`.

A "pair" is always a pair of DISTINCT INDICES `(i, j)` with `i < j`;
equal VALUES at different indices count as separate elements.

Functions:

1. `count_pairs_with_sum(nums: list[int], target: int) -> int`
   — the number of index pairs `(i, j)`, `i < j`, with
   `nums[i] + nums[j] == target`.
   `count_pairs_with_sum([1, 5, 3, 7, 2], 8) == 2`  (1+7, 5+3)
   `count_pairs_with_sum([1, 1, 1], 2) == 3`
   `count_pairs_with_sum([0, 0, 0], 0) == 3`
   `count_pairs_with_sum([-1, 1, -1, 1], 0) == 4`
   `count_pairs_with_sum([], 0) == 0`
   `count_pairs_with_sum([5], 10) == 0`
2. `two_sum_first(nums: list[int], target: int) -> tuple[int, int] | None`
   — the lexicographically smallest pair `(i, j)`, `i < j`, with
   `nums[i] + nums[j] == target` (smallest `i`, then smallest `j`);
   `None` when no pair exists.
   `two_sum_first([1, 5, 3, 7, 2], 8) == (0, 3)`
   `two_sum_first([3, 1, 5, 7], 8) == (0, 3)`  (3+5; 1+7 is later)
   `two_sum_first([5, 3, 1, 7], 8) == (0, 1)`
   `two_sum_first([1, 2], 5) is None`
   `two_sum_first([], 0) is None`
3. `max_pair_product(nums: list[int]) -> int | None`
   — the maximum product `nums[i] * nums[j]` over all index pairs
   `i < j`; `None` when the list has fewer than 2 elements.
   Two negative values can beat two positives.
   `max_pair_product([3, -1, 4, 0]) == 12`
   `max_pair_product([-5, -2, 3]) == 15`
   `max_pair_product([-1, -2]) == 2`
   `max_pair_product([7]) is None`
   `max_pair_product([]) is None`

## Requirements

- No network, no files, no global state.
- All functions are pure; no mutation of inputs.
- Negative values are valid everywhere.
- Duplicates are distinct elements (index-based counting).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_pairs_test.py` covers:
  - `count_pairs_with_sum`: all six vectors above; a no-match target
    returns 0; a large list (e.g. 200 elements) is counted correctly
    against a brute-force reference computed in the test.
  - `two_sum_first`: all five vectors above; a pair where the smallest
    `i` has several matching `j` returns the smallest `j`.
  - `max_pair_product`: all five vectors above; an all-negative list
    `[-4, -3, -1]` returns 12 (the two largest-magnitude negatives);
    a two-element list returns the product of its elements.
