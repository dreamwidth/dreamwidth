# Dreamwidth Plack Implementation

This document describes the Plack-based web server implementation for Dreamwidth, including architecture, components, and testing strategy.

## Overview

Dreamwidth is transitioning from Apache/mod_perl to a modern Plack-based architecture. This provides better deployment flexibility, improved performance characteristics, and easier development workflows.

## Architecture

### Core Components

#### app.psgi
The main PSGI application entry point located at `/app.psgi`. This file:
- Sets up the Plack middleware stack
- Handles request routing and dispatch
- Configures environment-specific settings
- Manages the request/response lifecycle

Key features:
- Uses `Plack::Builder` for middleware composition
- Distinguishes between API routes (`/api/v\d+/`) and other content
- Supports development mode configuration via `$LJ::IS_DEV_SERVER`
- Implements method filtering (GET, POST, PUT, DELETE, HEAD, OPTIONS)

#### DW::Request::Plack
Located at `/cgi-bin/DW/Request/Plack.pm`, this module provides:
- Abstraction layer over Plack's request/response model
- Compatibility with existing Dreamwidth request handling
- Pass-through methods to underlying `Plack::Request` and `Plack::Response` objects
- Integration with the `DW::Request` system

Key methods:
- `new($plack_env)` - Creates request object from PSGI environment
- `method()`, `uri()`, `path()`, `host()` - Request information
- `header_in()`, `header_out()` - Header management
- `status()`, `print()` - Response handling
- `res()` - Returns finalized PSGI response

### Middleware Stack

The middleware is applied in a specific order (important for proper functionality):

1. **Plack::Middleware::Options** - Handles OPTIONS requests and method filtering
2. **DW::RequestWrapper** - Manages request lifecycle, sets up DW::Request object
3. **DW::Redirects** - Domain redirect management and redirect.dat handling
4. **DW::Dev** - Development-specific middleware (only in dev mode)
5. **DW::XForwardedFor** - Extracts real client IP from proxy headers

#### Middleware Descriptions

**DW::RequestWrapper** (`/cgi-bin/Plack/Middleware/DW/RequestWrapper.pm`)
- Calls `LJ::start_request()` and `LJ::end_request()`
- Creates `DW::Request::Plack` object
- Handles process notification checks
- Wraps the entire request lifecycle

**DW::Redirects** (`/cgi-bin/Plack/Middleware/DW/Redirects.pm`)
- Ensures users land on correct domain
- Will implement redirect.dat functionality
- Handles canonical domain redirects

**DW::Dev** (`/cgi-bin/Plack/Middleware/DW/Dev.pm`)
- Development-specific functionality
- Only enabled when `$LJ::IS_DEV_SERVER` is set

**DW::XForwardedFor** (`/cgi-bin/Plack/Middleware/DW/XForwardedFor.pm`)
- Processes X-Forwarded-For headers
- Sets real client IP address
- Important for proxy deployments

## Routing

Currently, routing is handled in two ways:

1. **API Routes** (`/api/v\d+/`): Dispatched to `DW::Routing->call()`
2. **Other Routes**: Currently not implemented in the PSGI app (TODO)

The routing logic in `app.psgi` is deliberately simple and will be expanded as the migration continues.

## Configuration

### Environment Variables
- `LJHOME` - Path to Dreamwidth installation
- `LJ_IS_DEV_SERVER` - Enables development mode

### Development Mode
When `$LJ::IS_DEV_SERVER` is enabled:
- Warnings are enabled (`$^W = 1`)
- Development middleware is loaded
- Additional debugging features are available

## Testing Strategy

### Test Files

#### t/plack-app.t
Core functionality test that validates:
- Module loading (`DW::Request::Plack`, `DW::Routing`)
- `app.psgi` compilation and basic structure
- Request object creation and methods
- Response handling
- API routing detection
- Middleware availability

**Key Tests:**
- Request method, path, and host extraction
- Response status and header setting
- API vs non-API route detection
- PSGI environment handling

#### t/plack-integration.t
End-to-end integration test that would validate:
- Full middleware stack operation
- Request/response cycle through actual app
- Error handling
- HTTP method restrictions

**Note:** This test currently skips in most environments since it requires full application initialization.

#### t/plack-middleware.t
Component-level test for middleware:
- Individual middleware module loading
- Middleware instantiation
- Proper inheritance verification

### Testing Patterns

1. **Mocking Dependencies**: Tests mock `LJ::*` functions and other dependencies that may not be available in test environments
2. **Graceful Degradation**: Tests skip appropriately when full app initialization isn't possible
3. **Component Isolation**: Tests focus on what can be tested in isolation rather than requiring full system setup

### Running Tests

```bash
# Run all Plack tests
perl -Ilib t/plack-*.t

# Run individual tests
perl -Ilib t/plack-app.t
perl -Ilib t/plack-middleware.t
perl -Ilib t/plack-integration.t
```

## Development Workflow

### Adding New Middleware

1. Create middleware in `/cgi-bin/Plack/Middleware/DW/`
2. Follow the pattern of existing middleware
3. Add to the middleware stack in `app.psgi` in appropriate order
4. Add tests to verify the middleware works
5. Update this documentation

### Testing Changes

1. Run the Plack test suite: `perl -Ilib t/plack-*.t`
2. Verify all tests pass
3. Test manually with a development server if possible
4. Consider integration testing with the full application

## TODO Items

The following items are marked as TODO in the codebase:

### app.psgi
- Language library configuration (currently commented out)
- Random initialization per-child in preforking mode
- Static content middleware (concat res)
- Unique cookie middleware
- User authentication middleware (with 'as=' parameter support for dev)
- Sysban blocking middleware
- Embedded journal content handling

### Middleware
- Complete redirect.dat implementation in DW::Redirects
- User authentication system integration
- Static asset serving
- Session management

### Routing
- Full migration from legacy routing systems to DW::Routing
- Controller-based architecture
- Non-API route handling

## Deployment Considerations

### Production Deployment
- Use a proper PSGI server (Starman, uWSGI, etc.)
- Configure reverse proxy (nginx) for static assets
- Set up proper logging and monitoring
- Configure middleware stack for production environment

### Development Deployment
- Can use `plackup` for simple development
- Enable development middleware
- Use file watching for auto-restart during development

## Migration Notes

This Plack implementation is part of a gradual migration from the legacy Apache/mod_perl architecture. The system is designed to:

1. **Coexist** with existing systems during transition
2. **Maintain compatibility** with existing DW::Request interfaces
3. **Provide gradual migration path** for different components
4. **Support both development and production** environments

As the migration continues, more functionality will be moved into the Plack application and additional middleware will be implemented.

## References

- [PSGI Specification](https://metacpan.org/pod/PSGI)
- [Plack Documentation](https://metacpan.org/pod/Plack)
- [Plack::Builder](https://metacpan.org/pod/Plack::Builder)
- [Plack::Middleware](https://metacpan.org/pod/Plack::Middleware)
