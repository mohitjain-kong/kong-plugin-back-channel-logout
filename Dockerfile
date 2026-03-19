FROM kong:latest

# Install LuaRocks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install LuaRocks
RUN apt-get update && apt-get install -y --no-install-recommends lua5.1 luarocks && rm -rf /var/lib/apt/lists/*

# Create plugin directory
RUN mkdir -p /opt/kong/plugins/back-channel-logout

# Copy plugin files
COPY . /opt/kong/plugins/back-channel-logout/

# Install dependencies using LuaRocks
RUN cd /opt/kong/plugins/back-channel-logout && \
    luarocks make

# Update Kong configuration
RUN echo "plugins = bundled,back-channel-logout" >> /usr/local/kong/kong.conf.default

# Add custom environment variables (optional, adjust to your plugin's needs)
ENV KONG_BACK_CHANNEL_LOGOUT_JWKS_URL=http://example.com/jwks
ENV KONG_BACK_CHANNEL_LOGOUT_CREDENTIAL_CLAIM=sub
ENV KONG_BACK_CHANNEL_LOGOUT_REDIS_HOST=redis
ENV KONG_BACK_CHANNEL_LOGOUT_REDIS_PORT=6379
ENV KONG_BACK_CHANNEL_LOGOUT_SESSION_PREFIX=kong-session
ENV KONG_BACK_CHANNEL_LOGOUT_COOKIE_NAME=kong_session

# Expose Kong Admin API and Proxy ports
EXPOSE 8000
EXPOSE 8001

# Healthcheck (adjust as needed)
HEALTHCHECK --interval=5s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8001 || exit 1

# Command to start Kong
CMD ["kong", "start"]