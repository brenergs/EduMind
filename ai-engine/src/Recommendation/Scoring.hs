{-# LANGUAGE DeriveGeneric #-}

module Recommendation.Scoring
    ( LimiaresRecomendacao(..)
    , limiaresPadrao
    , nivelDificuldadeSugerido
    , recomendar
    , recomendarComPreRequisitos
    , gerarRecomendacoesHibridas
    , ordenarRecomendacoes
    , gerarRecomendacoesOrdenadas
    ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.List (intercalate, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
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

-- | Adequação da dificuldade das atividades (1 a 5) ao nível estimado do estudante,
-- evitando saltos bruscos de complexidade.
nivelDificuldadeSugerido :: Double -> Int
nivelDificuldadeSugerido prob
    | prob < 0.25 = 1
    | prob < 0.50 = 2
    | prob < 0.70 = 3
    | prob < 0.85 = 4
    | otherwise   = 5

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

-- | Ordena recomendações priorizando:
-- 0) Conteúdos não dominados com pré-requisitos consolidados que exigem reforço imediato
--    ou funcionam como pré-requisitos bloqueadores de outros conteúdos;
-- 1) Conteúdos bloqueados aguardando pré-requisitos ("revisar_pre_requisitos");
-- 2) Demais conteúdos em consolidação;
-- 3) Conteúdos já dominados ("avancar"),
-- desempatando pela sequência pedagógica e pela menor probabilidade de domínio.
ordenarRecomendacoes
    :: GrafoDependencias
    -> Double
    -> [Recomendacao]
    -> [Recomendacao]
ordenarRecomendacoes grafo limiarDom recs =
    sortOn chave recs
  where
    mapaProbs = Map.fromList
        [ (conteudoRecomendado r, probabilidadeDominio r)
        | r <- recs
        ]
    bloqueadores = Set.fromList
        [ prereq
        | r <- recs
        , probabilidadeDominio r < limiarDom
        , prereq <- todosPreRequisitosPendentes grafo limiarDom mapaProbs (conteudoRecomendado r)
        ]

    tier :: Recomendacao -> Int
    tier r
        | prob < limiarDom && null pendentes && (acao == "reforco" || ehBloqueador) = 0
        | acao == "revisar_pre_requisitos" || (prob < limiarDom && not (null pendentes)) = 1
        | prob < limiarDom = 2
        | otherwise = 3
      where
        c            = conteudoRecomendado r
        prob         = probabilidadeDominio r
        acao         = tipoAcao r
        pendentes    = todosPreRequisitosPendentes grafo limiarDom mapaProbs c
        ehBloqueador = Set.member c bloqueadores

    chave :: Recomendacao -> (Int, Conteudo, Double)
    chave r = (tier r, conteudoRecomendado r, probabilidadeDominio r)

gerarRecomendacoesOrdenadas
    :: LimiaresRecomendacao
    -> GrafoDependencias
    -> Map.Map Conteudo Double
    -> [Recomendacao]
gerarRecomendacoesOrdenadas limiares grafo mapaProbs =
    ordenarRecomendacoes grafo (limiarDominio limiares) (gerarRecomendacoesHibridas limiares grafo mapaProbs)
