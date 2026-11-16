{-# LANGUAGE OverloadedStrings #-}

module Infrastructure.Database
    ( DbConfig(..)
    , DbPool(..)
    , DbEstado(..)
    , EstudanteRow(..)
    , ProfessorRow(..)
    , ConteudoRow(..)
    , PreRequisitoRow(..)
    , AtividadeRow(..)
    , RespostaRow(..)
    , DesempenhoRow(..)
    , ModeloRow(..)
    , RecomendacaoRow(..)
    , carregarConfigBanco
    , inicializarPool
    , fecharPool
    , executarSqlSeguro
      -- 1. Estudantes
    , criarEstudante
    , buscarEstudantePorId
    , buscarEstudantePorEmail
    , listarEstudantes
    , atualizarEstudante
    , removerEstudante
      -- 2. Professores
    , criarProfessor
    , buscarProfessorPorId
    , listarProfessores
    , atualizarProfessor
    , removerProfessor
      -- 3. Conteudos
    , criarConteudo
    , buscarConteudoPorId
    , listarConteudos
    , atualizarConteudo
    , removerConteudo
      -- 4. Pre-requisitos
    , adicionarPreRequisito
    , listarPreRequisitos
    , listarPreRequisitosPorConteudo
    , removerPreRequisito
      -- 5. Atividades
    , criarAtividade
    , buscarAtividadePorId
    , listarAtividades
    , listarAtividadesPorConteudo
    , atualizarAtividade
    , removerAtividade
      -- 6. Respostas
    , registrarRespostaDB
    , buscarRespostaPorId
    , listarRespostasPorEstudante
    , removerResposta
      -- 7. Desempenho
    , upsertDesempenho
    , buscarDesempenhoEstudanteConteudo
    , listarDesempenhoPorEstudante
    , removerDesempenho
      -- 8. Modelos
    , salvarModelo
    , buscarModeloAtivo
    , buscarModeloPorVersao
    , listarModelos
    , removerModelo
      -- 9. Recomendacoes
    , salvarRecomendacao
    , salvarRecomendacoesLote
    , listarRecomendacoesPorEstudante
    , removerRecomendacoesPorEstudante
    ) where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, readTVarIO, writeTVar)
import Control.Exception (IOException, try)
import Data.List (find, sortOn)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ord (Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)

data DbConfig = DbConfig
    { dbHost          :: String
    , dbPort          :: String
    , dbUser          :: String
    , dbPassword      :: String
    , dbName          :: String
    , dbDatabaseUrl   :: Maybe String
    , dbContainerName :: String
    } deriving (Show, Eq)

data EstudanteRow = EstudanteRow
    { estId           :: Int
    , estNome         :: Text
    , estEmail        :: Text
    , estDataCadastro :: UTCTime
    } deriving (Show, Eq)

data ProfessorRow = ProfessorRow
    { profId    :: Int
    , profNome  :: Text
    , profEmail :: Text
    } deriving (Show, Eq)

data ConteudoRow = ConteudoRow
    { contId        :: Int
    , contTitulo    :: Text
    , contDescricao :: Text
    , contCategoria :: Text
    , contNivel     :: Int
    } deriving (Show, Eq)

data PreRequisitoRow = PreRequisitoRow
    { prConteudoId     :: Int
    , prPreRequisitoId :: Int
    } deriving (Show, Eq)

data AtividadeRow = AtividadeRow
    { ativId          :: Int
    , ativConteudoId  :: Int
    , ativTitulo      :: Text
    , ativDescricao   :: Text
    , ativDificuldade :: Int
    } deriving (Show, Eq)

data RespostaRow = RespostaRow
    { respId             :: Int
    , respEstudanteId    :: Int
    , respAtividadeId    :: Int
    , respTexto          :: Text
    , respResultado      :: Bool
    , respTempoResolucao :: Maybe Int
    , respDataRealizacao :: UTCTime
    } deriving (Show, Eq)

data DesempenhoRow = DesempenhoRow
    { desId              :: Int
    , desEstudanteId     :: Int
    , desConteudoId      :: Int
    , desPontuacao       :: Double
    , desDataAtualizacao :: UTCTime
    } deriving (Show, Eq)

data ModeloRow = ModeloRow
    { modId              :: Int
    , modAlgoritmo       :: Text
    , modVersao          :: Text
    , modParametros      :: Text
    , modMetricas        :: Text
    , modDataTreinamento :: UTCTime
    } deriving (Show, Eq)

