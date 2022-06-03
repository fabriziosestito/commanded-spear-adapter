# Changelog

## v1.1.0

- Support Commanded v1.1.0 including new `prefix` event store option.

---

## v1.0.0

### Enhancements

- Support multiple Commanded apps ([#25](https://github.com/commanded/commanded-extreme-adapter/pull/25)).

---

## v0.8.0

### Enhancements

- Support for Commanded v0.19.

---

## v0.7.0

### Bug fixes

- Skip deleted events instead of crashing ([#22](https://github.com/commanded/commanded-extreme-adapter/pull/22)).

---

## v0.6.0

### Enhancements

- Support for Commanded v0.18.

---

## v0.5.0

### Enhancements

- Add support for transient Event Store subscriptions ([#9](https://github.com/commanded/commanded-extreme-adapter/pull/9)).
- Raise log level of wrong expected version ([#10](https://github.com/commanded/commanded-extreme-adapter/pull/10)).

### Bug fixes

- Supervisor for subscription processes ([#8](https://github.com/commanded/commanded-extreme-adapter/pull/8)).

---

## v0.4.0

### Enhancements

- Include `event_id` in recorded event data.

---

## v0.3.0

### Bug fixes

- Fix compilation error with Commanded v0.14.0 due to removal of `Commanded.EventStore.TypeProvider` macro, replaced with runtime config lookup ([#5](https://github.com/commanded/commanded-extreme-adapter/issues/5)).

---

## v0.2.0

### Enhancements

- Raise an exception if `:stream_prefix` configuration contains a dash character ("-") as this does not work with subscriptions ([#3](https://github.com/commanded/commanded-extreme-adapter/issues/3)).

---

## v0.1.0

- Initial release.
