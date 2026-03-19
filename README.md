# Kong Back-Channel Logout Plugin

This plugin implements the OpenID Connect Back-Channel Logout 1.0 specification for Kong Gateway. It allows an Identity Provider (IdP) to directly notify Kong when a user logs out, enabling immediate termination of user sessions.

## Purpose

Back-channel logout offers a server-to-server communication channel for logout events.  This is in contrast to front-channel logout which relies on browser redirects. The back-channel mechanism allows for more reliable and immediate session termination.

## How it Works

1.  **IdP Notification:** The IdP sends a `logout_token` (JWT) to a dedicated Kong route.
2.  **Token Validation:** The plugin validates the token's signature using the IdP's JWKS, checks for expiry, and extracts the user's subject identifier.
3.  **Session Lookup:** The plugin queries Redis to find all active sessions associated with the user's subject.
4.  **Session Termination:** The plugin deletes the user's session data from Redis, effectively logging the user out.

## Diagram

  Identity Provider                Kong Gateway                       Redis
      │                               │                               │
      │  POST /logout                 │                               │
      │  Content-Type:                │                               │
      │  application/x-www-          │                               │
      │  form-urlencoded             │                               │
      │  logout_token=<JWT>          │                               │
      │──────────────────────────────►│                               │
      │                               │                               │
      │                               │  1. Parse logout_token        │
      │                               │  2. Fetch JWKS from IdP URL   │
      │                               │  3. Verify JWT signature      │
      │                               │  4. Check exp claim           │
      │                               │  5. Extract subject claim     │
      │                               │                               │
      │                               │  ZRANGE anchor_key 0 -1       │
      │                               │──────────────────────────────►│
      │                               │  [session_key_1, key_2, ...]  │
      │                               │◄──────────────────────────────│
      │                               │                               │
      │                               │  DEL session:cookie:key_1     │
      │                               │  DEL session:cookie:key_2     │
      │                               │  DEL anchor_key               │
      │                               │──────────────────────────────►│
      │                               │  OK                           │
      │                               │◄──────────────────────────────│
      │                               │                               │
      │  HTTP 200 { success: true }   │                               │
      │◄──────────────────────────────│                               │

## Installation

1.  Clone the repository into your Kong plugin directory.
2.  Install dependencies using `luarocks`:

    ```bash
    luarocks install lua-resty-jwt
    luarocks install redis
    

3.  Add the plugin to the `plugins` section of your `kong.conf` file:

    
    plugins = bundled,back-channel-logout
    

4.  Restart Kong.

## Configuration

| Field               | Type   | Required | Default | Description                                                                                                                  |
| ------------------- | ------ | -------- | ------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `jwks_url`          | string | Yes      |         | The URL of the IdP's JWKS (JSON Web Key Set) endpoint.                                                                       |
| `credential_claim`  | string | Yes      | `sub`   | The JWT claim that contains the user's unique identifier (subject).                                                           |
| `redis_host`        | string | Yes      |         | The hostname or IP address of the Redis server.                                                                               |
| `redis_port`        | number | No       | `6379`  | The port number of the Redis server.                                                                                           |
| `redis_password`    | string | No       |         | The password for the Redis server (if required).                                                                              |
| `redis_prefix`      | string | No       | `kong`  | Prefix for Redis keys. Should match the prefix used by your session plugin.                                                |
| `redis_cookie_name` | string | No       | `kong_session` |  The name of the cookie used for session management.  Should match the cookie name used by your session plugin.                                            |
| `redis_timeout`     | number | No       | `2000`  | Redis connection timeout in milliseconds                                                                                      |
| `accepted_alg`      | array  | No       | `[RS256, RS384, RS512]`   | Array of accepted JWA algorithm identifiers. Must be supported by `lua-resty-jwt`. |

### Example Configuration

{
  "name": "back-channel-logout",
  "service": { "id": "<your-service-id>" },
  "route": { "id": "<your-route-id>" },
  "config": {
    "jwks_url": "https://your-idp.com/jwks",
    "credential_claim": "sub",
    "redis_host": "redis.example.com",
    "redis_port": 6379,
    "redis_prefix": "my_app",
    "redis_cookie_name": "my_session"
  }
}

## Usage

1.  **Configure a Route:** Create a Kong route that will receive the logout tokens from your IdP.  Ensure that this route is *only* accessible from your IdP to prevent unauthorized session termination.  It is recommended to configure mutual TLS authentication on this route.
2.  **Enable the Plugin:** Enable the `back-channel-logout` plugin on the route, providing the necessary configuration values.
3.  **Configure your IdP:** Configure your IdP to send `POST` requests with the `logout_token` parameter to the Kong route. The content type must be `application/x-www-form-urlencoded`.

## Example Request from IdP

POST /logout HTTP/1.1
Content-Type: application/x-www-form-urlencoded

logout_token=eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS1pZCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.signature

## Response

On successful logout, the plugin returns a `200 OK` status code with a JSON body:

{
  "success": true,
  "sessions_terminated": [
    "session:cookie:key_1",
    "session:cookie:key_2"
  ],
  "subject": "1234567890"
}

On failure, the plugin returns an appropriate HTTP error code (e.g., 400, 500, 503) with an error message in the response body.

## Error Handling

The plugin handles the following error conditions:

*   **400 Bad Request:**
    *   `logout_token` parameter is missing or empty.
    *   `credential_claim` is missing in the JWT.
*   **500 Internal Server Error:**
    *   Failed to fetch JWKS from the IdP.
    *   No usable keys found in the JWKS.
    *   JWT verification failed.
    *   JWT `exp` claim is invalid.
*   **503 Service Unavailable:**
    *   Failed to connect to Redis.

## Dependencies

*   [lua-resty-jwt](https://github.com/zmartzone/lua-resty-jwt)
*   [lua-resty-redis](https://github.com/openresty/lua-resty-redis)

## Notes

*   Ensure the Kong route is secured (e.g., with mTLS) to prevent unauthorized access.
*   The `redis_prefix` and `redis_cookie_name` must match the configuration used by your session management plugin. If you're using Kong's built-in session plugin, the defaults should work.
*   The `credential_claim` must match the claim used by your IdP to identify users.
*   Monitor the Kong logs for any errors during the logout process.