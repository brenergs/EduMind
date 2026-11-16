module Recommendation.Prerequisites
    ( GrafoDependencias
    , sequenciaPedagogicaPadrao
    , grafoPadraoMatematica
    , preRequisitosPendentes
    , todosPreRequisitosDe
    , todosPreRequisitosPendentes
    ) where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Types (Conteudo(..))

type GrafoDependencias = Map.Map Conteudo [Conteudo]

sequenciaPedagogicaPadrao :: [Conteudo]
sequenciaPedagogicaPadrao = [minBound .. maxBound]

grafoPadraoMatematica :: GrafoDependencias
grafoPadraoMatematica = Map.fromList
    [ (Adicao,        [])
    , (Subtracao,     [Adicao])
    , (Multiplicacao, [Subtracao])
    , (Divisao,       [Multiplicacao])
    ]

preRequisitosDe :: GrafoDependencias -> Conteudo -> [Conteudo]
preRequisitosDe grafo c = Map.findWithDefault [] c grafo

-- | Retorna os pré-requisitos diretos cuja probabilidade estimada está abaixo do limiar de domínio.
preRequisitosPendentes :: GrafoDependencias -> Double -> Map.Map Conteudo Double -> Conteudo -> [Conteudo]
preRequisitosPendentes grafo limiarDominio mapaProbs c =
    [ prereq
    | prereq <- preRequisitosDe grafo c
    , Map.findWithDefault 0.0 prereq mapaProbs < limiarDominio
    ]

-- | Retorna todos os pré-requisitos (diretos e transitivos) em ordem fundacional,
-- com proteção contra ciclos via conjunto de nós visitados.
todosPreRequisitosDe :: GrafoDependencias -> Conteudo -> [Conteudo]
todosPreRequisitosDe grafo raiz = snd (dfs (Set.singleton raiz) raiz)
  where
    dfs :: Set.Set Conteudo -> Conteudo -> (Set.Set Conteudo, [Conteudo])
    dfs visitados atual =
        foldl' passo (visitados, []) (preRequisitosDe grafo atual)

    passo :: (Set.Set Conteudo, [Conteudo]) -> Conteudo -> (Set.Set Conteudo, [Conteudo])
    passo (vis, acc) prereq
        | Set.member prereq vis = (vis, acc)
        | otherwise =
            let (vis', sub) = dfs (Set.insert prereq vis) prereq
            in (vis', acc ++ sub ++ [prereq])

-- | Retorna todos os pré-requisitos (diretos e transitivos) ainda abaixo do limiar de domínio.
todosPreRequisitosPendentes :: GrafoDependencias -> Double -> Map.Map Conteudo Double -> Conteudo -> [Conteudo]
todosPreRequisitosPendentes grafo limiarDominio mapaProbs c =
    [ prereq
    | prereq <- todosPreRequisitosDe grafo c
    , Map.findWithDefault 0.0 prereq mapaProbs < limiarDominio
    ]
