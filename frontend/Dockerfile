# Stage 1: Build React app
FROM node:18-alpine AS builder

WORKDIR /app


COPY package*.json ./
RUN npm install


COPY . .

ENV NODE_OPTIONS=--openssl-legacy-provider

RUN npm run build

# Stage 2: 
FROM nginx:stable-alpine

RUN rm -rf /usr/share/nginx/html/*

# Copy built files from builder
COPY --from=builder /app/build /usr/share/nginx/html


EXPOSE 80


CMD ["nginx", "-g", "daemon off;"]
