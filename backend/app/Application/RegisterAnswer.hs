{-# LANGUAGE OverloadedStrings #-}

module Application.RegisterAnswer
    ( ErroRegistroResposta(..)
    , registrarRespostaCasoDeUso
    ) where

import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Domain.Recommendation (AnswerRequest(..), AnswerResponseDTO(..))
import Infrastructure.Database
    ( AtividadeRow(..)
    , DbPool
    , DesempenhoRow(..)
    , RespostaRow(..)
    , buscarAtividadePorId
    , buscarEstudantePorId
    , listarAtividades
    , listarRespostasPorEstudante
    , registrarRespostaDB
    , upsertDesempenho
    )

data ErroRegistroResposta
    = EstudanteNaoEncontrado
    | AtividadeNaoEncontrada
    | DadosInvalidos Text
    | ErroPersistencia Text
    deriving (Show, Eq)

registrarRespostaCasoDeUso
    :: DbPool
    -> AnswerRequest
    -> IO (Either ErroRegistroResposta AnswerResponseDTO)
registrarRespostaCasoDeUso pool req
    | ansAttempts req < 1 =
        pure (Left (DadosInvalidos "A quantidade de tentativas (attempts) deve ser maior ou igual a 1."))
    | maybe False (< 0) (ansResolutionTime req) =
        pure (Left (DadosInvalidos "O tempo de resolucao nao pode ser negativo."))
    | otherwise = do
        mEstudante <- buscarEstudantePorId pool (ansStudentId req)
        case mEstudante of
            Nothing -> pure (Left EstudanteNaoEncontrado)
            Just _ -> do
                mAtividade <- buscarAtividadePorId pool (ansActivityId req)
                case mAtividade of
                    Nothing -> pure (Left AtividadeNaoEncontrada)
                    Just atividade -> do
                        let textoResp = fromMaybe (if ansCorrect req then "correta" else "incorreta") (ansAnswerText req)
                        resDb <- registrarRespostaDB
                            pool
                            (ansStudentId req)
                            (ansActivityId req)
                            textoResp
                            (ansCorrect req)
                            (ansResolutionTime req)
                        case resDb of
                            Left err -> pure (Left (ErroPersistencia (T.pack err)))
                            Right row -> do
                                pontuacaoAtualizada <- recalcularDesempenhoConteudo pool (ansStudentId req) (ativConteudoId atividade) (ansAttempts req)
                                desRow <- upsertDesempenho pool (ansStudentId req) (ativConteudoId atividade) pontuacaoAtualizada
                                pure $ Right AnswerResponseDTO
                                    { ansRespId             = respId row
                                    , ansRespStudentId      = respEstudanteId row
                                    , ansRespActivityId     = respAtividadeId row
                                    , ansRespContentId      = ativConteudoId atividade
                                    , ansRespCorrect        = respResultado row
                                    , ansRespAttempts       = ansAttempts req
                                    , ansRespResolutionTime = respTempoResolucao row
                                    , ansRespUpdatedScore   = desPontuacao desRow
                                    , ansRespRecordedAt     = respDataRealizacao row
                                    }

recalcularDesempenhoConteudo :: DbPool -> Int -> Int -> Int -> IO Double
recalcularDesempenhoConteudo pool eid cid tentativasUltima = do
    todasRespostas <- listarRespostasPorEstudante pool eid
    todasAtivs     <- listarAtividades pool
    let pertenceAoConteudo r =
            case find (\a -> ativId a == respAtividadeId r) todasAtivs of
                Just a  -> ativConteudoId a == cid
                Nothing -> False
        respostasConteudo = filter pertenceAoConteudo todasRespostas
        total = length respostasConteudo
        corretas = length (filter respResultado respostasConteudo)
    if total == 0
        then pure 0.0
        else do
            let taxaBase = 100.0 * fromIntegral corretas / fromIntegral total
                fatorTentativas = if tentativasUltima > 1 then 1.0 / sqrt (fromIntegral tentativasUltima) else 1.0
                -- Pondera suavemente o excesso de tentativas na resposta atual mantendo escala 0..100
                pontuacaoAjustada = (taxaBase * 0.85) + (taxaBase * fatorTentativas * 0.15)
            pure (max 0.0 (min 100.0 pontuacaoAjustada))
