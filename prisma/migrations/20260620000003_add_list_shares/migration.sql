CREATE TABLE "list_shares" (
    "id" SERIAL NOT NULL,
    "list_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "list_shares_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "list_shares" ADD CONSTRAINT "list_shares_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "lists"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "list_shares" ADD CONSTRAINT "list_shares_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE UNIQUE INDEX "list_shares_list_id_user_id_key" ON "list_shares"("list_id", "user_id");
