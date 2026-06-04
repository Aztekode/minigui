%%% minigui_bootstrap.erl
%%% Downloads (if needed) the port executable from GitHub Releases.
%%%
%%% Goal: let users run `gleam add minigui` without a C toolchain and without
%%% installing development headers/libs. The "bridge" is a precompiled
%%% per-platform binary, downloaded into priv/ on first use.

-module(minigui_bootstrap).

-export([ensure_port/0]).

ensure_port() ->
  PrivDir = priv_dir(),
  {FileName, Url} = release_asset(),
  Path = filename:join(PrivDir, FileName),
  CacheDir = cache_dir(),
  CachePath = filename:join(CacheDir, FileName),

  case filelib:is_file(Path) of
    true ->
      %% If it already exists in priv/, validate it as well (production policy).
      ok = ensure_http_started(),
      case maybe_verify_sha256(Url, Path) of
        ok -> Path;
        {error, _} ->
          _ = file:delete(Path),
          ensure_port()
      end;
    false ->
      %% When running from a repo (dev), it's common for the binary to already
      %% exist in "./priv". This avoids forcing a download during development.
      case local_repo_port() of
        {ok, Local} ->
          Local;
        error ->
          ok = ensure_http_started(),
          ok = filelib:ensure_dir(CachePath),
          case ensure_cached(Url, CachePath) of
            ok ->
              ok = copy_file(CachePath, Path),
              ok = maybe_chmod(Path),
              Path;
            {error, Reason} ->
              %% If the download fails, try a typical dev fallback:
              %% priv/minigui_port or priv/minigui_port.exe (if present)
              case fallback_dev_port(PrivDir) of
                {ok, Fallback} -> Fallback;
                error -> erlang:error({minigui_port_download_failed, Url, Reason})
              end
          end
      end
  end.

priv_dir() ->
  %% When minigui is a dependency, priv_dir/1 points to the lib in _build.
  case code:priv_dir(minigui) of
    {error, _} ->
      %% fallback for direct execution from the repo
      filename:join([filename:dirname(code:which(?MODULE)), "..", "priv"]);
    Dir ->
      Dir
  end.

fallback_dev_port(PrivDir) ->
  %% Prefer release names (minigui/minigui.exe), but accept the historical
  %% minigui_port(/.exe) name for development.
  Candidates = [
    filename:join(PrivDir, "minigui"),
    filename:join(PrivDir, "minigui.exe"),
    filename:join(PrivDir, "minigui_port"),
    filename:join(PrivDir, "minigui_port.exe")
  ],
  first_existing(Candidates).

local_repo_port() ->
  Candidates = [
    filename:absname(filename:join(["priv", "minigui"])),
    filename:absname(filename:join(["priv", "minigui.exe"])),
    filename:absname(filename:join(["priv", "minigui_port"])),
    filename:absname(filename:join(["priv", "minigui_port.exe"]))
  ],
  first_existing(Candidates).

first_existing([]) ->
  error;
first_existing([Path | Rest]) ->
  case filelib:is_file(Path) of
    true -> {ok, Path};
    false -> first_existing(Rest)
  end.

ensure_http_started() ->
  %% inets/httpc lives in OTP; ssl is required for https.
  _ = application:ensure_all_started(crypto),
  _ = application:ensure_all_started(public_key),
  _ = application:ensure_all_started(ssl),
  case application:ensure_all_started(inets) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok;
    Other -> erlang:error({minigui_inets_start_failed, Other})
  end.

cache_dir() ->
  %% Per-user cache to avoid re-downloading per project.
  %% Linux: $XDG_CACHE_HOME/minigui/<vsn> or ~/.cache/minigui/<vsn>
  %% Windows: %LOCALAPPDATA%\\minigui\\<vsn>
  Vsn = app_vsn(),
  case os:type() of
    {win32, _} ->
      Base =
        case os:getenv("LOCALAPPDATA") of
          false -> ".";
          V -> V
        end,
      filename:join([Base, "minigui", Vsn]);
    _ ->
      Base =
        case os:getenv("XDG_CACHE_HOME") of
          false ->
            case os:getenv("HOME") of
              false -> ".";
              Home -> filename:join([Home, ".cache"])
            end;
          Xdg -> Xdg
        end,
      filename:join([Base, "minigui", Vsn])
  end.

