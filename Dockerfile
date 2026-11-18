FROM node:22-alpine

WORKDIR /app

# OpenSSL required by Prisma on Alpine
RUN apk add --no-cache openssl

# Install dependencies
# --mount=type=cache keeps npm's download cache across builds so
# subsequent rebuilds skip re-downloading unchanged packages.
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Generate Prisma client
COPY prisma ./prisma
RUN npx prisma generate

# Copy application source
COPY src ./src
COPY public ./public
COPY scripts ./scripts

# Non-root user. /app/uploads is the volume mount point; creating it here owned by
# the app user makes Docker give a fresh (empty) volume the same ownership.
RUN addgroup -g 1001 -S nodejs && adduser -S obelo -u 1001 -G nodejs
RUN mkdir -p /app/uploads && chown -R obelo:nodejs /app
USER obelo

EXPOSE 3000

COPY docker-entrypoint.sh ./
CMD ["sh", "docker-entrypoint.sh"]
