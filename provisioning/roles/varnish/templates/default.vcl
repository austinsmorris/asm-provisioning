#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and http://varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

# Default backend definition.  Set this to point to your content server.
backend default {
    .host = "10.0.2.2";
    .port = "80";
    .connect_timeout = 60s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 60s;
    .max_connections = 800;
}

acl purge {
    # List of hosts that are allowed to purge cache
    "10.0.2.2";
    "localhost";
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.

    # Set X-Forwarded-For header for logging in nginx
    unset req.http.X-Forwarded-For;
    set req.http.X-Forwarded-For = client.ip;

    # Remove has_js and CloudFlare/Google Analytics __* cookies and statcounter is_unique
    set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js|is_unique)=[^;]*", "");

    # Remove a ";" prefix, if present.
    set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

    # Either the admin pages or the login
    if (req.url ~ "/wp-(login|admin|cron)") {
        # Don't cache, pass to backend
        return (pass);
    }

    # Remove the wp-settings-1 cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-1=[^;]+(; )?", "");

    # Remove the wp-settings-time-1 cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-time-1=[^;]+(; )?", "");

    # Remove the wp test cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wordpress_test_cookie=[^;]+(;)?", "");

    # Static content unique to the theme can be cached (so no user uploaded images)
    # The reason I don't take the wp-content/uploads is because of cache size on bigger blogs
    # that would fill up with all those files getting pushed into cache
    if (req.url ~ "wp-content/themes/" && req.url ~ "\.(css|js|png|gif|jp(e)?g)") {
        unset req.http.cookie;
    }

    # Even if no cookies are present, I don't want my "uploads" to be cached due to their potential size
    if (req.url ~ "/wp-content/uploads/") {
        return (pass);
    }

    # any pages with captchas need to be excluded
    if (req.url ~ "^/contact/" || req.url ~ "^/links/domains-for-sale/") {
        return(pass);
    }

    # Check the cookies for wordpress-specific items
    if (req.http.Cookie ~ "wordpress_" || req.http.Cookie ~ "comment_") {
        # A wordpress specific cookie has been set
        return (pass);
    }

    # allow PURGE from localhost
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed"));
        }

        return (purge);
    }

    # Force lookup if the request is a no-cache request from the client
    if (req.http.Cache-Control ~ "no-cache") {
        return (pass);
    }

    # Try a cache-lookup
    return (hash);
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

    #if (beresp.ttl < 120s) {
    #    set beresp.ttl = 120s;
    #}

    #set obj.grace = 5m;
    set beresp.grace = 2m;
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.
}
