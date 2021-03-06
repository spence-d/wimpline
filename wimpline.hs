import System.Environment
import System.Directory
import Data.List
import Data.String
import Text.Printf

data Config = Config {
    rightSide :: Bool,
    padding :: Int,
    divider :: Maybe String,
    columns :: Maybe Int
} deriving (Show)

data Env = Env {
    cwd :: String,
    home :: String,
    ssh :: Bool
}

defaultConfig = Config { rightSide = False,
                         padding = 1,
                         divider = Nothing,
                         columns = Nothing }
                 

data SegmentConfig = SegmentConfig { background1 :: String,
                                     background2 :: String,
                                     foreground1 :: Maybe String,
                                     foreground2 :: Maybe String,
                                     alwaysShown :: Bool,
                                     width :: Maybe Int,
                                     bold :: Bool,
                                     short :: Bool } deriving (Show)

defaultSegmentConfig = SegmentConfig { background1 = "16",
                                       background2 = "16",
                                       foreground1 = Nothing,
                                       foreground2 = Nothing,
                                       alwaysShown = False,
                                       width = Nothing,
                                       bold = False,
                                       short = False }

data Segment = StrSegment String SegmentConfig
             | Path (Maybe Int) SegmentConfig
             | ViMode String SegmentConfig
             | ExitCode Int SegmentConfig
             | Hostname (Maybe String) SegmentConfig
             | Duration (Maybe Double) SegmentConfig
             | Condition String Segment Segment
             | Empty SegmentConfig deriving (Show)

--Process arguments that modify the previous segment's configuration
processSegmentConfig :: SegmentConfig -> Char -> String -> SegmentConfig
processSegmentConfig config flag arg =
    case flag of 's' -> config { alwaysShown = True }
                 'b' -> config { bold = True }
                 'k' -> config { background1 = arg }
                 'K' -> config { background2 = arg }
                 'f' -> config { foreground1 = Just arg }
                 'F' -> config { foreground2 = Just arg }
                 'w' -> config { width = Just (read arg :: Int) }

background :: Segment -> String
background (StrSegment _ SegmentConfig {background1 = bg}) = bg
background (Path _ SegmentConfig {background1 = bg}) = bg
background (ViMode mode SegmentConfig {background1 = bg1, background2 = bg2}) =
    if insertMode mode then bg2 else bg1
background (ExitCode code SegmentConfig {background1 = bg1, background2 = bg2}) =
    if code == 0 then bg1 else bg2
background (Hostname _ SegmentConfig {background1 = bg}) = bg
background (Duration _ SegmentConfig {background1 = bg}) = bg
background (Empty SegmentConfig {background1 = bg}) = bg

foreground :: Segment -> Maybe String
foreground (StrSegment _ SegmentConfig {foreground1 = fg}) = fg
foreground (Path _ SegmentConfig {foreground1 = fg}) = fg
foreground (ViMode mode SegmentConfig {foreground1 = fg1, foreground2 = fg2}) =
    if insertMode mode then fg2 else fg1
foreground (ExitCode code SegmentConfig {foreground1 = fg1, foreground2 = fg2}) =
    if code == 0 then fg2 else fg1
foreground (Hostname _ SegmentConfig {foreground1 = fg}) = fg
foreground (Duration _ SegmentConfig {foreground1 = fg}) = fg
foreground (Empty SegmentConfig {foreground1 = fg}) = fg

colorForeground :: Maybe String -> String -> String
colorForeground f string =
    case f of Just color -> "%F{" ++ color ++ "}" ++ string ++ "%f"
              Nothing    -> string

bolden :: Bool -> String -> String
bolden b string =
    if b then "%B" ++ string ++ "%b" else string

insertMode :: String -> Bool
insertMode "vicmd" = False
insertMode _ = True

viModeMsg :: String -> String
viModeMsg mode
    | insertMode mode = "INSERT"
    | otherwise       = "NORMAL"

exitMsg :: Int -> String
exitMsg 0 = "OK"
exitMsg 1 = "ERROR"
exitMsg 2 = "USAGE"

exitMsg 64 = "EX_USAGE"
exitMsg 65 = "EX_DATAERR"
exitMsg 66 = "EX_NOINPUT"
exitMsg 67 = "EX_NOUSER"
exitMsg 68 = "EX_NOHOST"
exitMsg 69 = "EX_UNAVAILABLE"
exitMsg 70 = "EX_SOFTWARE"
exitMsg 71 = "EX_OSERR"
exitMsg 72 = "EX_OSFILE"
exitMsg 73 = "EX_CANTCREAT"
exitMsg 74 = "EX_IOERR"
exitMsg 75 = "EX_TEMPFAIL"
exitMsg 76 = "EX_PROTOCOL"
exitMsg 77 = "EX_NOPERM"
exitMsg 78 = "EX_CONFIG"

