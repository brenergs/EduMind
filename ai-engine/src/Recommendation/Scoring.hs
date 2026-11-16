{-# LANGUAGE DeriveGeneric #-}

module Recommendation.Scoring
    ( LimiaresRecomendacao(..)
    , limiaresPadrao
    , recomendar
    , recomendarComPreRequisitos
    , gerarRecomendacoesHibridas
    ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import Data.Types (Conteudo(..), Recomendacao(..))
import GHC.Generics (Generic)
import Recommendation.Prerequisites
    ( GrafoDependencias
    , sequenciaPedagogicaPadrao
    , todosPreRequisitosPendentes
    )

data LimiaresRecomendacao = LimiaresRecomendacao
    { limiarReforco :: Double
    , limiarDominio :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON LimiaresRecomendacao
instance FromJSON LimiaresRecomendacao

limiaresPadrao :: LimiaresRecomendacao
limiaresPadrao = LimiaresRecomendacao
    { limiarReforco = 0.50
    , limiarDominio = 0.75
    }

nomeConteudo :: Conteudo -> String
nomeConteudo Adicao        = "Adicao"
nomeConteudo Subtracao     = "Subtracao"
nomeConteudo Multiplicacao = "Multiplicacao"
nomeConteudo Divisao       = "Divisao"

-- | Função conceitual base da Seção 13.5 (sem análise de pré-requisitos).
recomendar :: Double -> Conteudo -> Recomendacao
recomendar prob conteudo
    | prob < limiarReforco limiaresPadrao =
        Recomendacao
            { conteudoRecomendado  = conteudo
            , probabilidadeDominio = prob
            , tipoAcao             = "reforco"
            , justificativa        = "Desempenho estimado abaixo do limite de dominio. Recomendar atividades de reforco."
            }
    | prob < limiarDominio limiaresPadrao =
        Recomendacao
            { conteudoRecomendado  = conteudo
            , probabilidadeDominio = prob
            , tipoAcao             = "consolidacao"
            , justificativa        = "Dominio provavel em construcao. Recomendar atividades de consolidacao."
            }
    | otherwise =
        Recomendacao
            { conteudoRecomendado  = conteudo
            , probabilidadeDominio = prob
            , tipoAcao             = "avancar"
            , justificativa        = "Conteudo possivelmente dominado. Recomendar conteudos posteriores ou desafios graduais."
            }

-- | Estratégia híbrida (Seção 11 e 13.5): combina a probabilidade estimada pelo modelo de ML
-- com a verificação de pré-requisitos no grafo direcionado de dependências.
-- Probabilidades baixas orientam apoio pedagógico e revisão — nunca rotulam incapacidade.
recomendarComPreRequisitos
    :: LimiaresRecomendacao
    -> GrafoDependencias
    -> Map.Map Conteudo Double
    -> Conteudo
    -> Recomendacao
recomendarComPreRequisitos limiares grafo mapaProbs conteudo =
    Recomendacao
        { conteudoRecomendado  = conteudo
        , probabilidadeDominio = prob
        , tipoAcao             = acao
        , justificativa        = motivo
        }
  where
    prob = Map.findWithDefault 0.0 conteudo mapaProbs
    pendentes = todosPreRequisitosPendentes grafo (limiarDominio limiares) mapaProbs conteudo
    listaPendentes = intercalate ", " (map nomeConteudo pendentes)

    (acao, motivo)
        | prob < limiarReforco limiares && not (null pendentes) =
            ( "revisar_pre_requisitos"
            , "O conteudo anterior (" ++ listaPendentes ++ ") ainda precisa ser consolidado antes de avancar."
            )
        | prob < limiarReforco limiares =
            ( "reforco"
            , "Desempenho estimado abaixo do limite de dominio. Recomendar atividades de reforco."
            )
        | prob < limiarDominio limiares =
            ( "consolidacao"
            , "Dominio provavel em construcao. Recomendar atividades de consolidacao."
            )
        | otherwise =
            ( "avancar"
            , "Conteudo possivelmente dominado. Recomendar conteudos posteriores ou desafios graduais."
            )

gerarRecomendacoesHibridas
    :: LimiaresRecomendacao
    -> GrafoDependencias
    -> Map.Map Conteudo Double
    -> [Recomendacao]
gerarRecomendacoesHibridas limiares grafo mapaProbs =
    map (recomendarComPreRequisitos limiares grafo mapaProbs) sequenciaPedagogicaPadrao
