package main

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

// placeholder is the dummy key value agents receive so SDKs don't reject missing-key checks.
// The proxy replaces it with the real credential before forwarding.
const placeholder = "proxy"

// RouteConfig is one entry in routes.json.
type RouteConfig struct {
	Prefix    string `json:"prefix"`
	Upstream  string `json:"upstream"`
	EnvVar    string `json:"envVar"`
	AuthStyle string `json:"authStyle"` // "bearer" | "token" | "x-api-key"
}

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

func tokenGet(r *http.Request) string { return tokenVal(r.Header.Get("Authorization")) }
func tokenSet(r *http.Request, k string) { r.Header.Set("Authorization", "token "+k) }

func xApiKeyGet(r *http.Request) string { return r.Header.Get("x-api-key") }
func xApiKeySet(r *http.Request, k string) { r.Header.Set("x-api-key", k) }

func authFuncs(style string) (func(*http.Request) string, func(*http.Request, string)) {
	switch style {
	case "bearer":
		return bearerGet, bearerSet
	case "token":
		return tokenGet, tokenSet
	case "x-api-key":
		return xApiKeyGet, xApiKeySet
	default:
		log.Fatalf("unknown authStyle %q", style)
		return nil, nil
	}
}

// loadRoutes reads routes.json from the same directory as the binary.
func loadRoutes() []route {
	exe, err := os.Executable()
	if err != nil {
		log.Fatalf("cannot locate executable: %v", err)
	}
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil {
		log.Fatalf("cannot resolve executable symlinks: %v", err)
	}
	routesFile := filepath.Join(filepath.Dir(exe), "routes.json")

	data, err := os.ReadFile(routesFile)
	if err != nil {
		log.Fatalf("cannot read %s: %v", routesFile, err)
	}

	var configs []RouteConfig
	if err := json.Unmarshal(data, &configs); err != nil {
		log.Fatalf("cannot parse %s: %v", routesFile, err)
	}

	routes := make([]route, 0, len(configs))
	for _, c := range configs {
		u, err := url.Parse(c.Upstream)
		if err != nil {
			log.Fatalf("bad upstream URL %q: %v", c.Upstream, err)
		}
		getAuth, setAuth := authFuncs(c.AuthStyle)
		routes = append(routes, route{
			prefix:   c.Prefix,
			upstream: u,
			envVar:   c.EnvVar,
			getAuth:  getAuth,
			setAuth:  setAuth,
		})
	}
	return routes
}

func mustURL(s string) *url.URL {
	u, err := url.Parse(s)
	if err != nil {
		log.Fatalf("bad URL %q: %v", s, err)
	}
	return u
}

func main() {
	routes := loadRoutes()
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
	// Plain HTTP is intentional: the Docker bridge network is the trust boundary.
	// All containers on pi_network are controlled by this compose file; TLS is out of scope.
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
