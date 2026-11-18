CREATE TABLE "routine_streak_history" (
    "id" SERIAL NOT NULL,
    "routine_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "length" INTEGER NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "routine_streak_history_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "routine_streak_history_routine_id_start_date_key" ON "routine_streak_history"("routine_id", "start_date");

ALTER TABLE "routine_streak_history" ADD CONSTRAINT "routine_streak_history_routine_id_fkey" FOREIGN KEY ("routine_id") REFERENCES "routines"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "routine_streak_history" ADD CONSTRAINT "routine_streak_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
