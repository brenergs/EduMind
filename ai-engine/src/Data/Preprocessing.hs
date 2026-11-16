{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Preprocessing
    ( RegistroCSV(..)
    , DivisaoDados(..)
    , ScalerParams(..)
    , ConjuntosPreparados(..)
    , decodificarCSV
    , carregarCSV
    , dividirPorEstudante
    , calcularMedianaTempo
    , registroParaAmostra
    , ajustarNormalizador
    , aplicarNormalizacao
    , normalizarAmostra
    , prepararConjuntosTreino
    ) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.ByteString.Lazy as BL
import Data.Char (toLower)
import Data.Csv (FromField(..), FromNamedRecord(..), decodeByName, (.:))
import Data.Features (extrairCaracteristicas)
import Data.List (sort, transpose)
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import Data.Types
import qualified Data.Vector as V
import GHC.Generics (Generic)

data RegistroCSV = RegistroCSV
    { regEstudanteId             :: String
    , regConteudo                :: Conteudo
    , regDesempenhoAnterior      :: Double
    , regRespostasCorretas       :: Int
    , regTentativas              :: Int
    , regDesempenhoPrerequisitos :: Double
    , regDesempenhoRecente       :: Double
    , regTempoMedioResolucao     :: Maybe Double
    , regDominio                 :: Double
    , regOrigemDados             :: String
    } deriving (Show, Eq)

instance FromField Conteudo where
    parseField raw = do
        texto <- parseField raw
        case map toLower texto of
            "adicao"        -> pure Adicao
            "subtracao"     -> pure Subtracao
            "multiplicacao" -> pure Multiplicacao
            "divisao"       -> pure Divisao
            outro           -> fail ("Conteudo desconhecido no CSV: " ++ outro)

instance FromNamedRecord RegistroCSV where
    parseNamedRecord m =
        RegistroCSV
            <$> m .: "student_pseudo_id"
            <*> m .: "conteudo"
            <*> m .: "desempenho_anterior"
            <*> m .: "respostas_corretas"
            <*> m .: "tentativas"
            <*> m .: "desempenho_prerequisitos"
            <*> m .: "desempenho_recente"
            <*> m .: "tempo_medio_resolucao"
            <*> m .: "dominio"
            <*> m .: "origem_dados"

data DivisaoDados = DivisaoDados
    { registrosTreino    :: [RegistroCSV]
    , registrosValidacao :: [RegistroCSV]
    , registrosTeste     :: [RegistroCSV]
    } deriving (Show, Eq)

data ScalerParams = ScalerParams
    { medias  :: [Double]
    , desvios :: [Double]
    } deriving (Show, Eq, Generic)

instance ToJSON ScalerParams
instance FromJSON ScalerParams

data ConjuntosPreparados = ConjuntosPreparados
    { tempoImputado    :: Double
    , scalerParams     :: ScalerParams
    , amostrasTreino    :: [AmostraTreino]
    , amostrasValidacao :: [AmostraTreino]
    , amostrasTeste     :: [AmostraTreino]
    } deriving (Show, Eq)

decodificarCSV :: BL.ByteString -> Either String [RegistroCSV]
decodificarCSV bytes =
    case decodeByName bytes of
        Left err       -> Left err
        Right (_, vec) -> Right (V.toList vec)

carregarCSV :: FilePath -> IO (Either String [RegistroCSV])
carregarCSV caminho = decodificarCSV <$> BL.readFile caminho

-- | Mantém a ordem de aparição dos estudantes removendo duplicatas sem perder determinismo.
estudantesUnicos :: [RegistroCSV] -> [String]
estudantesUnicos = go Set.empty
  where
    go _ [] = []
    go vistos (r : rs)
        | Set.member eid vistos = go vistos rs
        | otherwise             = eid : go (Set.insert eid vistos) rs
      where
        eid = regEstudanteId r

-- | Separa os registros em Treino, Validação e Teste agrupando estritamente por identidade do estudante
-- para evitar vazamento de dados entre conjuntos (Seção 10.3 e 17.1).
dividirPorEstudante :: [RegistroCSV] -> DivisaoDados
dividirPorEstudante registros =
    DivisaoDados
        { registrosTreino    = filtrarPorConjunto treinoIds
        , registrosValidacao = filtrarPorConjunto validacaoIds
        , registrosTeste     = filtrarPorConjunto testeIds
        }
  where
    ids = estudantesUnicos registros
    n   = length ids
    (nTreino, nVal)
        | n <= 1    = (n, 0)
        | n == 2    = (1, 0)
        | otherwise =
            let t = max 1 (min (n - 2) (round (0.70 * fromIntegral n :: Double)))
                restante = n - t
                v = max 1 (restante `div` 2)
            in (t, v)
    treinoIds    = Set.fromList (take nTreino ids)
    validacaoIds = Set.fromList (take nVal (drop nTreino ids))
    testeIds     = Set.fromList (drop (nTreino + nVal) ids)
    filtrarPorConjunto conj = filter (\r -> Set.member (regEstudanteId r) conj) registros

-- | Calcula a mediana de tempo_medio_resolucao apenas sobre os registros fornecidos (treino),
-- com fallback seguro de 30.0 segundos caso todos os valores estejam ausentes.
calcularMedianaTempo :: [RegistroCSV] -> Double
calcularMedianaTempo registros =
    case sort (mapMaybe regTempoMedioResolucao registros) of
        [] -> 30.0
        xs ->
            let len = length xs
                meio = len `div` 2
            in if odd len
                then xs !! meio
                else (xs !! (meio - 1) + xs !! meio) / 2.0

registroParaAmostra :: Double -> RegistroCSV -> AmostraTreino
registroParaAmostra tempoPadrao r =
    let d = Desempenho
            { conteudo                = regConteudo r
            , notaAnterior            = regDesempenhoAnterior r
            , respostasCorretas       = regRespostasCorretas r
            , tentativas              = regTentativas r
            , desempenhoPrerequisitos = regDesempenhoPrerequisitos r
            , desempenhoRecente       = regDesempenhoRecente r
            , tempoMedioResolucao     = regTempoMedioResolucao r
            }
    in AmostraTreino
        { amostraEstudante = regEstudanteId r
        , amostraConteudo  = regConteudo r
        , amostraFeatures  = extrairCaracteristicas tempoPadrao d
        , amostraDominio   = regDominio r
        }

-- | Calcula média e desvio padrão Z-score por característica exclusivamente sobre o conjunto de treino.
ajustarNormalizador :: [[Double]] -> ScalerParams
ajustarNormalizador [] = ScalerParams [] []
ajustarNormalizador linhas =
    let n       = fromIntegral (length linhas)
        colunas = transpose linhas
        calcMedia col = sum col / n
        calcDesvio m col =
            let variancia = sum [ (x - m) ^ (2 :: Int) | x <- col ] / n
            in sqrt variancia
        ms = map calcMedia colunas
        ds = zipWith calcDesvio ms colunas
    in ScalerParams ms ds

-- | Aplica a normalização Z-score usando parâmetros congelados do treino,
-- protegendo contra divisão por zero quando o desvio padrão é nulo.
aplicarNormalizacao :: ScalerParams -> [Double] -> [Double]
aplicarNormalizacao (ScalerParams [] _) xs = xs
aplicarNormalizacao (ScalerParams ms ds) xs =
    zipWith3 normalizar xs ms ds
  where
    normalizar x m d
        | d <= 1e-12 = 0.0
        | otherwise  = (x - m) / d

normalizarAmostra :: ScalerParams -> AmostraTreino -> AmostraTreino
normalizarAmostra scaler amostra =
    amostra { amostraFeatures = aplicarNormalizacao scaler (amostraFeatures amostra) }

-- | Pipeline completo de preparação dos dados:
-- 1) Divide por estudante;
-- 2) Calcula mediana de imputação apenas no treino;
-- 3) Extrai características e ajusta o normalizador apenas no treino;
-- 4) Aplica os parâmetros congelados a treino, validação e teste.
prepararConjuntosTreino :: [RegistroCSV] -> ConjuntosPreparados
prepararConjuntosTreino registros =
    let divisao      = dividirPorEstudante registros
        tempoPadrao  = calcularMedianaTempo (registrosTreino divisao)
        brutoTreino  = map (registroParaAmostra tempoPadrao) (registrosTreino divisao)
        brutoVal     = map (registroParaAmostra tempoPadrao) (registrosValidacao divisao)
        brutoTeste   = map (registroParaAmostra tempoPadrao) (registrosTeste divisao)
        scaler       = ajustarNormalizador (map amostraFeatures brutoTreino)
    in ConjuntosPreparados
        { tempoImputado     = tempoPadrao
        , scalerParams      = scaler
        , amostrasTreino    = map (normalizarAmostra scaler) brutoTreino
        , amostrasValidacao = map (normalizarAmostra scaler) brutoVal
        , amostrasTeste     = map (normalizarAmostra scaler) brutoTeste
        }

