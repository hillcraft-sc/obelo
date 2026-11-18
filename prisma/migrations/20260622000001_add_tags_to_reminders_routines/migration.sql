-- Add tags column to reminders
ALTER TABLE "reminders" ADD COLUMN "tags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

-- Add tags column to routines
ALTER TABLE "routines" ADD COLUMN "tags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
