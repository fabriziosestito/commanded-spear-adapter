defmodule Commanded.EventStore.Adapters.Spear.Mapper do
  @moduledoc false

  alias Commanded.EventStore.{
    EventData,
    RecordedEvent,
    SnapshotData,
    TypeProvider
  }

  alias Commanded.Serialization.JsonDecoder

  def to_spear_event(read_resp) do
    # HACK: dummy json decopder function to prevent automatic json decoding
    # see: https://hexdocs.pm/spear/Spear.Event.html#from_read_response/2-json-decoding

    Spear.Event.from_read_response(read_resp, json_decoder: fn data, _ -> data end)
  end

  def to_recorded_event(
        %Spear.Event{
          id: id,
          type: "$>" = type,
          metadata: %{
            commit_position: commit_position,
            stream_revision: stream_revision,
            stream_name: stream_name,
            created: created
          },
          link: link
        } = spear_event,
        _serializer,
        stream_prefix
      ) do
    metadata = %{}

    {causation_id, metadata} = Map.pop(metadata, "$causationId")
    {correlation_id, metadata} = Map.pop(metadata, "$correlationId")

    recorded_event = %RecordedEvent{
      event_id: id,
      event_number: commit_position,
      stream_id: to_stream_id(stream_prefix, stream_name),
      stream_version: stream_revision + 1,
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: type,
      data: spear_event,
      metadata: metadata,
      created_at: created
    }

    if link do
      metadata = Map.put(recorded_event.metadata, :link, link)

      %{recorded_event | metadata: metadata}
    else
      recorded_event
    end
  end

  def to_recorded_event(
        %Spear.Event{
          id: id,
          body: body,
          type: type,
          metadata: %{
            commit_position: commit_position,
            stream_revision: stream_revision,
            stream_name: stream_name,
            created: created,
            custom_metadata: custom_metadata
          },
          link: link
        },
        serializer,
        stream_prefix
      ) do
    metadata =
      case custom_metadata do
        none when none in [nil, ""] -> %{}
        metadata -> serializer.deserialize(metadata, [])
      end

    data = serializer.deserialize(body, type: type)

    {causation_id, metadata} = Map.pop(metadata, "$causationId")
    {correlation_id, metadata} = Map.pop(metadata, "$correlationId")

    recorded_event = %RecordedEvent{
      event_id: id,
      event_number: commit_position,
      stream_id: to_stream_id(stream_prefix, stream_name),
      stream_version: stream_revision + 1,
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: type,
      data: data,
      metadata: metadata,
      created_at: created
    }

    if link do
      metadata = Map.put(recorded_event.metadata, :link, link)

      %{recorded_event | metadata: metadata}
    else
      recorded_event
    end
  end

  def to_proposed_message(
        %EventData{
          data: data,
          event_type: event_type
        } = event,
        serializer,
        serializer_content_type
      ) do
    content_type =
      if event_type == "$>" do
        "application/octet-stream"
      else
        serializer_content_type
      end

    custom_metadata =
      if event_type == "$>" do
        ""
      else
        serialize_metadata(event, serializer)
      end

    event_type
    |> Spear.Event.new(
      data,
      content_type: content_type,
      custom_metadata: custom_metadata
    )
    |> Spear.Event.to_proposed_message(%{serializer_content_type => &serializer.serialize/1})
  end

  def to_snapshot_data(%RecordedEvent{data: %SnapshotData{} = snapshot} = event)
      when is_struct(snapshot.data) do
    %SnapshotData{snapshot | created_at: event.created_at}
  end

  def to_snapshot_data(%RecordedEvent{data: snapshot} = event) do
    data =
      snapshot.source_type
      |> String.to_existing_atom()
      |> struct(snapshot.data)
      |> JsonDecoder.decode()

    %SnapshotData{snapshot | data: data, created_at: event.created_at}
  end

  def to_event_data(%SnapshotData{} = snapshot) do
    %EventData{
      event_type: TypeProvider.to_string(snapshot),
      data: snapshot
    }
  end

  defp serialize_metadata(
         %EventData{
           metadata: metadata,
           causation_id: causation_id,
           correlation_id: correlation_id
         },
         serializer
       ) do
    metadata
    |> add_causation_id(causation_id)
    |> add_correlation_id(correlation_id)
    |> serializer.serialize()
  end

  defp to_stream_id(stream_prefix, stream_name)

  defp to_stream_id(nil, stream_name) do
    stream_name
  end

  defp to_stream_id(stream_prefix, stream_name) when is_binary(stream_prefix) do
    cond do
      String.starts_with?(stream_name, "#{stream_prefix}snapshot-") ->
        String.replace_leading(stream_name, "#{stream_prefix}snapshot-", "")

      String.starts_with?(stream_name, "#{stream_prefix}-") ->
        String.replace_leading(stream_name, "#{stream_prefix}-", "")

      true ->
        stream_name
    end
  end

  defp add_causation_id(metadata, causation_id),
    do: add_to_metadata(metadata, "$causationId", causation_id)

  defp add_correlation_id(metadata, correlation_id),
    do: add_to_metadata(metadata, "$correlationId", correlation_id)

  defp add_to_metadata(metadata, key, value) when is_nil(metadata),
    do: add_to_metadata(%{}, key, value)

  defp add_to_metadata(metadata, _key, value) when is_nil(value), do: metadata

  defp add_to_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
