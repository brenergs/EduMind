{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module API.Routes
    ( handleCreateStudent
    , handleListStudents
    , handleGetStudent
    , handleGetContents
    , handleCreateActivity
    , handleRegisterAnswer
    , handleGetPerformance
    , handleGetRecommendations
    , handleTrainModel
    , handleGetModelStatus
    , despacharRequisicao
#ifdef USE_SERVANT
    , EduMindAPI
    , servidorEduMind
    , apiProxy
#endif
    ) where

import Application.GenerateRecommendations
    ( ErroRecomendacao(..)
    , consultarDesempenhoCasoDeUso
    , consultarStatusModeloCasoDeUso
    , gerarRecomendacoesCasoDeUso
    , treinarModeloCasoDeUso
    )
import Application.RegisterAnswer
    ( ErroRegistroResposta(..)
    , registrarRespostaCasoDeUso
    )
import Data.Aeson (eitherDecode, encode, object, (.=))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Char (isSpace, toUpper)
import Data.Text (Text)
import qualified Data.Text as T
import Domain.Content
    ( ActivityDTO
    , ContentDTO
    , CreateActivityRequest(..)
    , montarContentDTO
    , rowParaActivityDTO
    , validarNovaAtividade
    )
import Domain.Recommendation
    ( AnswerRequest
    , AnswerResponseDTO
    , ModelStatusDTO
    , StudentPerformanceResponse
    , StudentRecommendationsResponse
    , TrainModelRequestDTO
    , TrainModelResponseDTO
    )
import Domain.Student
    ( CreateStudentRequest
    , StudentDTO
    , rowParaStudentDTO
    , validarNovoEstudante
    )
import Infrastructure.Database
    ( ConteudoRow(..)
    , DbPool
    , buscarEstudantePorId
    , criarAtividade
    , criarEstudante
    , listarAtividadesPorConteudo
    , listarConteudos
    , listarEstudantes
    , listarPreRequisitosPorConteudo
    )
import Text.Read (readMaybe)

#ifdef USE_SERVANT
import Control.Monad.IO.Class (liftIO)
import Data.Proxy (Proxy(..))
import Servant
#endif

encodeErro :: Int -> Text -> BL.ByteString
encodeErro status msg = encode $ object
    [ "status" .= status
    , "error"  .= msg
    ]

-- ============================================================
-- Handlers de Caso de Uso (independentes de transporte HTTP)
-- ============================================================

handleCreateStudent :: DbPool -> CreateStudentRequest -> IO (Either (Int, Text) StudentDTO)
handleCreateStudent pool req =
    case validarNovoEstudante req of
        Left err -> pure (Left (400, err))
        Right (nome, email) -> do
            res <- criarEstudante pool nome email
            pure $ case res of
                Left errDup -> Left (409, T.pack errDup)
                Right row   -> Right (rowParaStudentDTO row)

handleListStudents :: DbPool -> IO [StudentDTO]
handleListStudents pool = map rowParaStudentDTO <$> listarEstudantes pool

handleGetStudent :: DbPool -> Int -> IO (Either (Int, Text) StudentDTO)
handleGetStudent pool sid = do
    mRow <- buscarEstudantePorId pool sid
    pure $ case mRow of
        Nothing  -> Left (404, "Estudante nao encontrado.")
        Just row -> Right (rowParaStudentDTO row)

handleGetContents :: DbPool -> IO [ContentDTO]
handleGetContents pool = do
    conteudos <- listarConteudos pool
    mapM montar conteudos
  where
    montar cRow = do
        prereqs    <- listarPreRequisitosPorConteudo pool (contId cRow)
        atividades <- listarAtividadesPorConteudo pool (contId cRow)
        pure (montarContentDTO cRow prereqs atividades)

handleCreateActivity :: DbPool -> CreateActivityRequest -> IO (Either (Int, Text) ActivityDTO)
handleCreateActivity pool req =
    case validarNovaAtividade req of
        Left err -> pure (Left (400, err))
        Right valido -> do
            res <- criarAtividade
                pool
                (reqActivityConteudoId valido)
                (reqActivityTitulo valido)
                (reqActivityDescricao valido)
                (reqActivityDificuldade valido)
            pure $ case res of
                Left err  -> Left (404, T.pack err)
                Right row -> Right (rowParaActivityDTO row)

handleRegisterAnswer :: DbPool -> AnswerRequest -> IO (Either (Int, Text) AnswerResponseDTO)
handleRegisterAnswer pool req = do
    res <- registrarRespostaCasoDeUso pool req
    pure $ case res of
        Left EstudanteNaoEncontrado -> Left (404, "Estudante nao encontrado.")
        Left AtividadeNaoEncontrada -> Left (404, "Atividade nao encontrada.")
        Left (DadosInvalidos msg)   -> Left (400, msg)
        Left (ErroPersistencia msg) -> Left (500, msg)
        Right dto                   -> Right dto

handleGetPerformance :: DbPool -> Int -> IO (Either (Int, Text) StudentPerformanceResponse)
handleGetPerformance pool sid = do
    res <- consultarDesempenhoCasoDeUso pool sid
    pure $ mapErroRecomendacao res

handleGetRecommendations :: DbPool -> Int -> IO (Either (Int, Text) StudentRecommendationsResponse)
handleGetRecommendations pool sid = do
    res <- gerarRecomendacoesCasoDeUso pool sid
    pure $ mapErroRecomendacao res

handleTrainModel :: DbPool -> Maybe TrainModelRequestDTO -> IO (Either (Int, Text) TrainModelResponseDTO)
handleTrainModel pool mReq = do
    res <- treinarModeloCasoDeUso pool mReq
    pure $ mapErroRecomendacao res

handleGetModelStatus :: DbPool -> IO ModelStatusDTO
handleGetModelStatus = consultarStatusModeloCasoDeUso

mapErroRecomendacao :: Either ErroRecomendacao a -> Either (Int, Text) a
mapErroRecomendacao (Right x)                          = Right x
mapErroRecomendacao (Left RecEstudanteNaoEncontrado)   = Left (404, "Estudante nao encontrado.")
mapErroRecomendacao (Left (RecErroDados msg))          = Left (400, msg)
mapErroRecomendacao (Left (RecErroTreino msg))         = Left (500, msg)

-- ============================================================
-- Despachante HTTP/JSON para testes integrados e CLI
-- ============================================================

despacharRequisicao :: DbPool -> String -> String -> BL.ByteString -> IO (Int, BL.ByteString)
despacharRequisicao pool metodoRaw caminhoRaw body =
    case (metodo, segmentos) of
        ("POST", ["api", "students"]) ->
            decodificarEExecutar 201 (handleCreateStudent pool)
        ("GET", ["api", "students"]) -> do
            dtos <- handleListStudents pool
            pure (200, encode dtos)
        ("GET", ["api", "students", sidTxt]) ->
            comId sidTxt (\sid -> responderEither 200 <$> handleGetStudent pool sid)
        ("GET", ["api", "contents"]) -> do
            dtos <- handleGetContents pool
            pure (200, encode dtos)
        ("POST", ["api", "activities"]) ->
            decodificarEExecutar 201 (handleCreateActivity pool)
        ("POST", ["api", "answers"]) ->
            decodificarEExecutar 201 (handleRegisterAnswer pool)
        ("GET", ["api", "students", sidTxt, "performance"]) ->
            comId sidTxt (\sid -> responderEither 200 <$> handleGetPerformance pool sid)
        ("GET", ["api", "students", sidTxt, "recommendations"]) ->
            comId sidTxt (\sid -> responderEither 200 <$> handleGetRecommendations pool sid)
        ("POST", ["api", "models", "train"]) ->
            if BLC.all isSpace body
                then responderEither 200 <$> handleTrainModel pool Nothing
                else case eitherDecode body of
                    Left err  -> pure (400, encodeErro 400 (T.pack ("JSON invalido: " ++ err)))
                    Right req -> responderEither 200 <$> handleTrainModel pool (Just req)
        ("GET", ["api", "models", "status"]) -> do
            st <- handleGetModelStatus pool
            pure (200, encode st)
        _ ->
            pure (404, encodeErro 404 "Endpoint nao encontrado.")
  where
    metodo = map toUpper metodoRaw
    caminhoSemQuery = takeWhile (/= '?') caminhoRaw
    segmentos = filter (not . null) (quebrarBarra caminhoSemQuery)

    decodificarEExecutar okCode acao =
        case eitherDecode body of
            Left err  -> pure (400, encodeErro 400 (T.pack ("JSON invalido: " ++ err)))
            Right req -> responderEither okCode <$> acao req

    comId sidTxt acao =
        case readMaybe sidTxt of
            Nothing  -> pure (400, encodeErro 400 "Identificador numerico invalido na rota.")
            Just sid -> acao sid

    responderEither okCode (Right val)       = (okCode, encode val)
    responderEither _      (Left (code, msg)) = (code, encodeErro code msg)

quebrarBarra :: String -> [String]
quebrarBarra [] = []
quebrarBarra s =
    let (parte, resto) = break (== '/') s
    in parte : case resto of
        []       -> []
        (_ : xs) -> quebrarBarra xs

#ifdef USE_SERVANT
type EduMindAPI =
         "api" :> "students" :> ReqBody '[JSON] CreateStudentRequest :> PostCreated '[JSON] StudentDTO
    :<|> "api" :> "students" :> Get '[JSON] [StudentDTO]
    :<|> "api" :> "students" :> Capture "id" Int :> Get '[JSON] StudentDTO
    :<|> "api" :> "contents" :> Get '[JSON] [ContentDTO]
    :<|> "api" :> "activities" :> ReqBody '[JSON] CreateActivityRequest :> PostCreated '[JSON] ActivityDTO
    :<|> "api" :> "answers" :> ReqBody '[JSON] AnswerRequest :> PostCreated '[JSON] AnswerResponseDTO
    :<|> "api" :> "students" :> Capture "id" Int :> "performance" :> Get '[JSON] StudentPerformanceResponse
    :<|> "api" :> "students" :> Capture "id" Int :> "recommendations" :> Get '[JSON] StudentRecommendationsResponse
    :<|> "api" :> "models" :> "train" :> ReqBody '[JSON] TrainModelRequestDTO :> Post '[JSON] TrainModelResponseDTO
    :<|> "api" :> "models" :> "status" :> Get '[JSON] ModelStatusDTO

apiProxy :: Proxy EduMindAPI
apiProxy = Proxy

servidorEduMind :: DbPool -> Server EduMindAPI
servidorEduMind pool =
         (\req -> liftIO (handleCreateStudent pool req) >>= eitherParaHandler)
    :<|> liftIO (handleListStudents pool)
    :<|> (\sid -> liftIO (handleGetStudent pool sid) >>= eitherParaHandler)
    :<|> liftIO (handleGetContents pool)
    :<|> (\req -> liftIO (handleCreateActivity pool req) >>= eitherParaHandler)
    :<|> (\req -> liftIO (handleRegisterAnswer pool req) >>= eitherParaHandler)
    :<|> (\sid -> liftIO (handleGetPerformance pool sid) >>= eitherParaHandler)
    :<|> (\sid -> liftIO (handleGetRecommendations pool sid) >>= eitherParaHandler)
    :<|> (\req -> liftIO (handleTrainModel pool (Just req)) >>= eitherParaHandler)
    :<|> liftIO (handleGetModelStatus pool)

eitherParaHandler :: Either (Int, Text) a -> Handler a
eitherParaHandler (Right x) = pure x
eitherParaHandler (Left (code, msg)) =
    throwError $ case code of
        400 -> err400 { errBody = encodeErro 400 msg }
        404 -> err404 { errBody = encodeErro 404 msg }
        409 -> err409 { errBody = encodeErro 409 msg }
        _   -> err500 { errBody = encodeErro code msg }
#endif
