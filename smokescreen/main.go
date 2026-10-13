// Command smokescreen wraps Stripe's smokescreen forward proxy for use as
// the base image's default egress proxy. It is built from source and
// pinned to an exact upstream commit via go.mod/go.sum -- see AGENTS.md
// and the Dockerfile's builder-smokescreen stage for the integrity story
// (no upstream binary releases exist to pin against instead).
package main

import (
	"context"
	"encoding/base64"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/stripe/goproxy"
	"github.com/stripe/smokescreen/cmd"
	"github.com/stripe/smokescreen/pkg/smokescreen"
)

func main() {
	conf, err := cmd.NewConfiguration(nil, nil)
	if err != nil {
		logrus.Fatalf("configuration error: %v", err)
	}
	if conf == nil {
		return // --help or --version was requested and already handled
	}

	// No RoleFromRequest and no egress ACL: every caller is treated as
	// anonymous and unrestricted. Smokescreen's own default range
	// blocking (private/loopback/link-local/CGNAT) still applies
	// regardless of ACL configuration.
	conf.AllowMissingRole = true

	// smokescreen.NewConfig() sets a JSON formatter on logrus's global
	// standard logger, but conf.Log (what every CANONICAL-PROXY-DECISION
	// line actually uses) is a separate *logrus.Logger left on the default
	// text formatter. Set it explicitly so all output is JSON.
	conf.Log.Formatter = &logrus.JSONFormatter{}

	// Upstream proxy from 42-http-proxy.sh, via the supervisor program
	// env rather than --upstream-*-proxy-addr: the URL may hold
	// credentials and argv is world-readable.
	httpUp := allowUpstream(conf, os.Getenv("SMOKESCREEN_UPSTREAM_HTTP_PROXY"))
	httpsUp := allowUpstream(conf, os.Getenv("SMOKESCREEN_UPSTREAM_HTTPS_PROXY"))
	if httpUp != nil {
		conf.UpstreamHttpProxyAddr = httpUp.String()
	}
	if httpsUp != nil {
		conf.UpstreamHttpsProxyAddr = httpsUp.String()
		if httpsUp.User != nil {
			conf.UpstreamProxyConnectReqHandler = connectAuth(httpsUp.User)
		}
	}

	smokescreen.StartWithConfig(conf, nil)
}

// allowUpstream allow-lists the upstream's ip:port(s), otherwise
// smokescreen's private-range blocking denies the dial to e.g. a
// 192.168.x.x upstream. Fatal if it doesn't resolve, so supervisor retries.
func allowUpstream(conf *smokescreen.Config, raw string) *url.URL {
	if raw == "" {
		return nil
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" {
		conf.Log.Warn("ignoring upstream proxy: not an http(s) proxy URL")
		return nil
	}
	port := u.Port()
	if port == "" {
		port = "80"
		if u.Scheme == "https" {
			port = "443"
		}
		u.Host = net.JoinHostPort(u.Hostname(), port)
	}
	// Scheme and host only: the userinfo may itself be the secret.
	log := conf.Log.WithFields(logrus.Fields{
		"upstream":        u.Scheme + "://" + u.Host,
		"has_credentials": u.User != nil,
	})

	// Bounded so a slow resolver can't hold up smokescreen's listener.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	// Same resolver smokescreen dials with (honours resolver_addresses).
	ips, err := conf.Resolver.LookupIP(ctx, "ip", u.Hostname())
	if err != nil {
		log.WithError(err).Fatal("could not resolve upstream proxy")
	}

	allow := make([]string, 0, len(ips))
	for _, ip := range ips {
		if ip.IsLoopback() && port == strconv.Itoa(int(conf.Port)) {
			log.Warn("ignoring upstream proxy: it is smokescreen itself")
			return nil
		}
		allow = append(allow, net.JoinHostPort(ip.String(), port))
	}
	if err := conf.SetAllowAddresses(allow); err != nil {
		log.WithError(err).Fatal("invalid upstream allow-address")
	}

	log.WithField("allow_addresses", allow).Info("upstream proxy configured")
	return u
}

// connectAuth rebuilds the CONNECT Proxy-Authorization from the decoded
// userinfo: goproxy encodes the still-percent-escaped form, so passwords
// with reserved characters (@ : %) would fail upstream auth. Requests where
// the client chose its own upstream (X-Upstream-Https-Proxy) are left
// alone so our credentials only ever go to our upstream. Drop this once
// goproxy builds the header from the decoded Username()/Password().
func connectAuth(user *url.Userinfo) func(*goproxy.ProxyCtx, *http.Request) error {
	password, _ := user.Password()
	header := "Basic " + base64.StdEncoding.EncodeToString([]byte(user.Username()+":"+password))
	return func(ctx *goproxy.ProxyCtx, req *http.Request) error {
		if ctx.Req != nil && ctx.Req.Header.Get(goproxy.PerRequestHTTPSProxyHeaderKey) != "" {
			return nil
		}
		req.Header.Set("Proxy-Authorization", header)
		return nil
	}
}
