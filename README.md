# Telegram Bot CAPTCHA
<img src="https://raw.githubusercontent.com/krot3232/logos/main/telegram_bot_captcha.png" width="200">

Telegram CAPTCHA Bot is an Erlang/OTP application for managing Telegram bots that protect chats from spam using CAPTCHA verification.

The application uses webhooks, supports multiple bots, and provides moderation tools such as muting and banning users.

[![Erlang](https://img.shields.io/badge/Erlang%2FOTP-27+-deeppink?style=flat-square&logo=erlang&logoColor=ffffff)](https://www.erlang.org)
[![Hex Version](https://img.shields.io/hexpm/v/telegram_bot_captcha.svg?style=flat-square)](https://hex.pm/packages/telegram_bot_captcha)
---

## ✨ Features

- Webhook-based Telegram bot integration
- Multi-bot support
- Dynamic bot management (add/remove at runtime)
- Event-driven architecture via `gen_event`
- Per-bot HTTP connection pools
- Built-in moderation:
  - Mute users
  - Ban users
- OTP-compliant (application + supervisor + gen_server)

---
## 📥 Installation
 The package can be installed by adding `telegram_bot_captcha` to your list of dependencies
in
`rebar.config`:
```erlang
{deps, [telegram_bot_captcha]}.
```
## ⚙️ Configuration

Configure the application in `sys.config`:

```erlang
{telegram_bot_captcha,[
    {webhook,#{
         %% public IP address where webhook data will be received
        ip => <<"1.1.1.1">>,
        %% port of the public IP
        port => 80,
        %% webhook URL is formed from IP and port
        %% secret token for verification sent by Telegram in webhook headers
        %% see (https://core.telegram.org/bots/api#setwebhook)
        secret_token => <<"secret">>,
        %% transport settings
        transport_opts => #{
            %% which IP to bind the HTTP server to
            ip => {0,0,0,0},
            %% certificate, see (https://core.telegram.org/bots/self-signed)
            %% you can generate a self-signed certificate
            %% example: openssl req -newkey rsa:2048 -sha256 -nodes -keyout YOURPRIVATE.key -x509 -days 365 -out YOURPUBLIC.pem -subj "/C=US/ST=New York/L=Brooklyn/O=Example Brooklyn Company/CN=1.1.1.1"
            certfile => <<"/etc/telegram_bot_captcha/ssl/YOURPUBLIC.pem">>,
            keyfile => <<"/etc/telegram_bot_captcha/ssl/YOURPRIVATE.key">>,
            %% disable verification for self-signed certificates
            verify => verify_none,
            fail_if_no_peer_cert => false,
            log_level => none
			}
        }},
        {bots, [
        #{
            name => my_bot,
            event => my_bot_event,
            set_webhook => true,
            handlers => [
                {my_handler, #{}}
            ]
        }
    ]}
]}
```
## 🚀 Starting the Application
```erlang
application:start(telegram_bot_captcha).
```
On startup:

+ Webhook server is initialized  
+ Supervisor is started  
+ Bots from config are registered

## 🤖 Bot Configuration

Each bot is defined as:
```erlang
#{
    name := atom(), %Bot identifier
    event := term(), %Event process (gen_event)
    set_webhook := boolean(), %Whether to register webhook in Telegram
    handlers := [{Module, Options}] %List of event handlers
}
```
## 📡 API
**Add Bot** 
```erlang
telegram_bot_captcha:add_bot(Bot).
```
**Delete Bot**
```erlang
telegram_bot_captcha:delete_bot(BotName).
```
**Delete All Bots**
```erlang
telegram_bot_captcha:delete_bots().
```

## 🔒 Moderation API
**Mute User**
```erlang
telegram_bot_captcha:mute_chat_member(BotName, ChatId, UserId, Minutes).
```
**Ban User**
```erlang
telegram_bot_captcha:ban_chat_member(BotName, ChatId, UserId, Minutes).
```
## 🦄 Handler 
[`telegram_bot_captcha_math_handler`](https://github.com/krot3232/telegram_bot_captcha/blob/main/src/telegram_bot_captcha_math_handler.erl)  
[`telegram_bot_captcha_port_handler`](https://github.com/krot3232/telegram_bot_captcha/blob/main/src/telegram_bot_captcha_port_handler.erl)  

## 🧪 Example 
Example [`config/sys.config`](https://github.com/krot3232/telegram_bot_captcha/blob/main/example/sys.config)  
Example [`captcha.php`](https://github.com/krot3232/telegram_bot_captcha/blob/main/example/captcha.php) for [`telegram_bot_captcha_port_handler`](https://github.com/krot3232/telegram_bot_captcha/blob/main/src/telegram_bot_captcha_port_handler.erl)  

## 📌 Other
* [Erlang Library for developing Telegram Bots](https://hex.pm/packages/telegram_bot_api)