data RecomendacaoRow = RecomendacaoRow
    { recId                    :: Int
    , recEstudanteId           :: Int
    , recConteudoId            :: Int
    , recJustificativa         :: Text
    , recProbabilidadeEstimada :: Double
    , recDataRecomendacao      :: UTCTime
    } deriving (Show, Eq)

data DbEstado = DbEstado
    { stEstudantes    :: [EstudanteRow]
    , stProfessores   :: [ProfessorRow]
    , stConteudos     :: [ConteudoRow]
    , stPreRequisitos :: [PreRequisitoRow]
    , stAtividades    :: [AtividadeRow]
    , stRespostas     :: [RespostaRow]
    , stDesempenho    :: [DesempenhoRow]
    , stModelos       :: [ModeloRow]
    , stRecomendacoes :: [RecomendacaoRow]
    } deriving (Show, Eq)

data DbPool = DbPool
    { poolConfig :: DbConfig
    , poolEstado :: TVar DbEstado
    }

conteudosIniciais :: [ConteudoRow]
conteudosIniciais =
    [ ConteudoRow 1 "Adicao"        "Operacoes fundamentais de soma com numeros naturais."            "Operacoes Matematicas" 1
    , ConteudoRow 2 "Subtracao"     "Operacoes fundamentais de subtracao com numeros naturais."       "Operacoes Matematicas" 2
    , ConteudoRow 3 "Multiplicacao" "Operacoes de multiplicacao e compreensao de fatores e produtos." "Operacoes Matematicas" 3
    , ConteudoRow 4 "Divisao"       "Operacoes de divisao exata e com resto entre numeros naturais."  "Operacoes Matematicas" 4
    ]

preRequisitosIniciais :: [PreRequisitoRow]
preRequisitosIniciais =
    [ PreRequisitoRow 2 1
    , PreRequisitoRow 3 2
    , PreRequisitoRow 4 3
    ]

atividadesIniciais :: [AtividadeRow]
atividadesIniciais =
    [ AtividadeRow 1 1 "Soma Basica I"         "Calcule 14 + 27."   1
    , AtividadeRow 2 2 "Subtracao Basica I"    "Calcule 45 - 19."   2
    , AtividadeRow 3 3 "Multiplicacao Basica"  "Calcule 8 x 7."     3
    , AtividadeRow 4 4 "Divisao Exata I"       "Calcule 56 / 8."    4
    ]

estadoInicial :: DbEstado
estadoInicial = DbEstado
    { stEstudantes    = []
    , stProfessores   = []
    , stConteudos     = conteudosIniciais
    , stPreRequisitos = preRequisitosIniciais
    , stAtividades    = atividadesIniciais
    , stRespostas     = []
    , stDesempenho    = []
    , stModelos       = []
    , stRecomendacoes = []
    }

carregarConfigBanco :: IO DbConfig
carregarConfigBanco = do
    mUrl       <- lookupEnv "DATABASE_URL"
    mHost      <- lookupEnv "PGHOST"
    mPort      <- lookupEnv "PGPORT"
    mUser      <- lookupEnv "PGUSER"
    mPass      <- lookupEnv "PGPASSWORD"
    mDb        <- lookupEnv "PGDATABASE"
    mContainer <- lookupEnv "PGCONTAINER"
    let baseCfg = DbConfig
            { dbHost          = fromMaybe "localhost" mHost
            , dbPort          = fromMaybe "5432" mPort
            , dbUser          = fromMaybe "edumind_user" mUser
            , dbPassword      = fromMaybe "edumind_dev_password" mPass
            , dbName          = fromMaybe "edumind" mDb
            , dbDatabaseUrl   = mUrl
            , dbContainerName = fromMaybe "edumind-db" mContainer
            }
    pure $ case mUrl of
        Nothing  -> baseCfg
        Just url -> aplicarDatabaseUrl url baseCfg

