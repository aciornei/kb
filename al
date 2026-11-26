sum by (vm) (
  label_replace(
    redis_up{
      job="redis_exporter_targets",
      instance_role="master"
    },
    "vm", "$1", "instance",
    "redis://([^:]+):[0-9]+"
  )
)
