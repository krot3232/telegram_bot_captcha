%%%-------------------------------------------------------------------
%% @doc
%% Telegram CAPTCHA Bot Application
%%
%% This application manages Telegram bots that use webhooks to implement
%% CAPTCHA and anti-spam verification when users join chats.
%%
%% Features:
%% <ul>
%%   <li>Webhook server initialization and management</li>
%%   <li>Dynamic bot registration and removal</li>
%%   <li>Event handling via gen_event</li>
%%   <li>Per-bot HTTP connection pools</li>
%%   <li>User moderation (mute / ban)</li>
%% </ul>
%%
%% Architecture:
%% <ul>
%%   <li>application behaviour — entry point</li>
%%   <li>gen_server — state management</li>
%%   <li>supervisor — child process management</li>
%%   <li>webhook server — receives Telegram updates</li>
%% </ul>
%%
%% Configuration example (sys.config):
%% <pre>
%% {telegram_bot_captcha, [
%%   {webhook, #{
%%       ip => ~"0.0.0.0",
%%       port => 8443,
%%       secret_token => ~"secret",
%%       transport_opts => #{certfile => "..."}
%%   }},
%%   {bots, [BotConfig]}
%% ]}.
%% </pre>
%%
%% @end
%%%-------------------------------------------------------------------
-module(telegram_bot_captcha).

-behaviour(application).
-behaviour(gen_server).

-export([start/2, stop/1]).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([add_bot/1, delete_bot/1, delete_bots/0]).
-export([mute_chat_member/4, ban_chat_member/4]).


-type bot_name() :: atom().
-type chat_id() :: integer() | binary().
-type user_id() :: integer().
-type minute() :: non_neg_integer().

-type webhook_id() :: term().

-type webhook_param() :: #{
    ip := binary() | string(),
    port := integer(),
    secret_token := binary(),
    transport_opts := map(),
    id => term()
}.

-type handler() :: {module(), term()}.

-type bot() :: #{
    event := term(),
    name := bot_name(),
    set_webhook := boolean(),
    handlers := [handler()],
    pool => term(),
    options => term()
}.

-type state() :: #{
    webhook_id := webhook_id(),
    webhook_param := webhook_param(),
    bots := [bot()]
}.


-spec start(application:start_type(), term()) ->
    {ok, pid(), map()} | {error, term()}.
