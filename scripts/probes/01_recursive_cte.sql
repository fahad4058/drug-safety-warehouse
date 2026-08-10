-- Probe 3: does this warehouse serve WITH RECURSIVE?
WITH RECURSIVE nums (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM nums WHERE n < 5
)
SELECT * FROM nums;
