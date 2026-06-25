package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

// placeholder is the dummy key value agents receive so SDKs don't reject missing-key checks.
// The proxy replaces it with the real credential before forwarding.
const placeholder = "proxy"

type route struct {
	prefix   string
	upstream *url.URL
	envVar   string
	getAuth  func(*http.Request) string
	setAuth  func(*http.Request, string)
}

// tokenVal strips Bearer/token prefixes from Authorization header values.
func tokenVal(v string) string {
	for _, pfx := range []string{"Bearer ", "bearer ", "token ", "Token "} {
		if strings.HasPrefix(v, pfx) {
			return v[len(pfx):]
		}
	}
	return v
}

func bearerGet(r *http.Request) string { return tokenVal(r.Header.Get("Authorization")) }
func bearerSet(r *http.Request, k string) { r.Header.Set("Authorization", "Bearer "+k) }

var routes = []route{
	{
		prefix:   "/anthropic",
		upstream: mustURL("https://api.anthropic.com"),
		envVar:   "ANTHROPIC_API_KEY",
		getAuth:  func(r *http.Request) string { return r.Header.Get("x-api-key") },
		setAuth:  func(r *http.Request, k string) { r.Header.Set("x-api-key", k) },
	},
	{
		prefix:   "/openai",
		upstream: mustURL("https://api.openai.com"),
		envVar:   "OPENAI_API_KEY",
		getAuth:  bearerGet,
		setAuth:  bearerSet,
	},
	{
		prefix:   "/openrouter",
		upstream: mustURL("https://openrouter.ai"),
		envVar:   "OPENROUTER_API_KEY",
		getAuth:  bearerGet,
		setAuth:  bearerSet,
	},
	{
		prefix:   "/github",
		upstream: mustURL("https://api.github.com"),
		envVar:   "GITHUB_TOKEN",
		getAuth:  func(r *http.Request) string { return tokenVal(r.Header.Get("Authorization")) },
		setAuth:  func(r *http.Request, k string) { r.Header.Set("Authorization", "token "+k) },
	},
}

func mustURL(s string) *url.URL {
	u, err := url.Parse(s)
	if err != nil {
		log.Fatalf("bad URL %q: %v", s, err)
	}
	return u
}

func main() {
	mux := http.NewServeMux()

	for _, rt := range routes {
		rt := rt
		key := os.Getenv(rt.envVar)
		if key != "" {
			log.Printf("[proxy] %s/ → %s  (%s configured)", rt.prefix, rt.upstream.Host, rt.envVar)
		} else {
			log.Printf("[proxy] %s/ → %s  (no key – passthrough only)", rt.prefix, rt.upstream.Host)
		}

		rp := &httputil.ReverseProxy{
			Director: func(req *http.Request) {
				req.URL.Scheme = rt.upstream.Scheme
				req.URL.Host = rt.upstream.Host
				req.Host = rt.upstream.Host

				req.URL.Path = stripPrefix(req.URL.Path, rt.prefix)
				if req.URL.RawPath != "" {
					req.URL.RawPath = stripPrefix(req.URL.RawPath, rt.prefix)
				}

				// Only inject credential when the incoming value is the placeholder or absent.
				// Non-placeholder values (OAuth tokens, real keys) pass through untouched.
				if key != "" {
					if auth := rt.getAuth(req); auth == "" || auth == placeholder {
						rt.setAuth(req, key)
					}
				}
			},
		}

		mux.Handle(rt.prefix+"/", rp)
	}

	log.Println("[proxy] listening on :8080")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("[proxy] %v", err)
	}
}

func stripPrefix(path, prefix string) string {
	s := strings.TrimPrefix(path, prefix)
	if s == "" || s[0] != '/' {
		return "/" + s
	}
	return s
}
