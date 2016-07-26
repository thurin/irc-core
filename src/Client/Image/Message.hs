{-|
Module      : Client.Image.Message
Description : Renderer for message lines
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module provides image renderers for messages.

-}
module Client.Image.Message
  ( MessageRendererParams(..)
  , RenderMode(..)
  , defaultRenderParams
  , msgImage
  , detailedMsgImage
  , metadataImg
  , ignoreImage
  , quietIdentifier
  , coloredUserInfo
  , coloredIdentifier
  ) where

import           Client.IdentifierColors
import           Client.Message
import           Client.MircFormatting
import           Control.Lens
import           Data.Time
import           Graphics.Vty.Image
import           Irc.Identifier
import           Irc.Message
import           Irc.RawIrcMsg
import           Irc.UserInfo
import qualified Data.HashSet as HashSet
import           Data.List
import qualified Data.Text as Text
import           Data.Text (Text)
import           Data.Char

-- | Parameters used when rendering messages
data MessageRendererParams = MessageRendererParams
  { rendStatusMsg  :: [Char] -- ^ restricted message sigils
  , rendUserSigils :: [Char] -- ^ sender sigils
  , rendNicks      :: [Identifier] -- ^ nicknames to highlight
  }

-- | Default 'MessageRenderParams' with no sigils or nicknames specified
defaultRenderParams :: MessageRendererParams
defaultRenderParams = MessageRendererParams
  { rendStatusMsg = ""
  , rendUserSigils = ""
  , rendNicks = []
  }

-- | Construct a message given the time the message was received and its
-- render parameters.
msgImage ::
  ZonedTime {- ^ time of message -} ->
  MessageRendererParams -> MessageBody -> Image
msgImage when params body = horizCat
  [ timeImage when
  , statusMsgImage (rendStatusMsg params)
  , bodyImage NormalRender (rendUserSigils params) (rendNicks params) body
  ]

-- | Construct a message given the time the message was received and its
-- render parameters using a detailed view.
detailedMsgImage :: ZonedTime -> MessageRendererParams -> MessageBody -> Image
detailedMsgImage when params body = horizCat
  [ datetimeImage when
  , statusMsgImage (rendStatusMsg params)
  , bodyImage DetailedRender (rendUserSigils params) (rendNicks params) body
  ]

-- | Render the sigils for a restricted message.
statusMsgImage :: [Char] {- ^ sigils -} -> Image
statusMsgImage modes
  | null modes = emptyImage
  | otherwise  = string defAttr "(" <|>
                 string statusMsgColor modes <|>
                 string defAttr ") "
  where
    statusMsgColor = withForeColor defAttr red

-- | Render a 'MessageBody' given the sender's sigils and the nicknames to
-- highlight.
bodyImage ::
  RenderMode ->
  [Char] {- ^ sigils -} ->
  [Identifier] {- ^ nicknames to highlight -} ->
  MessageBody -> Image
bodyImage rm modes nicks body =
  case body of
    IrcBody irc  -> ircLineImage rm modes nicks irc
    ErrorBody ex -> string defAttr ("Exception: " ++ show ex)
    ExitBody     -> string defAttr "Thread finished"

-- | Render a 'ZonedTime' as time using quiet attributes
--
-- @
-- 23:15
-- @
timeImage :: ZonedTime -> Image
timeImage
  = string (withForeColor defAttr brightBlack)
  . formatTime defaultTimeLocale "%R "

-- | Render a 'ZonedTime' as full date and time user quiet attributes
--
-- @
-- 2016-07-24 23:15:10
-- @
datetimeImage :: ZonedTime -> Image
datetimeImage
  = string (withForeColor defAttr brightBlack)
  . formatTime defaultTimeLocale "%F %T "

-- | Level of detail to use when rendering
data RenderMode
  = NormalRender -- ^ only render nicknames
  | DetailedRender -- ^ render full user info

-- | The attribute to be used for "quiet" content
quietAttr :: Attr
quietAttr = withForeColor defAttr brightBlack

-- | Render a chat message given a rendering mode, the sigils of the user
-- who sent the message, and a list of nicknames to highlight.
ircLineImage ::
  RenderMode ->
  [Char]       {- ^ sigils (e.g. \@+) -} ->
  [Identifier] {- ^ nicknames to highlight -} ->
  IrcMsg -> Image
