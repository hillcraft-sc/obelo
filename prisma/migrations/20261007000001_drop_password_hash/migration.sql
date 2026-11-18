-- Sign-in is SSO only since 3.16.0; nothing reads stored password hashes any more
ALTER TABLE "users" DROP COLUMN "password_hash";
