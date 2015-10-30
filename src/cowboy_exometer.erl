-module(cowboy_exometer).
-export([cowboy_response_hook/4, init/1, stats/1]).

-behaviour(cowboy_middleware).
-export([execute/2]).

-define(METRIC_HTTP_ACTIVE_REQS, [cowboy_exometer, api, http, active_requests]).

-define(STATUS_CODES, [200, 201, 202, 203, 204, 205, 206,
                       300, 301, 302, 303, 304, 305, 306, 307, 308,

                       400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410,
                       411, 412, 413, 414, 415, 416, 417, 418, 419, 421, 426,
                       428, 429, 431,

                       500, 501, 502, 503, 504, 505, 506, 511]).

cowboy_response_hook(Code, _Headers, _Body, Req) ->
    EndTs = timestamp(),

    {Path, _Req1} = cowboy_req:path(Req),
    EndPoint = case binary:split(Path, <<"/">>, [global]) of
                   [<<>>, EndPoint0|_] -> EndPoint0;
                   [<<>>] -> <<"">>;
                   [EndPoint0] -> EndPoint0
               end,
    {_Method, _Req2} = cowboy_req:method(Req),
    {StartTs, _Req3} = cowboy_req:meta(cowboy_exometer_req_start, Req),

    if is_integer(StartTs) ->
        ReqTime = EndTs - StartTs,
        exometer:update(endpoint_key(req_time, EndPoint), ReqTime);
       true -> ok
    end,

    exometer:update(endpoint_key(req_min, EndPoint), 1),
    exometer:update(resp_code_key(Code), 1),
    exometer:update(?METRIC_HTTP_ACTIVE_REQS, -1),

    Req.

timestamp() ->
    {Mega, Sec, Micro} = os:timestamp(),
    ((Mega * 1000000 + Sec) * 1000000 + Micro).

execute(Req, Env) ->
    Now = timestamp(),
    Req1 = cowboy_req:set_meta(cowboy_exometer_req_start, Now, Req),

    exometer:update(?METRIC_HTTP_ACTIVE_REQS, 1),

    {ok, Req1, Env}.

stats(Endpoints) ->
    ReqActive = unwrap_metric_value(?METRIC_HTTP_ACTIVE_REQS),
    [{resp, [{by_code, lists:map(fun get_resp_code_value/1, ?STATUS_CODES)}]},
     {req, [{time, lists:map(fun get_endpoint_time_value/1, Endpoints)},
            {active, ReqActive},
            {count, lists:map(fun get_endpoint_min_value/1, Endpoints)}]}].

init(Endpoints) ->
    lists:map(fun create_endpoint_time_metric/1, Endpoints),
    lists:map(fun create_endpoint_min_metric/1, Endpoints),
    lists:map(fun create_resp_code_metric/1, ?STATUS_CODES),

    exometer:new(?METRIC_HTTP_ACTIVE_REQS, counter, []).

get_endpoint_value(Type, EndPoint) ->
    Key = endpoint_key(Type, EndPoint),
    Value = unwrap_metric_value(Key),
    {EndPoint, Value}.

get_resp_code_value(Code) ->
    Key = resp_code_key(Code),
    Value = unwrap_metric_value(Key),
    {Code, Value}.

create_endpoint_min_metric(EndPoint) ->
    exometer:new(endpoint_key(req_min, EndPoint), spiral, [{time_span, 60000}]).

create_endpoint_time_metric(EndPoint) ->
    exometer:new(endpoint_key(req_time, EndPoint), histogram, []).

create_resp_code_metric(Code) ->
    exometer:new(resp_code_key(Code), spiral, [{time_span, 60000}]).

endpoint_key(Type, EndPoint) ->
    [cowboy_exometer, api, http, Type, EndPoint].

get_endpoint_min_value(EndPoint) ->
    get_endpoint_value(req_min, EndPoint).

get_endpoint_time_value(EndPoint) ->
    get_endpoint_value(req_time, EndPoint).

resp_code_key(Code) -> [cowboy_exometer, api, http, resp, Code].

unwrap_metric_value(Key) ->
    case exometer:get_value(Key) of
        {ok, Val} -> Val;
        Other -> 
            lager:warning("Error getting endpoint value ~p: ~p",
                          [Key, Other]),
            []
    end.
