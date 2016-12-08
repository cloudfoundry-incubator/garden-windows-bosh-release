# Cloud Foundry Garden Windows [BOSH release] [![slack.cloudfoundry.org](https://slack.cloudfoundry.org/badge.svg)](https://slack.cloudfoundry.org)

----
This repo is a [BOSH](https://github.com/cloudfoundry/bosh) release for
deploying [Garden Windows](https://github.com/cloudfoundry/garden-windows) and associated tasks.

This release relies on a separate deployment to provide:

- [rep](https://github.com/cloudfoundry/rep). In practice this comes from [diego-release](https://github.com/cloudfoundry/diego-release).
- [metron](https://github.com/cloudfoundry/loggregator/tree/develop/jobs/metron_agent_windows). In practice this comes from [loggregator-release](https://github.com/cloudfoundry/loggregator).
- [consul](https://github.com/cloudfoundry-incubator/consul-release/tree/master/jobs/consul_agent_windows). In practice this comes from [consul-release](https://github.com/cloudfoundry-incubator/consul-release).
