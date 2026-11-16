module Main where

import Control.Exception (IOException, try)
import qualified Data.Map.Strict as Map
import Data.Preprocessing
import Data.Types
import Models.LogisticRegression
import Models.Training
import Recommendation.Prerequisites
import Recommendation.Scoring
import System.Exit (exitFailure, exitSuccess)
import System.IO (hSetEncoding, stdout, utf8)
import Test.QuickCheck

prop_sigmoidLimites :: Double -> Bool
prop_sigmoidLimites z =
    let s = sigmoid z
    in s >= 0.0 && s <= 1.0 && not (isNaN s)

prop_sigmoidMonotonica :: Double -> Double -> Bool
prop_sigmoidMonotonica z1 z2 =
    let a = min z1 z2
        b = max z1 z2
    in sigmoid a <= sigmoid b

prop_perdaNaoNegativa :: Property
prop_perdaNaoNegativa =
    forAll (elements [0.0, 1.0]) $ \y ->
        forAll (choose (0.0, 1.0)) $ \p ->
            let l = perda y p
            in l >= 0.0 && not (isNaN l) && not (isInfinite l)

prop_perdaExtremos :: Bool
prop_perdaExtremos =
    all
        (\(y, p) -> let l = perda y p in l >= 0.0 && not (isNaN l) && not (isInfinite l))
        [(0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 1.0)]

prop_gradienteReduzPerda :: Property
prop_gradienteReduzPerda =
    forAll (choose (0.5, 5.0)) $ \delta ->
        let dados =
                [ ([-delta, -delta], 0.0)
                , ([-delta, 0.0],    0.0)
                , ([delta,  0.0],    1.0)
                , ([delta,  delta],  1.0)
                ]
            perdaInicial = perdaMedia [(y, prever [0.0, 0.0] xs 0.0) | (xs, y) <- dados]
            ModeloLogistico ws b = treinar (ConfigTreino 0.1 200 0.0) dados
            perdaFinal = perdaMedia [(y, prever ws xs b) | (xs, y) <- dados]
        in perdaFinal < perdaInicial

gerarRegistro :: String -> Conteudo -> Double -> Maybe Double -> Double -> RegistroCSV
gerarRegistro eid c nota t dom =
    RegistroCSV
        { regEstudanteId             = eid
        , regConteudo                = c
        , regDesempenhoAnterior      = nota
        , regRespostasCorretas       = 5
        , regTentativas              = 10
        , regDesempenhoPrerequisitos = 80.0
        , regDesempenhoRecente       = nota
        , regTempoMedioResolucao     = t
        , regDominio                 = dom
        , regOrigemDados             = "simulado"
        }

prop_semVazamentoEstudante :: Property
prop_semVazamentoEstudante =
    forAll (choose (3 :: Int, 15)) $ \numEstudantes ->
        forAll (elements [Adicao, Subtracao, Multiplicacao, Divisao]) $ \c ->
            let regs =
                    [ gerarRegistro ("stu_" ++ show idx) c (fromIntegral (idx * 7 `mod` 100)) (Just 25.0) (if even idx then 1.0 else 0.0)
                    | idx <- [1 .. numEstudantes]
                    , _ <- [1 :: Int, 2]
                    ]
                divisao = dividirPorEstudante regs
                idsTreino = map regEstudanteId (registrosTreino divisao)
                idsVal    = map regEstudanteId (registrosValidacao divisao)
                idsTeste  = map regEstudanteId (registrosTeste divisao)
                somaQtd   = length (registrosTreino divisao)
                          + length (registrosValidacao divisao)
                          + length (registrosTeste divisao)
                disjuntos as bs = all (`notElem` bs) as
            in somaQtd == length regs
                && disjuntos idsTreino idsVal
                && disjuntos idsTreino idsTeste
                && disjuntos idsVal idsTeste

prop_normalizacaoSemNaN :: Property
prop_normalizacaoSemNaN =
    forAll (choose (1, 10)) $ \nLinhas ->
        forAll (vectorOf nLinhas (choose (-100.0, 100.0))) $ \colVariavel ->
            forAll (choose (-50.0, 50.0)) $ \valConstante ->
                let matriz = [[x, valConstante] | x <- colVariavel]
                    scaler = ajustarNormalizador matriz
                    norm   = map (aplicarNormalizacao scaler) matriz
                in all (all (\v -> not (isNaN v) && not (isInfinite v))) norm

carregarSampleCSV :: IO (Either String [RegistroCSV])
carregarSampleCSV = do
    tentativaLocal <- try (carregarCSV "datasets/sample.csv") :: IO (Either IOException (Either String [RegistroCSV]))
    case tentativaLocal of
        Right res -> pure res
        Left _    -> do
            tentativaRaiz <- try (carregarCSV "ai-engine/datasets/sample.csv") :: IO (Either IOException (Either String [RegistroCSV]))
            case tentativaRaiz of
                Right res -> pure res
                Left ex   -> pure (Left (show ex))