exitMsg 126 = "NOPERM"
exitMsg 127 = "NOTFOUND"
exitMsg 128 = "BADERR"

exitMsg 129 = "SIGHUP"
exitMsg 130 = "SIGINT"
exitMsg 131 = "SIGQUIT"
exitMsg 132 = "SIGILL"
exitMsg 133 = "SIGTRAP"
exitMsg 134 = "SIGABRT"
exitMsg 135 = "SIGEMT"
exitMsg 136 = "SIGFPE"
exitMsg 137 = "SIGKILL"
exitMsg 138 = "SIGBUS"
exitMsg 139 = "SIGSEGV"
exitMsg 140 = "SIGSYS"
exitMsg 141 = "SIGPIPE"
exitMsg 142 = "SIGALRM"
exitMsg 143 = "SIGTERM"
exitMsg 144 = "SIGURG"
exitMsg 145 = "SIGSTOP"
exitMsg 146 = "SIGTSTP"
exitMsg 147 = "SIGCONT"
exitMsg 148 = "SIGCHLD"
exitMsg 149 = "SIGTTIN"
exitMsg 150 = "SIGTTOU"
exitMsg 151 = "SIGIO"
exitMsg 152 = "SIGXCPU"
exitMsg 153 = "SIGXFSZ"
exitMsg 154 = "SIGVTALRM"
exitMsg 155 = "SIGPROF"
exitMsg 156 = "SIGWINCH"
exitMsg 157 = "SIGINFO"
exitMsg 158 = "SIGUSR1"
exitMsg 159 = "SIGUSR2"

exitMsg 255 = "RANGE"

exitMsg code = show code

ellipseNodes :: Maybe Int -> [String] -> [String]
ellipseNodes (Just max) nodes =
    if size > max
    then (head nodes):"…":(drop (size - max + 1) nodes)
    else nodes
    where size = length nodes
ellipseNodes _ nodes = nodes

abbreviateNodes nodes = map abbreviate (init nodes) ++ [(last nodes)]
    where abbreviate str = if null str then str else [head str]

split :: Char -> String -> [String]
split sep str =  case dropWhile (==sep) str of
                         "" -> []
                         str' -> w : split sep str''
                                 where (w, str'') = break (==sep) str'

body :: Env -> Segment -> String
body _ (StrSegment string _) = string
body _ (ViMode mode SegmentConfig {short = short}) = if short then take 1 modeStr else modeStr
    where modeStr = viModeMsg mode
body Env {ssh = ssh } (Hostname (Just hostname) SegmentConfig {short = short, alwaysShown = shown}) =
    if shown || ssh
    then prefix ++ if short then takeWhile (/= '.') hostname else hostname
    else ""
    where prefix = if ssh then "\57506 " else ""
body Env {ssh = ssh } (Hostname _ SegmentConfig {short = short, alwaysShown = shown}) =
    if shown || ssh
    then prefix ++ if short then "%m" else "%M"
    else ""
    where prefix = if ssh then "\57506 " else ""
body _ (Duration (Just time) SegmentConfig {short = short, alwaysShown = shown}) =
    if time > 1.0 || shown
    then if short
         then show (floor time) ++ "s"
         else "\61463 " ++ printf "%.9f" time ++ "s"
    else ""
body _ (Duration Nothing SegmentConfig {short = short, alwaysShown = shown}) =
    ""
body _ (Condition condition _ _) = condition
body Env {cwd = cwd, home = home} (Path maxNodes SegmentConfig {short = short}) =
    if short
    then intercalate "/" $ abbreviateNodes ellipsedNodes
    else intercalate "/" ellipsedNodes
    where homeLength = length home
          path = if isPrefixOf home cwd
                 then "~" ++ drop homeLength cwd
                 else cwd
          nodes = split '/' path
          ellipsedNodes = ellipseNodes maxNodes nodes
body _ (ExitCode code SegmentConfig {alwaysShown = shown, short = short})
    | code == 0 && not shown = ""
    | short = show code
    | otherwise = exitMsg code
body _ (Empty _) = ""