aplicarDatabaseUrl :: String -> DbConfig -> DbConfig
aplicarDatabaseUrl url cfg =
    let semEsquema = case T.stripPrefix "postgresql://" (T.pack url) of
            Just rest -> rest
            Nothing   -> fromMaybe (T.pack url) (T.stripPrefix "postgres://" (T.pack url))
        (authPart, hostDbPart) = T.breakOn "@" semEsquema
        (usr, pwd) =
            if T.null hostDbPart
                then (T.pack (dbUser cfg), T.pack (dbPassword cfg))
                else
                    let (u, pComDoisPontos) = T.breakOn ":" authPart
                    in (u, T.drop 1 pComDoisPontos)
        resto = if T.null hostDbPart then semEsquema else T.drop 1 hostDbPart
        (hostPort, dbPart) = T.breakOn "/" resto
        (hst, prtComDoisPontos) = T.breakOn ":" hostPort
        prt = if T.null prtComDoisPontos then T.pack (dbPort cfg) else T.drop 1 prtComDoisPontos
        dbn = T.takeWhile (/= '?') (T.drop 1 dbPart)
    in cfg
        { dbUser     = if T.null usr then dbUser cfg else T.unpack usr
        , dbPassword = if T.null pwd then dbPassword cfg else T.unpack pwd
        , dbHost     = if T.null hst then dbHost cfg else T.unpack hst
        , dbPort     = if T.null prt then dbPort cfg else T.unpack prt
        , dbName     = if T.null dbn then dbName cfg else T.unpack dbn
        }

inicializarPool :: DbConfig -> IO DbPool
inicializarPool cfg = do
    tvar <- newTVarIO estadoInicial
    pure (DbPool cfg tvar)

fecharPool :: DbPool -> IO ()
fecharPool _ = pure ()

