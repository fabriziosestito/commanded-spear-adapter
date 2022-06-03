# Testing

The test suite uses Docker to run the official [Event Store](https://store.docker.com/community/images/eventstore/eventstore) container. You must start the container _before_ running the test suite.

### Getting started

Build

```
docker-compose build
```

Start the container using:

```
docker-compose up -d
```

### Web UI

Get the docker ip address:

```
docker-machine ip default
```

Using the ip address and the external http port (defaults to 2113) you can use the browser to view the event store admin UI.

e.g. http://localhost:2113/

### Running the tests

Use `mix test` to run the test suite.
