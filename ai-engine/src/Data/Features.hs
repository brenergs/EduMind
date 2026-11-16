module Data.Features
    ( extrairCaracteristicas
    , extrairCaracteristicasBasicas
    ) where

import Data.Maybe (fromMaybe)
import Data.Types

-- Versão conceitual inicial (Seção 13.2) útil para testes rápidos:
extrairCaracteristicasBasicas :: Double -> Int -> [Double]
extrairCaracteristicasBasicas nota t =
    [ nota / 100.0
    , fromIntegral t
    ]

-- Versão completa (X1..X6) com imputação padrão do tempo médio quando ausente:
extrairCaracteristicas :: Double -> Desempenho -> [Double]
extrairCaracteristicas tempoImputado d =
    [ notaAnterior d / 100.0
    , fromIntegral (respostasCorretas d)
    , fromIntegral (tentativas d)
    , desempenhoPrerequisitos d / 100.0
    , desempenhoRecente d / 100.0
    , fromMaybe tempoImputado (tempoMedioResolucao d)
    ]

