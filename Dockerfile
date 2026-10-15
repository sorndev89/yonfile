# =========================================================================
# STAGE 1: Build Flutter Web Client (PWA + WebAssembly/Skwasm)
# =========================================================================
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /workspace/apps/web_client

# ກ໊ອບປີ້ pubspec ກ່ອນເພື່ອໃຊ້ Docker Cache ຕອນດຶງແພັກເກັດ
COPY apps/web_client/pubspec.* ./
RUN flutter pub get

# ກ໊ອບປີ້ໂຄ້ດ Flutter ທັງໝົດ ແລ້ວສັ່ງ Build Web Release
COPY apps/web_client/ ./
RUN flutter build web --release --wasm

# =========================================================================
# STAGE 2: Build Node.js Signaling Server (TypeScript -> JS)
# =========================================================================
FROM node:20-alpine AS node-builder

RUN corepack enable && corepack prepare pnpm@9.15.9 --activate
WORKDIR /workspace

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/server/package.json ./apps/server/

RUN pnpm install --frozen-lockfile

COPY apps/server/ ./apps/server/
RUN pnpm --filter @yonfile/server build

# =========================================================================
# STAGE 3: Production Image (ບາງ, ປອດໄພ ແລະ ໃຊ້ RAM ໜ້ອຍ)
# =========================================================================
FROM node:20-alpine AS production

RUN corepack enable && corepack prepare pnpm@9.15.9 --activate
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# ຕິດຕັ້ງສະເພາະ Production Dependencies
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/server/package.json ./apps/server/
RUN pnpm install --prod --frozen-lockfile

# ດຶງໄຟລ໌ Server ຈາກ Stage 2
COPY --from=node-builder /workspace/apps/server/dist ./apps/server/dist

# ດຶງໄຟລ໌ Flutter Web ຈາກ Stage 1
COPY --from=flutter-builder /workspace/apps/web_client/build/web ./apps/web_client/build/web

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/health || exit 1

CMD ["node", "apps/server/dist/index.js"]
