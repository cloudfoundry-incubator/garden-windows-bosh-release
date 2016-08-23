# Work around for issue https://github.com/cloudfoundry/loggregator/issues/146
# This restarts metron_agent in case it failed to connect to etcd

Restart-Service -Name "metron_agent" -Force
