ALTER TABLE "notes" ADD COLUMN "has_drawing" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "notes" ADD COLUMN "drawing_data" TEXT;
