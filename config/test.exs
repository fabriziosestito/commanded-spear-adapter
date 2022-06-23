import Mix.Config

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 5_000,
  refute_receive_timeout: 1_000,
  exclude: [:skip]

config :commanded,
  assert_receive_event_timeout: 5_000,
  refute_receive_event_timeout: 1_000

# config :logger,
#   level: :error