comEstado :: DbPool -> (DbEstado -> (DbEstado, a)) -> IO a
comEstado pool fn = atomically $ do
    st <- readTVar (poolEstado pool)
    let (st', res) = fn st
    writeTVar (poolEstado pool) st'
    pure res

escaparSql :: Text -> String
escaparSql txt =
    "'" ++ concatMap escaparChar (T.unpack (T.replace "\0" "" txt)) ++ "'"
  where
    escaparChar '\'' = "''"
    escaparChar c    = [c]

executarSqlSeguro :: DbConfig -> String -> IO (Either String String)
executarSqlSeguro cfg sql = do
    res <- try (readProcessWithExitCode "docker"
        [ "exec", "-i", dbContainerName cfg
        , "psql", "-v", "ON_ERROR_STOP=1"
        , "-U", dbUser cfg
        , "-d", dbName cfg
        , "-t", "-A"
        ] sql) :: IO (Either IOException (ExitCode, String, String))
    case res of
        Left ex                       -> pure (Left (show ex))
        Right (ExitSuccess, out, _)   -> pure (Right out)
        Right (ExitFailure _, _, err) -> pure (Left err)

proximoId :: (a -> Int) -> [a] -> Int
proximoId getId xs = if null xs then 1 else maximum (map getId xs) + 1

-- ============================================================
-- 1. Estudantes
-- ============================================================

criarEstudante :: DbPool -> Text -> Text -> IO (Either String EstudanteRow)
criarEstudante pool nome email = do
    agora <- getCurrentTime
    res <- comEstado pool $ \st ->
        case find (\e -> estEmail e == email) (stEstudantes st) of
            Just _ -> (st, Left "Ja existe um estudante cadastrado com este e-mail.")
            Nothing ->
                let novo = EstudanteRow (proximoId estId (stEstudantes st)) nome email agora
                in (st { stEstudantes = stEstudantes st ++ [novo] }, Right novo)
    case res of
        Left err -> pure (Left err)
        Right row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "INSERT INTO estudantes (id, nome, email) VALUES ("
                ++ show (estId row) ++ ", " ++ escaparSql nome ++ ", " ++ escaparSql email
                ++ ") ON CONFLICT (email) DO NOTHING; "
                ++ "SELECT setval('estudantes_id_seq', COALESCE((SELECT MAX(id) FROM estudantes), 1));"
            pure (Right row)

buscarEstudantePorId :: DbPool -> Int -> IO (Maybe EstudanteRow)
buscarEstudantePorId pool eid =
    find (\e -> estId e == eid) . stEstudantes <$> readTVarIO (poolEstado pool)

buscarEstudantePorEmail :: DbPool -> Text -> IO (Maybe EstudanteRow)
buscarEstudantePorEmail pool email =
    find (\e -> estEmail e == email) . stEstudantes <$> readTVarIO (poolEstado pool)

listarEstudantes :: DbPool -> IO [EstudanteRow]
listarEstudantes pool = stEstudantes <$> readTVarIO (poolEstado pool)

atualizarEstudante :: DbPool -> Int -> Text -> Text -> IO (Maybe EstudanteRow)
atualizarEstudante pool eid nome email = do
    mRow <- comEstado pool $ \st ->
        case find (\e -> estId e == eid) (stEstudantes st) of
            Nothing -> (st, Nothing)
            Just antigo ->
                let atualizado = antigo { estNome = nome, estEmail = email }
                    lista = map (\e -> if estId e == eid then atualizado else e) (stEstudantes st)
                in (st { stEstudantes = lista }, Just atualizado)
    case mRow of
        Nothing -> pure Nothing
        Just row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "UPDATE estudantes SET nome = " ++ escaparSql nome
                ++ ", email = " ++ escaparSql email
                ++ " WHERE id = " ++ show eid ++ ";"
            pure (Just row)

removerEstudante :: DbPool -> Int -> IO Bool
removerEstudante pool eid = do
    removido <- comEstado pool $ \st ->
        let antes = stEstudantes st
            depois = filter (\e -> estId e /= eid) antes
        in (st { stEstudantes = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM estudantes WHERE id = " ++ show eid ++ ";")
            pure True
        else pure False

-- ============================================================
-- 2. Professores
-- ============================================================

criarProfessor :: DbPool -> Text -> Text -> IO (Either String ProfessorRow)
criarProfessor pool nome email = do
    res <- comEstado pool $ \st ->
        case find (\p -> profEmail p == email) (stProfessores st) of
            Just _ -> (st, Left "Ja existe um professor cadastrado com este e-mail.")
            Nothing ->
                let novo = ProfessorRow (proximoId profId (stProfessores st)) nome email
                in (st { stProfessores = stProfessores st ++ [novo] }, Right novo)
    case res of
        Left err -> pure (Left err)
        Right row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "INSERT INTO professores (id, nome, email) VALUES ("
                ++ show (profId row) ++ ", " ++ escaparSql nome ++ ", " ++ escaparSql email
                ++ ") ON CONFLICT (email) DO NOTHING; "
                ++ "SELECT setval('professores_id_seq', COALESCE((SELECT MAX(id) FROM professores), 1));"
            pure (Right row)

buscarProfessorPorId :: DbPool -> Int -> IO (Maybe ProfessorRow)
buscarProfessorPorId pool pid =
    find (\p -> profId p == pid) . stProfessores <$> readTVarIO (poolEstado pool)

listarProfessores :: DbPool -> IO [ProfessorRow]
listarProfessores pool = stProfessores <$> readTVarIO (poolEstado pool)

atualizarProfessor :: DbPool -> Int -> Text -> Text -> IO (Maybe ProfessorRow)
atualizarProfessor pool pid nome email = do
    mRow <- comEstado pool $ \st ->
        case find (\p -> profId p == pid) (stProfessores st) of
            Nothing -> (st, Nothing)
            Just antigo ->
                let atualizado = antigo { profNome = nome, profEmail = email }
                    lista = map (\p -> if profId p == pid then atualizado else p) (stProfessores st)
                in (st { stProfessores = lista }, Just atualizado)
    case mRow of
        Nothing -> pure Nothing
        Just row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "UPDATE professores SET nome = " ++ escaparSql nome
                ++ ", email = " ++ escaparSql email
                ++ " WHERE id = " ++ show pid ++ ";"
            pure (Just row)

removerProfessor :: DbPool -> Int -> IO Bool
removerProfessor pool pid = do
    removido <- comEstado pool $ \st ->
        let antes = stProfessores st
            depois = filter (\p -> profId p /= pid) antes
        in (st { stProfessores = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM professores WHERE id = " ++ show pid ++ ";")
            pure True
        else pure False

-- ============================================================
-- 3. Conteudos
-- ============================================================

criarConteudo :: DbPool -> Text -> Text -> Text -> Int -> IO (Either String ConteudoRow)
criarConteudo pool titulo descricao categoria nivel = do
    res <- comEstado pool $ \st ->
        case find (\c -> contTitulo c == titulo) (stConteudos st) of
            Just _ -> (st, Left "Ja existe um conteudo com este titulo.")
            Nothing ->
                let novo = ConteudoRow (proximoId contId (stConteudos st)) titulo descricao categoria nivel
                in (st { stConteudos = stConteudos st ++ [novo] }, Right novo)
    case res of
        Left err -> pure (Left err)
        Right row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "INSERT INTO conteudos (id, titulo, descricao, categoria, nivel) VALUES ("
                ++ show (contId row) ++ ", " ++ escaparSql titulo ++ ", " ++ escaparSql descricao
                ++ ", " ++ escaparSql categoria ++ ", " ++ show nivel
                ++ ") ON CONFLICT (titulo) DO NOTHING; "
                ++ "SELECT setval('conteudos_id_seq', COALESCE((SELECT MAX(id) FROM conteudos), 1));"
            pure (Right row)

buscarConteudoPorId :: DbPool -> Int -> IO (Maybe ConteudoRow)
buscarConteudoPorId pool cid =
    find (\c -> contId c == cid) . stConteudos <$> readTVarIO (poolEstado pool)

listarConteudos :: DbPool -> IO [ConteudoRow]
listarConteudos pool = sortOn contNivel . stConteudos <$> readTVarIO (poolEstado pool)

atualizarConteudo :: DbPool -> Int -> Text -> Text -> Text -> Int -> IO (Maybe ConteudoRow)
atualizarConteudo pool cid titulo descricao categoria nivel = do
    mRow <- comEstado pool $ \st ->
        case find (\c -> contId c == cid) (stConteudos st) of
            Nothing -> (st, Nothing)
            Just antigo ->
                let atualizado = antigo
                        { contTitulo    = titulo
                        , contDescricao = descricao
                        , contCategoria = categoria
                        , contNivel     = nivel
                        }
                    lista = map (\c -> if contId c == cid then atualizado else c) (stConteudos st)
                in (st { stConteudos = lista }, Just atualizado)
    case mRow of
        Nothing -> pure Nothing
        Just row -> do
            _ <- executarSqlSeguro (poolConfig pool) $
                "UPDATE conteudos SET titulo = " ++ escaparSql titulo
                ++ ", descricao = " ++ escaparSql descricao
                ++ ", categoria = " ++ escaparSql categoria
                ++ ", nivel = " ++ show nivel
                ++ " WHERE id = " ++ show cid ++ ";"
            pure (Just row)

removerConteudo :: DbPool -> Int -> IO Bool
removerConteudo pool cid = do
    removido <- comEstado pool $ \st ->
        let antes = stConteudos st
            depois = filter (\c -> contId c /= cid) antes
            prLimpos = filter (\pr -> prConteudoId pr /= cid && prPreRequisitoId pr /= cid) (stPreRequisitos st)
        in (st { stConteudos = depois, stPreRequisitos = prLimpos }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM conteudos WHERE id = " ++ show cid ++ ";")
            pure True
        else pure False

-- ============================================================
-- 4. Pre-requisitos
-- ============================================================

adicionarPreRequisito :: DbPool -> Int -> Int -> IO (Either String PreRequisitoRow)
adicionarPreRequisito pool cid prereqId
    | cid == prereqId = pure (Left "Um conteudo nao pode ser pre-requisito de si mesmo.")
    | otherwise = do
        let rel = PreRequisitoRow cid prereqId
        adicionado <- comEstado pool $ \st ->
            if rel `elem` stPreRequisitos st
                then (st, False)
                else (st { stPreRequisitos = stPreRequisitos st ++ [rel] }, True)
        if adicionado
            then do
                _ <- executarSqlSeguro (poolConfig pool) $
                    "INSERT INTO pre_requisitos (conteudo_id, pre_requisito_id) VALUES ("
                    ++ show cid ++ ", " ++ show prereqId ++ ") ON CONFLICT DO NOTHING;"
                pure (Right rel)
            else pure (Right rel)

listarPreRequisitos :: DbPool -> IO [PreRequisitoRow]
listarPreRequisitos pool = stPreRequisitos <$> readTVarIO (poolEstado pool)

listarPreRequisitosPorConteudo :: DbPool -> Int -> IO [Int]
listarPreRequisitosPorConteudo pool cid =
    map prPreRequisitoId . filter (\pr -> prConteudoId pr == cid) . stPreRequisitos
        <$> readTVarIO (poolEstado pool)

removerPreRequisito :: DbPool -> Int -> Int -> IO Bool
removerPreRequisito pool cid prereqId = do
    removido <- comEstado pool $ \st ->
        let antes = stPreRequisitos st
            depois = filter (\pr -> not (prConteudoId pr == cid && prPreRequisitoId pr == prereqId)) antes
        in (st { stPreRequisitos = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) $
                "DELETE FROM pre_requisitos WHERE conteudo_id = " ++ show cid
                ++ " AND pre_requisito_id = " ++ show prereqId ++ ";"
            pure True
        else pure False

-- ============================================================
-- 5. Atividades
-- ============================================================

criarAtividade :: DbPool -> Int -> Text -> Text -> Int -> IO (Either String AtividadeRow)
criarAtividade pool cid titulo descricao dificuldade
    | dificuldade < 1 || dificuldade > 5 =
        pure (Left "A dificuldade da atividade deve estar entre 1 e 5.")
    | otherwise = do
        res <- comEstado pool $ \st ->
            case find (\c -> contId c == cid) (stConteudos st) of
                Nothing -> (st, Left "Conteudo associado nao encontrado.")
                Just _ ->
                    let nova = AtividadeRow (proximoId ativId (stAtividades st)) cid titulo descricao dificuldade
                    in (st { stAtividades = stAtividades st ++ [nova] }, Right nova)
        case res of
            Left err -> pure (Left err)
            Right row -> do
                _ <- executarSqlSeguro (poolConfig pool) $
                    "INSERT INTO atividades (id, conteudo_id, titulo, descricao, dificuldade) VALUES ("
                    ++ show (ativId row) ++ ", " ++ show cid ++ ", " ++ escaparSql titulo
                    ++ ", " ++ escaparSql descricao ++ ", " ++ show dificuldade ++ "); "
                    ++ "SELECT setval('atividades_id_seq', COALESCE((SELECT MAX(id) FROM atividades), 1));"
                pure (Right row)

buscarAtividadePorId :: DbPool -> Int -> IO (Maybe AtividadeRow)
buscarAtividadePorId pool aid =
    find (\a -> ativId a == aid) . stAtividades <$> readTVarIO (poolEstado pool)

listarAtividades :: DbPool -> IO [AtividadeRow]
listarAtividades pool = stAtividades <$> readTVarIO (poolEstado pool)

listarAtividadesPorConteudo :: DbPool -> Int -> IO [AtividadeRow]
listarAtividadesPorConteudo pool cid =
    filter (\a -> ativConteudoId a == cid) . stAtividades <$> readTVarIO (poolEstado pool)

atualizarAtividade :: DbPool -> Int -> Text -> Text -> Int -> IO (Maybe AtividadeRow)
atualizarAtividade pool aid titulo descricao dificuldade
    | dificuldade < 1 || dificuldade > 5 = pure Nothing
    | otherwise = do
        mRow <- comEstado pool $ \st ->
            case find (\a -> ativId a == aid) (stAtividades st) of
                Nothing -> (st, Nothing)
                Just antiga ->
                    let atualizada = antiga
                            { ativTitulo      = titulo
                            , ativDescricao   = descricao
                            , ativDificuldade = dificuldade
                            }
                        lista = map (\a -> if ativId a == aid then atualizada else a) (stAtividades st)
                    in (st { stAtividades = lista }, Just atualizada)
        case mRow of
            Nothing -> pure Nothing
            Just row -> do
                _ <- executarSqlSeguro (poolConfig pool) $
                    "UPDATE atividades SET titulo = " ++ escaparSql titulo
                    ++ ", descricao = " ++ escaparSql descricao
                    ++ ", dificuldade = " ++ show dificuldade
                    ++ " WHERE id = " ++ show aid ++ ";"
                pure (Just row)

removerAtividade :: DbPool -> Int -> IO Bool
removerAtividade pool aid = do
    removido <- comEstado pool $ \st ->
        let antes = stAtividades st
            depois = filter (\a -> ativId a /= aid) antes
        in (st { stAtividades = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM atividades WHERE id = " ++ show aid ++ ";")
            pure True
        else pure False

-- ============================================================
-- 6. Respostas
-- ============================================================

registrarRespostaDB :: DbPool -> Int -> Int -> Text -> Bool -> Maybe Int -> IO (Either String RespostaRow)
registrarRespostaDB pool eid aid textoResultado acertou mTempo = do
    agora <- getCurrentTime
    res <- comEstado pool $ \st ->
        case (find (\e -> estId e == eid) (stEstudantes st), find (\a -> ativId a == aid) (stAtividades st)) of
            (Nothing, _) -> (st, Left "Estudante nao encontrado.")
            (_, Nothing) -> (st, Left "Atividade nao encontrada.")
            (Just _, Just _) ->
                let nova = RespostaRow (proximoId respId (stRespostas st)) eid aid textoResultado acertou mTempo agora
                in (st { stRespostas = stRespostas st ++ [nova] }, Right nova)
    case res of
        Left err -> pure (Left err)
        Right row -> do
            let tempoSql = maybe "NULL" show mTempo
                boolSql  = if acertou then "TRUE" else "FALSE"
            _ <- executarSqlSeguro (poolConfig pool) $
                "INSERT INTO respostas (id, estudante_id, atividade_id, resposta, resultado, tempo_resolucao) VALUES ("
                ++ show (respId row) ++ ", " ++ show eid ++ ", " ++ show aid ++ ", "
                ++ escaparSql textoResultado ++ ", " ++ boolSql ++ ", " ++ tempoSql ++ "); "
                ++ "SELECT setval('respostas_id_seq', COALESCE((SELECT MAX(id) FROM respostas), 1));"
            pure (Right row)

buscarRespostaPorId :: DbPool -> Int -> IO (Maybe RespostaRow)
buscarRespostaPorId pool rid =
    find (\r -> respId r == rid) . stRespostas <$> readTVarIO (poolEstado pool)

listarRespostasPorEstudante :: DbPool -> Int -> IO [RespostaRow]
listarRespostasPorEstudante pool eid =
    sortOn (\r -> (Down (respDataRealizacao r), Down (respId r)))
        . filter (\r -> respEstudanteId r == eid)
        . stRespostas
        <$> readTVarIO (poolEstado pool)

removerResposta :: DbPool -> Int -> IO Bool
removerResposta pool rid = do
    removido <- comEstado pool $ \st ->
        let antes = stRespostas st
            depois = filter (\r -> respId r /= rid) antes
        in (st { stRespostas = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM respostas WHERE id = " ++ show rid ++ ";")
            pure True
        else pure False

-- ============================================================
-- 7. Desempenho
-- ============================================================

upsertDesempenho :: DbPool -> Int -> Int -> Double -> IO DesempenhoRow
upsertDesempenho pool eid cid pontuacao = do
    agora <- getCurrentTime
    let pontuacaoLimitada = max 0.0 (min 100.0 pontuacao)
    row <- comEstado pool $ \st ->
        case find (\d -> desEstudanteId d == eid && desConteudoId d == cid) (stDesempenho st) of
            Nothing ->
                let novo = DesempenhoRow (proximoId desId (stDesempenho st)) eid cid pontuacaoLimitada agora
                in (st { stDesempenho = stDesempenho st ++ [novo] }, novo)
            Just antigo ->
                let atualizado = antigo { desPontuacao = pontuacaoLimitada, desDataAtualizacao = agora }
                    lista = map (\d -> if desId d == desId antigo then atualizado else d) (stDesempenho st)
                in (st { stDesempenho = lista }, atualizado)
    _ <- executarSqlSeguro (poolConfig pool) $
        "INSERT INTO desempenho (id, estudante_id, conteudo_id, pontuacao, data_atualizacao) VALUES ("
        ++ show (desId row) ++ ", " ++ show eid ++ ", " ++ show cid ++ ", " ++ show pontuacaoLimitada ++ ", NOW()) "
        ++ "ON CONFLICT (estudante_id, conteudo_id) DO UPDATE SET "
        ++ "pontuacao = EXCLUDED.pontuacao, data_atualizacao = EXCLUDED.data_atualizacao; "
        ++ "SELECT setval('desempenho_id_seq', COALESCE((SELECT MAX(id) FROM desempenho), 1));"
    pure row

buscarDesempenhoEstudanteConteudo :: DbPool -> Int -> Int -> IO (Maybe DesempenhoRow)
buscarDesempenhoEstudanteConteudo pool eid cid =
    find (\d -> desEstudanteId d == eid && desConteudoId d == cid) . stDesempenho
        <$> readTVarIO (poolEstado pool)

listarDesempenhoPorEstudante :: DbPool -> Int -> IO [DesempenhoRow]
listarDesempenhoPorEstudante pool eid =
    filter (\d -> desEstudanteId d == eid) . stDesempenho <$> readTVarIO (poolEstado pool)

removerDesempenho :: DbPool -> Int -> Int -> IO Bool
removerDesempenho pool eid cid = do
    removido <- comEstado pool $ \st ->
        let antes = stDesempenho st
            depois = filter (\d -> not (desEstudanteId d == eid && desConteudoId d == cid)) antes
        in (st { stDesempenho = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) $
                "DELETE FROM desempenho WHERE estudante_id = " ++ show eid ++ " AND conteudo_id = " ++ show cid ++ ";"
            pure True
        else pure False

-- ============================================================
-- 8. Modelos
-- ============================================================

salvarModelo :: DbPool -> Text -> Text -> Text -> Text -> IO ModeloRow
salvarModelo pool algoritmo versao parametrosJson metricasJson = do
    agora <- getCurrentTime
    row <- comEstado pool $ \st ->
        let novo = ModeloRow (proximoId modId (stModelos st)) algoritmo versao parametrosJson metricasJson agora
            semMesmaVersao = filter (\m -> modVersao m /= versao) (stModelos st)
        in (st { stModelos = semMesmaVersao ++ [novo] }, novo)
    _ <- executarSqlSeguro (poolConfig pool) $
        "INSERT INTO modelos (id, algoritmo, versao, parametros, metricas) VALUES ("
        ++ show (modId row) ++ ", " ++ escaparSql algoritmo ++ ", " ++ escaparSql versao
        ++ ", " ++ escaparSql parametrosJson ++ "::jsonb, " ++ escaparSql metricasJson ++ "::jsonb) "
        ++ "ON CONFLICT (versao) DO UPDATE SET "
        ++ "algoritmo = EXCLUDED.algoritmo, parametros = EXCLUDED.parametros, "
        ++ "metricas = EXCLUDED.metricas, data_treinamento = NOW(); "
        ++ "SELECT setval('modelos_id_seq', COALESCE((SELECT MAX(id) FROM modelos), 1));"
    pure row

buscarModeloAtivo :: DbPool -> IO (Maybe ModeloRow)
buscarModeloAtivo pool =
    listToMaybe . sortOn (\m -> (Down (modDataTreinamento m), Down (modId m))) . stModelos
        <$> readTVarIO (poolEstado pool)

buscarModeloPorVersao :: DbPool -> Text -> IO (Maybe ModeloRow)
buscarModeloPorVersao pool versao =
    find (\m -> modVersao m == versao) . stModelos <$> readTVarIO (poolEstado pool)

listarModelos :: DbPool -> IO [ModeloRow]
listarModelos pool =
    sortOn (\m -> (Down (modDataTreinamento m), Down (modId m))) . stModelos
        <$> readTVarIO (poolEstado pool)

removerModelo :: DbPool -> Text -> IO Bool
removerModelo pool versao = do
    removido <- comEstado pool $ \st ->
        let antes = stModelos st
            depois = filter (\m -> modVersao m /= versao) antes
        in (st { stModelos = depois }, length depois < length antes)
    if removido
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM modelos WHERE versao = " ++ escaparSql versao ++ ";")
            pure True
        else pure False

-- ============================================================
-- 9. Recomendacoes
-- ============================================================

salvarRecomendacao :: DbPool -> Int -> Int -> Text -> Double -> IO RecomendacaoRow
salvarRecomendacao pool eid cid justificativa prob = do
    agora <- getCurrentTime
    let probLimitada = max 0.0 (min 1.0 prob)
    row <- comEstado pool $ \st ->
        let nova = RecomendacaoRow (proximoId recId (stRecomendacoes st)) eid cid justificativa probLimitada agora
        in (st { stRecomendacoes = stRecomendacoes st ++ [nova] }, nova)
    _ <- executarSqlSeguro (poolConfig pool) $
        "INSERT INTO recomendacoes (id, estudante_id, conteudo_id, justificativa, probabilidade_estimada) VALUES ("
        ++ show (recId row) ++ ", " ++ show eid ++ ", " ++ show cid ++ ", "
        ++ escaparSql justificativa ++ ", " ++ show probLimitada ++ "); "
        ++ "SELECT setval('recomendacoes_id_seq', COALESCE((SELECT MAX(id) FROM recomendacoes), 1));"
    pure row

salvarRecomendacoesLote :: DbPool -> Int -> [(Int, Text, Double)] -> IO [RecomendacaoRow]
salvarRecomendacoesLote pool eid itens =
    mapM (\(cid, just, prob) -> salvarRecomendacao pool eid cid just prob) itens

listarRecomendacoesPorEstudante :: DbPool -> Int -> IO [RecomendacaoRow]
listarRecomendacoesPorEstudante pool eid =
    sortOn (\r -> (Down (recDataRecomendacao r), Down (recId r)))
        . filter (\r -> recEstudanteId r == eid)
        . stRecomendacoes
        <$> readTVarIO (poolEstado pool)

removerRecomendacoesPorEstudante :: DbPool -> Int -> IO Int
removerRecomendacoesPorEstudante pool eid = do
    removidos <- comEstado pool $ \st ->
        let antes = stRecomendacoes st
            depois = filter (\r -> recEstudanteId r /= eid) antes
        in (st { stRecomendacoes = depois }, length antes - length depois)
    if removidos > 0
        then do
            _ <- executarSqlSeguro (poolConfig pool) ("DELETE FROM recomendacoes WHERE estudante_id = " ++ show eid ++ ";")
            pure removidos
        else pure 0
