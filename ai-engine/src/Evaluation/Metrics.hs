{-# LANGUAGE DeriveGeneric #-}

module Evaluation.Metrics
    ( MatrizConfusao(..)
    , RelatorioMetricas(..)
    , FaixaCalibracao(..)
    , ComparativoBaseline(..)
    , calcularMatrizConfusao
    , calcularAccuracy
    , calcularPrecision
    , calcularRecall
    , calcularF1Score
    , calcularLogLoss
    , avaliarPrevisoes
    , avaliarModeloEmAmostras
    , calibrarLimiarDominio
    , calibrarLimiaresRecomendacao
    , curvaCalibracao
    , preverBaselineRegras
    , avaliarBaselineRegistros
    , compararComBaseline
    ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.List (foldl', maximumBy)
import Data.Ord (comparing)
import Data.Preprocessing
    ( ConjuntosPreparados(..)
    , DivisaoDados(..)
    , RegistroCSV(..)
    , dividirPorEstudante
    , prepararConjuntosTreino
    )
import Data.Types (AmostraTreino(..))
import GHC.Generics (Generic)
import Models.LogisticRegression (ModeloLogistico(..), perdaMedia, prever)
import Recommendation.Scoring (LimiaresRecomendacao(..))

data MatrizConfusao = MatrizConfusao
    { vp :: Int -- Verdadeiros Positivos
    , vn :: Int -- Verdadeiros Negativos
    , fp :: Int -- Falsos Positivos
    , fn :: Int -- Falsos Negativos
    } deriving (Show, Eq, Generic)

instance ToJSON MatrizConfusao
instance FromJSON MatrizConfusao

data RelatorioMetricas = RelatorioMetricas
    { limiarClassificacao :: Double
    , matrizConfusao      :: MatrizConfusao
    , accuracy            :: Double
    , precision           :: Double
    , recall              :: Double
    , f1Score             :: Double
    , logLoss             :: Double
    , totalAmostras       :: Int
    } deriving (Show, Eq, Generic)

instance ToJSON RelatorioMetricas
instance FromJSON RelatorioMetricas

data FaixaCalibracao = FaixaCalibracao
    { faixaInicio                :: Double
    , faixaFim                   :: Double
    , quantidadeAmostras         :: Int
    , probabilidadeMediaPrevista :: Double
    , proporcaoPositivaReal      :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON FaixaCalibracao
instance FromJSON FaixaCalibracao

data ComparativoBaseline = ComparativoBaseline
    { metricasValidacaoML       :: RelatorioMetricas
    , metricasTesteML           :: RelatorioMetricas
    , metricasValidacaoBaseline :: RelatorioMetricas
    , metricasTesteBaseline     :: RelatorioMetricas
    , ganhoAccuracyTeste        :: Double
    , ganhoF1Teste              :: Double
    , reducaoLogLossTeste       :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON ComparativoBaseline
instance FromJSON ComparativoBaseline

calcularMatrizConfusao :: Double -> [(Double, Double)] -> MatrizConfusao
calcularMatrizConfusao limiar = foldl' contar (MatrizConfusao 0 0 0 0)
  where
    contar (MatrizConfusao cVp cVn cFp cFn) (yReal, pPrev) =
        let realPos = yReal >= 0.5
            predPos = pPrev >= limiar
        in case (realPos, predPos) of
            (True,  True)  -> MatrizConfusao (cVp + 1) cVn cFp cFn
            (False, False) -> MatrizConfusao cVp (cVn + 1) cFp cFn
            (False, True)  -> MatrizConfusao cVp cVn (cFp + 1) cFn
            (True,  False) -> MatrizConfusao cVp cVn cFp (cFn + 1)

calcularAccuracy :: MatrizConfusao -> Double
calcularAccuracy (MatrizConfusao cVp cVn cFp cFn)
    | total == 0 = 0.0
    | otherwise  = fromIntegral (cVp + cVn) / fromIntegral total
  where
    total = cVp + cVn + cFp + cFn

calcularPrecision :: MatrizConfusao -> Double
calcularPrecision (MatrizConfusao cVp _ cFp _)
    | denom == 0 = 0.0
    | otherwise  = fromIntegral cVp / fromIntegral denom
  where
    denom = cVp + cFp

calcularRecall :: MatrizConfusao -> Double
calcularRecall (MatrizConfusao cVp _ _ cFn)
    | denom == 0 = 0.0
    | otherwise  = fromIntegral cVp / fromIntegral denom
  where
    denom = cVp + cFn

calcularF1Score :: MatrizConfusao -> Double
calcularF1Score m
    | prec + rec == 0.0 = 0.0
    | otherwise         = 2.0 * prec * rec / (prec + rec)
  where
    prec = calcularPrecision m
    rec  = calcularRecall m

calcularLogLoss :: [(Double, Double)] -> Double
calcularLogLoss = perdaMedia

avaliarPrevisoes :: Double -> [(Double, Double)] -> RelatorioMetricas
avaliarPrevisoes limiar pares =
    let mat = calcularMatrizConfusao limiar pares
    in RelatorioMetricas
        { limiarClassificacao = limiar
        , matrizConfusao      = mat
        , accuracy            = calcularAccuracy mat
        , precision           = calcularPrecision mat
        , recall              = calcularRecall mat
        , f1Score             = calcularF1Score mat
        , logLoss             = calcularLogLoss pares
        , totalAmostras       = length pares
        }

avaliarModeloEmAmostras :: Double -> ModeloLogistico -> [AmostraTreino] -> RelatorioMetricas
avaliarModeloEmAmostras limiar (ModeloLogistico ws b) amostras =
    avaliarPrevisoes
        limiar
        [ (amostraDominio a, prever ws (amostraFeatures a) b)
        | a <- amostras
        ]

-- | Seleciona o limiar de classificação de domínio sobre o conjunto de validação
-- equilibrando F1-score, precisão (para evitar falsos positivos de domínio) e acurácia.
calibrarLimiarDominio :: [Double] -> [(Double, Double)] -> (Double, RelatorioMetricas)
calibrarLimiarDominio [] pares = (0.75, avaliarPrevisoes 0.75 pares)
calibrarLimiarDominio candidatos pares =
    let avaliados = [(lim, avaliarPrevisoes lim pares) | lim <- candidatos]
        criterio (lim, rel) =
            ( f1Score rel
            , precision rel
            , accuracy rel
            , negate (abs (lim - 0.75))
            )
    in maximumBy (comparing criterio) avaliados

calibrarLimiaresRecomendacao :: [(Double, Double)] -> LimiaresRecomendacao
calibrarLimiaresRecomendacao paresValidacao =
    let (limDom, _) = calibrarLimiarDominio [0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85] paresValidacao
        limRef = max 0.30 (min 0.55 (limDom - 0.25))
    in LimiaresRecomendacao
        { limiarReforco = limRef
        , limiarDominio = limDom
        }

-- | Agrupa previsões em faixas de probabilidade [0, 1] para inspecionar a calibração do modelo.
curvaCalibracao :: Int -> [(Double, Double)] -> [FaixaCalibracao]
curvaCalibracao nFaixasBruto pares =
    [ FaixaCalibracao
        { faixaInicio                = ini
        , faixaFim                   = fim
        , quantidadeAmostras         = length noBin
        , probabilidadeMediaPrevista = sum (map snd noBin) / fromIntegral (length noBin)
        , proporcaoPositivaReal      = sum [if y >= 0.5 then 1.0 else 0.0 | (y, _) <- noBin] / fromIntegral (length noBin)
        }
    | idx <- [0 .. nFaixas - 1]
    , let ini = fromIntegral idx * passo
          fim = if idx == nFaixas - 1 then 1.0 else fromIntegral (idx + 1) * passo
          pertence (_, p) =
              if idx == nFaixas - 1
                  then p >= ini && p <= fim
                  else p >= ini && p < fim
          noBin = filter pertence pares
    , not (null noBin)
    ]
  where
    nFaixas = max 1 nFaixasBruto
    passo   = 1.0 / fromIntegral nFaixas

-- | Baseline determinístico simples baseado apenas em desempenho_anterior / 100.0
-- (classificação positiva quando notaAnterior >= 70.0, i.e., limiar 0.70).
preverBaselineRegras :: RegistroCSV -> Double
preverBaselineRegras r = max 0.0 (min 1.0 (regDesempenhoAnterior r / 100.0))

avaliarBaselineRegistros :: Double -> [RegistroCSV] -> RelatorioMetricas
avaliarBaselineRegistros limiarBaseline regs =
    avaliarPrevisoes
        limiarBaseline
        [ (regDominio r, preverBaselineRegras r)
        | r <- regs
        ]

-- | Compara o modelo de Regressão Logística com o baseline baseado em regras
-- sobre a mesma divisão agrupada por estudante (Validação e Teste).
compararComBaseline :: Double -> ModeloLogistico -> [RegistroCSV] -> ComparativoBaseline
compararComBaseline limiarML modelo registros =
    let divisao   = dividirPorEstudante registros
        prep      = prepararConjuntosTreino registros
        mlVal     = avaliarModeloEmAmostras limiarML modelo (amostrasValidacao prep)
        mlTeste   = avaliarModeloEmAmostras limiarML modelo (amostrasTeste prep)
        baseVal   = avaliarBaselineRegistros 0.70 (registrosValidacao divisao)
        baseTeste = avaliarBaselineRegistros 0.70 (registrosTeste divisao)
    in ComparativoBaseline
        { metricasValidacaoML       = mlVal
        , metricasTesteML           = mlTeste
        , metricasValidacaoBaseline = baseVal
        , metricasTesteBaseline     = baseTeste
        , ganhoAccuracyTeste        = accuracy mlTeste - accuracy baseTeste
        , ganhoF1Teste              = f1Score mlTeste - f1Score baseTeste
        , reducaoLogLossTeste       = logLoss baseTeste - logLoss mlTeste
        }