start(_StartType, _StartArgs) ->
    case application:get_env(telegram_bot_captcha, webhook, []) of
        #{ip := Ip, port := Port, secret_token := _, transport_opts := TransportOpts} =
                WebhookParam ->
            TransportOpts1 =
                case maps:get(port, TransportOpts, undef) of
                    undef -> TransportOpts#{port => Port};
                    _P -> TransportOpts
                end,
            WebhookId = telegram_bot_api_webhook_server:name_server(Ip, Port),
            WebhookParam1 = WebhookParam#{id => WebhookId, transport_opts => TransportOpts1},
            global:sync(),
            {ok, _Pid} =
                case global:whereis_name(WebhookId) of
                    Pid1 when is_pid(Pid1) -> {ok, Pid1};
                    _ -> telegram_bot_api_sup:start_webhook(WebhookParam1)
                end,
            {ok, Pid} = telegram_bot_captcha_sup:start_link(#{
                webhook_id => WebhookId, webhook_param => WebhookParam
            }),
            [
                telegram_bot_captcha:add_bot(Bot)
             || Bot <- application:get_env(telegram_bot_captcha, bots, [])
            ],
            {ok, Pid, #{webhook_id => WebhookId}};
        _ ->
            {error, {webhook_empty, "Set env telegram_bot_captcha.webhook file sys.config"}}
    end.


-spec stop(map()) -> ok.
stop(#{webhook_id := WebhookId} = _State) ->
    try telegram_bot_api_webhook_server:get_bots({global, WebhookId}) of
        {ok, Map} when Map =:= #{} -> telegram_bot_api_sup:stop_webhook(WebhookId);
        _ -> {error, match}
    catch
        E:R-> {error, {E,R}}
    end,
    ok.


-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(P) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [P], []).


-spec init([map()]) -> {ok, state()}.
init([Param]) when is_map(Param) ->
    {ok, Param#{bots => []}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(
    {add_bot, #{event := Event, name := BotName, set_webhook := SetWh, handlers := Handlers} = Bot},
    _From,
    #{
        bots := Bots,
        webhook_id := WebhookId,
        webhook_param := #{
            ip := WebhookIp,
            port := WebhookPort,
            secret_token := WebhookSecretToken,
            transport_opts := WebhookTransport
        }
    } = State
) ->
    {ok, PidEvent} = telegram_bot_captcha_sup:start_child(Event),
    [ok = gen_event:add_handler(PidEvent, H, [Bot#{options => Options}])|| {H, Options} <- Handlers],
    {ok, HttpPool} = telegram_bot_api_sup:start_pool(Bot),
    BotNameBin = atom_to_binary(BotName),
    ok = telegram_bot_api_webhook_server:add_bot(
        {global, WebhookId},
        BotNameBin,
        #{event => Event, name => BotName}
    ),
    Bot1 = Bot#{pool => HttpPool},
    case SetWh of
        true ->
            try
                WebhookUrl = telegram_bot_api_webhook_server:make_url(
                    WebhookIp, integer_to_binary(WebhookPort), BotNameBin
                ),
                telegram_bot_api:setWebhook(BotName, #{
                    url => WebhookUrl,
                    ip_address => WebhookIp,
                    certificate => #{
                        file => maps:get(certfile, WebhookTransport),
                        name => <<"p.pem">>
                    },
                    secret_token => WebhookSecretToken,
                    allowed_updates => [chat_member, message]
                },true),
                {reply, ok, State#{bots => [Bot1 | Bots]}}
            catch
                E:M ->
                    {reply, {error, {E, M}}, State}
            end;
        _ ->
            {reply, ok, State#{bots => [Bot1 | Bots]}}
    end;
handle_call({delete_bot, BotName}, _From, #{bots := Bots, webhook_id := WebhookId} = State) ->
    Bots1 = [
        begin
            delete_bot(WebhookId, BotName, Event),
            Bot
        end
     || #{event := Event, name := Name} = Bot <- Bots, Name =:= BotName
    ],
    {reply, ok, State#{bots => Bots -- Bots1}};
handle_call(delete_bots, _From, #{bots := Bots, webhook_id := WebhookId} = State) ->
    [delete_bot(WebhookId, BotName, Event) || #{event := Event, name := BotName} <- Bots],
    {reply, ok, State#{bots => []}};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.


handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


-spec add_bot(bot()) -> term().
add_bot(Bot) ->
    gen_server:call(?MODULE, {add_bot, Bot}).


-spec delete_bot(bot_name()) -> term().
delete_bot(BotName) ->
    gen_server:call(?MODULE, {delete_bot, BotName}).


-spec delete_bots() -> term().
delete_bots() ->
    gen_server:call(?MODULE, delete_bots).


-spec delete_bot(webhook_id(), bot_name(), term()) -> ok.
delete_bot(WebhookId, BotName, Event) ->
    %% TODO telegram_bot_api delete httpc profile
    %{HttpProfiles, _} = wpool:broadcall(BotName, {get_http_profile}, 5000),
    ok = telegram_bot_api_webhook_server:delete_bot({global, WebhookId}, BotName),
    ok = telegram_bot_captcha_sup:stop_child(Event),
    ok = telegram_bot_api_sup:stop_pool(BotName),
    ok.



-spec mute_chat_member(bot_name(), chat_id(), user_id(), minute()) ->
    boolean().
mute_chat_member(BotName, ChatId, UserId, Minute) ->
    Result = telegram_bot_api:restrictChatMember(BotName, #{
        chat_id => ChatId,
        user_id => UserId,
        until_date => erlang:system_time(seconds) + (60 * Minute),
        permissions => #{
            can_send_messages => false,
            can_send_audios => false,
            can_send_documents => false,
            can_send_photos => false,
            can_send_videos => false,
            can_send_video_notes => false,
            can_send_voice_notes => false,
            can_send_polls => false,
            can_send_other_messages => false,
            can_add_web_page_previews => false,
            can_change_info => false,
            can_invite_users => false,
            can_pin_messages => false,
            can_manage_topics => false
        }
    }),
    case Result of
        {ok, 200, #{ok := true, result := true}} -> true;
        _ -> false
    end.

-spec ban_chat_member(bot_name(), chat_id(), user_id(), minute()) ->
    boolean().
ban_chat_member(BotName, ChatId, UserId, Minute) ->
    Result = telegram_bot_api:banChatMember(BotName, #{
        chat_id => ChatId,
        user_id => UserId,
        until_date => erlang:system_time(seconds) + (60 * Minute)
    }),
    case Result of
        {ok, 200, #{ok := true, result := true}} -> true;
        _ -> false
    end.
