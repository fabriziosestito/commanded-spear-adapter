# Testing

The test suite uses Docker to run the official [Event Store](https://store.docker.com/community/images/eventstore/eventstore) container. You must pull the docker image and start the container *before* running the test suite.

### Getting started

Pull the docker image:

```
docker pull eventstore/eventstore
```

Run the container using:

```
docker run --rm --name eventstore -it -p 2113:2113 -p 1113:1113 \
  -e EVENTSTORE_CLUSTER_SIZE=1 \
  -e EVENTSTORE_RUN_PROJECTIONS=All \
  -e EVENTSTORE_START_STANDARD_PROJECTIONS=True \
  -e EVENTSTORE_INSECURE=True \
  -e EVENTSTORE_ENABLE_EXTERNAL_TCP=True \
  -e EVENTSTORE_ENABLE_ATOM_PUB_OVER_HTTP=True \
  eventstore/eventstore:latest
```

Note: The admin UI and atom feeds will only work if you publish the node's http port to a matching port on the host. (i.e. you need to run the container with -p 2113:2113).

### Web UI

Get the docker ip address:

```
docker-machine ip default
```

Using the ip address and the external http port (defaults to 2113) you can use the browser to view the event store admin UI.

e.g. http://localhost:2113/

Username and password is `admin` and `changeit` respectively.

### Running the tests

Use `mix test` to run the test suite.
