{-# LANGUAGE OverloadedStrings #-}

module Response (Response (..), ResponseType (..), send, parseResponseType) where

import ArgOptions
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List
import Data.Maybe
import Data.Time
import Duration
import GHC.Exts
import Table
import Task
import Worktime

data ResponseType
  = Json
  | Text
  deriving (Show, Read)

data Response
  = TasksResponse UTCTime [Task]
  | TaskResponse UTCTime Task
  | WtimeResponse UTCTime [DailyWorktime]
  | StatusResponse UTCTime (Maybe Task)
  | VersionResponse String
  | ContextResponse [Tag]
  | CommandResponse String String
  | MessageResponse String
  | ErrorResponse String

send :: ResponseType -> Response -> IO ()
send rtype (TasksResponse now tasks) = showTasks now rtype tasks
send rtype (TaskResponse now task) = showTask now rtype task
send rtype (WtimeResponse now wtimes) = showWtime now rtype wtimes
send rtype (StatusResponse now task) = showStatus now rtype task
send rtype (VersionResponse version) = showVersion rtype version
send rtype (ContextResponse ctx) = showContext rtype ctx
send rtype (CommandResponse cat action) = showCommandMsg rtype cat action
send rtype (MessageResponse msg) = showMessage rtype msg
send rtype (ErrorResponse msg) = showError rtype msg

-- Tasks

showTasks :: UTCTime -> ResponseType -> [Task] -> IO ()
showTasks now Text tasks = putStrLn $ showTasksText now tasks
showTasks now Json tasks = BL.putStr $ encode $ showTasksJson now tasks

showTasksText now tasks = render $ head : body
  where
    head = map (bold . underline . cell) ["ID", "DESC", "TAGS", "ACTIVE"]
    body = map rows tasks
    rows task =
      [ red $ cell $ getId task,
        cell $ getDesc task,
        blue $ cell $ unwords $ getTags task,
        green $ cell $ showApproxActiveRel now $ getActive task
      ]

showTasksJson :: UTCTime -> [Task] -> Data.Aeson.Value
showTasksJson now tasks =
  object
    [ "success" .= (1 :: Int),
      "tasks" .= (Array $ fromList $ map (showTaskJson now) tasks)
    ]

-- Task

showTask :: UTCTime -> ResponseType -> Task -> IO ()
showTask now Text task = putStrLn $ showTaskText now task
showTask now Json task = BL.putStr $ encode $ showTaskJson now task

showTaskText now task = render $ head : body
  where
    head = map (bold . underline . cell) ["KEY", "VALUE"]
    body =
      transpose
        [ map cell ["ID", "DESC", "TAGS", "ACTIVE"],
          [ red $ cell $ getId task,
            cell $ getDesc task,
            blue $ cell $ unwords $ getTags task,
            green $ cell $ showFullActiveRel now $ getActive task
          ]
        ]

showTaskJson :: UTCTime -> Task -> Data.Aeson.Value
showTaskJson now task =
  object
    [ "success" .= (1 :: Int),
      "task"
        .= object
          [ "id" .= getId task,
            "desc" .= getDesc task,
            "tags" .= getTags task,
            "active" .= showActiveJson now (getActive task),
            "done" .= if isNothing (getDone task) then 1 else 0 :: Int
          ]
    ]

-- Worktime

showWtime :: UTCTime -> ResponseType -> [DailyWorktime] -> IO ()
showWtime now Text dwtimes = putStrLn $ showDailyWtimeText now dwtimes
showWtime now Json dwtimes = BL.putStr $ encode $ Array $ fromList $ map (showDailyWtimeJson now) dwtimes

showDailyWtimeText :: UTCTime -> [DailyWorktime] -> String
showDailyWtimeText now dwtimes = render $ head : body ++ foot
  where
    head = map (underline . bold . cell) ["DATE", "WORKTIME"]
    body = map rows dwtimes
    foot =
      [ replicate 2 $ ext 8 . cell $ replicate 3 '-',
        [bold . cell $ "TOTAL RAW", bold . cell $ showFullDuration total],
        [bold . cell $ "TOTAL WDAY", bold . cell $ showFullDuration (total * 3.2)]
      ]
    rows dwtime = [cell $ fst dwtime, yellow $ cell $ showFullDuration $ sum $ map getWtimeDuration $ snd dwtime]
    total = sum $ map getWtimeDuration $ concatMap snd dwtimes

showDailyWtimeJson :: UTCTime -> DailyWorktime -> Data.Aeson.Value
showDailyWtimeJson now (day, wtimes) =
  object
    [ "success" .= (1 :: Int),
      "worktime"
        .= object
          [ "day" .= day,
            "total" .= showWtimesJson wtimes
          ]
    ]

-- Status

showStatus :: UTCTime -> ResponseType -> Maybe Task -> IO ()
showStatus now Text task = putStrLn $ showStatusText now task
showStatus now Json task = BL.putStr $ encode $ showStatusJson now task

showStatusJson :: UTCTime -> Maybe Task -> Maybe Data.Aeson.Value
showStatusJson now = fmap showStatusJson'
  where
    showStatusJson' task =
      object
        [ "desc" .= getDesc task,
          "active" .= showActiveJson now (getActive task)
        ]

showStatusText :: UTCTime -> Maybe Task -> String
showStatusText now task = case task of
  Nothing -> ""
  Just task -> getDesc task ++ ": " ++ showApproxActiveRel now (getActive task)

-- Version

showVersion :: ResponseType -> String -> IO ()
showVersion Text version = putStrLn $ showVersionText version
showVersion Json version = BL.putStr $ encode $ showVersionJson version

showVersionJson :: String -> Data.Aeson.Value
showVersionJson version = object ["version" .= version]

showVersionText :: String -> String
showVersionText version = version

-- Context

showContext :: ResponseType -> [Tag] -> IO ()
showContext rtype ctx = case rtype of
  Json -> BL.putStr $ encode $ showMessageJson plainMsg
  Text -> putStrLn styledMsg
  where
    plainMsg
      | null ctx = "Context cleared"
      | otherwise = "Context updated [" ++ intercalate ", " ctx ++ "]"
    styledMsg
      | null ctx = "Context \x1b[31mcleared\x1b[0m"
      | otherwise = "Context \x1b[32mupdated\x1b[0m [\x1b[34m" ++ intercalate "\x1b[0m, \x1b[34m" ctx ++ "\x1b[0m]"

-- Command message

showCommandMsg :: ResponseType -> String -> String -> IO ()
showCommandMsg Text cat action = putStrLn $ showCommandMsgText cat action
showCommandMsg Json cat action = BL.putStr $ encode $ showCommandMsgJson cat action

showCommandMsgText :: String -> String -> String
showCommandMsgText cat "created" = cat ++ " \x1b[32mcreated\x1b[0m"
showCommandMsgText cat "updated" = cat ++ " \x1b[34mupdated\x1b[0m"
showCommandMsgText cat "started" = cat ++ " \x1b[33mstarted\x1b[0m"
showCommandMsgText cat "stopped" = cat ++ " \x1b[31mstopped\x1b[0m"
showCommandMsgText cat "done" = cat ++ " \x1b[35mdone\x1b[0m"
showCommandMsgText cat "undone" = cat ++ " \x1b[36mundone\x1b[0m"
showCommandMsgText cat "deleted" = cat ++ " \x1b[31mdeleted\x1b[0m"
showCommandMsgText cat action = unwords [cat, action]

showCommandMsgJson :: String -> String -> Data.Aeson.Value
showCommandMsgJson cat action =
  object
    [ "success" .= (1 :: Int),
      "message" .= (cat ++ action)
    ]

-- Message

showMessage :: ResponseType -> String -> IO ()
showMessage rtype msg = case rtype of
  Json -> BL.putStr $ encode $ showMessageJson msg
  Text -> putStrLn msg

showMessageJson :: String -> Data.Aeson.Value
showMessageJson msg =
  object
    [ "success" .= (1 :: Int),
      "message" .= msg
    ]

-- Error

showError :: ResponseType -> String -> IO ()
showError rtype msg = case rtype of
  Json -> BL.putStr $ encode $ showErrorJson msg
  Text -> putStrLn $ showErrorText msg

showErrorJson :: String -> Data.Aeson.Value
showErrorJson msg =
  object
    [ "success" .= (0 :: Int),
      "message" .= ("Error: " ++ msg)
    ]

showErrorText :: String -> String
showErrorText msg = "\x1b[31mError: " ++ msg ++ "\x1b[0m"

-- Helpers

showMicroActive :: UTCTime -> Active -> Duration
showMicroActive _ Nothing = 0
showMicroActive now (Just active) = realToFrac $ diffUTCTime active now

showApproxActiveRel :: UTCTime -> Active -> String
showApproxActiveRel _ Nothing = ""
showApproxActiveRel now (Just active) = showApproxDurationRel $ showMicroActive now (Just active)

showFullActiveRel :: UTCTime -> Active -> String
showFullActiveRel _ Nothing = ""
showFullActiveRel now (Just active) = showFullDurationRel $ showMicroActive now (Just active)

showDurationJson :: Duration -> String -> String -> Data.Aeson.Value
showDurationJson micro approx full =
  object
    [ "micro" .= micro,
      "approx" .= approx,
      "full" .= full
    ]

showActiveJson :: UTCTime -> Active -> Maybe Data.Aeson.Value
showActiveJson _ Nothing = Nothing
showActiveJson now active = Just $ showDurationJson micro approx full
  where
    micro = showMicroActive now active
    approx = showApproxActiveRel now active
    full = showFullActiveRel now active

showWtimesJson :: [Worktime] -> Data.Aeson.Value
showWtimesJson wtimes = showDurationJson micro approx full
  where
    micro = sum $ map getWtimeDuration wtimes
    approx = showApproxDuration micro
    full = showFullDuration micro

parseResponseType :: JsonOpt -> ResponseType
parseResponseType True = Json
parseResponseType False = Text
