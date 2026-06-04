%%% minigui_ffi.erl
%%% Minimal FFI to open/use an external port with {packet, 2}.

-module(minigui_ffi).

-export([
  start/0,
  start_with_path/1,
  send/2,
  recv/2,
  ensure_port/0,
  unique_request_id/0,
  send_hello/2,
  send_cmd/4,
  send_add_button/4
]).

start() ->
  case ensure_port() of
    {ok, PathBin} -> start_with_path(PathBin);
    Error -> Error
  end.

start_with_path(Path) when is_binary(Path) ->
  try
    Port = erlang:open_port({spawn_executable, binary_to_list(Path)}, [binary, {packet, 2}, exit_status, use_stdio]),
    {ok, Port}
  catch
    _:Reason -> {error, term_to_string({open_port_failed, Reason})}
  end.

send(Port, Data) ->
  true = erlang:port_command(Port, Data),
  nil.

send_hello(Port, Version) ->
  true = erlang:port_command(Port, <<16#00:8, Version:16/unsigned-big-integer>>),
  nil.

send_cmd(Port, Cmd, ReqId, Payload) ->
  true =
    erlang:port_command(
      Port,
      <<Cmd:8, ReqId:32/unsigned-big-integer, Payload/bitstring>>
    ),
  nil.

send_add_button(Port, ReqId, Id, Label) ->
  true =
    erlang:port_command(
      Port,
      <<16#13:8, ReqId:32/unsigned-big-integer, Id:8, Label/bitstring>>
    ),
  nil.

recv(Port, TimeoutMs) ->
  receive
    {Port, {data, Data}} ->
      {data, Data};
    {Port, {exit_status, _Status}} ->
      port_closed
  after TimeoutMs ->
    timeout
  end.

ensure_port() ->
  try
    {ok, list_to_binary(minigui_bootstrap:ensure_port())}
  catch
    _:Reason -> {error, term_to_string({ensure_port_failed, Reason})}
  end.

unique_request_id() ->
  %% A monotonic, positive request_id, limited to 32 bits for the protocol.
  (erlang:unique_integer([monotonic, positive]) band 16#FFFFFFFF).

term_to_string(Term) ->
  unicode:characters_to_binary(io_lib:format("~p", [Term])).