chop :: Maybe Int -> (String, Int) -> (String, Int)
chop (Just width) (string, bodyWidth)
    | bodyWidth > width = (((take (width - 1) string) ++ "…"), width)
    | otherwise = (string, bodyWidth)
chop _ ret = ret

pad :: Maybe Int -> Int -> (String, Int) -> (String, Int)
pad (Just width) _ (string, bodyWidth)
    | bodyWidth == width = (string, width)
    | otherwise = (((padding left) ++ string ++ (padding right)), width)
    where num = width - bodyWidth
          left = num `div` 2
          right = num - left
          padding x = take x $ repeat ' '
pad Nothing num (string, bodyWidth)
    | null string = (string, num * 2)
    | otherwise = ((padding ++ string ++ padding), bodyWidth + (num * 2))
    where padding = take num $ repeat ' '

format :: Bool -> Maybe String -> (String, Int) -> (String, Int)
format bold foreground (string, width) =
    ((bolden bold $ colorForeground foreground string), width)

draw :: Env -> Bool -> Bool -> String -> Int -> Segment -> (String, Int)
draw env dir skipDivider divider padding (Condition condition first second) =
    ("%(" ++ condition ++ "." ++ firstStr ++ "." ++ secondStr ++ ")", width)
    where drawSegment = draw env dir skipDivider divider padding
          (firstStr, firstWidth) = if visible env first
                                   then drawSegment first
                                   else ("", 0)
          (secondStr, secondWidth) = if visible env second
                                     then drawSegment second
                                     else ("", 0)
          width = if firstWidth > secondWidth then firstWidth else secondWidth
draw env reverse skipDivider divider padding segment
    | reverse = ("%F{" ++ bg ++ "}" ++ divider ++ "%f%K{" ++ bg ++ "}" ++ body'', (width'' + (length divider)))
    | otherwise = ("%K{" ++ bg ++ "}" ++ div ++ "%f" ++ body'' ++ "%F{" ++ bg ++ "}%k", (width'' + (length div)))
    where bg = background segment
          fg = foreground segment
          config = getSegmentConfig segment
          b = bold config
          expectedWidth = width config
          body' = body env segment
          width' = length body'
          (body'', width'') = pad expectedWidth padding $ format b fg $ chop expectedWidth $ (body', width')
          div = if skipDivider then "" else divider

--Extract config from a segment
getSegmentConfig :: Segment -> SegmentConfig
getSegmentConfig (StrSegment _ c) = c
getSegmentConfig (Path _ c) = c
getSegmentConfig (ViMode _ c) = c
getSegmentConfig (ExitCode _ c) = c
getSegmentConfig (Hostname _ c) = c
getSegmentConfig (Duration _ c) = c
getSegmentConfig (Empty c) = c

--Create a segment with updated config
setSegmentConfig :: Segment -> SegmentConfig -> Segment
setSegmentConfig (StrSegment x _) c = StrSegment x c
setSegmentConfig (Path x _) c = Path x c
setSegmentConfig (ViMode x _) c = ViMode x c
setSegmentConfig (ExitCode x _) c = ExitCode x c
setSegmentConfig (Hostname x _) c = Hostname x c
setSegmentConfig (Duration x _) c = Duration x c
setSegmentConfig (Empty _) c = Empty c

--Process list of segments with their configurations
processSegments :: Env -> [String] -> ([Segment], Maybe Segment, [Segment])
processSegments _ [] = ([], Nothing, [])
processSegments env (('-':flag:arg):args) =
    case flag of 'h' -> ((Hostname (if null arg
                                   then Nothing
                                   else Just arg) defaultSegmentConfig { short = True }):left, middle, right)
                 'H' -> ((Hostname (if null arg
                                   then Nothing
                                   else Just arg) defaultSegmentConfig):left, middle, right)
                 'x' -> ((ExitCode (read arg :: Int) defaultSegmentConfig { short = True }):left, middle, right)
                 'X' -> ((ExitCode (read arg :: Int) defaultSegmentConfig):left, middle, right)
                 'v' -> ((ViMode arg defaultSegmentConfig { short = True }):left, middle, right)
                 'V' -> ((ViMode arg defaultSegmentConfig):left, middle, right)
                 't' -> ((Duration (if null arg
                                   then Nothing
                                   else Just (read arg :: Double)) defaultSegmentConfig { short = True }):left, middle, right)
                 'T' -> ((Duration (if null arg
                                   then Nothing
                                   else Just (read arg :: Double)) defaultSegmentConfig):left, middle, right)
                 '0' -> ((Empty defaultSegmentConfig):left, middle, right)
                 'd' -> ((Path (if null arg
                               then Nothing
                               else Just (read arg :: Int)) defaultSegmentConfig { short = True }):left, middle, right)
                 'D' -> ((Path (if null arg
                               then Nothing
                               else Just (read arg :: Int)) defaultSegmentConfig):left, middle, right)
                 'o' -> let (first:second:rest) = left
                        in if visible env first then (first:rest, middle, right) else (second:rest, middle, right)
                 'c' -> let (first:second:rest) = left
                        in ((Condition arg first second):rest, middle, right)
                 'p' -> let (segment:rest) = left
                        in ([], Just segment, rest)
                 _   -> let (segment:rest) = left
                            config = getSegmentConfig segment
                            updatedConfig = processSegmentConfig config flag arg
                        in ((setSegmentConfig segment updatedConfig):rest, middle, right)
    where (left, middle, right) = processSegments env args
