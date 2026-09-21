// Command smokescreen wraps Stripe's smokescreen forward proxy for use as
// the base image's default egress proxy. It is built from source and
// pinned to an exact upstream commit via go.mod/go.sum -- see AGENTS.md
// and the Dockerfile's builder-smokescreen stage for the integrity story
// (no upstream binary releases exist to pin against instead).
package main

import (
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

	smokescreen.StartWithConfig(conf, nil)
}
