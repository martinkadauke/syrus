# Register the running Rails process in instance_versions on boot
# (and start a heartbeat thread) IF this looks like a server process.
# server_process? gates on SYRUS_ROLE being explicitly set by the K8s
# manifest — local dev / rake / console / tests skip cleanly.
#
# `to_prepare` runs after the initial Rails load (and on every code
# reload in dev, which is a no-op for ensure_running since it's
# idempotent). This ordering ensures models + AR are fully booted
# before we try to write a row.
Rails.application.config.to_prepare do
  next unless SyrusVersion.server_process?

  InstanceVersionSupervisor.ensure_running
end
