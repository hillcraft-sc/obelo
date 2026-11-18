-- AlterTable: add calendarName and localCalendarId to calendar_events
ALTER TABLE "calendar_events" ADD COLUMN "calendar_name" TEXT;
ALTER TABLE "calendar_events" ADD COLUMN "local_calendar_id" INTEGER;

-- CreateTable: local_calendars
CREATE TABLE "local_calendars" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "color" TEXT NOT NULL DEFAULT '#6366f1',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "local_calendars_pkey" PRIMARY KEY ("id")
);

-- CreateTable: local_calendar_members
CREATE TABLE "local_calendar_members" (
    "id" SERIAL NOT NULL,
    "calendar_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "can_edit" BOOLEAN NOT NULL DEFAULT true,
    "added_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "local_calendar_members_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "local_calendar_members_calendar_id_user_id_key" ON "local_calendar_members"("calendar_id", "user_id");

-- AddForeignKey: calendar_events -> local_calendars (SetNull on delete)
ALTER TABLE "calendar_events" ADD CONSTRAINT "calendar_events_local_calendar_id_fkey" FOREIGN KEY ("local_calendar_id") REFERENCES "local_calendars"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey: local_calendars -> users
ALTER TABLE "local_calendars" ADD CONSTRAINT "local_calendars_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: local_calendar_members -> local_calendars
ALTER TABLE "local_calendar_members" ADD CONSTRAINT "local_calendar_members_calendar_id_fkey" FOREIGN KEY ("calendar_id") REFERENCES "local_calendars"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: local_calendar_members -> users
ALTER TABLE "local_calendar_members" ADD CONSTRAINT "local_calendar_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
