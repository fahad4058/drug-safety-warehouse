SELECT
  count(*)                          AS descriptor_rows,
  count(DISTINCT descriptor_ui)     AS distinct_descriptors,
  count(DISTINCT _pulled_at)        AS distinct_pulls,
  sum(size(tree_numbers))           AS tree_numbers_total,
  count_if(tree_numbers IS NULL OR size(tree_numbers) = 0) AS no_tree_number,
  max(size(tree_numbers))           AS max_per_descriptor
FROM raw.landing.mesh_descriptors;

SELECT
  count(tree_number)              AS tree_numbers,
  count(DISTINCT tree_number)     AS distinct_tree_numbers
FROM raw.landing.mesh_descriptors
LATERAL VIEW explode(tree_numbers) t AS tree_number;
