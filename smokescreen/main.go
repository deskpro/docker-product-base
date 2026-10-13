// Command smokescreen wraps Stripe's smokescreen forward proxy for use as
// the base image's default egress proxy. It is built from source and
// pinned to an exact upstream commit via go.mod/go.sum -- see AGENTS.md
// and the Dockerfile's builder-smokescreen stage for the integrity story
// (no upstream binary releases exist to pin against instead).
package main

import (
	"context"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
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
	httpUp := os.Getenv("SMOKESCREEN_UPSTREAM_HTTP_PROXY")
	httpsUp := os.Getenv("SMOKESCREEN_UPSTREAM_HTTPS_PROXY")
	conf.UpstreamHttpProxyAddr = allowUpstream(conf, httpUp)
	if httpsUp == httpUp {
		conf.UpstreamHttpsProxyAddr = conf.UpstreamHttpProxyAddr
	} else {
		conf.UpstreamHttpsProxyAddr = allowUpstream(conf, httpsUp)
	}

	smokescreen.StartWithConfig(conf, nil)
}

// allowUpstream allow-lists the upstream proxy's address(es), otherwise
// smokescreen's default private-range blocking denies the dial to e.g. a
// 192.168.x.x upstream, and returns raw. Unusable values (unparseable,
// SOCKS, smokescreen itself) are skipped and "" is returned.
func allowUpstream(conf *smokescreen.Config, raw string) string {
	if raw == "" {
		return ""
	}
	withScheme := raw
	if !strings.Contains(raw, "://") {
		withScheme = "http://" + raw
	}
	u, err := url.Parse(withScheme)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		conf.Log.Warn("ignoring upstream proxy: not an http(s) proxy URL")
		return ""
	}
	log := conf.Log.WithField("upstream", u.Redacted())

	// Bounded so a slow resolver can't hold up smokescreen's listener.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	ips, err := net.DefaultResolver.LookupIP(ctx, "ip", u.Hostname())
	if err != nil {
		log.WithError(err).Warn("could not resolve upstream proxy; using it without an allow-address")
	}

	allow := make([]string, 0, len(ips))
	for _, ip := range ips {
		if ip.IsLoopback() && u.Port() == strconv.Itoa(int(conf.Port)) {
			log.Warn("ignoring upstream proxy: it is smokescreen itself")
			return ""
		}
		addr := ip.String()
		if u.Port() != "" {
			addr = net.JoinHostPort(addr, u.Port())
		}
		allow = append(allow, addr)
	}
	if err := conf.SetAllowAddresses(allow); err != nil {
		log.WithError(err).Fatal("invalid upstream allow-address")
	}

	log.WithField("allow_addresses", allow).Info("upstream proxy configured")
	return raw
}
