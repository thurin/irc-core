{-# Language QuasiQuotes, OverloadedStrings #-}
{-|
Module      : Client.Hook.FreRelay
Description : Hook for interpreting FreFrelay messages
Copyright   : (c) Eric Mertens 2019
License     : ISC
Maintainer  : emertens@gmail.com

The #dronebl channel uses the FreRelay bot to relay messages from
other networks. This hook integrates those messages into the native
format.

-}
module Client.Hook.FreRelay
  ( freRelayHook
  ) where

import           Data.List (uncons)
import qualified Data.Text as Text
import           Data.Text (Text)
import           Data.Foldable (asum)

import           Text.Regex.TDFA (match, defaultCompOpt, defaultExecOpt)
import           Text.Regex.TDFA.Text (Regex, compile)

import           Client.Hook (MessageHook(..), MessageResult(..))
import           Irc.Message
import           Irc.Identifier (mkId, Identifier)
import           Irc.UserInfo (UserInfo(..))
import           StrQuote (str)

freRelayHook :: MessageHook
freRelayHook = MessageHook "frerelay" False remap

-- | Remap messages from frerelay on #dronebl that match one of the
-- rewrite rules.
remap :: IrcMsg -> MessageResult
remap (Privmsg (UserInfo "frerelay" _ _) chan@"#dronebl" msg)
  | Just sub <- rules chan msg = RemapMessage sub
remap _ = PassMessage

-- | Generate a replacement message for a chat message from frerelay
-- when the message matches one of the replacement rules.
rules ::
  Identifier {- ^ channel -} ->
  Text       {- ^ message -} ->
  Maybe IrcMsg
rules chan msg =
  asum
    [ rule (chatMsg chan) chatRe msg
    , rule (actionMsg chan) actionRe msg
    , rule (joinMsg chan) joinRe msg
    , rule (partMsg chan) partRe msg
    , rule quitMsg quitRe msg
    , rule nickMsg nickRe msg
    ]

-- | Match the message against the regular expression and use the given
-- consume to consume all of the captured groups.
rule ::
  Rule r =>
  r     {- ^ capture consumer   -} ->
  Regex {- ^ regular expression -} ->
  Text  {- ^ message            -} ->
  Maybe IrcMsg
rule mk re s =
  case match re s of
    [_:xs] -> matchRule xs mk
    _      -> Nothing

chatRe, actionRe, joinRe, quitRe, nickRe, partRe :: Regex
Right chatRe   = compRe [str|^<([^>]+)> (.*)$|]
Right actionRe = compRe [str|^\* ([^ ]+) (.*)$|]
Right joinRe   = compRe [str|^\*\*\* \[([^]]+)\] ([^ ]+) \(([^@]+)@([^)]+)\) has joined the channel$|]
Right quitRe   = compRe [str|^\*\*\* \[([^]]+)\] ([^ ]+) has signed off \((.*)\)$|]
Right nickRe   = compRe [str|^\*\*\* \[([^]]+)\] ([^ ]+) changed nick to ([^ ]+)$|]
Right partRe   = compRe [str|^\*\*\* \[([^]]+)\] ([^ ]+) has left the channel( \((.*)\))?$|]

-- | Compile a regular expression for using in message matching.
compRe ::
  Text                {- ^ regular expression           -} ->
  Either String Regex {- ^ error or compiled expression -}
compRe = compile defaultCompOpt defaultExecOpt

------------------------------------------------------------------------

chatMsg ::
  Identifier {- ^ channel  -} ->
  Text       {- ^ nickname -} ->
  Text       {- ^ message  -} ->
  IrcMsg
chatMsg chan nick msg =
  Privmsg
    (userInfo nick)
    chan
    msg

actionMsg ::
  Identifier {- ^ channel  -} ->
  Text       {- ^ nickname -} ->
  Text       {- ^ message  -} ->
  IrcMsg
actionMsg chan nick msg =
  Ctcp
    (userInfo nick)
    chan
    "ACTION"
    msg

joinMsg ::
  Identifier {- ^ channel  -} ->
  Text       {- ^ server   -} ->
  Text       {- ^ nickname -} ->
  Text       {- ^ username -} ->
  Text       {- ^ hostname -} ->
  IrcMsg
joinMsg chan srv nick user host =
  Join
    (UserInfo (mkId (nick <> "@" <> srv)) user host)
    chan
    "" -- account

partMsg ::
  Identifier {- ^ channel        -} ->
  Text       {- ^ server         -} ->
  Text       {- ^ nickname       -} ->
  Text       {- ^ reason wrapper -} ->
  Text       {- ^ reason         -} ->
  IrcMsg
partMsg chan srv nick msg_outer msg =
  Part
    (userInfo (nick <> "@" <> srv))
    chan
    (if Text.null msg_outer then Nothing else Just msg)

quitMsg ::
  Text {- ^ server       -} ->
  Text {- ^ nickname     -} ->
  Text {- ^ quit message -} ->
  IrcMsg
quitMsg srv nick msg =
  Quit
    (userInfo (nick <> "@" <> srv))
    (Just msg)

nickMsg ::
  Text {- ^ server   -} ->
  Text {- ^ old nick -} ->
  Text {- ^ new nick -} ->
  IrcMsg
nickMsg srv old new =
  Nick
    (userInfo (old <> "@" <> srv))
    (mkId (new <> "@" <> srv))

-- | Construct dummy user info when we don't know the user or host part.
userInfo ::
  Text {- ^ nickname -} ->
  UserInfo
userInfo nick = UserInfo (mkId nick) "*" "*"

------------------------------------------------------------------------

class Rule a where
  matchRule :: [Text] -> a -> Maybe IrcMsg

class RuleArg a where
  matchArg :: Text -> Maybe a

instance RuleArg Text where
  matchArg = Just

instance (RuleArg a, Rule b) => Rule (a -> b) where
  matchRule tts f =
    do (t,ts) <- uncons tts
       a      <- matchArg t
       matchRule ts (f a)

instance Rule IrcMsg where
  matchRule args ircMsg
    | null args = Just ircMsg
    | otherwise = Nothing
