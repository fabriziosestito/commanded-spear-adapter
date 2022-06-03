defmodule Commanded.EventStore.Adapters.Extreme.Mapper do
  @moduledoc false

  alias Commanded.EventStore.RecordedEvent
  alias Extreme.Msg, as: ExMsg

  def to_recorded_event(%ExMsg.ResolvedIndexedEvent{event: event, link: nil}, serializer),
    do: to_recorded_event(event, event.event_number + 1, serializer)

  def to_recorded_event(%ExMsg.ResolvedIndexedEvent{event: event, link: link}, serializer),
    do: to_recorded_event(event, link.event_number + 1, serializer)

  def to_recorded_event(%ExMsg.ResolvedEvent{event: event, link: nil}, serializer),
    do: to_recorded_event(event, event.event_number + 1, serializer)

  def to_recorded_event(%ExMsg.ResolvedEvent{event: event, link: link}, serializer),
    do: to_recorded_event(event, link.event_number + 1, serializer)

  def to_recorded_event(%ExMsg.EventRecord{} = event, serializer),
    do: to_recorded_event(event, event.event_number + 1, serializer)

  def to_recorded_event(%ExMsg.EventRecord{} = event, event_number, serializer) do
    %ExMsg.EventRecord{
      event_id: event_id,
      event_type: event_type,
      event_number: stream_version,
      created_epoch: created_epoch,
      data: data,
      metadata: metadata
    } = event

    data = serializer.deserialize(data, type: event_type)

    metadata =
      case metadata do
        none when none in [nil, ""] -> %{}
        metadata -> serializer.deserialize(metadata, [])
      end

    {causation_id, metadata} = Map.pop(metadata, "$causationId")
    {correlation_id, metadata} = Map.pop(metadata, "$correlationId")

    %RecordedEvent{
      event_id: UUID.binary_to_string!(event_id),
      event_number: event_number,
      stream_id: to_stream_id(event),
      stream_version: stream_version + 1,
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: event_type,
      data: data,
      metadata: metadata,
      created_at: to_date_time(created_epoch)
    }
  end

  defp to_stream_id(%ExMsg.EventRecord{event_stream_id: event_stream_id}) do
    event_stream_id
    |> String.split("-")
    |> Enum.drop(1)
    |> Enum.join("-")
  end

  defp to_date_time(millis_since_epoch) do
    DateTime.from_unix!(millis_since_epoch, :millisecond)
  end
end