ircLineImage rm sigils nicks body =
  let detail img =
        case rm of
          NormalRender -> emptyImage
          DetailedRender -> img
  in
  case body of
    Nick old new ->
      detail (string quietAttr "nick ") <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm old <|>
      string defAttr " became " <|>
      coloredIdentifier new

    Join nick _chan ->
      string quietAttr "join " <|>
      coloredUserInfo rm nick

    Part nick _chan mbreason ->
      string quietAttr "part " <|>
      coloredUserInfo rm nick <|>
      foldMap (\reason -> string quietAttr " (" <|>
                          parseIrcText reason <|>
                          string quietAttr ")") mbreason

    Quit nick mbreason ->
      string quietAttr "quit "   <|>
      coloredUserInfo rm nick   <|>
      foldMap (\reason -> string quietAttr " (" <|>
                          parseIrcText reason <|>
                          string quietAttr ")") mbreason

    Kick kicker _channel kickee reason ->
      detail (string quietAttr "kick ") <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm kicker <|>
      string defAttr " kicked " <|>
      coloredIdentifier kickee <|>
      string defAttr ": " <|>
      parseIrcText reason

    Topic src _dst txt ->
      coloredUserInfo rm src <|>
      string defAttr " changed topic to " <|>
      parseIrcText txt

    Notice src _dst txt ->
      detail (string quietAttr "note ") <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm src <|>
      string (withForeColor defAttr red) ": " <|>
      parseIrcTextWithNicks nicks txt

    Privmsg src _dst txt ->
      detail (string quietAttr "chat ") <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm src <|>
      string defAttr ": " <|>
      parseIrcTextWithNicks nicks txt

    Action src _dst txt ->
      detail (string quietAttr "chat ") <|>
      string (withForeColor defAttr blue) "* " <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm src <|>
      string defAttr " " <|>
      parseIrcTextWithNicks nicks txt

    Ping params ->
      string defAttr "PING" <|>
      horizCat [char (withForeColor defAttr blue) '·' <|>
                 parseIrcText p | p <- params]

    Pong params ->
      string defAttr "PONG" <|>
      horizCat [char (withForeColor defAttr blue) '·' <|>
                 parseIrcText p | p <- params]

    Error reason ->
      string (withForeColor defAttr red) "ERROR " <|>
      parseIrcText reason

    Reply code params ->
      string defAttr (show code) <|>
      horizCat [char (withForeColor defAttr blue) '·' <|>
                parseIrcText p | p <- params]

    UnknownMsg irc ->
      maybe emptyImage (\ui -> coloredUserInfo rm ui <|> char defAttr ' ')
        (view msgPrefix irc) <|>
      text' defAttr (view msgCommand irc) <|>
      horizCat [char (withForeColor defAttr blue) '·' <|>
                parseIrcText p | p <- view msgParams irc]

    Cap cmd args ->
      string defAttr (show cmd) <|>
      horizCat [char (withForeColor defAttr blue) '·' <|>
                text' defAttr a | a <- args]

    Mode nick _chan params ->
      detail (string quietAttr "mode ") <|>
      string (withForeColor defAttr cyan) sigils <|>
      coloredUserInfo rm nick <|>
      string defAttr " set mode: " <|>
      horizCat (intersperse (char (withForeColor defAttr blue) '·')
                            (text' defAttr <$> params))

-- | Render a nickname in its hash-based color.
coloredIdentifier :: Identifier -> Image
coloredIdentifier ident =
  text' (withForeColor defAttr (identifierColor ident)) (idText ident)

-- | Render an a full user. In normal mode only the nickname will be rendered.
-- If detailed mode the full user info including the username and hostname parts
-- will be rendered. The nickname will be colored.
coloredUserInfo :: RenderMode -> UserInfo -> Image
coloredUserInfo NormalRender ui = coloredIdentifier (userNick ui)
coloredUserInfo DetailedRender ui = horizCat
  [ coloredIdentifier (userNick ui)
  , foldMap (\user -> char defAttr '!' <|> text' quietAttr user) (userName ui)
  , foldMap (\host -> char defAttr '@' <|> text' quietAttr host) (userHost ui)
  ]

-- | Render an identifier without using colors. This is useful for metadata.
quietIdentifier :: Identifier -> Image
quietIdentifier ident =
  text' (withForeColor defAttr brightBlack) (idText ident)

-- | Parse message text to construct an image. If the text has formatting
-- control characters in it then the text will be rendered according to
-- the formatting codes. Otherwise the nicknames in the message are
-- highlighted.
parseIrcTextWithNicks :: [Identifier] -> Text -> Image
parseIrcTextWithNicks nicks txt
  | Text.any isControl txt = parseIrcText txt
  | otherwise              = highlightNicks nicks txt

-- | Given a list of nicknames and a chat message, this will generate
-- an image where all of the occurrences of those nicknames are colored.
highlightNicks :: [Identifier] -> Text -> Image
highlightNicks nicks txt = horizCat (highlight1 <$> txtParts)
  where
    nickSet = HashSet.fromList nicks
    txtParts = nickSplit txt
    highlight1 part
      | HashSet.member partId nickSet = coloredIdentifier partId
      | otherwise                     = text' defAttr part
      where
        partId = mkId part

-- | Returns image and identifier to be used when collapsing metadata
-- messages.
metadataImg :: IrcMsg -> Maybe (Image, Maybe Identifier)
metadataImg msg =
  case msg of
    Quit who _   -> Just (char (withForeColor defAttr red  ) 'x', Just (userNick who))
    Part who _ _ -> Just (char (withForeColor defAttr red  ) '-', Just (userNick who))
    Join who _   -> Just (char (withForeColor defAttr green) '+', Just (userNick who))
    Nick old new -> Just (quietIdentifier (userNick old) <|>
                          char (withForeColor defAttr yellow) '-' <|>
                          quietIdentifier new, Nothing)
    _            -> Nothing

-- | Image used when treating ignored chat messages as metadata
ignoreImage :: Image
ignoreImage = char (withForeColor defAttr yellow) 'I'