testeIntegracaoSampleCSV :: IO Bool
testeIntegracaoSampleCSV = do
    putStrLn "Executando teste de integracao com datasets/sample.csv..."
    resCsv <- carregarSampleCSV
    case resCsv of
        Left err -> do
            putStrLn ("FALHA ao carregar sample.csv: " ++ err)
            pure False
        Right registros -> do
            let resultado = treinarPipelineCompleto "1.0-test" configTreinoPadrao registros
                art       = artefato resultado
                roundTrip = desserializarArtefato (serializarArtefato art)
                exemploSemTempo = Desempenho
                    { conteudo                = Divisao
                    , notaAnterior            = 60.0
                    , respostasCorretas       = 6
                    , tentativas              = 12
                    , desempenhoPrerequisitos = 75.0
                    , desempenhoRecente       = 65.0
                    , tempoMedioResolucao     = Nothing
                    }
                prob = preverComArtefato art exemploSemTempo
                ok = not (null (pesos (modelo art)))
                    && perdaTreino resultado < 0.693
                    && not (isNaN (perdaValidacao resultado))
                    && not (isNaN (perdaTeste resultado))
                    && roundTrip == Right art
                    && prob >= 0.0 && prob <= 1.0 && not (isNaN prob)
            putStrLn ("  Perda treino:    " ++ show (perdaTreino resultado))
            putStrLn ("  Perda validacao: " ++ show (perdaValidacao resultado))
            putStrLn ("  Perda teste:     " ++ show (perdaTeste resultado))
            putStrLn ("  Prob. exemplo:   " ++ show prob)
            pure ok

prop_nivelDificuldadeLimites :: Property
prop_nivelDificuldadeLimites =
    forAll (choose (0.0, 1.0)) $ \p1 ->
        forAll (choose (0.0, 1.0)) $ \p2 ->
            let a = min p1 p2
                b = max p1 p2
                na = nivelDificuldadeSugerido a
                nb = nivelDificuldadeSugerido b
            in na >= 1 && na <= 5 && nb >= 1 && nb <= 5 && na <= nb

prop_ordenacaoPreservaElementos :: Property
prop_ordenacaoPreservaElementos =
    forAll (vectorOf 4 (choose (0.0, 1.0))) $ \probs ->
        let mapa = Map.fromList (zip sequenciaPedagogicaPadrao probs)
            recs = gerarRecomendacoesOrdenadas limiaresPadrao grafoPadraoMatematica mapa
            conteudos = map conteudoRecomendado recs
        in length recs == 4
            && all (`elem` conteudos) sequenciaPedagogicaPadrao

testeRecomendacaoSecao11 :: IO Bool
testeRecomendacaoSecao11 = do
    putStrLn "Executando teste do sistema de recomendacao (cenario Secao 11.1)..."
    let mapaProbs = Map.fromList
            [ (Adicao,        0.96)
            , (Subtracao,     0.88)
            , (Multiplicacao, 0.58)
            , (Divisao,       0.32)
            ]
        prereqsDivisao = todosPreRequisitosDe grafoPadraoMatematica Divisao
        pendentesDiv   = todosPreRequisitosPendentes grafoPadraoMatematica 0.75 mapaProbs Divisao
        ordenadas      = gerarRecomendacoesOrdenadas limiaresPadrao grafoPadraoMatematica mapaProbs
        ordemConteudos = map conteudoRecomendado ordenadas
        acoesPorItem   = [(conteudoRecomendado r, tipoAcao r) | r <- ordenadas]

        mapaBaixo = Map.fromList
            [ (Adicao,        0.40)
            , (Subtracao,     0.35)
            , (Multiplicacao, 0.25)
            , (Divisao,       0.15)
            ]
        ordenadasBaixo = gerarRecomendacoesOrdenadas limiaresPadrao grafoPadraoMatematica mapaBaixo
        ok = prereqsDivisao == [Adicao, Subtracao, Multiplicacao]
            && pendentesDiv == [Multiplicacao]
            && ordemConteudos == [Multiplicacao, Divisao, Adicao, Subtracao]
            && lookup Multiplicacao acoesPorItem == Just "consolidacao"
            && lookup Divisao acoesPorItem == Just "revisar_pre_requisitos"
            && lookup Adicao acoesPorItem == Just "avancar"
            && lookup Subtracao acoesPorItem == Just "avancar"
            && map conteudoRecomendado ordenadasBaixo == [Adicao, Subtracao, Multiplicacao, Divisao]
            && map tipoAcao ordenadasBaixo == ["reforco", "revisar_pre_requisitos", "revisar_pre_requisitos", "revisar_pre_requisitos"]
    putStrLn ("  Ordem cenario 11.1: " ++ show ordemConteudos)
    pure ok

main :: IO ()
main = do
    hSetEncoding stdout utf8
    putStrLn "=== Testes QuickCheck - Nucleo de ML e Recomendacao (EduMind) ==="
    resultadosQC <- sequence
        [ quickCheckResult prop_sigmoidLimites
        , quickCheckResult prop_sigmoidMonotonica
        , quickCheckResult prop_perdaNaoNegativa
        , quickCheckResult prop_perdaExtremos
        , quickCheckResult prop_gradienteReduzPerda
        , quickCheckResult prop_semVazamentoEstudante
        , quickCheckResult prop_normalizacaoSemNaN
        , quickCheckResult prop_nivelDificuldadeLimites
        , quickCheckResult prop_ordenacaoPreservaElementos
        ]
    okIntegracao <- testeIntegracaoSampleCSV
    okRecomendacao <- testeRecomendacaoSecao11
    if all isSuccess resultadosQC && okIntegracao && okRecomendacao
        then do
            putStrLn "Todos os testes matematicos, computacionais e de recomendacao passaram!"
            exitSuccess
        else do
            putStrLn "Falha em um ou mais testes."
            exitFailure

