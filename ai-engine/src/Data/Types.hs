{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Types where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data Conteudo
    = Adicao
    | Subtracao
    | Multiplicacao
    | Divisao
    deriving (Show, Eq, Ord, Enum, Bounded, Generic)

instance ToJSON Conteudo
instance FromJSON Conteudo

data Desempenho = Desempenho
    { conteudo                :: Conteudo
    , notaAnterior            :: Double       -- X1: desempenho em atividades anteriores (0..100)
    , respostasCorretas       :: Int          -- X2: quantidade de respostas corretas
    , tentativas              :: Int          -- X3: quantidade de tentativas
    , desempenhoPrerequisitos :: Double       -- X4: desempenho nos pré-requisitos (0..100)
    , desempenhoRecente       :: Double       -- X5: desempenho em atividades recentes (0..100)
    , tempoMedioResolucao     :: Maybe Double -- X6: opcional (segundos)
    } deriving (Show, Eq, Generic)

instance ToJSON Desempenho
instance FromJSON Desempenho

data Estudante = Estudante
    { estudanteId :: Int
    , historico   :: [Desempenho]
    } deriving (Show, Eq, Generic)

data Recomendacao = Recomendacao
    { conteudoRecomendado  :: Conteudo
    , probabilidadeDominio :: Double
    , tipoAcao             :: String -- ex.: "reforco", "consolidacao", "revisar_pre_requisitos", "avancar"
    , justificativa        :: String
    } deriving (Show, Eq, Generic)

instance ToJSON Recomendacao
instance FromJSON Recomendacao

data AmostraTreino = AmostraTreino
    { amostraEstudante :: String
    , amostraConteudo  :: Conteudo
    , amostraFeatures  :: [Double]
    , amostraDominio   :: Double -- 0.0 ou 1.0
    } deriving (Show, Eq)

