-module(telegram_bot_captcha_port_handler).
-behaviour(gen_event).
-include_lib("telegram_bot_api/include/emoji.hrl").
-include_lib("telegram_bot_api/include/message_reaction.hrl").

-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

-define(TIME_DEFAULT, 120).

captcha_open_port(PortCmd) ->
    Port = erlang:open_port(
        {
            spawn, PortCmd
        },
        [
            binary, use_stdio, exit_status
        ]
    ),
    erlang:monitor(port, Port),
    Port.
init([#{options := #{port_cmd := PortCmd}} = Args]) ->
    {ok, Args#{db => #{}, port => captcha_open_port(PortCmd)}}.
%%1
handle_event(
    {update, BotName,
        #{
            chat_member := Msg = #{
                chat := #{id := ChatId},
                from := #{id := UserId, first_name := UserName},
                new_chat_member := #{status := <<"member">>, user := #{is_bot := false}}
            }
        } = _Result},
    #{port := Port} = State
) ->
    Bin = telegram_bot_api_util:json_encode(#{
        chat_id => ChatId, user_id => UserId, user_name => UserName
    }),
    true = erlang:port_command(Port, <<Bin/binary, $\n>>),
    {ok, State};
%%%2
handle_event(
    {update, BotName,
        #{
            message := Msg = #{
                chat := #{id := ChatId},
                from := #{id := UserId},
                message_id := MessageId,
                text := Text
            }
        } = _Result},
    #{db := DB, port := Port, options := #{code_ok := CodeOk, code_bad := CodeBad}} = State
) ->
    Key = {ChatId, UserId},
    DBNew =
        case maps:get(Key, DB, undef) of
            undef ->
                DB;
            Code when is_binary(Code) ->
                if
                    Code =:= Text ->
                        telegram_bot_api:setMessageReaction(
                            BotName,
                            #{
                                chat_id => ChatId,
                                message_id => MessageId,
                                reaction => [
                                    #{
                                        type => ?REACTION_TYPE_EMOJI,
                                        emoji => ?REACTION_OK_HAND
                                    }
                                ]
                            },
                            true
                        ),
                        send_clear(CodeOk, Key, MessageId),
                        maps:remove(Key, DB);
                    true ->
                        send_clear(CodeBad, Key, MessageId),
                        DB
                end
        end,
    {ok, State#{db => DBNew}};
handle_event({error, BotName, Err, Msg}, State) ->
    {ok, State};
handle_event(_Event, State) ->
    {ok, State}.
handle_call(_Request, State) ->
    {ok, no_reply, State}.
handle_info({async, Ref, {ok, 200, #{ok := true, result := true}}}, State) ->
    {ok, State};

handle_info(
    {{Type, Minute}, {ChatId, UserId} = Key, MessageId}, #{name := BotName, db := DB} = State
) ->
    telegram_bot_api:deleteMessage(
        BotName,
        #{
            chat_id => ChatId,
            message_id => MessageId
        },
        true
    ),
    case maps:get(Key, DB, undef) of
        undef ->
            ok;
        _ ->
           Result = case Type of
                ban -> telegram_bot_captcha:ban_chat_member(BotName, ChatId, UserId, Minute);
                mute -> telegram_bot_captcha:mute_chat_member(BotName, ChatId, UserId, Minute);
                _ -> ok
            end,
            Result
    end,
    {ok, State};
handle_info({'DOWN', MonitorRef, port, Port, Reason}, State) ->
    %%TODO
    {ok, State};
handle_info(
    {Port, {data, Bin}}, #{name := BotName, db := DB, options := #{room_join := RoomJoin}} = State
) when is_port(Port) ->
    #{
        code := Code,
        file := File,
        chat_id := ChatId,
        user_id := UserId,
        user_name := UserName
    } = telegram_bot_api_util:json_decode(Bin),
    Key = {ChatId, UserId},
    Param = #{
        chat_id => ChatId,
        parse_mode => <<"HTML">>,
        photo => #{file => File, name => <<"captcha.jpg">>},
        text =>
            <<?EMOJI_WAVE/binary, " <a href=\"tg://user?id=", (integer_to_binary(UserId))/binary,
                "\">", UserName/binary, "</a>", $\n, "Enter captcha">>
    },
    Result = telegram_bot_api:sendPhoto(BotName, Param),
    case Result of
        {ok, 200, #{ok := true, result := #{message_id := MessageId}}} ->
            send_clear(RoomJoin, Key, MessageId);
        _ ->
            error
    end,
    {ok, State#{db => DB#{Key => Code}}};
handle_info(_Info, State) ->
    {ok, State}.
terminate(_Args, State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send_clear(Options, Key, MessageId) ->
    case maps:get(send, Options, undef) of
        undef ->
            ok;
        Ev ->
            erlang:send_after(
                maps:get(time, Options, ?TIME_DEFAULT) * 1000,
                self(),
                {{Ev, maps:get(param, Options, [])}, Key, MessageId}
            )
    end.
