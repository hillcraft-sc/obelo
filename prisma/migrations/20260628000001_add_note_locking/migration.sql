-- AlterTable
ALTER TABLE "notes" ADD COLUMN "locked" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "notes" ADD COLUMN "locked_content" TEXT;
ALTER TABLE "notes" ADD COLUMN "lock_salt" TEXT;
