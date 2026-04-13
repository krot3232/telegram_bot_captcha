%%%-------------------------------------------------------------------
%% @doc telegram_bot_captcha top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(telegram_bot_captcha_sup).

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).
-export([start_child/1, stop_child/1]).

-define(SERVER, ?MODULE).

start_link(L) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [L]).

init(Param) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 100,
        period => 60
    },
    ChildSpecs1 = [
        #{
            id => telegram_bot_captcha,
            start => {telegram_bot_captcha, start_link, Param},
            restart => permanent,
            shutdown => 1000,
            type => worker,
            modules => [telegram_bot_captcha]
        }
    ],
    {ok, {SupFlags, ChildSpecs1}}.

start_child(Event) ->
    Spec = #{
        id => element(2, Event),
        start => {gen_event, start_link, [Event]},
        restart => transient,
        shutdown => 1000,
        type => worker,
        modules => [dynamic]
    },
    supervisor:start_child(?SERVER, Spec).
stop_child(Event) ->
    Id = element(2, Event),
    supervisor:terminate_child(?SERVER, Id),
    supervisor:delete_child(?SERVER, Id),
    ok.
