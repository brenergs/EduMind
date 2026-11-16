{-# LANGUAGE OverloadedStrings #-}

module Application.GenerateRecommendations
    ( ErroRecomendacao(..)
    , consultarDesempenhoCasoDeUso
    , treinarModeloCasoDeUso
    , consultarStatusModeloCasoDeUso
    , gerarRecomendacoesCasoDeUso
    ) where

import Control.Exception (IOException, try)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy as BL
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Preprocessing (RegistroCSV, carregarCSV)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Types (Conteudo(..), Desempenho(..), Recomendacao(..))
import Domain.Content (conteudoIdParaDominio, dominioParaConteudoId, dominioParaSlug, tituloParaDominio)
import Domain.Recommendation
    ( ContentPerformanceDTO(..)
    , ModelStatusDTO(..)
    , RecommendationItemDTO(..)
    , StudentPerformanceResponse(..)
    , StudentRecommendationsResponse(..)
    , TrainModelRequestDTO(..)
    , TrainModelResponseDTO(..)
    )
import Evaluation.Metrics (ComparativoBaseline(..), compararComBaseline)
import Infrastructure.Database
    ( AtividadeRow(..)
    , ConteudoRow(..)
    , DbPool
    , DesempenhoRow(..)
    , EstudanteRow(..)
    , ModeloRow(..)
    , PreRequisitoRow(..)
    , RespostaRow(..)
    , buscarEstudantePorId
    , buscarModeloAtivo
    , listarAtividades
    , listarConteudos
    , listarDesempenhoPorEstudante
    , listarPreRequisitos
    , listarRespostasPorEstudante
    , salvarModelo
    , salvarRecomendacoesLote
    )
import Models.Training
    ( ArtefatoModelo(..)
    , ConfigTreino(..)
    , ResultadoTreino(..)
    , configTreinoPadrao
    , desserializarArtefato
    , preverComArtefato
    , serializarArtefato
    , treinarPipelineCompleto
    )
import Recommendation.Prerequisites
    ( GrafoDependencias
    , grafoPadraoMatematica
    , preRequisitosDe
    , sequenciaPedagogicaPadrao
    )
import Recommendation.Scoring
    ( LimiaresRecomendacao(..)
    , gerarRecomendacoesOrdenadas
    , limiaresPadrao
    , nivelDificuldadeSugerido
    )

data ErroRecomendacao
    = RecEstudanteNaoEncontrado
    | RecErroDados Text
    | RecErroTreino Text
    deriving (Show, Eq)

consultarDesempenhoCasoDeUso
    :: DbPool
    -> Int
    -> IO (Either ErroRecomendacao StudentPerformanceResponse)
consultarDesempenhoCasoDeUso pool eid = do
    mEst <- buscarEstudantePorId pool eid
    case mEst of
        Nothing -> pure (Left RecEstudanteNaoEncontrado)
        Just est -> do
            conteudos  <- listarConteudos pool
            atividades <- listarAtividades pool
            respostas  <- listarRespostasPorEstudante pool eid
            desempenhos <- listarDesempenhoPorEstudante pool eid
            let mapaAtivConteudo = Map.fromList [(ativId a, ativConteudoId a) | a <- atividades]
                porConteudo cRow =
                    let cid = contId cRow
                        respsC = filter (\r -> Map.lookup (respAtividadeId r) mapaAtivConteudo == Just cid) respostas
                        tentativasC = length respsC
                        corretasC   = length (filter respResultado respsC)
                        temposC     = mapMaybe respTempoResolucao respsC
                        tempoMedioC = if null temposC
                            then Nothing
                            else Just (fromIntegral (sum temposC) / fromIntegral (length temposC))
                        mDes = find (\d -> desConteudoId d == cid) desempenhos
                        pontuacaoC = maybe (if tentativasC == 0 then 0.0 else 100.0 * fromIntegral corretasC / fromIntegral tentativasC) desPontuacao mDes
                        slug = maybe (T.toLower (contTitulo cRow)) dominioParaSlug (tituloParaDominio (contTitulo cRow))
                    in ContentPerformanceDTO
                        { perfContentId     = cid
                        , perfContentSlug   = slug
                        , perfContentTitle  = contTitulo cRow
                        , perfScore         = pontuacaoC
                        , perfAttempts      = tentativasC
                        , perfCorrectCount  = corretasC
                        , perfAvgTime       = tempoMedioC
                        , perfUpdatedAt     = fmap desDataAtualizacao mDes
                        }
                itens = map porConteudo conteudos
                comTentativas = filter (\i -> perfAttempts i > 0) itens
                mediaGeral = if null comTentativas
                    then 0.0
                    else sum (map perfScore comTentativas) / fromIntegral (length comTentativas)
            pure $ Right StudentPerformanceResponse
                { studPerfStudentId     = eid
                , studPerfStudentName   = estNome est
                , studPerfOverallScore  = mediaGeral
                , studPerfTotalAttempts = length respostas
                , studPerfContents      = itens
                }

carregarDatasetPadrao :: IO (Either String [RegistroCSV])
carregarDatasetPadrao = do
    tent1 <- try (carregarCSV "../ai-engine/datasets/sample.csv") :: IO (Either IOException (Either String [RegistroCSV]))
    case tent1 of
        Right res -> pure res
        Left _ -> do
            tent2 <- try (carregarCSV "ai-engine/datasets/sample.csv") :: IO (Either IOException (Either String [RegistroCSV]))
            case tent2 of
                Right res -> pure res
                Left _ -> do
                    tent3 <- try (carregarCSV "datasets/sample.csv") :: IO (Either IOException (Either String [RegistroCSV]))
                    case tent3 of
                        Right res -> pure res
                        Left ex   -> pure (Left (show ex))

treinarModeloCasoDeUso
    :: DbPool
    -> Maybe TrainModelRequestDTO
    -> IO (Either ErroRecomendacao TrainModelResponseDTO)
treinarModeloCasoDeUso pool mReq = do
    resCsv <- carregarDatasetPadrao
    case resCsv of
        Left err -> pure (Left (RecErroTreino (T.pack ("Nao foi possivel carregar o dataset: " ++ err))))
        Right [] -> pure (Left (RecErroTreino "Dataset de treinamento vazio."))
        Right registros -> do
            let versao = maybe "1.0" (fromMaybe "1.0" . trainReqVersion) mReq
                cfg = ConfigTreino
                    { taxaAprendizado = maybe (taxaAprendizado configTreinoPadrao) (fromMaybe (taxaAprendizado configTreinoPadrao) . trainReqLearningRate) mReq
                    , epocas          = maybe (epocas configTreinoPadrao) (fromMaybe (epocas configTreinoPadrao) . trainReqEpochs) mReq
                    , regularizacaoL2 = maybe (regularizacaoL2 configTreinoPadrao) (fromMaybe (regularizacaoL2 configTreinoPadrao) . trainReqL2) mReq
                    }
                resultado = treinarPipelineCompleto (T.unpack versao) cfg registros
                comparativo = compararComBaseline (limiarDominio limiaresPadrao) (modelo (artefato resultado)) registros
                paramsJsonText = lazyBytesParaText (serializarArtefato (artefato resultado))
                metricasJsonText = lazyBytesParaText $ encode $ object
                    [ "train_loss"             .= perdaTreino resultado
                    , "validation_loss"        .= perdaValidacao resultado
                    , "test_loss"              .= perdaTeste resultado
                    , "ml_validation"          .= metricasValidacaoML comparativo
                    , "ml_test"                .= metricasTesteML comparativo
                    , "baseline_validation"    .= metricasValidacaoBaseline comparativo
                    , "baseline_test"          .= metricasTesteBaseline comparativo
                    , "ganho_accuracy_teste"   .= ganhoAccuracyTeste comparativo
                    , "ganho_f1_teste"         .= ganhoF1Teste comparativo
                    , "reducao_logloss_teste"  .= reducaoLogLossTeste comparativo
                    ]
            _ <- salvarModelo pool "RegressaoLogistica" versao paramsJsonText metricasJsonText
            pure $ Right TrainModelResponseDTO
                { trainRespAlgorithm      = "RegressaoLogistica"
                , trainRespVersion        = versao
                , trainRespTrainLoss      = perdaTreino resultado
                , trainRespValidationLoss = perdaValidacao resultado
                , trainRespTestLoss       = perdaTeste resultado
                , trainRespStatus         = "treinado"
                }

consultarStatusModeloCasoDeUso :: DbPool -> IO ModelStatusDTO
consultarStatusModeloCasoDeUso pool = do
    mModelo <- buscarModeloAtivo pool
    pure $ case mModelo of
        Nothing -> ModelStatusDTO
            { statusModelActive    = False
            , statusModelAlgorithm = "RegressaoLogistica"
            , statusModelVersion   = "nao_treinado"
            , statusModelMetrics   = "{}"
            , statusModelTrainedAt = Nothing
            }
        Just m -> ModelStatusDTO
            { statusModelActive    = True
            , statusModelAlgorithm = modAlgoritmo m
            , statusModelVersion   = modVersao m
            , statusModelMetrics   = modMetricas m
            , statusModelTrainedAt = Just (modDataTreinamento m)
            }

gerarRecomendacoesCasoDeUso
    :: DbPool
    -> Int
    -> IO (Either ErroRecomendacao StudentRecommendationsResponse)
gerarRecomendacoesCasoDeUso pool eid = do
    mEst <- buscarEstudantePorId pool eid
    case mEst of
        Nothing -> pure (Left RecEstudanteNaoEncontrado)
        Just _ -> do
            preReqs    <- listarPreRequisitos pool
            atividades <- listarAtividades pool
            respostas  <- listarRespostasPorEstudante pool eid
            desempenhos <- listarDesempenhoPorEstudante pool eid
            mArtefato  <- obterOuTreinarArtefato pool
            let grafo = construirGrafo preReqs
                mapaAtivConteudo = Map.fromList [(ativId a, ativConteudoId a) | a <- atividades]
                mapaDesempenho = Map.fromList [(desConteudoId d, desPontuacao d) | d <- desempenhos]

                extrairNotaConteudo :: Conteudo -> Double
                extrairNotaConteudo c =
                    let cid = dominioParaConteudoId c
                        respsC = filter (\r -> Map.lookup (respAtividadeId r) mapaAtivConteudo == Just cid) respostas
                    in case Map.lookup cid mapaDesempenho of
                        Just p  -> p
                        Nothing -> if null respsC
                            then 50.0
                            else 100.0 * fromIntegral (length (filter respResultado respsC)) / fromIntegral (length respsC)

                montarDesempenho :: Conteudo -> Desempenho
                montarDesempenho c =
                    let cid = dominioParaConteudoId c
                        respsC = filter (\r -> Map.lookup (respAtividadeId r) mapaAtivConteudo == Just cid) respostas
                        corretasC = length (filter respResultado respsC)
                        tentativasC = length respsC
                        recentes = take 5 respsC
                        notaAtual = extrairNotaConteudo c
                        notaRecente = if null recentes
                            then notaAtual
                            else 100.0 * fromIntegral (length (filter respResultado recentes)) / fromIntegral (length recentes)
                        tempos = mapMaybe respTempoResolucao respsC
                        tempoMedio = if null tempos
                            then Nothing
                            else Just (fromIntegral (sum tempos) / fromIntegral (length tempos))
                        prereqsC = preRequisitosDe grafo c
                        notaPrereq = if null prereqsC
                            then 100.0
                            else sum (map extrairNotaConteudo prereqsC) / fromIntegral (length prereqsC)
                    in Desempenho
                        { conteudo                = c
                        , notaAnterior            = notaAtual
                        , respostasCorretas       = corretasC
                        , tentativas              = max 1 tentativasC
                        , desempenhoPrerequisitos = notaPrereq
                        , desempenhoRecente       = notaRecente
                        , tempoMedioResolucao     = tempoMedio
                        }

                estimarProb :: Maybe ArtefatoModelo -> Conteudo -> Double
                estimarProb (Just art) c =
                    let cid = dominioParaConteudoId c
                        respsC = filter (\r -> Map.lookup (respAtividadeId r) mapaAtivConteudo == Just cid) respostas
                        mDes = Map.lookup cid mapaDesempenho
                    in if null respsC && mDes == Nothing
                        then 0.0
                        else preverComArtefato art (montarDesempenho c)
                estimarProb Nothing c = extrairNotaConteudo c / 100.0

                mapaProbs = Map.fromList
                    [ (c, estimarProb mArtefato c)
                    | c <- sequenciaPedagogicaPadrao
                    ]
                recomendacoesOrdenadas = gerarRecomendacoesOrdenadas limiaresPadrao grafo mapaProbs
                versaoUsada = maybe "heuristica-1.0" (T.pack . versaoModelo) mArtefato

                paraItemDTO rec = RecommendationItemDTO
                    { recItemContent             = dominioParaSlug (conteudoRecomendado rec)
                    , recItemEstimatedMastery    = arredondar4 (probabilidadeDominio rec)
                    , recItemRecommendation      = T.pack (tipoAcao rec)
                    , recItemReason              = T.pack (justificativa rec)
                    , recItemSuggestedDifficulty = nivelDificuldadeSugerido (probabilidadeDominio rec)
                    }

                lotePersistencia =
                    [ ( dominioParaConteudoId (conteudoRecomendado rec)
                      , T.pack (justificativa rec)
                      , probabilidadeDominio rec
                      )
                    | rec <- recomendacoesOrdenadas
                    ]

            _ <- salvarRecomendacoesLote pool eid lotePersistencia
            pure $ Right StudentRecommendationsResponse
                { recsStudentId       = eid
                , recsRecommendations = map paraItemDTO recomendacoesOrdenadas
                , recsModelVersion    = versaoUsada
                }

obterOuTreinarArtefato :: DbPool -> IO (Maybe ArtefatoModelo)
obterOuTreinarArtefato pool = do
    mModelo <- buscarModeloAtivo pool
    case mModelo of
        Just m ->
            case desserializarArtefato (textParaLazyBytes (modParametros m)) of
                Right art -> pure (Just art)
                Left _    -> treinarPadraoSilencioso
        Nothing -> treinarPadraoSilencioso
  where
    treinarPadraoSilencioso = do
        res <- treinarModeloCasoDeUso pool Nothing
        case res of
            Left _ -> pure Nothing
            Right _ -> do
                mNovo <- buscarModeloAtivo pool
                pure $ case mNovo of
                    Nothing -> Nothing
                    Just m  -> either (const Nothing) Just (desserializarArtefato (textParaLazyBytes (modParametros m)))

construirGrafo :: [PreRequisitoRow] -> GrafoDependencias
construirGrafo [] = grafoPadraoMatematica
construirGrafo rows =
    let baseVazia = Map.fromList [(c, []) | c <- sequenciaPedagogicaPadrao]
        inserir mapa r =
            case (conteudoIdParaDominio (prConteudoId r), conteudoIdParaDominio (prPreRequisitoId r)) of
                (Just c, Just pr) -> Map.insertWith (++) c [pr] mapa
                _                 -> mapa
    in foldl inserir baseVazia rows

lazyBytesParaText :: BL.ByteString -> Text
lazyBytesParaText = TE.decodeUtf8 . BL.toStrict

textParaLazyBytes :: Text -> BL.ByteString
textParaLazyBytes = BL.fromStrict . TE.encodeUtf8

arredondar4 :: Double -> Double
arredondar4 x = fromIntegral (round (x * 10000.0) :: Int) / 10000.0
