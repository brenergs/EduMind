{-# LANGUAGE DeriveGeneric #-}

module Models.Training
    ( ConfigTreino(..)
    , ArtefatoModelo(..)
    , ResultadoTreino(..)
    , configTreinoPadrao
    , passoGradiente
    , treinar
    , treinarAmostras
    , avaliarPerda
    , preverComArtefato
    , treinarPipelineCompleto
    , serializarArtefato
    , desserializarArtefato
    , salvarArtefatoJSON
    , carregarArtefatoJSON
    ) where

import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import qualified Data.ByteString.Lazy as BL
import Data.Features (extrairCaracteristicas)
import Data.List (foldl', transpose)
import Data.Preprocessing
    ( ConjuntosPreparados(..)
    , RegistroCSV
    , ScalerParams
    , aplicarNormalizacao
    , prepararConjuntosTreino
    )
import Data.Types (AmostraTreino(..), Desempenho)
import GHC.Generics (Generic)
import Models.LogisticRegression
    ( ModeloLogistico(..)
    , perdaMedia
    , prever
    )

data ConfigTreino = ConfigTreino
    { taxaAprendizado :: Double
    , epocas          :: Int
    , regularizacaoL2 :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON ConfigTreino
instance FromJSON ConfigTreino

configTreinoPadrao :: ConfigTreino
configTreinoPadrao = ConfigTreino
    { taxaAprendizado = 0.1
    , epocas          = 1000
    , regularizacaoL2 = 0.01
    }

data ArtefatoModelo = ArtefatoModelo
    { modelo               :: ModeloLogistico
    , scaler               :: ScalerParams
    , tempoImputacaoModelo :: Double
    , versaoModelo         :: String
    } deriving (Show, Eq, Generic)

instance ToJSON ArtefatoModelo
instance FromJSON ArtefatoModelo

data ResultadoTreino = ResultadoTreino
    { artefato       :: ArtefatoModelo
    , perdaTreino    :: Double
    , perdaValidacao :: Double
    , perdaTeste     :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON ResultadoTreino
instance FromJSON ResultadoTreino

passoGradiente :: Double -> Double -> ModeloLogistico -> [([Double], Double)] -> ModeloLogistico
passoGradiente _ _ modelo [] = modelo
passoGradiente lr lambda (ModeloLogistico ws b) dados =
    let m = fromIntegral (length dados)
        erros = [prever ws xs b - y | (xs, y) <- dados]
        gradB = sum erros / m
        xsTransposta = transpose (map fst dados)
        gradWs =
            [ (sum (zipWith (*) erros col) / m) + (lambda * w / m)
            | (col, w) <- zip xsTransposta ws
            ]
        novosWs = zipWith (\w g -> w - lr * g) ws gradWs
        novoB   = b - lr * gradB
    in ModeloLogistico novosWs novoB

treinar :: ConfigTreino -> [([Double], Double)] -> ModeloLogistico
treinar _ [] = ModeloLogistico [] 0.0
treinar cfg dados@(primeira : _) =
    let nFeatures = length (fst primeira)
        modeloInicial = ModeloLogistico (replicate nFeatures 0.0) 0.0
        passo m _ = passoGradiente (taxaAprendizado cfg) (regularizacaoL2 cfg) m dados
    in foldl' passo modeloInicial [1 .. epocas cfg]

treinarAmostras :: ConfigTreino -> [AmostraTreino] -> ModeloLogistico
treinarAmostras cfg amostras =
    treinar cfg [(amostraFeatures a, amostraDominio a) | a <- amostras]

avaliarPerda :: ModeloLogistico -> [AmostraTreino] -> Double
avaliarPerda (ModeloLogistico ws b) amostras =
    perdaMedia
        [ (amostraDominio a, prever ws (amostraFeatures a) b)
        | a <- amostras
        ]

-- | Executa inferência usando exatamente a mesma extração e normalização congeladas do treino.
preverComArtefato :: ArtefatoModelo -> Desempenho -> Double
preverComArtefato art d =
    let bruto       = extrairCaracteristicas (tempoImputacaoModelo art) d
        normalizado = aplicarNormalizacao (scaler art) bruto
        ModeloLogistico ws b = modelo art
    in prever ws normalizado b

-- | Executa o pipeline completo das 10 etapas da Seção 10.3 sobre registros CSV.
treinarPipelineCompleto :: String -> ConfigTreino -> [RegistroCSV] -> ResultadoTreino
treinarPipelineCompleto versao cfg registros =
    let prep     = prepararConjuntosTreino registros
        treinado = treinarAmostras cfg (amostrasTreino prep)
        art      = ArtefatoModelo
            { modelo               = treinado
            , scaler               = scalerParams prep
            , tempoImputacaoModelo = tempoImputado prep
            , versaoModelo         = versao
            }
    in ResultadoTreino
        { artefato       = art
        , perdaTreino    = avaliarPerda treinado (amostrasTreino prep)
        , perdaValidacao = avaliarPerda treinado (amostrasValidacao prep)
        , perdaTeste     = avaliarPerda treinado (amostrasTeste prep)
        }

serializarArtefato :: ArtefatoModelo -> BL.ByteString
serializarArtefato = encode

desserializarArtefato :: BL.ByteString -> Either String ArtefatoModelo
desserializarArtefato = eitherDecode

salvarArtefatoJSON :: FilePath -> ArtefatoModelo -> IO ()
salvarArtefatoJSON caminho art = BL.writeFile caminho (serializarArtefato art)

carregarArtefatoJSON :: FilePath -> IO (Either String ArtefatoModelo)
carregarArtefatoJSON caminho = desserializarArtefato <$> BL.readFile caminho

