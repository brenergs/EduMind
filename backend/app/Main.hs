{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import API.Routes (despacharRequisicao)
import Data.Aeson (Value(..), decode, encode, object, (.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Foldable (toList)
import Data.Maybe (isJust)
import Infrastructure.Database (DbConfig(..), DbPool, carregarConfigBanco, fecharPool, inicializarPool)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hSetEncoding, stdout, utf8)

#ifdef USE_SERVANT
import API.Routes (apiProxy, servidorEduMind)
import Data.Maybe (fromMaybe)
import Network.Wai (Middleware)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors (cors, corsRequestHeaders, simpleCorsResourcePolicy)
import Servant (serve)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
#endif

executarFluxoDemonstracao :: DbPool -> IO Bool
executarFluxoDemonstracao pool = do
    putStrLn "=== Validacao Integrada dos 9 Endpoints REST (EduMind) ==="

    -- 1. GET /api/models/status (antes do treino)
    (st1, bodySt1) <- despacharRequisicao pool "GET" "/api/models/status" BL.empty
    putStrLn $ "1) GET /api/models/status -> HTTP " ++ show st1

    -- 2. POST /api/models/train
    (stTrain, bodyTrain) <- despacharRequisicao pool "POST" "/api/models/train" (encode (object ["version" .= ("1.0" :: String)]))
    putStrLn $ "2) POST /api/models/train -> HTTP " ++ show stTrain ++ " | " ++ BLC.unpack bodyTrain

    -- 3. GET /api/models/status (apos treino)
    (st2, bodySt2) <- despacharRequisicao pool "GET" "/api/models/status" BL.empty
    putStrLn $ "3) GET /api/models/status -> HTTP " ++ show st2

    -- 4. POST /api/students
    (stStud, bodyStud) <- despacharRequisicao pool "POST" "/api/students" $ encode $ object
        [ "nome"  .= ("Ana Clara" :: String)
        , "email" .= ("ana.clara@escola.edu.br" :: String)
        ]
    putStrLn $ "4) POST /api/students -> HTTP " ++ show stStud ++ " | " ++ BLC.unpack bodyStud

    -- 5. GET /api/students/1
    (stGetStud, _) <- despacharRequisicao pool "GET" "/api/students/1" BL.empty
    putStrLn $ "5) GET /api/students/1 -> HTTP " ++ show stGetStud

    -- 6. GET /api/contents
    (stCont, bodyCont) <- despacharRequisicao pool "GET" "/api/contents" BL.empty
    putStrLn $ "6) GET /api/contents -> HTTP " ++ show stCont

    -- 7. POST /api/activities
    (stAct, bodyAct) <- despacharRequisicao pool "POST" "/api/activities" $ encode $ object
        [ "conteudo_id" .= (3 :: Int)
        , "titulo"      .= ("Multiplicacao Intermediaria" :: String)
        , "descricao"   .= ("Resolva 12 x 4." :: String)
        , "dificuldade" .= (3 :: Int)
        ]
    putStrLn $ "7) POST /api/activities -> HTTP " ++ show stAct ++ " | " ++ BLC.unpack bodyAct

    -- 8. POST /api/answers (payload da Secao 15)
    let answerPayload = encode $ object
            [ "student_id"      .= (1 :: Int)
            , "activity_id"     .= (1 :: Int)
            , "correct"         .= True
            , "attempts"        .= (1 :: Int)
            , "resolution_time" .= (35 :: Int)
            ]
    (stAns1, _) <- despacharRequisicao pool "POST" "/api/answers" answerPayload
    (stAns2, bodyAns2) <- despacharRequisicao pool "POST" "/api/answers" $ encode $ object
        [ "student_id"      .= (1 :: Int)
        , "activity_id"     .= (5 :: Int)
        , "correct"         .= False
        , "attempts"        .= (2 :: Int)
        , "resolution_time" .= (48 :: Int)
        ]
    putStrLn $ "8) POST /api/answers -> HTTP " ++ show stAns1 ++ " / " ++ show stAns2 ++ " | " ++ BLC.unpack bodyAns2

    -- 9. GET /api/students/1/performance
    (stPerf, bodyPerf) <- despacharRequisicao pool "GET" "/api/students/1/performance" BL.empty
    putStrLn $ "9) GET /api/students/1/performance -> HTTP " ++ show stPerf

    -- 10. GET /api/students/1/recommendations
    (stRec, bodyRec) <- despacharRequisicao pool "GET" "/api/students/1/recommendations" BL.empty
    putStrLn $ "10) GET /api/students/1/recommendations -> HTTP " ++ show stRec
    putStrLn $ "    Payload: " ++ BLC.unpack bodyRec

    let contratoRecOk = validarContratoRecomendacoes bodyRec
        contratoSt1Ok = isJust (decode bodySt1 :: Maybe Value)
        contratoSt2Ok = isJust (decode bodySt2 :: Maybe Value)
        contratoContOk = isJust (decode bodyCont :: Maybe Value)
        contratoPerfOk = isJust (decode bodyPerf :: Maybe Value)
        todosOk = st1 == 200
            && stTrain == 200
            && st2 == 200
            && stStud == 201
            && stGetStud == 200
            && stCont == 200
            && stAct == 201
            && stAns1 == 201
            && stAns2 == 201
            && stPerf == 200
            && stRec == 200
            && contratoRecOk
            && contratoSt1Ok
            && contratoSt2Ok
            && contratoContOk
            && contratoPerfOk
    pure todosOk

validarContratoRecomendacoes :: BL.ByteString -> Bool
validarContratoRecomendacoes raw =
    case decode raw :: Maybe Value of
        Just (Object obj) ->
            KM.member "student_id" obj
                && KM.member "model_version" obj
                && case KM.lookup "recommendations" obj of
                    Just (Array arr) ->
                        let itens = toList arr
                        in not (null itens) && all itemValido itens
                    _ -> False
        _ -> False
  where
    itemValido (Object item) =
        KM.member "content" item
            && KM.member "estimated_mastery" item
            && KM.member "recommendation" item
            && KM.member "reason" item
    itemValido _ = False

#ifdef USE_SERVANT
corsMiddleware :: Middleware
corsMiddleware = cors $ const $ Just $ simpleCorsResourcePolicy
    { corsRequestHeaders = ["Content-Type", "Authorization"]
    }
#endif

main :: IO ()
main = do
    hSetEncoding stdout utf8
    args <- getArgs
    cfg  <- carregarConfigBanco
    pool <- inicializarPool cfg
    putStrLn ("EduMind backend pronto (banco: " ++ dbName cfg ++ ", host: " ++ dbHost cfg ++ ":" ++ dbPort cfg ++ ").")
#ifdef USE_SERVANT
    if "--demo" `elem` args
        then executarDemoESair pool
        else do
            mPorta <- lookupEnv "PORT"
            let porta = fromMaybe 8080 (mPorta >>= readMaybe)
            putStrLn ("Servidor Servant/Warp escutando na porta " ++ show porta ++ "...")
            run porta (corsMiddleware (serve apiProxy (servidorEduMind pool)))
            fecharPool pool
#else
    _ <- pure args
    executarDemoESair pool
#endif

executarDemoESair :: DbPool -> IO ()
executarDemoESair pool = do
    ok <- executarFluxoDemonstracao pool
    fecharPool pool
    if ok
        then do
            putStrLn "Todos os 9 endpoints REST e contratos JSON da Secao 15 foram validados com sucesso!"
            exitSuccess
        else do
            putStrLn "Falha na validacao de um ou mais endpoints REST."
            exitFailure