processSegments env (arg:args) = ((StrSegment arg defaultSegmentConfig):left, middle, right)
    where (left, middle, right) = processSegments env args

--Process list of arguments until -- and pass off to processSegments
processArgs :: Env -> [String] -> (Config, ([Segment], Maybe Segment, [Segment]))
processArgs _ [] = (defaultConfig, ([], Nothing, []))

processArgs env ("--":xs) = (defaultConfig, processSegments env xs)

processArgs env (('-':flag:arg):xs) =
    case flag of 'r' -> (retConf { rightSide = True }, retSeg)
                 'p' -> (retConf { padding = read arg :: Int }, retSeg)
                 'w' -> (retConf { columns = Just (read arg :: Int) }, retSeg)
                 'd' -> (retConf { divider = Just arg }, retSeg)
    where (retConf, retSeg) = processArgs env xs

processArgs env (x:xs) = processArgs env xs

visible :: Env -> Segment -> Bool
visible _ (Empty _) = True
visible env segment = not $ null $ body env segment

border :: Config -> String
border Config {divider = divider, rightSide = reverse} =
    case divider of Just d    -> --TODO make this work for headers
                        if length d == 1 && head d >= '\57520' && head d <= '\57537'
                        then [succ $ succ (head d)]
                        else d
                    otherwise -> if reverse then "\57522" else "\57520"

prompt :: Env -> (Config, [Segment]) -> (String, Maybe Int)
prompt env (config, segments) =
    foldl concatSegments ("", columns) shownSegments
    where shownSegments = filter (visible env) segments
          Config {padding = padding, divider = divider,
                  rightSide = reverse, columns = columns} = config
          concatSegments (buf, Nothing) segment = (buf ++ body,
                                                   Nothing)
              where pad = case segment of Empty _ -> 0
                                          otherwise -> padding
                    (body, width) = draw env reverse (null buf) (border config) pad segment
          concatSegments (buf, Just colsLeft) segment = if adjustedCols >= 0
                                                        then (buf ++ body,
                                                              Just adjustedCols)
                                                        else (buf, Just colsLeft)
              where adjustedCols = colsLeft - width
                    pad = case segment of Empty _ -> 0
                                          otherwise -> padding
                    (body, width) = draw env reverse (null buf) (border config) pad segment

line :: Env -> (Config, ([Segment], Maybe Segment, [Segment])) -> String
line env (config, (left, Just middle, right)) =
    left' ++ middle'' ++ "%K{" ++ bg ++ "}" ++ right' ++ "%k"
    where (left', leftLen) = prompt env (config, left)
          (right', rightLen) = prompt env (config {rightSide = True, columns = leftLen}, right)
          middleConfig = getSegmentConfig middle
          Just remainingCols = rightLen
          middle' = setSegmentConfig middle middleConfig {width = Just (remainingCols - 1)}
          middle'' = fst $ draw env False False (border config) 0 middle'
          bg = background middle
line env (config, (left, _, _)) = (fst $ prompt env (config, left)) ++ suffix
    where reverse = rightSide config
          suffix = if reverse then "%k" else (border config) ++ "%f "

main :: IO ()
main = do
    args <- getArgs
    cwd  <- getCurrentDirectory
    home <- getHomeDirectory
    sshClient <- lookupEnv "SSH_CONNECTION" --TODO display IPs
    let env = Env {cwd = cwd,
                   home = home,
                   ssh = (sshClient /= Nothing)}
        in putStr $ line env $ processArgs env args
