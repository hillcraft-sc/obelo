ALTER TABLE "list_items" ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0;

UPDATE "list_items" li
SET position = sub.rn - 1
FROM (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY list_id ORDER BY created_at ASC) - 1 AS rn
  FROM list_items
) sub
WHERE li.id = sub.id;