ssl_http_opts(Url) ->
  %% By default we require HTTPS and certificate verification.
  %% For local development (http://), allow an override:
  %%   MINIGUI_ALLOW_INSECURE=1
  case is_http_url(Url) of
    true ->
      case os:getenv("MINIGUI_ALLOW_INSECURE") of
        "1" -> [];
        "true" -> [];
        _ -> erlang:error({minigui_insecure_url_not_allowed, Url})
      end;
    false ->
      %% Try to locate a standard CA bundle.
      Ca =
        case os:getenv("MINIGUI_CACERTFILE") of
          false ->
            case filelib:is_file("/etc/ssl/certs/ca-certificates.crt") of
              true -> "/etc/ssl/certs/ca-certificates.crt";
              false -> ""
            end;
          V -> V
        end,
      SslOpts0 = [{verify, verify_peer}],
      SslOpts =
        case Ca of
          "" -> SslOpts0;
          _ -> [{cacertfile, Ca} | SslOpts0]
        end,
      [{ssl, SslOpts}]
  end.

is_http_url(Url) when is_list(Url) ->
  lists:prefix("http://", Url).

maybe_chmod(Path) ->
  case os:type() of
    {win32, _} -> ok;
    _ -> file:change_mode(Path, 8#755)
  end.

release_asset() ->
  %% Allows forcing an exact URL, e.g.:
  %%   MINIGUI_PORT_URL="https://github.com/Aztekode/minigui/releases/download/0.0.1/minigui.exe"
  case os:getenv("MINIGUI_PORT_URL") of
    false ->
      {Os, Arch} = detect_platform(),
      Base = release_base_url(),
      FileName =
        case Os of
          %% For a basic library, we recommend simple assets:
          %%  - Windows x86_64: minigui.exe
          %%  - Linux x86_64:   minigui
          %% If you need to distinguish by architecture, use MINIGUI_PORT_URL.
          windows when Arch =:= "x86_64" -> "minigui.exe";
          linux when Arch =:= "x86_64" -> "minigui";
          darwin -> "minigui-macos-" ++ Arch;
          other -> "minigui-" ++ atom_to_list(Os) ++ "-" ++ Arch
        end,
      {FileName, Base ++ "/" ++ FileName};
    Url ->
      {filename:basename(Url), Url}
  end.

detect_platform() ->
  Os =
    case os:type() of
      {win32, _} -> windows;
      {unix, darwin} -> darwin;
      {unix, linux} -> linux;
      {unix, _} -> unix;
      _ -> other
    end,
  Arch =
    case erlang:system_info(system_architecture) of
      %% Examples:
      %% "x86_64-pc-linux-gnu"
      %% "aarch64-unknown-linux-gnu"
      Str when is_list(Str) ->
        normalize_arch(Str)
    end,
  {Os, Arch}.

normalize_arch(Str) ->
  case string:find(Str, "aarch64") of
    nomatch ->
      case string:find(Str, "arm64") of
        nomatch ->
          case string:find(Str, "x86_64") of
            nomatch ->
              case string:find(Str, "amd64") of
                nomatch -> "unknown";
                _ -> "x86_64"
              end;
            _ -> "x86_64"
          end;
        _ -> "aarch64"
      end;
    _ -> "aarch64"
  end.

release_base_url() ->
  %% Recommended: publish binaries by version, e.g.:
  %% https://github.com/Aztekode/minigui/releases/download/v0.1.0
  %% Allows environment override:
  %%   MINIGUI_RELEASE_BASE_URL="https://.../download/v0.1.0"
  case os:getenv("MINIGUI_RELEASE_BASE_URL") of
    false ->
      DefaultRepo = "https://github.com/Aztekode/minigui/releases/download",
      Vsn = app_vsn(),
      DefaultRepo ++ "/v" ++ Vsn;
    Url ->
      Url
  end.

app_vsn() ->
  %% The .app version is derived from gleam.toml.
  %% Ensure the .app is loaded so application:get_key/2 works even if minigui
  %% hasn't been started yet.
  _ = application:load(minigui),
  case application:get_key(minigui, vsn) of
    {ok, Vsn} when is_list(Vsn) -> Vsn;
    _ -> "0.0.1"
  end.

download_to_file(Url, Path) ->
  %% Note: httpc returns body as a list unless we request binary.
  Req = {Url, []},
  HttpOpts = [{timeout, 30000}] ++ ssl_http_opts(Url),
  Opts = [{body_format, binary}],
  case httpc:request(get, Req, HttpOpts, Opts) of
    {ok, {{_, 200, _}, _Headers, Body}} when is_binary(Body) ->
      file:write_file(Path, Body);
    {ok, {{_, Status, _}, _Headers, Body}} ->
      {error, {http_status, Status, Body}};
    {error, Reason} ->
      {error, Reason}
  end.

ensure_cached(Url, CachePath) ->
  %% If it already exists in cache and passes validation (if applicable), ok.
  case filelib:is_file(CachePath) of
    true ->
      case maybe_verify_sha256(Url, CachePath) of
        ok -> ok;
        {error, _} ->
          %% Corrupt cache: re-download
          file:delete(CachePath),
          download_with_retries(Url, CachePath, 3)
      end;
    false ->
      download_with_retries(Url, CachePath, 3)
  end.

download_with_retries(_Url, _Path, 0) ->
  {error, retries_exhausted};
download_with_retries(Url, Path, N) ->
  Tmp = Path ++ ".tmp",
  case download_to_file(Url, Tmp) of
    ok ->
      case maybe_verify_sha256(Url, Tmp) of
        ok ->
          ok = file:rename(Tmp, Path),
          ok;
        {error, Reason} ->
          _ = file:delete(Tmp),
          {error, Reason}
      end;
    {error, _Reason} ->
      _ = file:delete(Tmp),
      timer:sleep(300),
      download_with_retries(Url, Path, N - 1)
  end.

maybe_verify_sha256(Url, Path) ->
  %% If a `<asset>.sha256` exists, verify it.
  %% Production policy: SHA256 required by default.
  %% You can disable it only at your own risk with:
  %%   MINIGUI_REQUIRE_SHA=0
  Require =
    case os:getenv("MINIGUI_REQUIRE_SHA") of
      false -> true;
      "0" -> false;
      "false" -> false;
      "FALSE" -> false;
      _ -> true
    end,
  case fetch_sha256(Url ++ ".sha256") of
    {ok, ExpectedHex} ->
      verify_sha256_file(Path, ExpectedHex);
    {error, not_found} ->
      case Require of
        true -> {error, sha256_missing};
        false -> ok
      end;
    {error, Reason} ->
      case Require of
        true -> {error, {sha256_fetch_failed, Reason}};
        false -> ok
      end
  end.

fetch_sha256(Url) ->
  Req = {Url, []},
  HttpOpts = [{timeout, 15000}] ++ ssl_http_opts(Url),
  Opts = [{body_format, binary}],
  case httpc:request(get, Req, HttpOpts, Opts) of
    {ok, {{_, 200, _}, _Headers, Body}} when is_binary(Body) ->
      parse_sha256(Body);
    {ok, {{_, 404, _}, _Headers, _Body}} ->
      {error, not_found};
    {ok, {{_, Status, _}, _Headers, Body}} ->
      {error, {http_status, Status, Body}};
    {error, Reason} ->
      {error, Reason}
  end.

parse_sha256(Bin) ->
  %% Formatos comunes:
  %%  - "<hex>  <filename>\n"
  %%  - "<hex>\n"
  Line =
    case binary:split(Bin, <<"\n">>, [global]) of
      [First | _] -> First;
      _ -> Bin
    end,
  Parts = binary:split(Line, <<" ">>, [global, trim_all]),
  case Parts of
    [Hex | _] when byte_size(Hex) >= 64 ->
      {ok, string:lowercase(binary_to_list(binary:part(Hex, 0, 64)))};
    _ ->
      {error, invalid_sha256_format}
  end.

verify_sha256_file(Path, ExpectedHex) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      ActualBin = crypto:hash(sha256, Bin),
      ActualHex = to_hex(ActualBin),
      case ActualHex =:= ExpectedHex of
        true -> ok;
        false -> {error, {sha256_mismatch, ExpectedHex, ActualHex}}
      end;
    {error, Reason} ->
      {error, Reason}
  end.

to_hex(Bin) when is_binary(Bin) ->
  lists:flatten([io_lib:format("~2.16.0b", [B]) || <<B:8>> <= Bin]).

copy_file(Src, Dst) ->
  case file:read_file(Src) of
    {ok, Bin} ->
      ok = filelib:ensure_dir(Dst),
      file:write_file(Dst, Bin);
    Error ->
      Error
  end.
