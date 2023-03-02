[![CI](https://github.com/fabriziosestito/commanded-spear-adapter/actions/workflows/test.yml/badge.svg)](https://github.com/fabriziosestito/commanded-spear-adapter/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/commanded_spear_adapter.svg)](https://hex.pm/packages/commanded_spear_adapter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/commanded_spear_adapter/)

# Spear EventStoreDB adapter for Commanded

Commanded EvenstoreDB adapter based on [spear](https://github.com/NFIBrokerage/spear).
The code is based on [commanded-extreme-adapter](https://github.com/commanded/commanded-extreme-adapter).

---

[Hex package](https://hex.pm/packages/commanded_spear_adapter)

[Changelog](CHANGELOG.md)

---

## Getting started

The package can be installed from hex as follows.

1. Add `commanded_spear_adapter` to your list of dependencies in `mix.exs`:

   ```elixir
   def deps do
     [{:commanded_spear_adapter, "~> 0.1"}]
   end
   ```

2. Define and configure your Commanded application:

   ```elixir
   defmodule MyApp.Application do
     use Commanded.Application, otp_app: :my_app
   end
   ```

3. Configure the Commanded application to use the `Commanded.EventStore.Adapters.Spear` adapter and set the connection settings for the Event Store you are using:

   ```elixir
   # config/config.exs
   config :my_app, MyApp.Application,
     event_store: [
       adapter: Commanded.EventStore.Adapters.Spear,
       serializer: Commanded.Serialization.JsonSerializer,
       stream_prefix: "myapp",
       spear: [
         connection_string: "esdb://localhost:2113"
       ]
     ]
   ```

   Refer to the [Spear](https://hexdocs.pm/spear/) library documentation for details on the available connection settings.

   **Note:** Stream prefix _must not_ contain a dash character ("-").

### Use a serializer other than JSON

To serialize and deserialize events in formats other than JSON, you must specify the content-type of the event body.

```elixir
# config/config.exs
config :my_app, MyApp.Application,
  event_store: [
    adapter: Commanded.EventStore.Adapters.Spear,
    serializer: MyApp.MessagePackSerializer,
    content_type: "application/x-msgpack"
    ...
  ]
```

The `content_type` settings defaults to `application/json`.

### Running the Event Store

You **must** run the Event Store with all projections _enabled_ and standard projections _started_.

Use the `--run-projections=all --start-standard-projections=true` flags when running the Event Store executable.

### Credits

- [Ben Smith](https://github.com/slashdotdash/) for [commanded](https://github.com/commanded/commanded) and [commanded-extreme-adapter](https://github.com/commanded/commanded-extreme-adapter)
- [Michael Davis](https://github.com/the-mikedavis/) for [spear](https://github.com/NFIBrokerage/spear)
- [Fabrizio Sestito](https://github.com/fabriziosestito) hacking on this during [SUSE/openSUSE Hack Week 21](https://hackweek.opensuse.org/)
